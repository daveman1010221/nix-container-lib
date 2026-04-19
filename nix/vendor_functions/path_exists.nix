{ pkgs, cfg, devEnv }:
pkgs.writeText "path_exists.fish" ''
  function path_exists --description="Checks if the path exists"
      if test -e $argv[1]
          echo "true"
      else
          echo "false"
      end
  end
''
