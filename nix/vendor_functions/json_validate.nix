{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "json_validate.fish" ''
     function json_validate --description="Validate provided json against provided schema."
         ${needs "json_validate" [ "jsonschema" ]}
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
