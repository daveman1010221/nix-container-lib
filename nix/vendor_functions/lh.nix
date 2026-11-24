{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "lh.fish" ''
     function lh --description 'An approximation of "ls -alh", but uses eza.'
         ${needs "lh" [ "eza" ]}
         eza --group --header --group-directories-first --long --icons --git --all --binary --dereference --links $argv
     end
   ''
