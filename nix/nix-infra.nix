# polar-container-lib/nix/nix-infra.nix
#
# Everything required for the Nix daemon to operate correctly inside a
# container that was itself built by Nix. This is the most arcane cluster
# of knowledge in the library — it encodes several non-obvious interactions
# between the Nix store, the OCI layer model, and cross-arch builds.
#
# Outputs:
#   result.configFiles  — list of derivations for image contents
#   result.ldLinker     — the dynamic linker stub
#   result.usrBinEnv    — /usr/bin/env stub
#   result.fhsDirs      — FHS directory scaffolding
#   result.nixRegistry  — flake registry pinned to build-time nixpkgs
#   result.nixConfig    — /etc/nix/nix.conf
#   result.containerPolicy — /etc/containers/policy.json
#
# Key problems solved here (each has a comment explaining why):
#
#   1. The dynamic linker stub
#   2. The /usr/bin/env stub
#   3. The flake registry pin
#   4. The container policy
#   5. The nix.conf base (runtime arch config is handled in entrypoint.nix)
#   6. FHS directory scaffolding
#
# NOT solved here (handled elsewhere):
#   - Nix DB seeding/materialization  → entrypoint.nix (runtime)
#   - nixbld user provisioning        → entrypoint.nix (runtime)
#   - GC root registration            → gc-roots.nix
#   - closureInfo                     → container.nix (needs full contents list)

