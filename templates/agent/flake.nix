{
  description = "My project agent container — built with nix-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";

    nix-container-lib.url = "github:daveman1010221/nix-container-lib/b8b418e";
    nix-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    nix-container-lib.inputs.flake-utils.follows  = "flake-utils";
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
        packages.agentContainer = container.image;
        packages.default        = container.image;

        packages.tlsCerts = pkgs.callPackage
          "${nix-container-lib}/nix/gen-certs.nix"
          { inherit pkgs; cfg.tls = { generateCerts = true; certsPath = null; }; };
      }
    );
}

