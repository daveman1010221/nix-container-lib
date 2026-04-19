{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "nvim" || !hasBin "fzf" || !hasBin "rg" then null
   else pkgs.writeText "nvim_goto_line.fish" ''
     function nvim_goto_line --description="ripgrep to find contents, fzf to select, open in neovim."
         set nvim_exists (which nvim)
         if test -z "$nvim_exists"
             return
         end
         set selection (display_rg_piped_fzf)
         if test -z "$selection"
             return
         else
             set filename (echo $selection | awk -F ':' '{print $1}')
             set line (echo $selection | awk -F ':' '{print $2}')
             nvim +$line $filename
         end
     end
   ''
