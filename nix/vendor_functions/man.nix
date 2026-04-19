{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "bat" then null
   else pkgs.writeText "man.fish" ''
     function man --description="Get the page, man"
         ${pkgs.man}/bin/man $argv | bat --language man --style plain
     end
   ''
