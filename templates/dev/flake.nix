{
  description = "My project dev container — built with polar-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";
    rust-overlay.url        = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    polar-container-lib.url = "github:daveman1010221/nix-container-lib";
    polar-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    polar-container-lib.inputs.flake-utils.follows  = "flake-utils";

    # Add your project-specific flake inputs here:
    # myTool.url = "github:your-org/my-tool";
    # myTool.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, polar-container-lib, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        # Build the container from the Dhall config
        container = polar-container-lib.lib.${system}.mkContainer {
          inherit system pkgs inputs;
          configPath = ./container.dhall;
        };
      in
      {
        # The OCI container image
        # Build with: nix build .#devContainer
        # Load with:  docker load < result
        packages.devContainer  = container.image;
        packages.default       = container.image;

        # The host-side dev shell
        # Enter with: nix develop
        devShells.default = container.devShell;
      }
    );
}

