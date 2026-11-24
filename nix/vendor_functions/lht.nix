{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "lht.fish" ''
     function lht --description="ls -alh, but show only files modified today"
         ${needs "lht" [ "eza" ]}
         lh (find . -maxdepth 1 -type f -newermt (date +%Y-%m-%d) ! -newermt (date -d tomorrow +%Y-%m-%d))
     end
   ''
