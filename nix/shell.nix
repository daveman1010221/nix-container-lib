# nix-container-lib/nix/shell.nix
#
# Shell environment dispatcher.
# Inspects cfg.shell.shell and delegates to the appropriate shell module.
#
# This module is ONLY invoked when cfg.shell != null and cfg.mode != "minimal".
# CI and agent containers set shell = None and pay zero cost for this module.
#
# Supported shells:
#   /bin/fish  → shell-fish.nix  (Fish with bobthefish, atuin, starship, direnv)
#   /bin/nu    → shell-nu.nix    (Nushell with plugins, atuin, starship, direnv)
#
# To add a new shell:
#   1. Add a new shell-<name>.nix module following the same contract:
#      takes { pkgs, cfg, devEnv }, returns a list of derivations.
#   2. Add a branch here.
#   3. Add the shell binary to the package layer it belongs in (packages.nix).

{ pkgs
, cfg
, devEnv
}:

let
  shell = cfg.shell.shell;
in
  if shell == "/bin/fish" then
    import ./shell-fish.nix { inherit pkgs cfg devEnv; }
  else if shell == "/bin/nu" then
    import ./shell-nu.nix  { inherit pkgs cfg devEnv; }
  else
    throw "shell.nix: unsupported shell '${shell}'. Supported: /bin/fish, /bin/nu"
