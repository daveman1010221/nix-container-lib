{
  description = "nix-container-lib: typed, composable OCI dev container library";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    uutils-micro.url = "github:daveman1010221/uutils-micro/7cda0210b076f384906d189171c065a1884cad96";
    uutils-micro.inputs.nixpkgs.follows = "nixpkgs";
    uutils-micro.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, uutils-micro }:
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
        # -----------------------------------------------------------------------
        # Library functions — primary API surface for consuming flakes.
        #
        # AUTHORING WORKFLOW (dhall → nix → build):
        #
        #   1. Write your container config in Dhall:
        #        container.dhall
        #
        #   2. Pre-render to Nix OUTSIDE the sandbox:
        #        just render-container
        #        # or: dhall-to-nix --file container.dhall > container.nix
        #
        #   3. Commit both files.
        #
        #   4. Reference the rendered file in your flake:
        #        mkContainer { ...; configNixPath = ./container.nix; }
        #
        # WHY NOT dhallToNix AT BUILD TIME?
        #   Dhall's import system resolves dependencies at evaluation time.
        #   The Nix sandbox has no network access, so any Dhall file that
        #   imports from a URL (including the nix-container-lib prelude) fails.
        #   Pre-rendering moves the Dhall evaluation to authoring time where
        #   full filesystem and network access is available.
        # -----------------------------------------------------------------------
        lib = {
          # Primary entry point. Takes a pre-rendered Nix path.
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

        # -----------------------------------------------------------------------
        # Smoke test
        # Uses a pre-rendered smoke-test.nix (produced from smoke-test.dhall).
        # Build with: nix build .#smokeTest
        # Re-render with: just render-smoke-test
        # -----------------------------------------------------------------------
        legacyPackages.smokeTest = (import ./nix/container.nix {
          inherit system pkgs;
          inputs      = {};
          configNixPath = ./smoke-test.nix;
        }).image;

        # -----------------------------------------------------------------------
        # Library development shell
        # Provides Dhall tooling for type-checking and rendering configs.
        # Enter with: nix develop
        # -----------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "nix-container-lib-dev";

          packages = with pkgs; [
            # Dhall tooling
            # dhall        # type-checker and REPL
            dhall-json   # dhall-to-json, dhall-to-yaml
            dhall-nix    # dhall-to-nix  ← renders .dhall → .nix for sandbox-safe builds

            # Nix tooling
            nix
            nix-prefetch-git
            just         # for the render-* recipes

            # General dev tools
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
