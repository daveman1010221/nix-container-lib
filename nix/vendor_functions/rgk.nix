{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "rgk.fish" ''
     function rgk
         ${needs "rgk" [ "rg" ]}
         rg --hyperlink-format=kitty $argv
     end
   ''
