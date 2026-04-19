{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "nvim" || !hasBin "fzf" then null
   else pkgs.writeText "nvim_goto_files.fish" ''
     function nvim_goto_files --description="Open fzf to find a file, then open it in neovim"
         set nvim_exists (which nvim)
         if test -z "$nvim_exists"
             return
         end
         set selection (display_fzf_files)
         if test -z "$selection"
             return
         else
             nvim $selection
         end
     end
   ''
