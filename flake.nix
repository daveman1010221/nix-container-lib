{
  description = "nix-container-lib: typed, composable OCI dev container library";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    uutils-micro.url = "github:daveman1010221/uutils-micro/7cda0210b076f384906d189171c065a1884cad96";
    uutils-micro.inputs.nixpkgs.follows = "nixpkgs";
    uutils-micro.inputs.flake-utils.follows = "flake-utils";
    vigil-rs.url = "github:daveman1010221/vigil-rs-nix";
    vigil-rs.inputs.nixpkgs.follows = "nixpkgs";
    vigil-rs.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, uutils-micro, vigil-rs }:
    let
      # -------------------------------------------------------------------------
      # System-independent outputs
      # -------------------------------------------------------------------------
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
        minimal = {
          path        = ./templates/minimal;
          description = "Minimal single-binary container";
        };
      };

      # Dhall library paths — for consumers who want to import the types/defaults
      # directly from Nix without going through mkContainer.
      dhall = {
        prelude  = ./dhall/prelude.dhall;
        types    = ./dhall/types.dhall;
        defaults = ./dhall/defaults.dhall;
      };

    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        lib = {
          mkContainer = import ./nix/container.nix;
          fromDhall  = import ./nix/from-dhall.nix;
          packages   = import ./nix/packages.nix;
          entrypoint = import ./nix/entrypoint.nix;
          identity   = import ./nix/identity.nix;
          nixInfra   = import ./nix/nix-infra.nix;
          shell      = import ./nix/shell.nix;
          pipeline   = import ./nix/pipeline.nix;
          gcRoots    = import ./nix/gc-roots.nix;
        };

        legacyPackages.smokeTest = (import ./nix/container.nix {
          inherit system pkgs;
          inputs      = { inherit uutils-micro vigil-rs; };
          configNixPath = ./smoke-test.nix;
        }).image;

        devShells.default = pkgs.mkShell {
          name = "nix-container-lib-dev";

          packages = with pkgs; [
            dhall-json
            dhall-nix
            nix
            nix-prefetch-git
            just
            jq
            git
          ];

          shellHook = ''
            echo "nix-container-lib dev shell"
            echo ""
            echo "Dhall commands:"
            echo "  just render-container        render container.dhall → container.nix"
            echo "  just render-smoke-test       render smoke-test.dhall → smoke-test.nix"
            echo "  just check-dhall             type-check all .dhall files"
            echo ""
            echo "Nix commands:"
            echo "  nix build .#smokeTest        build smoke test image"
            echo "  nix flake check              check flake outputs"
          '';
        };
      }
    ))
    // { inherit templates dhall; };
}
