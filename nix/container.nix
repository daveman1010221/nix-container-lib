# polar-container-lib/nix/container.nix
#
# mkContainer: the library's primary entry point.
#
# Takes a pre-rendered Nix file (produced by `dhall-to-nix` from a Dhall
# ContainerConfig) and produces a complete OCI image derivation plus a
# host-side devShell.
#
# PARAMETERS
# ----------
#   pkgs             — nixpkgs instance
#   system           — e.g. "x86_64-linux"
#   inputs           — consuming flake's inputs (for PackageRef resolution)
#   configNixPath    — path to the pre-rendered Nix file (from dhall-to-nix)
#   extraDerivations — optional list of additional derivations to add to the
#                      image's bin environment (e.g. a custom entrypoint binary)
#
# AUTHORING WORKFLOW
# ------------------
# 1. Edit your container.dhall
# 2. Run: just render   (or: dhall-to-nix --file container.dhall > container.nix)
# 3. Commit both container.dhall and container.nix
# 4. nix build — sandbox-safe, no Dhall evaluation at build time
#
# TYPE SAFETY
# -----------
# You still get full Dhall type checking when you run `just render-container`.
# The type errors surface at authoring time, not at Nix build time. The
# committed container.nix is the validated, rendered output.
#
# USAGE IN A PROJECT FLAKE
# ------------------------
#   let
#     lib = inputs.nix-container-lib;
#     container = lib.lib.${system}.mkContainer {
#       inherit system pkgs inputs;
#       configNixPath = ./container.nix;   # pre-rendered from container.dhall
#     };
#   in {
#     packages.devContainer = container.image;
#     devShells.default     = container.devShell;
#   }

