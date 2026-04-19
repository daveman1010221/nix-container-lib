{
  description = "My minimal init container — built with nix-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";

    nix-container-lib.url = "github:daveman1010221/nix-container-lib/b8b418e";
    nix-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    nix-container-lib.inputs.flake-utils.follows  = "flake-utils";

    uutils-micro.url = "github:daveman1010221/uutils-micro/7cda0210b076f384906d189171c065a1884cad96";
    uutils-micro.inputs.nixpkgs.follows = "nixpkgs";
    uutils-micro.inputs.flake-utils.follows = "flake-utils";

    # Add your entrypoint flake input here:
    # myInput.url = "github:your-org/my-entrypoint";
    # myInput.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, nix-container-lib, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # -----------------------------------------------------------------------
        # container.nix is the pre-rendered output of container.dhall.
        # To regenerate it after editing container.dhall:
        #   just render-container
        # -----------------------------------------------------------------------
        container = nix-container-lib.lib.${system}.mkContainer {
          inherit system pkgs inputs;
          configNixPath = ./container.nix;
        };
      in
      {
        # Build with: nix build .#initContainer
        # Load with:  podman load -i result
        # Run with:   podman run --rm \
        #               -e REQUIRED_VAR=value \
        #               -v /workspace:/workspace \
        #               my-init-container
        packages.initContainer = container.image;
        packages.default       = container.image;
      }
    );
}
