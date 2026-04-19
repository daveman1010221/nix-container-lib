{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "pwgen" then null
   else pkgs.writeText "filename_get_random.fish" ''
     function filename_get_random --description="Sometimes you need a random name for a file and UUIDs suck"
         pwgen --capitalize --numerals --ambiguous 16 1
     end
   ''
