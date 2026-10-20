{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "cowsay" then null
   else pkgs.writeText "lol.fish" ''
     function lol --description="lolcat (dotacat) inside cowsay"
         set cows (ls ${pkgs.cowsay}/share/cowsay/cows/*.cow)
         set total_cows (count $cows)
         set random_cow (random 1 $total_cows)
         set my_cow (string replace -r "\.cow\$" "" -- (path basename $cows[$random_cow]))
         # Piped straight through: a command substitution splits the figure into lines, and `echo` joins them with spaces.
         if type -q dotacat
             printf "%s\n" $argv | cowsay -n -f $my_cow | dotacat
         else
             printf "%s\n" $argv | cowsay -n -f $my_cow
         end
     end
   ''
