{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "python3" then null
   else pkgs.writeText "prettyjson.fish" ''
     function prettyjson --description="Pretty print JSON output"
         python -m json.tool $argv[1]
     end
   ''
