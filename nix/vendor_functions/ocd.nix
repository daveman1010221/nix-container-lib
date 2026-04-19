{ pkgs, cfg, devEnv }:
pkgs.writeText "ocd.fish" ''
  function ocd --description="Open the current terminal directory in your default file manager."
      echo "This function needs updated for nixos."
  end
''
