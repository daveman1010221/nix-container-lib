{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "yaml_to_json.fish" ''
     function yaml_to_json --description="Converts YAML input to JSON output."
         ${needs "yaml_to_json" [ "python3" ]}
         python -c 'import sys, yaml, json; y=yaml.safe_load(sys.stdin.read()); print(json.dumps(y))' $argv[1] | read; or exit -1
     end
   ''
