{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "jsonschema" then null
   else pkgs.writeText "json_validate.fish" ''
     function json_validate --description="Validate provided json against provided schema."
         if ! isatty stdin
             set -l tmp_file get_random_filename
             read > /tmp/$tmp_file; or exit -1
             jsonschema -F "{error.message}" -i /tmp/$tmp_file $argv[1]
             rm -f /tmp/$tmp_file
         else
             jsonschema -F "{error.message}" -i $argv[1] $argv[2]
         end
     end
   ''
