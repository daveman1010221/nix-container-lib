# ~/.config/nushell/config.nu

# --- Nix Daemon Path ---
if ("/nix/var/nix/profiles/default/bin" | path exists ) {
  $env.PATH = ([
    "/nix/var/nix/profiles/default/bin"
  ] ++ ($env.PATH | split row (char esep))) | uniq | str join (char esep)
}

let home = $env.HOME

$env.EDITOR = "nvim"
