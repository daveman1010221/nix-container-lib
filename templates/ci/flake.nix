{
  description = "My project CI container — built with nix-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";

    nix-container-lib.url = "github:daveman1010221/nix-container-lib/7b5ba3f9c44faaa29279f1e7400d8254c969bde2";
    nix-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    nix-container-lib.inputs.flake-utils.follows  = "flake-utils";

    vigil-rs.url = "github:daveman1010221/vigil-rs-nix/0d19379";
    vigil-rs.inputs.nixpkgs.follows    = "nixpkgs";
    vigil-rs.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, nix-container-lib, vigil-rs, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        container = nix-container-lib.lib.${system}.mkContainer {
          inherit system pkgs inputs;
          configNixPath = ./container.nix;
        };
      in
      {
        packages.ciContainer = container.image;
        packages.default     = container.image;
      }
    );
}
