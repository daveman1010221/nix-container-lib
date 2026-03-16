# polar-container-lib/nix/gc-roots.nix
#
# Creates GC root symlinks for every derivation in the container image.
#
# WHY THIS EXISTS
# ---------------
# When a developer runs `nix-collect-garbage` inside the container, the Nix
# daemon walks /nix/var/nix/gcroots/ looking for live roots. If no roots
# point at the container's environment, the daemon sees the entire container
# closure as unreachable garbage and deletes it — destroying the container's
# own tools from within.
#
# GC roots are symlinks that originate OUTSIDE the Nix store and point AT
# store paths. Only this arrangement is recognized as a live root. A symlink
# from one store path to another provides no protection.
#
# The conventional location is /nix/var/nix/gcroots/. We use a flat naming
# scheme: polar-<descriptive-name> → <store-path>. The name is for human
# readability in `nix-store --gc --print-roots` output.
#
# WHAT IS INCLUDED
# ----------------
# Every derivation listed in the container's image contents needs a GC root.
# container.nix passes `allContents` here — the same list used for both
# `buildLayeredImage contents` and `closureInfo rootPaths`.
#
# WHAT IS EXCLUDED
# ----------------
# nixDbRegistration and gcRoots itself are intentionally NOT in allContents
# and therefore not registered as roots here.
#
# nixDbRegistration depends on closureInfo (it reads closureInfo/registration
# at build time). Including it in closureInfo's rootPaths would create a cycle:
#   closureInfo → nixDbRegistration → closureInfo
#
# gcRoots itself is protected by being listed in image contents — its store
# path is covered by the Nix DB registration, which is sufficient. A GC root
# pointing at gcRoots from within gcRoots would be circular.
#
# NAMING SCHEME
# -------------
# Symlinks are named polar-<n> where n is the zero-padded index of the
# derivation in allContents. Descriptive names would be better but require
# knowing the name of each derivation at the call site — the flat index
# scheme keeps this function general and the names are stable (index doesn't
# change unless allContents order changes, which is controlled by container.nix).
#
# If you need human-readable names, pass a list of { drv, name } attrsets
# instead of a plain list and adjust the buildCommand accordingly.

{ pkgs
, allContents   # List of derivations — every item in image contents
, extraRoots ? []  # Optional: additional store paths to protect
}:

let
  lib = pkgs.lib;

  allRoots = allContents ++ extraRoots;

  # Generate "ln -s <storepath> $out/nix/var/nix/gcroots/polar-<n>" for each
  symlinkCommands = lib.concatImapStringsSep "\n"
    (i: drv:
      let
        # Zero-pad to 4 digits for stable sort order in ls output
        n    = lib.fixedWidthNumber 4 (i - 1);
        name = "polar-${n}";
      in
        "ln -s ${drv} $out/nix/var/nix/gcroots/${name}"
    )
    allRoots;

in
  pkgs.runCommand "gc-roots" {} ''
    mkdir -p $out/nix/var/nix/gcroots
    ${symlinkCommands}
  ''
