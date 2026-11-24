{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "lol_fig.fish" ''
     function lol_fig --description="lolcat (dotacat) inside a figlet"
         ${needs "lol_fig" [ "figlet" ]}
         if type -q dotacat
             echo $argv | figlet | dotacat
         else
             echo $argv | figlet
         end
     end
   ''
