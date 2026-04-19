{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "fd" || !hasBin "fzf" then null
   else pkgs.writeText "fdfz.fish" ''
     function fdfz
         fd_fzf $argv
     end
   ''
