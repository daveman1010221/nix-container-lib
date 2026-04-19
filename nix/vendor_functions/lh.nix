{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "eza" then null
   else pkgs.writeText "lh.fish" ''
     function lh --description 'An approximation of "ls -alh", but uses eza.'
         eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links $argv
     end
   ''
