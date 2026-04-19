# polar-container-lib/nix/entrypoint.nix
#
# Generates the container entrypoint script (start.sh) from a translated
# ContainerConfig. Only invoked for non-minimal containers — minimal containers
# exec their entrypoint or shell binary directly, no start.sh involved.
#
# Phase order:
#   1. Preamble       (set -euo pipefail, helpers)
#   2. Store-path exports (StartTime env vars)
#   3. User creation  (optional)
#   4. AI setup       (optional)
#   5. Sudo setup     (optional, GPU workloads)
#   6. Arch config    (aarch64 sandbox/seccomp detection)
#   7. Nix daemon     (optional)
#   8. SFTP symlink   (optional, SSH support)
#   9. Cargo cache    (writable target dir)
#  10. SSH server     (optional, Dropbear)
#  11. Banner
#  12. Exec handoff   (mode-specific: shell, pipeline runner, agent)

{ pkgs
, cfg
, devEnv
}:

let
  lib = pkgs.lib;

  # The configured shell binary — used throughout for shell-specific setup.
  # Defaults to fish for interactive containers that don't set shell explicitly.
  shellBin =
    if cfg.shell != null
    then cfg.shell.shell
    else "/bin/fish";

  # ---------------------------------------------------------------------------
  # Phase 1: Preamble
  # ---------------------------------------------------------------------------
  phasePreamble = ''
    #!/usr/bin/env bash
    set -euo pipefail

    die()  { echo >&2 "error: $*"; exit 1; }
    need() { command -v "$1" >/dev/null || die "missing binary: $1"; }
  '';

  # ---------------------------------------------------------------------------
  # Phase 2: Store-path exports
  # Only include paths that are actually in the container's closure.
  # Removed hardcoded fish plugin paths — those only belong in fish containers.
  # ---------------------------------------------------------------------------
  phaseStorePathExports =
    let
      builtinExports = ''
        ##############################################################################
        # Store-path exports (arch-correct — evaluated in target derivation context)
        ##############################################################################
        export LOCALE_ARCHIVE="${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive"
        export COREUTILS="${pkgs.uutils-coreutils-noprefix}"
        export OPENSSL_DIR="${pkgs.openssl.dev}"
        export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
        export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include"
        export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      '' + lib.optionalString (cfg.shell != null && cfg.shell.type == "interactive-fish") ''
        export BOB_THE_FISH="${pkgs.fishPlugins.bobthefish}"
        export FISH_BASS="${pkgs.fishPlugins.bass}"
        export FISH_GRC="${pkgs.fishPlugins.grc}"
      '' + lib.optionalString (cfg.mode == "dev" || cfg.mode == "ci" || cfg.mode == "pipeline") ''
        export LIBCLANG_PATH="${pkgs.llvmPackages_19.libclang.lib}/lib"
      '';

      userExports = lib.concatMapStrings
        (ev: "export ${ev.name}=${lib.escapeShellArg ev.value}\n")
        cfg.startTimeEnv;
    in
      builtinExports + userExports;

  # ---------------------------------------------------------------------------
  # Phase 3: User creation (optional)
  # ---------------------------------------------------------------------------
  phaseUserCreation =
    if cfg.user.createUser
    then ''
      ##############################################################################
      # User creation
      ##############################################################################
      create_user() {
          local user=$1 uid=$2 gid=$3

          [[ -z $user || -z $uid || -z $gid ]] && \
              die "CREATE_USER/CREATE_UID/CREATE_GID must all be set"

          local myshell=${shellBin}

          sed -i "s|^$user:.*|$user:x:$uid:$gid::/home/$user:$myshell|" /etc/passwd
          echo "$user:!x:::::::" >> /etc/shadow

          mkdir -p  /home/$user
          chmod -R 755 /home/$user
          chown -R "$uid:$gid" /home/$user

          install -d -m 700 \
              /home/$user/.config \
              /home/$user/.local/share \
              /home/$user/.cache \
              /home/$user/.ssh

          chown "$uid:$gid" \
              /home/$user/.config \
              /home/$user/.local/share \
              /home/$user/.cache \
              /home/$user/.ssh

          need rsync
          rsync -a --chown=$uid:$gid \
              /root/ /home/$user/ || true

          chmod 1777 /tmp

          ${if shellBin == "/bin/nu" then ''
          mkdir -p /home/$user/.config/nushell
          install -Dm644 ${cfg.user.skeletonPath}/config.nu \
                         /home/$user/.config/nushell/config.nu
          install -Dm644 ${cfg.user.skeletonPath}/env.nu \
                         /home/$user/.config/nushell/env.nu
          if [[ -f /etc/nushell/plugin-registry.msgpackz ]]; then
            install -Dm644 /etc/nushell/plugin-registry.msgpackz \
                           /home/$user/.config/nushell/plugin.msgpackz
          fi
          '' else ''
          install -Dm644 ${cfg.user.skeletonPath}/config.fish \
                         /home/$user/.config/fish/config.fish
          touch /home/$user/.config/fish/fish_variables
          ''}

          chown -R "$uid:$gid" /home/$user
          chmod -R 755 /home/$user
          chmod u+w /home/$user

          SUPP_GROUPS="${builtins.concatStringsSep "," (
            map (g: "${g.name}:${toString g.gid}") cfg.user.supplementalGroups
          )}"
          if [[ -n "$SUPP_GROUPS" ]]; then
            IFS=',' read -ra ENTRIES <<< "$SUPP_GROUPS"
            for entry in "''${ENTRIES[@]}"; do
              g_name="''${entry%%:*}"
              g_gid="''${entry##*:}"
              if getent group "$g_name" >/dev/null 2>&1; then
                sed -i "/^$g_name:/ s/$/,$user/" /etc/group
              else
                echo "$g_name:x:$g_gid:$user" >> /etc/group
                echo "$g_name:!::" >> /etc/gshadow 2>/dev/null || true
              fi
            done
          fi
      }

      (( EUID == 0 )) || die "please run as root"

      if [[ -n "''${CREATE_USER:-}" && -n "''${CREATE_UID:-}" && -n "''${CREATE_GID:-}" ]]; then
          create_user "$CREATE_USER" "$CREATE_UID" "$CREATE_GID"
          DEV_USER=$CREATE_USER
          DEV_UID=$CREATE_UID
          DEV_GID=$CREATE_GID
      else
          DEV_USER=root
          DEV_UID=0
          DEV_GID=0
      fi
    ''
    else ''
      DEV_USER=root
      DEV_UID=0
      DEV_GID=0
    '';

  # ---------------------------------------------------------------------------
  # Phase 3.2: AI tooling setup (optional)
  # ---------------------------------------------------------------------------
  phaseAiSetup =
    if cfg.ai.enable or false
    then ''
      ##############################################################################
      # AI tooling setup
      ##############################################################################
      if [[ -d /opt/llama-models ]]; then
        mkdir -p /home/$DEV_USER/.cache/huggingface
        ln -sfn /opt/llama-models /home/$DEV_USER/.cache/llama.cpp
        ln -sfn /opt/llama-models /home/$DEV_USER/.cache/huggingface/hub
        chown -h "$DEV_UID:$DEV_GID" /home/$DEV_USER/.cache/llama.cpp
        chown -h "$DEV_UID:$DEV_GID" /home/$DEV_USER/.cache/huggingface/hub
      fi
      if [[ -d /opt/ollama ]]; then
        ln -sfn /opt/ollama /home/$DEV_USER/.ollama
        chown -h "$DEV_UID:$DEV_GID" /home/$DEV_USER/.ollama
      fi
      if [[ -d /opt/pi ]]; then
        ln -sfn /opt/pi /home/$DEV_USER/.pi
        chown -h "$DEV_UID:$DEV_GID" /home/$DEV_USER/.pi
      fi
      if command -v ollama >/dev/null 2>&1; then
        OLLAMA_BIN=$(readlink -f $(which ollama))
        OLLAMA_LIB=$(dirname "$OLLAMA_BIN")/../lib/ollama
        if [[ -d "$OLLAMA_LIB" ]]; then
          export LD_LIBRARY_PATH="$OLLAMA_LIB:''${LD_LIBRARY_PATH:-}"
        fi
      fi
      if [[ -d /run/opengl-driver/lib ]]; then
        export LD_LIBRARY_PATH="/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}"
      fi
    ''
    else "";

  # ---------------------------------------------------------------------------
  # Phase 3.5: Sudo setup (optional)
  # ---------------------------------------------------------------------------
  phaseSudo =
    if cfg.user.supplementalGroups != []
    then ''
      ##############################################################################
      # Sudo setup for GPU workloads
      ##############################################################################
      SUDO_REAL=$(readlink -f /bin/sudo 2>/dev/null || \
        find /nix/store -name "sudo" -type f 2>/dev/null | head -1)
      if [[ -n "$SUDO_REAL" ]]; then
        cp "$SUDO_REAL" /usr/bin/sudo
        chown root:root /usr/bin/sudo
        chmod 4755 /usr/bin/sudo
        if [[ ! -f /etc/sudoers ]]; then
          echo "root ALL=(ALL:ALL) ALL"     > /etc/sudoers
          echo "#includedir /etc/sudoers.d" >> /etc/sudoers
          chmod 440 /etc/sudoers
        fi
        mkdir -p /etc/sudoers.d
        LLAMA_BIN=$(which llama-server 2>/dev/null || true)
        if [[ -n "$LLAMA_BIN" ]]; then
          echo "$DEV_USER ALL=(root) NOPASSWD: $LLAMA_BIN" \
            > /etc/sudoers.d/llama-server
          chmod 440 /etc/sudoers.d/llama-server
        fi
        mkdir -p /etc/pam.d
        printf '%s\n' \
          "auth       sufficient   pam_permit.so" \
          "account    sufficient   pam_permit.so" \
          "session    sufficient   pam_permit.so" \
          > /etc/pam.d/sudo
      fi
    ''
    else "";

  # ---------------------------------------------------------------------------
  # Phase 4: Nix daemon (optional)
  # ---------------------------------------------------------------------------
  phaseNixDaemon =
    if cfg.nix.enableDaemon
    then
      let
        buildUserBlock =
          if cfg.nix.buildUserCount.dynamic
          then "cpus=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)"
          else "cpus=${toString cfg.nix.buildUserCount.fixed}";
      in ''
        ##############################################################################
        # Nix build users and daemon
        ##############################################################################
        printf "\nextra-trusted-users = %s\n" "$DEV_USER" >> /etc/nix/nix.conf

        ${buildUserBlock}

        echo "nixbld:x:30000:" >> /etc/group
        echo "nixbld:x::"      >> /etc/gshadow

        mkdir -p /var/empty
        DUMMY_SHELL=/bin/nologin
        [ -x "$DUMMY_SHELL" ] || DUMMY_SHELL=/bin/false

        members=()
        for i in $(seq 1 "$cpus"); do
          muid=$((30000 + i))
          mname="nixbld$i"
          if ! getent passwd "$mname" >/dev/null; then
            printf '%s:x:%d:30000:Nix build user %d:/var/empty:%s\n' \
                   "$mname" "$muid" "$i" "$DUMMY_SHELL" >> /etc/passwd
          fi
          members+=("$mname")
        done

        member_list=$(IFS=, ; echo "''${members[*]}")
        grep -v '^nixbld:' /etc/group   > /etc/group.new
        grep -v '^nixbld:' /etc/gshadow > /etc/gshadow.new 2>/dev/null || true
        echo "nixbld:x:30000:''${member_list}" >> /etc/group.new
        echo "nixbld:!:''${member_list}:"      >> /etc/gshadow.new 2>/dev/null || true
        mv -f /etc/group.new   /etc/group
        mv -f /etc/gshadow.new /etc/gshadow 2>/dev/null || true

        if [[ -L /nix/var/nix/db/db.sqlite ]]; then
            db_src="$(dirname "$(readlink -f /nix/var/nix/db/db.sqlite)")"
            tmp="$(mktemp -d)"
            cp -r "$db_src/." "$tmp/"
            rm -f /nix/var/nix/db/db.sqlite \
                  /nix/var/nix/db/db.sqlite-shm \
                  /nix/var/nix/db/db.sqlite-wal \
                  /nix/var/nix/db/big-lock \
                  /nix/var/nix/db/reserved \
                  /nix/var/nix/db/schema
            cp -r "$tmp/." /nix/var/nix/db/
            rm -rf "$tmp"
            chmod 644 /nix/var/nix/db/db.sqlite
            chmod 600 /nix/var/nix/db/big-lock
            chmod 600 /nix/var/nix/db/reserved
        fi

        if ! { command -v pgrep >/dev/null && pgrep -x nix-daemon >/dev/null; } \
           && ! { ps aux 2>/dev/null | grep -q "[n]ix-daemon"; }; then
            PATH=/nix/var/nix/profiles/default/bin:$PATH \
                /bin/nix-daemon --daemon &
        fi
      ''
    else ''
      # Nix daemon disabled (${cfg.mode} mode)
    '';

  # ---------------------------------------------------------------------------
  # Phase 5: Architecture self-configuration
  # ---------------------------------------------------------------------------
  phaseArchConfig =
    if cfg.nix.enableDaemon
    then
      let
        sandboxBlock =
          if cfg.nix.sandboxPolicy == "enabled" then
            ''printf "\nsandbox = true\n" >> /etc/nix/nix.conf''
          else if cfg.nix.sandboxPolicy == "disabled" then
            ''printf "\nsandbox = false\n" >> /etc/nix/nix.conf''
          else ''
            CPU_IMPLEMENTER=$(grep "CPU implementer" /proc/cpuinfo | head -1 | awk '{print $NF}')
            if [[ "$CPU_IMPLEMENTER" == "0x00" ]]; then
                printf "\nsandbox = false\n"        >> /etc/nix/nix.conf
                printf "\nfilter-syscalls = false\n" >> /etc/nix/nix.conf
            fi
          '';
      in ''
        ##############################################################################
        # Architecture self-configuration
        ##############################################################################
        CONTAINER_ARCH="$(uname -m)"
        if [[ "$CONTAINER_ARCH" == "aarch64" ]]; then
            printf "\nsystem = aarch64-linux\n"         >> /etc/nix/nix.conf
            printf "\nextra-platforms = x86_64-linux\n" >> /etc/nix/nix.conf
            ${sandboxBlock}
        fi
      ''
    else "";

  # ---------------------------------------------------------------------------
  # Phase 6: SFTP symlink
  # ---------------------------------------------------------------------------
  phaseSftpSymlink =
    if cfg.ssh != null then ''
      ##############################################################################
      # SFTP server symlink
      ##############################################################################
      if [[ -f "${pkgs.openssh}/libexec/sftp-server" ]]; then
        ln -sf "${pkgs.openssh}/libexec/sftp-server" /bin/sftp-server
        mkdir -p /run/current-system/sw/libexec
        ln -sf "${pkgs.openssh}/libexec/sftp-server" /run/current-system/sw/libexec/sftp-server
      fi
    ''
    else "";

  # ---------------------------------------------------------------------------
  # Phase 7: Cargo cache
  # ---------------------------------------------------------------------------
  phaseCargoCache = ''
    ##############################################################################
    # Cargo target cache
    ##############################################################################
    CARGO_TARGET_DIR="/var/cache/cargo-target"
    mkdir -p "$CARGO_TARGET_DIR"
    chown -R "$DEV_UID:$DEV_GID" /var/cache
    chmod 0755 "$CARGO_TARGET_DIR"
    export CARGO_TARGET_DIR
  '';

  # ---------------------------------------------------------------------------
  # Phase 8: SSH server
  # ---------------------------------------------------------------------------
  phaseSSH =
    if cfg.ssh != null
    then
      let port = toString cfg.ssh.port;
      in ''
        ##############################################################################
        # SSH server (Dropbear)
        ##############################################################################
        DROPBEAR_STATUS='not started — set DROPBEAR_ENABLE=1 or run ssh-start'

        if [[ "''${DROPBEAR_ENABLE:-0}" == "1" ]]; then
          SSH_DIR="/home/$DEV_USER/.ssh"
          AUTH_KEYS="$SSH_DIR/authorized_keys"
          RSA_KEY="$SSH_DIR/dropbear_rsa_host_key"
          ED25519_KEY="$SSH_DIR/dropbear_ed25519_host_key"
          DROPBEAR_PORT="''${DROPBEAR_PORT:-${port}}"

          mkdir -p "$SSH_DIR"
          chmod 700 "$SSH_DIR"
          chown "$DEV_UID:$DEV_GID" "$SSH_DIR"

          if [[ -n "''${AUTHORIZED_KEYS_B64:-}" ]]; then
            echo "$AUTHORIZED_KEYS_B64" | base64 -d > "$AUTH_KEYS"
            chmod 600 "$AUTH_KEYS"
            chown "$DEV_UID:$DEV_GID" "$AUTH_KEYS"
          else
            DROPBEAR_STATUS="authorized_keys missing (AUTHORIZED_KEYS_B64 not set)"
          fi

          if [[ ! -f "$RSA_KEY" ]];     then dropbearkey -t rsa    -f "$RSA_KEY"     > /dev/null; fi
          if [[ ! -f "$ED25519_KEY" ]]; then dropbearkey -t ed25519 -f "$ED25519_KEY" > /dev/null; fi
          chown "$DEV_UID:$DEV_GID" "$RSA_KEY" "$ED25519_KEY" 2>/dev/null || true

          if [[ -f "$AUTH_KEYS" ]]; then
            chroot --userspec="$DEV_UID:$DEV_GID" / \
              dropbear -F -E -e -a -s \
                -r "$RSA_KEY" -r "$ED25519_KEY" \
                -p "0.0.0.0:$DROPBEAR_PORT" \
                -P "$SSH_DIR/dropbear.pid" &
            sleep 1
            if pgrep -x dropbear >/dev/null 2>&1; then
              DROPBEAR_STATUS="running on port $DROPBEAR_PORT"
            else
              DROPBEAR_STATUS="failed to start"
            fi
          fi
        fi
      ''
    else ''
      DROPBEAR_STATUS="not configured"
    '';

  # ---------------------------------------------------------------------------
  # Phase 9: Banner
  # ---------------------------------------------------------------------------
  phaseBanner = ''
    ##############################################################################
    # Banner
    ##############################################################################
    cat /etc/container-info
    echo " • User ............. $DEV_USER  (uid=$DEV_UID / gid=$DEV_GID)"
    echo " • SSH server ....... $DROPBEAR_STATUS"
    if mountpoint -q /workspace 2>/dev/null; then
      echo " • Volume mount ..... /workspace is mounted"
    fi
    echo " 🆘  Type 'container-help' for usage instructions"
    echo "────────────────────────────────────────────────────────────────────────────"
  '';

  # ---------------------------------------------------------------------------
  # Phase 10: Exec handoff
  # ---------------------------------------------------------------------------
  phaseExec =
    if cfg.mode == "dev" then ''
      ##############################################################################
      # Exec handoff → interactive shell (${shellBin})
      ##############################################################################
      HOME=/home/$DEV_USER \
        LOGNAME=$DEV_USER \
        SHELL=${shellBin} \
        USER=$DEV_USER \
        XDG_CACHE_HOME=/home/$DEV_USER/.cache \
        XDG_CONFIG_HOME=/home/$DEV_USER/.config \
        XDG_DATA_HOME=/home/$DEV_USER/.local/share \
        ${lib.concatMapStrings (ev: "${ev.name}=${lib.escapeShellArg ev.value} \\\n    ") cfg.startTimeEnv}\
        chroot --userspec="$DEV_UID:$DEV_GID" / ${shellBin} -l
    ''
    else if cfg.mode == "ci" || cfg.mode == "pipeline" then ''
      ##############################################################################
      # Exec handoff → pipeline runner
      ##############################################################################
      PIPELINE_TARGET="''${PIPELINE_STAGE:-all}" exec /bin/pipeline-runner "$@"
    ''
    else if cfg.mode == "agent" then ''
      ##############################################################################
      # Exec handoff → agent supervisor
      ##############################################################################
      exec /bin/agent-supervisor "$@"
    ''
    else
      throw "entrypoint: unknown mode '${cfg.mode}'";

in
  pkgs.writeShellScriptBin "start.sh" (
    phasePreamble
    + phaseStorePathExports
    + phaseUserCreation
    + phaseAiSetup
    + phaseSudo
    + phaseArchConfig
    + phaseNixDaemon
    + phaseSftpSymlink
    + phaseCargoCache
    + phaseSSH
    + phaseBanner
    + phaseExec
  )
