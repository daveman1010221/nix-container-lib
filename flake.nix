{
  description = "polar-container-lib: typed, composable OCI dev container library";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # -------------------------------------------------------------------------
      # System-independent outputs
      # Templates and dhall paths do not vary by architecture — lifted outside
      # eachDefaultSystem so nix flake check doesn't treat them as per-system.
      # -------------------------------------------------------------------------

      # Flake templates
      # Usage: nix flake init -t github:your-org/polar-container-lib#dev
      templates = {
        dev = {
          path        = ./templates/dev;
          description = "Interactive developer container with full toolchain";
        };
        ci = {
          path        = ./templates/ci;
          description = "Headless CI container with pipeline runner";
        };
        agent = {
          path        = ./templates/agent;
          description = "Autonomous agent container with mTLS";
        };
      };

      # Dhall library paths
      # Usage: inputs.polar-container-lib.dhall.prelude
      dhall = {
        prelude  = ./dhall/prelude.dhall;
        types    = ./dhall/types.dhall;
        defaults = ./dhall/defaults.dhall;
      };

    in
    # -------------------------------------------------------------------------
    # System-specific outputs merged with top-level outputs
    # -------------------------------------------------------------------------
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # Library functions — primary API surface for consuming flakes.
        #
        # Usage:
        #   inputs.polar-container-lib.lib.${system}.mkContainer {
        #     inherit system pkgs inputs;
        #     configPath = ./container.dhall;
        #   }
        lib = {
          mkContainer = import ./nix/container.nix;

          # Escape hatches for advanced composition
          fromDhall  = import ./nix/from-dhall.nix;
          packages   = import ./nix/packages.nix;
          entrypoint = import ./nix/entrypoint.nix;
          identity   = import ./nix/identity.nix;
          nixInfra   = import ./nix/nix-infra.nix;
          shell      = import ./nix/shell.nix;
          pipeline   = import ./nix/pipeline.nix;
          gcRoots    = import ./nix/gc-roots.nix;
        };
      }
    ))
    // { inherit templates dhall; };
}
