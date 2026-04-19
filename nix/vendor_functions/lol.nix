{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "cowsay" then null
   else pkgs.writeText "lol.fish" ''
     function lol --description="lolcat (dotacat) inside cowsay"
         set cows (ls ${pkgs.cowsay}/share/cowsay/cows)
         set total_cows (count $cows)
         set random_cow (random 1 $total_cows)
         set my_cow (echo -n $cows[$random_cow] | cut -d '.' -f 1)
         set output (printf "%s\n" $argv | cowsay -n -f $my_cow -W 79)
         if type -q dotacat
             echo $output | dotacat
         else
             echo $output
         end
     end
   ''
