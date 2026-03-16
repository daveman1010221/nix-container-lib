# polar-container-lib/nix/identity.nix
#
# Produces the minimum set of files that make a container a valid Linux
# system, independent of any tools being installed.
#
# Everything here is synthesized from Nix expressions rather than copied
# from a base image. That means we know exactly what is in these files
# because we built them — there are no inherited decisions from ubuntu:22.04
# or similar.
#
# Outputs:
#   result.baseInfo   — list of derivations for use in image contents
#   result.etcPasswd  — exposed individually so nix-infra.nix can extend
#   result.etcGroup     the user/group files with nixbld entries if needed
#   result.etcShadow
#   result.etcGshadow
#   result.etcShells
#   result.etcOsRelease
#
# Design notes:
#   - The root user is always present. It is not optional.
#   - Additional named users (e.g. a dev user) are NOT provisioned here —
#     that happens at container runtime in start.sh via the user creation
#     phase, so the uid/gid can match the host user. Baking a uid into the
#     image is wrong for a dev container that will be used by multiple
#     developers on different machines.
#   - nixbld users are also NOT provisioned here. They are added at runtime
#     in start.sh based on nproc (or a fixed count from NixConfig). The
#     static nixbld provisioning in nixbld.nix in the original polar repo
#     was a build-time approximation that start.sh already supersedes.
#   - /etc/shells lists shells that are present in the image. The library
#     derives this from the resolved package list rather than hardcoding it,
#     but provides a sensible default for the common case.

{ pkgs
, system    # e.g. "x86_64-linux" or "aarch64-linux"
, cfg       # Translated config from from-dhall.nix
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # OS identity
  # We present as NixOS because that is truthful — this is a Nix-built
  # container running on the NixOS package set. Tools that key on
  # /etc/os-release (e.g. some package managers, some CI detection scripts)
  # will see a consistent identity across all containers built by this library.
  # ---------------------------------------------------------------------------
  osReleaseText = ''
    NAME="NixOS"
    ID=nixos
    VERSION="unstable"
    VERSION_CODENAME=unstable
    PRETTY_NAME="NixOS (unstable)"
    HOME_URL="https://nixos.org/"
    SUPPORT_URL="https://nixos.org/nixos/manual/"
    BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
  '';

  # ---------------------------------------------------------------------------
  # User database
  #
  # Only root is provisioned at image build time. This is intentional.
  #
  # A dev container used by multiple developers cannot have a single baked-in
  # uid:gid — each developer has a different uid on their host machine, and
  # bind-mounted files need correct ownership. start.sh handles this by
  # reading CREATE_USER/CREATE_UID/CREATE_GID from the environment and
  # creating a matching user at runtime.
  #
  # The shell for root is the runtime shell (usually bash/sh), NOT fish.
  # Fish is set as the shell for the provisioned dev user in start.sh.
  # This avoids any dependency on fish being present before the dev user
  # is created.
  # ---------------------------------------------------------------------------
  rootShell = pkgs.runtimeShell;

  passwdText = ''
    root:x:0:0::/root:${rootShell}
  '';

  shadowText = ''
    root:!x:::::::
  '';

  groupText = ''
    root:x:0:
  '';

  gshadowText = ''
    root:x::
  '';

  # ---------------------------------------------------------------------------
  # Registered shells
  #
  # /etc/shells is consulted by tools like chsh, su, and some PAM modules
  # to determine whether a shell is valid for a user. We register the shells
  # that will actually be present in the container.
  #
  # The shell from cfg.user.defaultShell is always included if set.
  # bash and sh are always included as fallbacks regardless.
  #
  # Note: paths here must match where the shells actually land in the image.
  # buildEnv symlinks everything into /bin, so all shells are under /bin.
  # ---------------------------------------------------------------------------
  registeredShells =
    let
      always = [ "/bin/sh" "/bin/bash" ];
      fromUser =
        if cfg.user.defaultShell != null && cfg.user.defaultShell != ""
        then [ cfg.user.defaultShell ]
        else [];
      # Fish is included when the shell layer is present
      fromShellCfg =
        if cfg.shell != null
        then [ "/bin/fish" ]
        else [];
    in
      lib.unique (always ++ fromUser ++ fromShellCfg);

  shellsText = lib.concatStringsSep "\n" registeredShells + "\n";

  # ---------------------------------------------------------------------------
  # Derivations
  #
  # Each file is its own derivation so it can be:
  #   1. Listed individually in closureInfo rootPaths
  #   2. Used as a GC root symlink target
  #   3. Extended by nix-infra.nix (passwd and group in particular)
  #
  # pkgs.writeTextDir places the file at the given path inside $out,
  # so "${etcPasswd}/etc/passwd" is the full path to the file.
  # This is the pattern buildLayeredImage contents expects.
  # ---------------------------------------------------------------------------
  etcPasswd    = pkgs.writeTextDir "etc/passwd"     passwdText;
  etcShadow    = pkgs.writeTextDir "etc/shadow"     shadowText;
  etcGroup     = pkgs.writeTextDir "etc/group"      groupText;
  etcGshadow   = pkgs.writeTextDir "etc/gshadow"    gshadowText;
  etcShells    = pkgs.writeTextDir "etc/shells"     shellsText;
  etcOsRelease = pkgs.writeTextDir "etc/os-release" osReleaseText;

  # ---------------------------------------------------------------------------
  # /root home directory skeleton
  #
  # A minimal home directory for root. The dev user's home is created at
  # runtime by start.sh, but root needs something to exist at image build
  # time so that tools which reference $HOME don't fail before user creation
  # runs.
  # ---------------------------------------------------------------------------
  rootHome = pkgs.runCommand "root-home" {} ''
    mkdir -p $out/root
    chmod 700 $out/root
  '';

in
{
  # Individual derivations — exposed for GC roots and closure registration
  inherit etcPasswd etcShadow etcGroup etcGshadow etcShells etcOsRelease rootHome;

  # Convenience: the full list for image contents and closureInfo
  baseInfo = [
    etcPasswd
    etcShadow
    etcGroup
    etcGshadow
    etcShells
    etcOsRelease
    rootHome
  ];
}
