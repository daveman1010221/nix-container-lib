{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "display_fzf_files.fish" ''
     function display_fzf_files --description="Call fzf and preview file contents using bat."
         ${needs "display_fzf_files" [ "fzf" "bat" ]}
         set preview_command "bat --theme=gruvbox-dark --color=always --style=header,grid --line-range :400 {}"
         fzf --ansi --preview $preview_command
     end
   ''
