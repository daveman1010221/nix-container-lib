{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "display_rg_piped_fzf.fish" ''
     function display_rg_piped_fzf --description="Pipe ripgrep output into fzf"
         ${needs "display_rg_piped_fzf" [ "rg" "fzf" ]}
         rg . -n --glob "!.git/" | fzf
     end
   ''
