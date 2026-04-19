{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "eza" then null
   else pkgs.writeText "lht.fish" ''
     function lht --description="ls -alh, but show only files modified today"
         lh (find . -maxdepth 1 -type f -newermt (date +%Y-%m-%d) ! -newermt (date -d tomorrow +%Y-%m-%d))
     end
   ''
