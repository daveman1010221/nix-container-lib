{
  description = "polar-container-lib: typed, composable OCI dev container library";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url  = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # ---------------------------------------------------------------------------
        # Library functions
        # The primary API surface for consuming flakes.
        #
        # Usage:
        #   inputs.polar-container-lib.lib.${system}.mkContainer { ... }
        # ---------------------------------------------------------------------------
        lib = {

          # mkContainer: full container + devShell from a Dhall config path
          mkContainer = import ./nix/container.nix;

          # Escape hatches: individual nix functions for advanced composition
          fromDhall  = import ./nix/from-dhall.nix;
          packages   = import ./nix/packages.nix;
          entrypoint = import ./nix/entrypoint.nix;
          identity   = import ./nix/identity.nix;
          nixInfra   = import ./nix/nix-infra.nix;
          shell      = import ./nix/shell.nix;
          pipeline   = import ./nix/pipeline.nix;
          gcRoots    = import ./nix/gc-roots.nix;
        };

        # ---------------------------------------------------------------------------
        # Flake templates
        # nix flake init -t github:your-org/polar-container-lib#dev
        # nix flake init -t github:your-org/polar-container-lib#ci
        # nix flake init -t github:your-org/polar-container-lib#agent
        # ---------------------------------------------------------------------------
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

        # ---------------------------------------------------------------------------
        # The Dhall library path
        # Consumers can reference individual type files:
        #   inputs.polar-container-lib.dhall.${system}.prelude
        # ---------------------------------------------------------------------------
        dhall = {
          prelude  = ./dhall/lib/prelude.dhall;
          types    = ./dhall/lib/types.dhall;
          defaults = ./dhall/lib/defaults.dhall;
        };
      }
    );
}
