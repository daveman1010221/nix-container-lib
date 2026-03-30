# nix-container-lib/nix/container.nix
#
# mkContainer: the library's primary entry point.
#
# Takes a pre-rendered Nix file (produced by `dhall-to-nix` from a Dhall
# ContainerConfig) and produces a complete OCI image derivation plus a
# host-side devShell.
#
# WHY PRE-RENDERED?
# -----------------
# Nix sandbox builds have no network access. `pkgs.dhallToNix` evaluates Dhall
# at build time and Dhall's import system attempts network resolution for any
# library imports (including the nix-container-lib prelude). This causes builds
# to fail in the sandbox.
#
# The solution: evaluate Dhall to Nix BEFORE the build, outside the sandbox,
# using the `just render-container` recipe (which shells out to `dhall-to-nix`).
# The resulting `.nix` file is committed alongside the `.dhall` source and
# imported directly here — no Dhall runtime involved in the build at all.
#
# AUTHORING WORKFLOW
# ------------------
# 1. Edit your container.dhall
# 2. Run: just render-container   (or: dhall-to-nix --file container.dhall > container.nix)
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
, inputs       # The consuming flake's inputs (for PackageRef resolution)
, configNixPath  # Path to the pre-rendered Nix file (from dhall-to-nix)
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Import the pre-rendered Nix config.
  # This is a pure Nix import — no Dhall runtime, no network, sandbox-safe.
  # The file was produced by: dhall-to-nix --file container.dhall > container.nix
  # ---------------------------------------------------------------------------
  rawCfg = import configNixPath;

  # ---------------------------------------------------------------------------
  # Translate the raw Dhall-to-Nix output to the internal config structure
  # ---------------------------------------------------------------------------
  cfg = import ./from-dhall.nix { inherit pkgs inputs; cfg = rawCfg; };

  # ---------------------------------------------------------------------------
  # Identity & filesystem spine
  # ---------------------------------------------------------------------------
  identity = import ./identity.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Nix-in-Nix infrastructure
  # ---------------------------------------------------------------------------
  nixInfra = import ./nix-infra.nix { inherit pkgs system cfg; };

  # ---------------------------------------------------------------------------
  # Build the package environment
  # ---------------------------------------------------------------------------
  startScript         = import ./entrypoint.nix { inherit pkgs cfg devEnv; };
  containerHelpScript = import ./container-help.nix { inherit pkgs cfg; };

  devEnv = pkgs.buildEnv {
    name        = "${cfg.name}-env";
    paths       = cfg.packages
                  ++ lib.optionals (cfg.mode != "minimal")
                       [ startScript containerHelpScript ];
    pathsToLink = [ "/bin" "/lib" "/inc" "/etc/ssl/certs" ];
  };

  # ---------------------------------------------------------------------------
  # Shell environment (optional)
  # ---------------------------------------------------------------------------
  shellFiles =
    if cfg.shell != null && cfg.mode != "minimal"
    then import ./shell.nix { inherit pkgs cfg devEnv; }
    else [];

  # ---------------------------------------------------------------------------
  # Pipeline runner (optional)
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

  closureInfo = pkgs.closureInfo {
    rootPaths = allContents ++ identity.baseInfo;
  };

  nixDbRegistration = pkgs.runCommand "nix-db-registration" {} ''
    mkdir -p $out/nix/var/nix/db
    export NIX_REMOTE=local?root=$out
    ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo}/registration
  '';

  gcRoots = import ./gc-roots.nix { inherit pkgs allContents; };

  # ---------------------------------------------------------------------------
  # OCI User field
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
  # ---------------------------------------------------------------------------
  containerCmd =
    if cfg.mode == "minimal"
    then [ "/bin/${cfg.entrypoint}" ]
    else [ "/bin/start.sh" ];

  # ---------------------------------------------------------------------------
  # Build-time env
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
    maxLayers = if cfg.mode == "minimal" then 60 else 100;

    contents =
      allContents
      ++ [ nixDbRegistration gcRoots ];

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
