{
  description = "My minimal init container — built with polar-container-lib";

  inputs = {
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url         = "github:numtide/flake-utils";

    polar-container-lib.url = "github:daveman1010221/nix-container-lib";
    polar-container-lib.inputs.nixpkgs.follows      = "nixpkgs";
    polar-container-lib.inputs.flake-utils.follows  = "flake-utils";

    # Add your entrypoint flake input here:
    # myInput.url = "github:your-org/my-entrypoint";
    # myInput.inputs.nixpkgs.follows = "nixpkgs";
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
