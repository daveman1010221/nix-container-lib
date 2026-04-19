# polar-container-lib/nix/shell.nix
#
# Shell environment dispatcher.
# Inspects cfg.shell.type (as resolved by from-dhall.nix) and delegates
# to the appropriate shell module.
#
# This module is ONLY invoked when cfg.shell != null.
#
# Shell type → module mapping:
#   "minimal-dash"       → shell-dash.nix      (/bin/sh, no config)
#   "minimal-nu"         → shell-nu-minimal.nix (/bin/nu, bare config)
#   "interactive-fish"   → shell-fish.nix       (full fish experience)
#   "interactive-nu"     → shell-nu.nix         (full nushell experience)
#
# To add a new shell:
#   1. Add a shell-<name>.nix module: takes { pkgs, cfg }, returns list of derivations.
#   2. Add a branch here.
#   3. Add the shell binary to packages.nix in the appropriate shell set.
#   4. Add the shell type to from-dhall.nix resolveShell.
#   5. Add the Dhall variant to types.dhall if needed.

{ pkgs
, cfg
, devEnv
}:

let
  shellType = cfg.shell.type;
in
  if shellType == "minimal-dash" then
    import ./shell-dash.nix { inherit pkgs cfg; }

  else if shellType == "minimal-nu" then
    import ./shell-nu-minimal.nix { inherit pkgs cfg; }

  else if shellType == "interactive-fish" then
    import ./shell-fish.nix { inherit pkgs cfg devEnv; }

  else if shellType == "interactive-nu" then
    import ./shell-nu.nix { inherit pkgs cfg devEnv; }

  else
    throw "shell.nix: unknown shell type '${shellType}'"
