{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "python3" then null
   else pkgs.writeText "yaml_to_json.fish" ''
     function yaml_to_json --description="Converts YAML input to JSON output."
         python -c 'import sys, yaml, json; y=yaml.safe_load(sys.stdin.read()); print(json.dumps(y))' $argv[1] | read; or exit -1
     end
   ''
