{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "nviml.fish" ''
     function nviml
         ${needs "nviml" [ "nvim" "fzf" "rg" ]}
         nvim_goto_line $argv
     end
   ''
