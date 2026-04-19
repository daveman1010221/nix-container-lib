{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "figlet" then null
   else pkgs.writeText "lol_fig.fish" ''
     function lol_fig --description="lolcat (dotacat) inside a figlet"
         if type -q dotacat
             echo $argv | figlet | dotacat
         else
             echo $argv | figlet
         end
     end
   ''
