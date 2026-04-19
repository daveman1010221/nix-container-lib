{ pkgs, cfg, devEnv }:
pkgs.writeText "is_a_directory.fish" ''
  function is_a_directory --description="Checks if the path is a directory"
      if test -d $argv[1]
          echo "true"
      else
          echo "false"
      end
  end
''
