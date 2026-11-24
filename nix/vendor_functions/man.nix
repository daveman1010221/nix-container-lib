{ pkgs, cfg }:
# Paged through bat where the image has it, looked for when it is called; else as man pages itself.
pkgs.writeText "man.fish" ''
  function man --description="Get the page, man"
      if command -q bat
          ${pkgs.man}/bin/man $argv | bat --language man --style plain
      else
          ${pkgs.man}/bin/man $argv
      end
  end
''
