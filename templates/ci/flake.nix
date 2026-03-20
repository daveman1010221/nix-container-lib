{
  description = "My project CI container — built with polar-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";

    polar-container-lib.url = "github:daveman1010221/nix-container-lib";
    polar-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    polar-container-lib.inputs.flake-utils.follows  = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, polar-container-lib, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        container = polar-container-lib.lib.${system}.mkContainer {
          inherit system pkgs inputs;
          configPath = pkgs.writeText "container.dhall" (
            builtins.replaceStrings
              [ "PRELUDE_PATH" ]
              [ "${polar-container-lib}/dhall/prelude.dhall" ]
              (builtins.readFile ./container.dhall)
          );
        };
      in
      {
        # Build with: nix build .#ciContainer
        # Load with:  docker load < result
        # Run with:   docker run --rm -v $PWD:/workspace my-project-ci
        #             docker run --rm -v $PWD:/workspace -e CI_FULL=1 my-project-ci
        packages.ciContainer = container.image;
        packages.default     = container.image;
      }
    );
}

