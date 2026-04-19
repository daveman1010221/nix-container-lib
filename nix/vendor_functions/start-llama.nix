{ pkgs, cfg, devEnv }:
let hasBin = name: builtins.pathExists "${devEnv}/bin/${name}";
in if !hasBin "llama-server" then null
   else pkgs.writeText "start-llama.fish" ''
     function start-llama --description "Start llama.cpp server with a model"
         set -l port     (test -n "$LLAMA_PORT"       && echo "$LLAMA_PORT"       || echo "8080")
         set -l ctx      (test -n "$LLAMA_CTX_SIZE"   && echo "$LLAMA_CTX_SIZE"   || echo "32768")
         set -l gpu_lay  (test -n "$LLAMA_GPU_LAYERS" && echo "$LLAMA_GPU_LAYERS" || echo "99")
         set -l host     (test -n "$LLAMA_HOST"       && echo "$LLAMA_HOST"       || echo "0.0.0.0")

         if test (count $argv) -eq 0
             echo "Usage: start-llama [--hf <repo:quant>] [<model.gguf>]"
             return 1
         end

         if test "$argv[1]" = "--hf"
             if test (count $argv) -lt 2
                 echo "Error: --hf requires a repo:quant argument"
                 return 1
             end
             set hf_flag "--hf-repo" (string split ":" $argv[2])[1] "--hf-file" (string split ":" $argv[2])[2]
             sudo llama-server $hf_flag --host $host --port $port --ctx-size $ctx --n-gpu-layers $gpu_lay --flash-attn --alias "local-model"
         else
             set model_path $argv[1]
             if not test -f "$model_path"
                 echo "Error: model file not found: $model_path"
                 return 1
             end
             sudo llama-server --model $model_path --host $host --port $port --ctx-size $ctx --n-gpu-layers $gpu_lay --flash-attn --alias "local-model"
         end
     end
   ''
