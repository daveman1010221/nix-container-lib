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
        # -----------------------------------------------------------------------
        # Library functions — primary API surface for consuming flakes.
        #
        # Usage:
        #   inputs.polar-container-lib.lib.${system}.mkContainer {
        #     inherit system pkgs inputs;
        #     configPath = ./container.dhall;
        #   }
        # -----------------------------------------------------------------------
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

        # -----------------------------------------------------------------------
        # Smoke test
        # Exercises the full mkContainer evaluation chain against a real Dhall
        # config. Uses the CI archetype — minimal package set, no optional
        # subsystems — to keep build time short while still exercising the full
        # path: dhallToNix → from-dhall → identity → nix-infra → packages →
        # entrypoint → gc-roots → buildLayeredImage.
        #
        # Build with: nix build .#smokeTest
        # -----------------------------------------------------------------------
        legacyPackages.smokeTest = (import ./nix/container.nix {
          inherit system pkgs;
          inputs     = { };   # Core + CI layers need no external flake inputs
          configPath = ./smoke-test.dhall;
        }).image;

        # -----------------------------------------------------------------------
        # Library development shell
        # For working on the library itself. Provides Dhall tooling for type-
        # checking configs and translating to Nix, plus nix for builds.
        #
        # Enter with: nix develop
        # -----------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "polar-container-lib-dev";

          packages = with pkgs; [
            # Dhall tooling
            dhall           # type-check and evaluate .dhall files
            dhall-json      # dhall-to-json, json-to-dhall
            dhall-yaml      # dhall-to-yaml, yaml-to-dhall
            dhall-nix       # dhall-to-nix (the bridge used by mkContainer)

            # Nix tooling
            nixVersions.stable  # ensure a modern nix is available
            nix-prefetch-git    # useful for updating flake input revisions

            # General dev tools
            jq    # inspect generated pipeline.json manifests
            git
          ];

          shellHook = ''
            echo "polar-container-lib dev shell"
            echo ""
            echo "Available commands:"
            echo "  dhall type --file dhall/types.dhall     type-check types"
            echo "  dhall type --file dhall/defaults.dhall  type-check defaults"
            echo "  dhall type --file dhall/prelude.dhall   type-check prelude"
            echo "  dhall type --file smoke-test.dhall      type-check smoke test"
            echo "  nix build .#smokeTest                   build smoke test image"
            echo "  nix flake check                         check flake outputs"
          '';
        };
      }
    ))
    // { inherit templates dhall; };
}
