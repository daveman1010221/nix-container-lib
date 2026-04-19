{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "nvim" || !hasBin "fzf" || !hasBin "rg" then null
   else pkgs.writeText "nviml.fish" ''
     function nviml
         nvim_goto_line $argv
     end
   ''