{ pkgs
, system
, inputs
, configNixPath
, extraDerivations ? []
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Import and translate config
  # ---------------------------------------------------------------------------
  rawCfg = import configNixPath;
  cfg    = import ./from-dhall.nix { inherit pkgs inputs; cfg = rawCfg; };

  isMinimal = cfg.mode == "minimal";

  # ---------------------------------------------------------------------------
  # Identity & filesystem spine
  # ---------------------------------------------------------------------------
  identity = import ./identity.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Nix-in-Nix infrastructure (mode-aware)
  # ---------------------------------------------------------------------------
  nixInfra = import ./nix-infra.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Package sets (for banner tool list)
  # ---------------------------------------------------------------------------
  packageSets = import ./packages.nix { inherit pkgs inputs; };

  # ---------------------------------------------------------------------------
  # Build the package environment
  # ---------------------------------------------------------------------------
  startScript =
    if isMinimal then null
    else import ./entrypoint.nix { inherit pkgs cfg devEnv; };

  containerHelpScript =
    if isMinimal then null
    else import ./container-help.nix { inherit pkgs cfg; };

  devEnv = pkgs.buildEnv {
    name        = "${cfg.name}-env";
    paths       =
      cfg.packages
      ++ extraDerivations
      # Include shSymlink in devEnv so buildEnv correctly merges /bin/sh
      # alongside other /bin entries. Adding it only to allContents/contents
      # causes buildLayeredImage to see it as a separate layer whose /bin
      # directory doesn't merge with devEnv's /bin symlink farm.
      ++ lib.optional (identity.shSymlink != null) identity.shSymlink
      ++ lib.optionals (!isMinimal) (
           [ startScript containerHelpScript ]
         );
    pathsToLink = [ "/bin" "/lib" "/inc" "/etc/ssl/certs" ];
  };

  # ---------------------------------------------------------------------------
  # Shell files (mode-aware)
  # Minimal shells get minimal configs. Interactive shells get full configs.
  # No shell = no shell files.
  # ---------------------------------------------------------------------------
  shellFiles =
    if cfg.shell == null then []
    else import ./shell.nix { inherit pkgs cfg devEnv; };

  # ---------------------------------------------------------------------------
  # Pipeline runner (non-minimal only)
  # ---------------------------------------------------------------------------
  pipelineFiles =
    if cfg.pipeline != null && !isMinimal
    then import ./pipeline.nix { inherit pkgs cfg; }
    else [];

  # ---------------------------------------------------------------------------
  # TLS certificates (non-minimal only)
  # ---------------------------------------------------------------------------
  tlsDerivation =
    if cfg.tls != null && cfg.tls.generateCerts && !isMinimal
    then import ./gen-certs.nix { inherit pkgs cfg; }
    else null;

  # ---------------------------------------------------------------------------
  # SBOM — generated from closure, embedded in image
  # ---------------------------------------------------------------------------
  # We generate the SBOM after assembling allContents so the closure is complete.
  # The SBOM derivation references closureInfo which is computed below.
  # To break the circularity, we compute a preliminary closure for SBOM purposes.
  preliminaryContents =
    [ devEnv ]
    ++ shellFiles
    ++ pipelineFiles
    ++ nixInfra.configFiles
    ++ [ nixInfra.ldLinker nixInfra.usrBinEnv nixInfra.fhsDirs ]
    ++ lib.optional (tlsDerivation != null) tlsDerivation;

  preliminaryClosureInfo = pkgs.closureInfo {
    rootPaths = preliminaryContents ++ identity.baseInfo;
  };

  sbom = import ./sbom.nix {
    inherit pkgs cfg;
    closureInfo = preliminaryClosureInfo;
  };

  # ---------------------------------------------------------------------------
  # Container info banner
  # ---------------------------------------------------------------------------
  containerInfo = import ./banner.nix {
    inherit pkgs cfg packageSets;
  };

  # ---------------------------------------------------------------------------
  # Full contents list
  # ---------------------------------------------------------------------------
  allContents =
    preliminaryContents
    ++ [ sbom containerInfo ];

  # ---------------------------------------------------------------------------
  # Nix DB and GC roots (non-minimal)
  # ---------------------------------------------------------------------------
  closureInfo = pkgs.closureInfo {
    rootPaths = allContents ++ identity.baseInfo;
  };

  nixDbRegistration =
    if isMinimal then null
    else pkgs.runCommand "nix-db-registration" {} ''
      mkdir -p $out/nix/var/nix/db
      export NIX_REMOTE=local?root=$out
      ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo}/registration
    '';

  gcRoots =
    if isMinimal then null
    else import ./gc-roots.nix { inherit pkgs allContents; };

  # ---------------------------------------------------------------------------
  # OCI User field
  # ---------------------------------------------------------------------------
  containerUser =
    if cfg.staticUid != null && cfg.staticGid != null
    then "${toString cfg.staticUid}:${toString cfg.staticGid}"
    else "0:0";

  # ---------------------------------------------------------------------------
  # OCI Cmd
  #
  # Minimal mode priority:
  #   1. Explicit entrypoint → /bin/<entrypoint>
  #   2. Shell → shell binary path
  # Non-minimal: always start.sh
  # ---------------------------------------------------------------------------
  containerCmd =
    if isMinimal then
      if cfg.entrypoint != null then
        [ "/bin/${cfg.entrypoint}" ]
      else if cfg.shell != null then
        [ cfg.shell.shell ]
      else
        throw "container.nix: minimal mode requires entrypoint or shell"
    else
      [ "/bin/start.sh" ];

  # ---------------------------------------------------------------------------
  # Build-time env
  # ---------------------------------------------------------------------------
  minimalBuildEnv =
    [ "PATH=/bin:/usr/bin" ]
    ++ lib.optionals (cfg.shell != null) [
      "SHELL=${cfg.shell.shell}"
    ]
    ++ cfg.buildTimeEnv;

  standardBuildEnv =
    [ "PATH=/bin:/usr/bin:/root/.cargo/bin"
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
      "SHELL=${if cfg.shell != null then cfg.shell.shell else "/bin/fish"}"
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
    maxLayers = if isMinimal then 10 else 20;

    contents =
      allContents
      ++ lib.optionals (!isMinimal) [
           nixDbRegistration
           gcRoots
         ];

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
      Env        = if isMinimal then minimalBuildEnv else standardBuildEnv;
      Volumes    = {};
      Labels     = {
        "org.opencontainers.image.title"   = cfg.name;
        "org.opencontainers.image.created" = "1970-01-01T00:00:00Z";
        "org.opencontainers.image.vendor"  = "nix-container-lib";
        "org.opencontainers.image.sbom"    = "/_manifest/spdx.json";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Host-side dev shell (non-minimal)
  # ---------------------------------------------------------------------------
  devShell = import ./dev-shell.nix {
    inherit pkgs cfg inputs;
    tlsDerivation = tlsDerivation;
  };

in
  {
    inherit image devShell;
    inherit cfg devEnv closureInfo;
  }
