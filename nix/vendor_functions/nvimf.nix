{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "nvimf.fish" ''
     function nvimf
         ${needs "nvimf" [ "nvim" "fzf" ]}
         nvim_goto_files $argv
     end
   ''
