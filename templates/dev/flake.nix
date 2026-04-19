{
  description = "My project dev container — built with nix-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";
    rust-overlay.url        = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    
    myNeovimOverlay.url = "github:daveman1010221/nix-neovim";
    myNeovimOverlay.inputs.nixpkgs.follows    = "nixpkgs";
    myNeovimOverlay.inputs.flake-utils.url    = "github:numtide/flake-utils";

    nix-container-lib.url = "github:daveman1010221/nix-container-lib/7b22e78";
    nix-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    nix-container-lib.inputs.flake-utils.follows  = "flake-utils";

    # Add your project-specific flake inputs here:
    # myTool.url = "github:your-org/my-tool";
    # myTool.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, myNeovimOverlay, nix-container-lib, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
            myNeovimOverlay.overlays.default
          ];
        };

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
        # Build with: nix build .#devContainer
        # Load with:  docker load < result
        packages.devContainer = container.image;
        packages.default      = container.image;

        # Enter with: nix develop
        devShells.default = container.devShell;
      }
    );
}
