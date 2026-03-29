# nix-container-lib/nix/container.nix
#
# mkContainer: the library's primary entry point.
#
# Takes a Dhall ContainerConfig (as a Nix path), resolves it through
# from-dhall.nix, and produces a complete OCI image derivation plus
# a host-side devShell.
#
# Usage in a project flake:
#
#   let
#     lib = inputs.polar-container-lib;
#     container = lib.mkContainer {
#       inherit system pkgs inputs;
#       config = ./my-container.dhall;
#     };
#   in {
#     packages.devContainer = container.image;
#     devShells.default     = container.devShell;
#   }

{ pkgs
, system
, inputs      # The consuming flake's inputs (for PackageRef resolution)
, configPath  # Path to the Dhall ContainerConfig file
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Evaluate the Dhall config to a Nix attrset.
  # dhallToNix is available in nixpkgs as pkgs.dhallToNix.
  # The result is a Nix value with the same structure as the Dhall type.
  # ---------------------------------------------------------------------------
  rawCfg = pkgs.dhallToNix configPath;

  # ---------------------------------------------------------------------------
  # Translate the raw Dhall output to the internal config structure
  # ---------------------------------------------------------------------------
  cfg = import ./from-dhall.nix { inherit pkgs inputs; cfg = rawCfg; };

  # ---------------------------------------------------------------------------
  # Identity & filesystem spine
  # Everything that makes this a valid Linux system before tools are installed.
  # ---------------------------------------------------------------------------
  identity = import ./identity.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Nix-in-Nix infrastructure
  # ---------------------------------------------------------------------------
  nixInfra = import ./nix-infra.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Build the package environment
  # ---------------------------------------------------------------------------
  startScript    = import ./entrypoint.nix { inherit pkgs cfg devEnv; };
  containerHelpScript = import ./container-help.nix { inherit pkgs cfg; };

  devEnv = pkgs.buildEnv {
    name         = "${cfg.name}-env";
    paths        = cfg.packages
                   ++ lib.optionals (cfg.mode != "minimal")
                        [ startScript containerHelpScript ];
    pathsToLink  = [ "/bin" "/lib" "/inc" "/etc/ssl/certs" ];
  };

  # ---------------------------------------------------------------------------
  # Shell environment (optional)
  # Only assembled when cfg.shell != null
  # ---------------------------------------------------------------------------
  shellFiles =
    if cfg.shell != null && cfg.mode != "minimal"
    then import ./shell.nix { inherit pkgs cfg devEnv; }
    else [];

  # ---------------------------------------------------------------------------
  # Pipeline runner (optional)
  # Only assembled when cfg.pipeline != null
  # ---------------------------------------------------------------------------
  pipelineFiles =
    if cfg.pipeline != null && cfg.mode != "minimal"
    then import ./pipeline.nix { inherit pkgs cfg; }
    else [];

  # ---------------------------------------------------------------------------
  # TLS certificates (optional)
  # ---------------------------------------------------------------------------
  tlsDerivation =
    if cfg.tls != null && cfg.tls.generateCerts && cfg.mode != "minimal"
    then import ./gen-certs.nix { inherit pkgs cfg; }
    else null;

  # ---------------------------------------------------------------------------
  # Nix DB and GC roots
  # The full set of derivations that need to be registered and protected.
  # ---------------------------------------------------------------------------
  allContents =
    [ devEnv ]
    ++ shellFiles
    ++ pipelineFiles
    ++ nixInfra.configFiles
    ++ [
      nixInfra.ldLinker
      nixInfra.usrBinEnv
      nixInfra.fhsDirs
    ]
    ++ lib.optional (tlsDerivation != null) tlsDerivation;

  # Identity files registered separately for closure/GC but materialized via extraCommands
  closureInfo = pkgs.closureInfo {
    rootPaths = allContents ++ identity.baseInfo;
  };

  nixDbRegistration = pkgs.runCommand "nix-db-registration" {} ''
    mkdir -p $out/nix/var/nix/db
    export NIX_REMOTE=local?root=$out
    ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo}/registration
  '';

  # allContents already includes all nixInfra derivations — no extraRoots.
  gcRoots = import ./gc-roots.nix { inherit pkgs allContents; };

  # ---------------------------------------------------------------------------
  # OCI User field
  # Minimal mode: use staticUid/staticGid if set, else root.
  # All other modes: root (runtime user creation handled by start.sh).
  # ---------------------------------------------------------------------------
  containerUser =
    if cfg.mode == "minimal"
    then
      if cfg.staticUid != null && cfg.staticGid != null
      then "${toString cfg.staticUid}:${toString cfg.staticGid}"
      else "0:0"
    else "0:0";

  # ---------------------------------------------------------------------------
  # OCI Cmd
  # Minimal mode: exec the named binary directly — no start.sh.
  # All other modes: /bin/start.sh as always.
  # ---------------------------------------------------------------------------
  containerCmd =
    if cfg.mode == "minimal"
    then [ "/bin/${cfg.entrypoint}" ]
    else [ "/bin/start.sh" ];

  # ---------------------------------------------------------------------------
  # Standard build-time env
  # Minimal mode: only emit cfg.buildTimeEnv — skip the dev toolchain vars.
  # All other modes: full standard set plus cfg.buildTimeEnv.
  # ---------------------------------------------------------------------------
  standardBuildEnv =
    if cfg.mode == "minimal"
    then cfg.buildTimeEnv
    else [
      "PATH=/bin:/usr/bin:/root/.cargo/bin"
      "CC=clang"
      "CXX=clang++"
      "CMAKE=/bin/cmake"
      "CMAKE_MAKE_PROGRAM=/bin/make"
      "LANG=en_US.UTF-8"
      "TZ=UTC"
      "MANPAGER=sh -c 'col -bx | bat --language man --style plain'"
      "MANPATH=/share/man"
      "RUSTFLAGS=-Clinker=clang-lld-wrapper"
      "PKG_CONFIG_PATH=/lib/pkgconfig"
      "SHELL=/bin/fish"
      "SSL_CERT_DIR=/etc/ssl/certs"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "CARGO_HTTP_CAINFO=/etc/ssl/certs/ca-bundle.crt"
      "USER=root"
    ] ++ cfg.buildTimeEnv;


  # ---------------------------------------------------------------------------
  # OCI image assembly
  # ---------------------------------------------------------------------------
  image = pkgs.dockerTools.buildLayeredImage {
    name      = cfg.name;
    tag       = "latest";
    maxLayers = if cfg.mode == "minimal" then 60 else 100;

    contents =
      allContents
      ++ [ nixDbRegistration gcRoots ];

    # Materialize /etc identity files as real inodes rather than Nix store
    # symlinks. nerdctl/runc performs a pre-entrypoint root filesystem check
    # that rejects symlinks into the store for these files. Podman and Docker
    # do not perform this check, but materializing real files is correct
    # behavior regardless. start.sh overwrites these at runtime anyway.
    extraCommands = ''
      mkdir -p etc
      install -m 644 ${identity.etcPasswd}/etc/passwd       etc/passwd
      install -m 644 ${identity.etcGroup}/etc/group         etc/group
      install -m 644 ${identity.etcShells}/etc/shells       etc/shells
      install -m 644 ${identity.etcOsRelease}/etc/os-release etc/os-release
      install -m 640 ${identity.etcShadow}/etc/shadow       etc/shadow
      install -m 640 ${identity.etcGshadow}/etc/gshadow     etc/gshadow
    '';

    config = {
      Cmd        = containerCmd;
      User       = containerUser;
      WorkingDir = "/workspace";
      Env        = standardBuildEnv;
      Volumes    = {};
    };
  };

  # ---------------------------------------------------------------------------
  # Host-side dev shell
  # Shares packages and TLS logic but runs on the host, not in the container.
  # ---------------------------------------------------------------------------
  devShell = import ./dev-shell.nix {
    inherit pkgs cfg inputs;
    tlsDerivation = tlsDerivation;
  };

in
  {
    inherit image devShell;

    # Expose internals for composability and debugging
    inherit cfg devEnv closureInfo;
  }