{ pkgs
, system    # e.g. "x86_64-linux" or "aarch64-linux"
, cfg       # Translated config from from-dhall.nix
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # 1. Dynamic linker stub
  #
  # Many dynamically-linked binaries in the container expect the dynamic
  # linker to live at a well-known FHS path (/lib64/ld-linux-x86-64.so.2
  # on x86, /lib/ld-linux-aarch64.so.1 on aarch64). The Nix store has the
  # real linker under its hash path, but programs that were not built with
  # Nix (or that use dlopen) look in the FHS location.
  #
  # PORTABILITY FIX (preserved from polar):
  # The source must be pkgs.glibc, NOT pkgs.stdenv.cc.cc. The compiler
  # runtime (cc.cc) does not own the glibc dynamic linker. On x86 this
  # happened to work because of how the host stdenv was assembled, masking
  # the bug on aarch64 where the paths are genuinely different.
  #
  # The linker name and directory are arch-specific:
  #   x86_64  → /lib64/ld-linux-x86-64.so.2
  #   aarch64 → /lib/ld-linux-aarch64.so.1
  # ---------------------------------------------------------------------------
  linkerAttrs =
    if system == "x86_64-linux" then
      { name = "ld-linux-x86-64.so.2"; dir = "lib64"; }
    else if system == "aarch64-linux" then
      { name = "ld-linux-aarch64.so.1"; dir = "lib"; }
    else
      throw "nix-infra: unsupported system '${system}'. Add linker attrs for this arch.";

  ldLinker = pkgs.runCommand "ld-linker" {} ''
    mkdir -p $out/${linkerAttrs.dir}
    ln -sf ${pkgs.glibc}/lib/${linkerAttrs.name} \
           $out/${linkerAttrs.dir}/${linkerAttrs.name}
  '';

  # ---------------------------------------------------------------------------
  # 2. /usr/bin/env stub
  #
  # Many scripts have #!/usr/bin/env bash or #!/usr/bin/env python3 shebangs.
  # In a pure Nix environment, env lives at ${pkgs.coreutils}/bin/env — a
  # store path, not a stable FHS location. The stub makes these shebangs work
  # without patching every script.
  # ---------------------------------------------------------------------------
  usrBinEnv = pkgs.runCommand "usr-bin-env" {} ''
    mkdir -p $out/usr/bin
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
  '';

  # ---------------------------------------------------------------------------
  # 3. FHS directory scaffolding
  #
  # Certain FHS directories must exist even if nothing is mounted there.
  # Tools that create temp files, write to /var, or check for /tmp will fail
  # if these are absent. We create them as a derivation rather than relying
  # on the OCI runtime to create them, because we want them registered in
  # the Nix DB and visible in the image layer listing.
  # ---------------------------------------------------------------------------
  fhsDirs = pkgs.runCommand "fhs-dirs" {} ''
    mkdir -p $out/var/tmp
    mkdir -p $out/tmp
    mkdir -p $out/workspace
  '';

  # ---------------------------------------------------------------------------
  # 4. Flake registry pinned to build-time nixpkgs
  #
  # This registers the exact nixpkgs revision the container was built against
  # as the "nixpkgs" flake registry entry. Developers inside the container
  # can then run:
  #   nix shell nixpkgs#ripgrep
  #   nix search nixpkgs curl
  #   nix run nixpkgs#hello
  #
  # ...without network access and without drift — they get the same nixpkgs
  # tree that produced the container, already present in the Nix store.
  #
  # pkgs.path is the store path of the nixpkgs input as resolved by the
  # flake.lock at build time. Using a path: reference rather than a
  # github: reference means resolution is local and requires no fetch.
  # ---------------------------------------------------------------------------
  nixRegistry = pkgs.writeTextFile {
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
  # 5. nix.conf base configuration
  #
  # This is the STATIC base configuration. Dynamic configuration
  # (trusted-users, system, extra-platforms, sandbox policy, filter-syscalls)
  # is appended at runtime in start.sh because:
  #
  #   a) trusted-users needs the actual runtime user name, which is not known
  #      at image build time
  #   b) system and extra-platforms depend on the actual running architecture
  #   c) sandbox policy depends on whether we're under qemu-user emulation,
  #      which can only be detected at runtime
  #
  # The experimental-features line enables flakes and the nix-command CLI,
  # which are still technically experimental but universally needed in a
  # dev container. Without this, every nix command requires --extra-experimental-features.
  #
  # keep-outputs and keep-derivations prevent the garbage collector from
  # removing build inputs and .drv files — important in a dev container where
  # developers may want to inspect build artifacts or re-run builds.
  # ---------------------------------------------------------------------------
  nixConfText = ''
    # Base configuration — dynamic settings appended by start.sh at runtime.
    # See entrypoint.nix for the runtime configuration logic.

    experimental-features = nix-command flakes
    keep-outputs           = true
    keep-derivations       = true

    # Substituters: use the official cache.
    # Projects that have their own binary cache should add it via extraEnv
    # or by overriding this file.
    substituters          = https://cache.nixos.org
    trusted-public-keys   = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
  '';

  nixConfig = pkgs.writeTextFile {
    name        = "nix.conf";
    destination = "/etc/nix/nix.conf";
    text        = nixConfText;
  };

  # ---------------------------------------------------------------------------
  # 6. Container policy
  #
  # /etc/containers/policy.json is required by container tooling (skopeo,
  # podman, buildah) that may be run inside the dev container to pull or
  # push images. The "insecureAcceptAnything" policy is appropriate for a
  # dev container where the developer is explicitly choosing what to pull.
  # A production deployment container would use a more restrictive policy.
  # ---------------------------------------------------------------------------
  containerPolicyText = builtins.toJSON {
    default = [{ type = "insecureAcceptAnything"; }];
    transports = {
      docker-daemon = {
        "" = [{ type = "insecureAcceptAnything"; }];
      };
    };
  };

  containerPolicy = pkgs.writeTextFile {
    name        = "policy.json";
    destination = "/etc/containers/policy.json";
    text        = containerPolicyText;
  };

in
{
  # Individual derivations — exposed for GC roots, closure registration,
  # and for container.nix to compose into allContents
  inherit ldLinker usrBinEnv fhsDirs nixRegistry nixConfig containerPolicy;

  # Convenience: config files that go into image contents
  # (ldLinker, usrBinEnv, fhsDirs are also in contents but listed separately
  # in container.nix for clarity about what they are)
  configFiles = [
    nixConfig
    nixRegistry
    containerPolicy
  ];
}
