{ pkgs, cfg, devEnv }:
pkgs.writeText "is_valid_argument.fish" ''
  function is_valid_argument --description="Checks if it has been passed a valid argument"
      if test (count $argv) -gt 0
          echo "true"
      else
          echo "false"
      end
  end
''
