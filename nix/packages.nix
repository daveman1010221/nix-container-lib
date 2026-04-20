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
    [ cacert
      coreutils
      findutils
      getent
      glibcLocalesUtf8
      gnutar
      gzip
      nix
      openssl
      uutils-coreutils-noprefix
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
    gnugrep
    gnused
    grype
    jq
    oras
    skopeo
    sops
    syft
    vulnix
    yq
  ];

  # ---------------------------------------------------------------------------
  # Dev
  # vigil CLI included for interactive control of supervised services.
  # ---------------------------------------------------------------------------
  dev = with pkgs;
    [ atuin
      bat
      cowsay
      delta
      direnv
      eza
      fd
      figlet
      fish
      fishPlugins.bass
      fishPlugins.bobthefish
      fishPlugins.foreign-env
      fishPlugins.grc
      fzf
      gawk
      git
      grc
      iproute2
      jq
      just
      lsof
      man
      man-db
      man-pages
      man-pages-posix
      ncurses
      procps
      ripgrep
      rsync
      sqlite
      starship
      strace
      tree
      tree-sitter
      which
      openssh
      nushell
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
  toolchain = with pkgs; [
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
  # Pipeline
  # ---------------------------------------------------------------------------
  pipeline = with pkgs;
    [ grype syft vulnix nushell ]
    ++ lib.optional
         (inputs ? staticanalysis && inputs.staticanalysis.packages ? ${pkgs.system})
         inputs.staticanalysis.packages.${pkgs.system}.default
    ++ lib.optional
         (inputs ? dotacat && inputs.dotacat.packages ? ${pkgs.system})
         inputs.dotacat.packages.${pkgs.system}.default;

  # ---------------------------------------------------------------------------
  # Agent
  # ---------------------------------------------------------------------------
  agent = with pkgs; [
    curl
    git
    jq
    openssh
    openssl
  ];

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
