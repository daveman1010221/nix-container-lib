{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "rg" then null
   else pkgs.writeText "rgk.fish" ''
     function rgk
         rg --hyperlink-format=kitty $argv
     end
   ''
