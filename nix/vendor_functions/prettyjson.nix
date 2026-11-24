{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "prettyjson.fish" ''
     function prettyjson --description="Pretty print JSON output"
         ${needs "prettyjson" [ "python3" ]}
         python -m json.tool $argv[1]
     end
   ''
