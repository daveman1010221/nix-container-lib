{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "rg" || !hasBin "fzf" then null
   else pkgs.writeText "display_rg_piped_fzf.fish" ''
     function display_rg_piped_fzf --description="Pipe ripgrep output into fzf"
         rg . -n --glob "!.git/" | fzf
     end
   ''
