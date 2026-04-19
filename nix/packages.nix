# polar-container-lib/nix/packages.nix
#
# Concrete package lists for each named PackageLayer.
# This is the single source of truth for what "Micro", "Core", "Dev", etc.
# mean in terms of actual Nix derivations.
#
# Layer hierarchy (each is independent — from-dhall.nix composes them):
#
#   Micro       — Absolute minimum for a functional OCI container.
#                 No shell, no Nix, no locales. Just enough to exec a binary.
#                 Use as the base for minimal containers.
#
#   Core        — Practical container baseline. Micro + compression tools,
#                 full uutils, glibc locales. Use for containers that need
#                 general-purpose POSIX utilities but not a full dev env.
#
#   CI          — Audit and scanning tools. Language-agnostic security layer.
#
#   Dev         — Full interactive developer experience. Assumes Core + CI.
#
#   Toolchain   — LLVM + Rust compiler stack. Heavy. Only for build containers.
#
#   Pipeline    — Static analysis and artifact tooling.
#
#   Agent       — Minimal runtime tooling for autonomous agent containers.
#
# Shell packages are NOT in any layer — they are added by from-dhall.nix
# when cfg.shell is set, using shell-specific subsets defined below.
# This ensures no shell binary sneaks into a container that doesn't want one.

{ pkgs
, inputs
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Toolchain helpers (used by Toolchain layer)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Shell-specific uutils subsets
  #
  # Built from source with only the tools each shell context actually needs.
  # dash users get a POSIX-baseline set. nu users get that plus tools that
  # complement nushell's built-ins when shelling out.
  #
  # We build with --no-default-features + explicit feature flags so only
  # the requested tools are compiled into the multicall binary.
  #
  # The feature names correspond to uutils tool names (lowercase, no prefix).
  # ---------------------------------------------------------------------------

  # Shell-specific uutils — use full package for now.
  # TODO: build with specific cargo features per shell type for true minimalism.
  dashUutils  = pkgs.uutils-coreutils-noprefix;
  nuMinUutils = pkgs.uutils-coreutils-noprefix;

in
{
  # ---------------------------------------------------------------------------
  # Micro
  # Absolute minimum for OCI compliance. Every minimal container uses this.
  # No shells. No Nix. No locales. No compression tools.
  # Just: SSL certs, basic POSIX utilities, user/group lookup, TLS library.
  # ---------------------------------------------------------------------------
  micro = with pkgs; [
    cacert
    uutils-coreutils-noprefix
    getent
    openssl
  ];

  # ---------------------------------------------------------------------------
  # Core
  # Practical container baseline. Micro + compression + full uutils + locales.
  # Use for containers that need general-purpose POSIX utilities.
  # ---------------------------------------------------------------------------
  core = with pkgs; [
    cacert
    coreutils
    findutils
    getent
    glibcLocalesUtf8
    gnutar
    gzip
    nix
    openssl
    uutils-coreutils-noprefix
  ];

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
  # ---------------------------------------------------------------------------
  dev = with pkgs; [
    atuin
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
  ];

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
  # Exported for use by from-dhall.nix when resolving shell configs.
  # Not referenced by any PackageLayer — always added explicitly.
  # ---------------------------------------------------------------------------

  # Minimal dash (POSIX sh)
  shellDash = [
    pkgs.dash
    dashUutils
  ];

  # Minimal nushell — just the binary + its minimal uutils complement
  shellNuMinimal = [
    pkgs.nushell
    nuMinUutils
  ];

  # Full interactive fish — binary + plugins + all interactive tools
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

  # Full interactive nushell — binary + plugins + all interactive tools
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

  # Expose the custom uutils derivations for shell modules that need them
  inherit dashUutils nuMinUutils;
}
