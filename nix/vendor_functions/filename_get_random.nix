{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "filename_get_random.fish" ''
     function filename_get_random --description="Sometimes you need a random name for a file and UUIDs suck"
         ${needs "filename_get_random" [ "pwgen" ]}
         pwgen --capitalize --numerals --ambiguous 16 1
     end
   ''
