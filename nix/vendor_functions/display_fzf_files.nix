{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "fzf" || !hasBin "bat" then null
   else pkgs.writeText "display_fzf_files.fish" ''
     function display_fzf_files --description="Call fzf and preview file contents using bat."
         set preview_command "bat --theme=gruvbox-dark --color=always --style=header,grid --line-range :400 {}"
         fzf --ansi --preview $preview_command
     end
   ''
