# polar-container-lib/nix/packages.nix
#
# Concrete package lists for each named PackageLayer.
# This is the single source of truth for what "Core", "Dev", etc. mean
# in terms of actual Nix derivations.
#
# Design notes:
#   - Each set is a function of pkgs and inputs, returning a list.
#   - Sets are intentionally NOT cumulative here — from-dhall.nix handles
#     layer composition by concatenating resolved lists. This keeps each
#     set independently inspectable and testable.
#   - The toolchain (LLVM, Rust) is a separate layer because not every
#     project needs it, and it's large. A documentation site's dev container
#     shouldn't pull in LLVM.
#   - Custom wrappers (clang-lld-wrapper pattern) belong in toolchain,
#     not in a project's extraPackages, if they're generally useful.

{ pkgs
, inputs    # Flake inputs, for layers that draw from external flakes
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Toolchain helpers
  # Defined here so toolchain layer can reference them, and so projects that
  # need a custom linker wrapper can import and reuse the pattern.
  # ---------------------------------------------------------------------------

  rustSysroot = pkgs.buildEnv {
    name  = "rust-sysroot";
    paths = [ pkgs.glibc pkgs.glibc.dev pkgs.gcc.cc.lib ];
  };

  # Wraps clang to always use lld and the correct sysroot.
  # This is the pattern that makes Rust + LLVM work correctly in the container
  # without relying on the host linker. Projects set RUSTFLAGS=-Clinker=clang-lld-wrapper.
  clangLldWrapper = pkgs.writeShellScriptBin "clang-lld-wrapper" ''
    exec ${pkgs.llvmPackages_19.clang}/bin/clang \
      -fuse-ld=lld \
      --sysroot=${rustSysroot} \
      "$@"
  '';

in
{
  # ---------------------------------------------------------------------------
  # Core
  # Minimum viable Linux container. Every container gets this.
  # Includes: init essentials, SSL, nix, coreutils, basic shell.
  # Does NOT include: editors, compilers, interactive tools.
  # ---------------------------------------------------------------------------
  core = with pkgs; [
    bash
    cacert
    coreutils
    findutils
    fish
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
  # Audit and scanning tools shared between developer and CI containers.
  # This is the invariant security layer — running the same tools locally
  # and in CI is the "right-sized devsecops" guarantee.
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
  # Interactive developer experience layer.
  # Assumes Core and CI are also present.
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
  ];

  # ---------------------------------------------------------------------------
  # Toolchain
  # Compiler stack. Separate from Dev because not every container needs it.
  # Includes the clang-lld-wrapper so RUSTFLAGS can reference a stable name.
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

    # Rust nightly with rust-analyzer and wasm target
    (lib.meta.hiPrio (
      inputs.rust-overlay.packages.${pkgs.system}.rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets    = [ "wasm32-unknown-unknown" ];
      }
    ))

    cargo-binutils
  ];

  # ---------------------------------------------------------------------------
  # Pipeline
  # Tools for running automation pipelines.
  # Includes the static analysis suite from the external flake input.
  # ---------------------------------------------------------------------------
  pipeline = with pkgs;
    [
      # Security/quality scanning (also in CI layer, explicit here for clarity
      # when Pipeline is used without CI)
      grype
      syft
      vulnix
    ]
    ++
    # Static analysis tools from external flake input
    lib.optional
      (inputs ? staticanalysis && inputs.staticanalysis.packages ? ${pkgs.system})
      inputs.staticanalysis.packages.${pkgs.system}.default
    ++
    # dotacat (colorized output for pipeline logs)
    lib.optional
      (inputs ? dotacat && inputs.dotacat.packages ? ${pkgs.system})
      inputs.dotacat.packages.${pkgs.system}.default;

  # ---------------------------------------------------------------------------
  # Agent
  # Runtime tooling for autonomous agent containers.
  # Minimal by design — agents should declare their specific needs via Custom.
  # This layer will grow as the agent container pattern matures.
  # ---------------------------------------------------------------------------
  agent = with pkgs; [
    curl
    git
    jq
    openssh
    openssl
  ];
}
