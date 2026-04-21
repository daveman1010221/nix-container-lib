# polar-container-lib/nix/nix-infra.nix
#
# Everything required for the Nix daemon to operate correctly inside a
# container that was itself built by Nix — and the minimal FHS scaffolding
# that ALL containers need regardless of mode.
#
# Minimal mode skips nixRegistry, nixConfig, and containerPolicy entirely.
# These are only needed when a Nix daemon runs inside the container.
# Minimal containers exec a single binary and have no use for them.
#
# Outputs:
#   result.configFiles  — list of derivations for image contents (mode-aware)
#   result.ldLinker     — the dynamic linker stub (always included)
#   result.usrBinEnv    — /usr/bin/env stub (always included)
#   result.fhsDirs      — FHS directory scaffolding (always included)
#
# The following are only produced in non-minimal modes:
#   result.nixRegistry  — flake registry pinned to build-time nixpkgs
#   result.nixConfig    — /etc/nix/nix.conf
#   result.containerPolicy — /etc/containers/policy.json

{ pkgs
, system
, cfg
, inputs ? {}
}:

let
  lib = pkgs.lib;
  isMinimal = cfg.mode == "minimal";

  # ---------------------------------------------------------------------------
  # Dynamic linker stub (always included)
  # ---------------------------------------------------------------------------
  linkerAttrs =
    if system == "x86_64-linux" then
      { name = "ld-linux-x86-64.so.2"; dir = "lib64"; }
    else if system == "aarch64-linux" then
      { name = "ld-linux-aarch64.so.1"; dir = "lib"; }
    else
      throw "nix-infra: unsupported system '${system}'";

  ldLinker = pkgs.runCommand "ld-linker" {} ''
    mkdir -p $out/${linkerAttrs.dir}
    ln -sf ${pkgs.glibc}/lib/${linkerAttrs.name} \
           $out/${linkerAttrs.dir}/${linkerAttrs.name}
  '';

  # ---------------------------------------------------------------------------
  # /usr/bin/env stub (always included)
  # ---------------------------------------------------------------------------
  usrBinEnv = pkgs.runCommand "usr-bin-env" {} ''
    mkdir -p $out/usr/bin
    ln -s ${(inputs.uutils-micro.packages.${system}.default or pkgs.coreutils)}/bin/env $out/usr/bin/env
  '';

  # ---------------------------------------------------------------------------
  # FHS directory scaffolding (always included)
  # ---------------------------------------------------------------------------
  fhsDirs = pkgs.runCommand "fhs-dirs" {} ''
    mkdir -p $out/var/tmp
    mkdir -p $out/tmp
    mkdir -p $out/workspace
  '';

  # ---------------------------------------------------------------------------
  # Nix registry (non-minimal only)
  # ---------------------------------------------------------------------------
  nixRegistry =
    if isMinimal then null
    else pkgs.writeTextFile {
      name        = "registry.json";
      destination = "/etc/nix/registry.json";
      text        = builtins.toJSON {
        version = 2;
        flakes  = [{
          from = { type = "indirect"; id = "nixpkgs"; };
          to   = { type = "path"; path = "${pkgs.path}"; };
        }];
      };
    };

  # ---------------------------------------------------------------------------
  # nix.conf (non-minimal only)
  # ---------------------------------------------------------------------------
  nixConfig =
    if isMinimal then null
    else pkgs.writeTextFile {
      name        = "nix.conf";
      destination = "/etc/nix/nix.conf";
      text        = ''
        # Base configuration — dynamic settings appended by start.sh at runtime.
        experimental-features = nix-command flakes
        keep-outputs           = true
        keep-derivations       = true
        substituters          = https://cache.nixos.org
        trusted-public-keys   = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
      '';
    };

  # ---------------------------------------------------------------------------
  # Container policy (non-minimal only)
  # ---------------------------------------------------------------------------
  containerPolicy =
    if isMinimal then null
    else pkgs.writeTextFile {
      name        = "policy.json";
      destination = "/etc/containers/policy.json";
      text        = builtins.toJSON {
        default = [{ type = "insecureAcceptAnything"; }];
        transports.docker-daemon."" = [{ type = "insecureAcceptAnything"; }];
      };
    };

  # Config files for image contents — mode-aware
  configFiles =
    if isMinimal
    then []
    else [
      nixConfig
      nixRegistry
      containerPolicy
    ];

in
{
  inherit ldLinker usrBinEnv fhsDirs configFiles;
  # Expose individual items for non-minimal consumers that reference them
  nixRegistry    = if isMinimal then null else nixRegistry;
  nixConfig      = if isMinimal then null else nixConfig;
  containerPolicy = if isMinimal then null else containerPolicy;
}
