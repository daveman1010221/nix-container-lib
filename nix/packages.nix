# polar-container-lib/nix/packages.nix
#
# Concrete package lists for each named PackageLayer.

{ pkgs
, inputs
}:

let
  lib = pkgs.lib;

  rustSysroot = pkgs.buildEnv {
    name  = "rust-sysroot";
    paths = [ pkgs.glibc pkgs.glibc.dev pkgs.gcc.cc.lib ];
  };

  clangLldWrapper = pkgs.writeShellScriptBin "clang-lld-wrapper" ''
    exec ${pkgs.llvmPackages_19.clang}/bin/clang \
      -fuse-ld=lld \
      --sysroot=${rustSysroot} \
      "$@"
  '';

  dashUutils  = inputs.uutils-micro.packages.${pkgs.system}.default or pkgs.uutils-coreutils-noprefix;
  nuMinUutils = inputs.uutils-micro.packages.${pkgs.system}.default or pkgs.uutils-coreutils-noprefix;

  # vigil-rs packages — vigild in core, vigil CLI in dev
  vigild = inputs.vigil-rs.packages.${pkgs.system}.vigild or null;
  vigilCli = inputs.vigil-rs.packages.${pkgs.system}.vigil or null;

in
{
  # ---------------------------------------------------------------------------
  # Micro
  # ---------------------------------------------------------------------------
  micro = with pkgs; [
    cacert
    (inputs.uutils-micro.packages.${pkgs.system}.default or pkgs.uutils-coreutils-noprefix)
    getent
    openssl
  ];

  # ---------------------------------------------------------------------------
  # Core
  # vigild is included here so all non-minimal containers have the supervisor.
  # ---------------------------------------------------------------------------
  core = with pkgs;
  [ fd
    glibcLocalesUtf8
    gnutar
    gzip
    nix
    nushell
  ]
  ++ lib.optional (vigild != null) vigild;

  # ---------------------------------------------------------------------------
  # CI
  # ---------------------------------------------------------------------------
  ci = with pkgs; [
    curl
    dhall
    dhall-json
    dhall-yaml
    envsubst
    git
    grype
    oras
    skopeo
    sops
    syft
    vulnix
  ];

  # ---------------------------------------------------------------------------
  # Dev
  # vigil CLI included for interactive control of supervised services.
  # ---------------------------------------------------------------------------
  interactiveDev = with pkgs;
  [ atuin
    bat
    cowsay
    delta
    direnv
    eza
    figlet
    fish
    fishPlugins.bass
    fishPlugins.bobthefish
    fishPlugins.foreign-env
    fishPlugins.grc
    fzf
    grc
    iproute2
    jq
    just
    lsof
    openssh
    procps
    ripgrep
    rsync
    sqlite
    starship
    strace
    tree
    tree-sitter
    nushellPlugins.query
    nushellPlugins.formats
    nushellPlugins.gstat
    nushellPlugins.highlight
    nushellPlugins.polars
    nushellPlugins.semver
  ]
  ++ [ (if pkgs ? nvim-pkg then pkgs.nvim-pkg else pkgs.neovim) ]
  ++ lib.optional (vigilCli != null) vigilCli;

  # ---------------------------------------------------------------------------
  # Toolchain
  # ---------------------------------------------------------------------------
  rustToolchain = with pkgs; [
    bzip2
    clangLldWrapper
    cmake
    glibc
    gnumake
    lz4
    pkg-config
    pkgs.llvmPackages_19.clang
    pkgs.llvmPackages_19.lld
    snappy
    util-linux
    zlib
    zstd
    (lib.meta.hiPrio (
      pkgs.rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets    = [ "wasm32-unknown-unknown" ];
      }
    ))
    cargo-binutils
  ];

  # ---------------------------------------------------------------------------
  # Python toolchain
  # ---------------------------------------------------------------------------
  pythonToolchain = with pkgs; [
    python3
    python3Packages.pip
    python3Packages.virtualenv
    uv
  ];

  # ---------------------------------------------------------------------------
  # Node toolchain
  # ---------------------------------------------------------------------------
  nodeToolchain = with pkgs; [
    nodejs
    nodePackages.npm
    nodePackages.typescript
    nodePackages.yarn
  ];

  # ---------------------------------------------------------------------------
  # Infrastructure
  # Tools for containers that interact with cluster infrastructure.
  # ---------------------------------------------------------------------------
  infrastructure = with pkgs; [
    curl
    git
    jq
    kubectl
    openssl
    sops
    skopeo
    oras
  ]
  ++ lib.optional
       (inputs ? cassini-client && inputs.cassini-client.packages ? ${pkgs.system})
       inputs.cassini-client.packages.${pkgs.system}.default;

  # ---------------------------------------------------------------------------
  # Shell package sets
  # ---------------------------------------------------------------------------
  shellDash = [
    pkgs.dash
    dashUutils
  ];

  shellNuMinimal = [
    pkgs.nushell
    nuMinUutils
  ];

  shellFishInteractive = with pkgs; [
    fish
    fishPlugins.bass
    fishPlugins.bobthefish
    fishPlugins.foreign-env
    fishPlugins.grc
    atuin
    starship
    direnv
  ];

  shellNuInteractive = with pkgs; [
    nushell
    nushellPlugins.query
    nushellPlugins.formats
    nushellPlugins.gstat
    nushellPlugins.highlight
    nushellPlugins.polars
    nushellPlugins.semver
    atuin
    starship
    direnv
  ];

  inherit dashUutils nuMinUutils;
}
