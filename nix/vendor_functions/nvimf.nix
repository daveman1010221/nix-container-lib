{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "nvim" || !hasBin "fzf" then null
   else pkgs.writeText "nvimf.fish" ''
     function nvimf
         nvim_goto_files $argv
     end
   ''
