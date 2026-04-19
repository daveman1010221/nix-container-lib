{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "pi" || !hasBin "curl" then null
   else pkgs.writeText "pi-local.fish" ''
     function pi-local --description "Run pi agent against local llama.cpp server"
         set -l base_url (test -n "$LLAMA_BASE_URL" && echo "$LLAMA_BASE_URL" || echo "http://localhost:8080/v1")
         set -l model    (test -n "$LLAMA_MODEL"    && echo "$LLAMA_MODEL"    || echo "local-model")
         if not curl -sf "$base_url/models" >/dev/null 2>&1
             echo "Error: llama-server not reachable at $base_url"
             echo "Start it first with: start-llama <model>"
             return 1
         end
         env \
             OPENAI_API_KEY="local" \
             OPENAI_BASE_URL="$base_url" \
             pi --provider openai --model "$model" $argv
     end
   ''
