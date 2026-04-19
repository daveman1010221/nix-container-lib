# polar-container-lib/nix/identity.nix
#
# Produces the minimum set of files that make a container a valid Linux
# system, independent of any tools being installed.
#
# Outputs:
#   result.baseInfo   — list of derivations for image contents
#   result.etcPasswd  — /etc/passwd (root only at build time)
#   result.etcGroup   — /etc/group
#   result.etcShadow  — /etc/shadow
#   result.etcGshadow — /etc/gshadow
#   result.etcShells  — /etc/shells (derived from shell config, not hardcoded)
#   result.etcOsRelease — /etc/os-release
#   result.shSymlink  — /bin/sh → bash symlink (when bash is the root shell)

{ pkgs
, system
, cfg
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # OS identity
  # ---------------------------------------------------------------------------
  osReleaseText = ''
    NAME="NixOS"
    ID=nixos
    VERSION="unstable"
    VERSION_CODENAME=unstable
    PRETTY_NAME="NixOS (unstable)"
    HOME_URL="https://nixos.org/"
    SUPPORT_URL="https://nixos.org/nixos/manual/"
    BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
  '';

  # ---------------------------------------------------------------------------
  # Root shell selection
  #
  # For minimal containers: use the configured shell if set, otherwise
  # fall back to bash (it will be a transitive dep anyway).
  # For non-minimal: always bash for root — the dev user gets fish/nu
  # via start.sh after user creation.
  # ---------------------------------------------------------------------------
  rootShell =
    if cfg.mode == "minimal" && cfg.shell != null then
      cfg.shell.shell
    else
      "${pkgs.bash}/bin/bash";

  # ---------------------------------------------------------------------------
  # User database — root only at build time
  # ---------------------------------------------------------------------------
  passwdText    = "root:x:0:0::/root:${rootShell}\n";
  shadowText    = "root:!x:::::::\n";
  groupText     = "root:x:0:\n";
  gshadowText   = "root:x::\n";

  # ---------------------------------------------------------------------------
  # Registered shells
  #
  # /etc/shells lists shells valid for login. We derive this strictly from
  # what the container is configured to have — no hardcoded bash/sh fallbacks.
  #
  # Rules:
  #   - shell = None           → empty (no login shells registered)
  #   - shell = Minimal dash   → /bin/sh, /bin/dash
  #   - shell = Minimal nu     → /bin/nu
  #   - shell = Interactive *  → the configured shell binary
  #
  # bash and sh are NOT unconditionally added. If bash lands as a transitive
  # dep but was not requested as a shell, it should not be a registered login
  # shell. That's a security posture decision, not an oversight.
  # ---------------------------------------------------------------------------
  registeredShells =
    if cfg.shell == null then
      []
    else if cfg.shell.type == "minimal-dash" then
      [ "/bin/sh" "/bin/dash" ]
    else if cfg.shell.type == "minimal-nu" then
      [ "/bin/nu" ]
    else if cfg.shell.type == "interactive-fish" then
      [ "/bin/fish" ]
    else if cfg.shell.type == "interactive-nu" then
      [ "/bin/nu" ]
    else
      [];

  shellsText = lib.concatStringsSep "\n" registeredShells
    + (if registeredShells != [] then "\n" else "");

  # ---------------------------------------------------------------------------
  # /bin/sh symlink
  #
  # Many scripts and tools assume /bin/sh exists. For non-minimal containers
  # where bash is the root shell, we create a /bin/sh → bash symlink.
  # For minimal containers:
  #   - dash mode: dash provides /bin/sh natively
  #   - nu mode: no /bin/sh (nushell is not POSIX sh compatible)
  #   - no shell: no /bin/sh
  # ---------------------------------------------------------------------------
  shSymlink =
    if cfg.mode != "minimal" then
      pkgs.runCommand "sh-symlink" {} ''
        mkdir -p $out/bin
        ln -s ${pkgs.bash}/bin/bash $out/bin/sh
      ''
    else if cfg.shell != null && cfg.shell.type == "minimal-dash" then
      pkgs.runCommand "sh-symlink-dash" {} ''
        mkdir -p $out/bin
        ln -s ${pkgs.dash}/bin/dash $out/bin/sh
      ''
    else
      null;

  # ---------------------------------------------------------------------------
  # Derivations
  # ---------------------------------------------------------------------------
  etcPasswd    = pkgs.writeTextDir "etc/passwd"     passwdText;
  etcShadow    = pkgs.writeTextDir "etc/shadow"     shadowText;
  etcGroup     = pkgs.writeTextDir "etc/group"      groupText;
  etcGshadow   = pkgs.writeTextDir "etc/gshadow"    gshadowText;
  etcShells    = pkgs.writeTextDir "etc/shells"     shellsText;
  etcOsRelease = pkgs.writeTextDir "etc/os-release" osReleaseText;

  rootHome = pkgs.runCommand "root-home" {} ''
    mkdir -p $out/root
    chmod 700 $out/root
  '';

in
{
  inherit etcPasswd etcShadow etcGroup etcGshadow etcShells etcOsRelease rootHome;
  inherit shSymlink;

  baseInfo =
    [ etcPasswd etcShadow etcGroup etcGshadow etcShells etcOsRelease rootHome ]
    ++ lib.optional (shSymlink != null) shSymlink;
}
