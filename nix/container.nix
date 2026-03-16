# polar-container-lib/nix/container.nix
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
  # Evaluate the Dhall config to a Nix attrset
  # dhallToNix is available in nixpkgs as pkgs.dhallToNix.
  # The result is a Nix value with the same structure as the Dhall type.
  # ---------------------------------------------------------------------------
  rawCfg = (pkgs.dhallToNix configPath).result;

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
  nixInfra = import ./nix-infra.nix { inherit pkgs cfg; };

  # ---------------------------------------------------------------------------
  # Build the package environment
  # ---------------------------------------------------------------------------
  startScript    = import ./entrypoint.nix { inherit pkgs cfg devEnv; };
  polarHelpScript = import ./polar-help.nix { inherit pkgs cfg; };

  devEnv = pkgs.buildEnv {
    name         = "${cfg.name}-env";
    paths        = cfg.packages ++ [ startScript polarHelpScript ];
    pathsToLink  = [ "/bin" "/lib" "/inc" "/etc/ssl/certs" ];
  };

  # ---------------------------------------------------------------------------
  # Shell environment (optional)
  # Only assembled when cfg.shell != null
  # ---------------------------------------------------------------------------
  shellFiles =
    if cfg.shell != null
    then import ./shell.nix { inherit pkgs cfg devEnv; }
    else [];

  # ---------------------------------------------------------------------------
  # Pipeline runner (optional)
  # Only assembled when cfg.pipeline != null
  # ---------------------------------------------------------------------------
  pipelineFiles =
    if cfg.pipeline != null
    then import ./pipeline.nix { inherit pkgs cfg; }
    else [];

  # ---------------------------------------------------------------------------
  # TLS certificates (optional)
  # ---------------------------------------------------------------------------
  tlsDerivation =
    if cfg.tls != null && cfg.tls.generateCerts
    then pkgs.callPackage ./gen-certs.nix {}
    else null;

  # ---------------------------------------------------------------------------
  # Nix DB and GC roots
  # The full set of derivations that need to be registered and protected.
  # ---------------------------------------------------------------------------
  allContents =
    identity.baseInfo
    ++ [ devEnv ]
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
    rootPaths = allContents;
  };

  nixDbRegistration = pkgs.runCommand "nix-db-registration" {} ''
    mkdir -p $out/nix/var/nix/db
    export NIX_REMOTE=local?root=$out
    ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo}/registration
  '';

  gcRoots = import ./gc-roots.nix {
    inherit pkgs allContents;
    extraRoots = nixInfra.configFiles;
  };

  # ---------------------------------------------------------------------------
  # Standard build-time environment variables (safe for config.Env)
  # These never contain store paths — see EnvVarPlacement documentation.
  # ---------------------------------------------------------------------------
  standardBuildEnv = [
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
    maxLayers = 100;

    contents =
      allContents
      ++ [ nixDbRegistration gcRoots ];

    config = {
      WorkingDir = "/workspace";
      Env        = standardBuildEnv;
      Cmd        = [ "/bin/start.sh" ];
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
