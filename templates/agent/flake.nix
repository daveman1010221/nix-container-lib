{
  description = "My project agent container — built with polar-container-lib";

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
          configPath = ./container.dhall;
        };
      in
      {
        # Build with: nix build .#agentContainer
        # Load with:  docker load < result
        # Run with:   docker run -d \
        #               -v $PWD:/workspace \
        #               -e AUTHORIZED_KEYS_B64=$(base64 < ~/.ssh/id_ed25519.pub) \
        #               my-project-agent
        packages.agentContainer = container.image;
        packages.default        = container.image;

        # tlsCerts output — build separately, reference from container
        # nix build .#tlsCerts -o result-tlsCerts
        packages.tlsCerts = pkgs.callPackage
          "${polar-container-lib}/nix/gen-certs.nix"
          { inherit pkgs; cfg.tls = { generateCerts = true; certsPath = null; }; };
      }
    );
}

