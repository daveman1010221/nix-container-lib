{ pkgs, cfg }:
let needs = import ./needs.nix;
in pkgs.writeText "ssh-stop.fish" ''
     function ssh-stop
         ${needs "ssh-stop" [ "dropbear" ]}
         set pids (pgrep dropbear)
         if test -z "$pids"
             echo "ℹ️  No Dropbear processes running."
             return 0
         end
         echo "🛑 Stopping Dropbear..."
         for pid in $pids
             echo "  Killing PID $pid"
             kill $pid
         end
         echo "✔️ Dropbear stopped."
     end
   ''
