{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "fdfz.fish" ''
     function fdfz
         ${needs "fdfz" [ "fd" "fzf" ]}
         fd_fzf $argv
     end
   ''
