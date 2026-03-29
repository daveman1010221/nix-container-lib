# nix-container-lib/nix/shell-nu.nix
#
# Nushell interactive environment assembly.
# Invoked by shell.nix when cfg.shell.shell == "/bin/nu".
#
# Outputs (a list of derivations):
#   - nuConfig        → /etc/nushell/config.nu        (system-wide config)
#   - nuEnv           → /etc/nushell/env.nu            (system-wide env setup)
#   - nuSkelConfig    → /etc/container-skel/config.nu  (copied to ~/.config/nushell/)
#   - nuSkelEnv       → /etc/container-skel/env.nu     (copied to ~/.config/nushell/)
#   - nuPluginReg     → /etc/nushell/plugin-registry.msgpackz (pre-registered plugins)
#
# Tool integrations:
#   - atuin    — shell history (atuin init nu)
#   - starship — prompt (starship init nu)
#   - direnv   — .envrc support (direnv hook nu)
#
# Nushell plugins baked in (registered at image build time):
#   - nu_plugin_query    — query JSON, XML, web data (jq-style for nu)
#   - nu_plugin_formats  — from/to toml, yaml, msgpack, etc.
#   - nu_plugin_gstat    — git status structured output
#   - nu_plugin_highlight — syntax highlighting in output
#   - nu_plugin_polars   — dataframe commands for structured log/data analysis
#   - nu_plugin_semver   — semver parsing and comparison
#
# Plugin registration:
#   Nushell plugins must be registered before use. We pre-register them at
#   image build time by running `nu --commands` against a temp plugin registry,
#   then baking the resulting msgpackz file into /etc/nushell/. The user's
#   config.nu imports from this system registry via $env.NU_PLUGIN_DIRS.

{ pkgs
, cfg
, devEnv
}:

let
  lib = pkgs.lib;
  shellCfg = cfg.shell;

  # ---------------------------------------------------------------------------
  # Tool store paths
  # ---------------------------------------------------------------------------
  starshipBin = "${pkgs.starship}/bin/starship";
  atuinBin    = "${pkgs.atuin}/bin/atuin";
  direnvBin   = "${pkgs.direnv}/bin/direnv";
  editorBin   = "${devEnv}/bin/nvim";
  nuBin       = "${pkgs.nushell}/bin/nu";

  ldLibraryPath = pkgs.lib.makeLibraryPath [
    devEnv
    pkgs.stdenv.cc.cc.lib
  ];

  # ---------------------------------------------------------------------------
  # Plugins
  # All version-matched to nushell 0.111 in nixpkgs.
  # ---------------------------------------------------------------------------
  nuPlugins = with pkgs.nushellPlugins; [
    query      # JSON/XML/web querying — essential for cargo metadata, API data
    formats    # from/to toml, yaml, msgpack — critical for Rust projects
    gstat      # structured git status — replaces bobthefish git integration
    highlight  # syntax highlighting in shell output
    polars     # dataframe commands — log analysis, structured agent output
    semver     # semver parsing — version management in Rust projects
  ];

  # ---------------------------------------------------------------------------
  # Color scheme
  # Gruvbox palette — same as the fish module for visual consistency.
  # ---------------------------------------------------------------------------
  colorPalette =
    if shellCfg.colorScheme == "gruvbox" then {
      foreground = "#ebdbb2";
      background = "#282828";
      comment    = "#928374";
      red        = "#fb4934";
      orange     = "#fe8019";
      yellow     = "#fabd2f";
      green      = "#b8bb26";
      cyan       = "#8ec07c";
      blue       = "#83a598";
      purple     = "#d3869b";
    }
    else throw "shell-nu.nix: unknown colorScheme '${shellCfg.colorScheme}'. Supported: gruvbox";

  # ---------------------------------------------------------------------------
  # Plugin pre-registration derivation
  #
  # Runs `nu --plugin-add` for each plugin binary at build time, producing a
  # plugin registry file that is baked into /etc/nushell/. Users get all
  # plugins available immediately without any post-start setup.
  # ---------------------------------------------------------------------------
  pluginRegistry = pkgs.runCommand "nu-plugin-registry" {
    nativeBuildInputs = [ pkgs.nushell ] ++ nuPlugins;
  } ''
    export HOME=$(mktemp -d)
    mkdir -p $HOME/.config/nushell
    # Start with an empty registry
    touch $HOME/.config/nushell/plugin.msgpackz

    # Register each plugin. nu --plugin-add writes to the user's registry.
    # We then copy the result to the output.
    ${lib.concatMapStrings (plugin:
      let
        # Each plugin derivation has its binary at bin/nu_plugin_<name>
        # Find it by looking in the bin directory
        pluginBin = "${plugin}/bin/${plugin.pname or plugin.name}";
      in ''
        echo "Registering ${plugin.pname or plugin.name}..."
        ${pkgs.nushell}/bin/nu --plugin-add ${pluginBin} \
          --config $HOME/.config/nushell/config.nu 2>/dev/null || \
          echo "Warning: could not register ${pluginBin}, continuing..."
      ''
    ) nuPlugins}

    mkdir -p $out/etc/nushell
    if [ -f "$HOME/.config/nushell/plugin.msgpackz" ]; then
      cp $HOME/.config/nushell/plugin.msgpackz $out/etc/nushell/plugin-registry.msgpackz
    else
      touch $out/etc/nushell/plugin-registry.msgpackz
    fi
  '';

  # ---------------------------------------------------------------------------
  # env.nu (system-wide)
  #
  # Sets environment variables. Nushell sources this before config.nu.
  # Store-path interpolations are safe here — this is a Nix derivation
  # evaluated in the target-arch context.
  # ---------------------------------------------------------------------------
  nuEnvText = ''
    # /etc/nushell/env.nu — system-wide environment setup
    # Generated by nix-container-lib. Edit with care.

    # Editor
    $env.EDITOR = "${editorBin}"
    $env.VISUAL = "${editorBin}"

    # Shell identity
    $env.SHELL = "${nuBin}"

    # Terminal
    $env.TERM = "xterm-256color"
    $env.COLORTERM = "truecolor"

    # Bat (used by man wrapper and syntax highlighting)
    $env.BAT_THEME = "gruvbox-dark"

    # Man pager
    $env.MANPAGER = "sh -c 'col -bx | bat --language man --style plain'"

    # FZF
    $env.FZF_DEFAULT_OPTS = '--prompt="🔭 " --height 80% --layout=reverse --border'
    $env.FZF_DEFAULT_COMMAND = 'rg --files --no-ignore --hidden --follow --glob "!.git/"'

    # LD_LIBRARY_PATH — allows dynamically-linked Rust binaries to find their
    # libraries without nix-shell wrapping. Interactive only (set here, not in
    # the OCI config.Env, so it only affects interactive processes).
    $env.LD_LIBRARY_PATH = "${ldLibraryPath}"

    # Nushell plugin directory — points at the system-wide pre-registered plugins.
    # The user registry at ~/.config/nushell/plugin.msgpackz extends this.
    $env.NU_PLUGIN_DIRS = ["/etc/nushell"]

    # Starship prompt init
    ${starshipBin} init nu | save --force /tmp/starship-init.nu

    # Atuin history init
    ${atuinBin} init nu | save --force /tmp/atuin-init.nu

    # Direnv hook — direnv hook nu is not supported; use json export approach
    # This is the community-standard nushell+direnv integration
    "
# direnv integration for nushell
# Source this file to enable .envrc support
$env.config = ($env.config | upsert hooks {|config|
  let hooks = ($config | get -o hooks | default {})
  $hooks | upsert env_change {|h|
    let existing = ($h | get -o env_change | default {})
    $existing | upsert PWD {|e|
      let existing_pwd = ($e | get -o PWD | default [])
      $existing_pwd | append {||
        if (which direnv | is-not-empty) {
          direnv export json | from json | load-env
        }
      }
    }
  }
})
" | save --force /tmp/direnv-hook.nu
  '';

  # ---------------------------------------------------------------------------
  # config.nu (system-wide)
  #
  # The interactive experience. Sources env.nu outputs and configures the
  # shell appearance, keybindings, and tool integrations.
  # ---------------------------------------------------------------------------
  nuConfigText = ''
    # /etc/nushell/config.nu — system-wide nushell configuration
    # Generated by nix-container-lib. Edit with care.

    # Source the generated integration scripts (produced by env.nu)
    source /tmp/starship-init.nu
    source /tmp/atuin-init.nu
    source /tmp/direnv-hook.nu

    # ---------------------------------------------------------------------------
    # Color theme: ${shellCfg.colorScheme}
    # ---------------------------------------------------------------------------
    let gruvbox = {
      fg:     "${colorPalette.foreground}"
      bg:     "${colorPalette.background}"
      comment: "${colorPalette.comment}"
      red:    "${colorPalette.red}"
      orange: "${colorPalette.orange}"
      yellow: "${colorPalette.yellow}"
      green:  "${colorPalette.green}"
      cyan:   "${colorPalette.cyan}"
      blue:   "${colorPalette.blue}"
      purple: "${colorPalette.purple}"
    }

    # Belt-and-suspenders: suppress welcome banner even if config block errors
    $env.config = ($env.config? | default {} | merge {show_banner: false})

    $env.config = {
      show_banner: false

      # ---------------------------------------------------------------------------
      # Color config
      # ---------------------------------------------------------------------------
      color_config: {
        separator:         $gruvbox.comment
        leading_trailing_space_bg: { attr: n }
        header:            { fg: $gruvbox.blue   attr: b }
        empty:             $gruvbox.blue
        bool:              $gruvbox.cyan
        int:               $gruvbox.cyan
        filesize:          $gruvbox.cyan
        duration:          $gruvbox.cyan
        date:              $gruvbox.purple
        range:             $gruvbox.fg
        float:             $gruvbox.cyan
        string:            $gruvbox.green
        nothing:           $gruvbox.comment
        binary:            $gruvbox.purple
        cell-path:         $gruvbox.fg
        row_index:         { fg: $gruvbox.comment attr: b }
        record:            $gruvbox.fg
        list:              $gruvbox.fg
        block:             $gruvbox.fg
        hints:             $gruvbox.comment
        search_result:     { fg: $gruvbox.red bg: $gruvbox.bg }
        shape_and:         { fg: $gruvbox.purple attr: b }
        shape_binary:      { fg: $gruvbox.purple attr: b }
        shape_block:       { fg: $gruvbox.blue   attr: b }
        shape_bool:        $gruvbox.cyan
        shape_closure:     { fg: $gruvbox.green  attr: b }
        shape_custom:      $gruvbox.green
        shape_datetime:    { fg: $gruvbox.cyan   attr: b }
        shape_directory:   $gruvbox.cyan
        shape_external:    $gruvbox.cyan
        shape_external_resolved: { fg: $gruvbox.green attr: b }
        shape_externalarg: $gruvbox.green
        shape_filepath:    $gruvbox.cyan
        shape_flag:        { fg: $gruvbox.blue   attr: b }
        shape_float:       { fg: $gruvbox.purple attr: b }
        shape_garbage:     { fg: "#ffffff" bg: $gruvbox.red attr: b }
        shape_glob_interpolation: { fg: $gruvbox.cyan attr: b }
        shape_globpattern: { fg: $gruvbox.cyan   attr: b }
        shape_int:         { fg: $gruvbox.purple attr: b }
        shape_internalcall: { fg: $gruvbox.cyan  attr: b }
        shape_keyword:     { fg: $gruvbox.cyan   attr: b }
        shape_list:        { fg: $gruvbox.cyan   attr: b }
        shape_literal:     $gruvbox.blue
        shape_match_pattern: $gruvbox.green
        shape_matching_brackets: { attr: u }
        shape_nothing:     $gruvbox.cyan
        shape_operator:    $gruvbox.orange
        shape_or:          { fg: $gruvbox.purple attr: b }
        shape_pipe:        { fg: $gruvbox.purple attr: b }
        shape_range:       { fg: $gruvbox.yellow attr: b }
        shape_raw_string:  { fg: $gruvbox.green  attr: b }
        shape_record:      { fg: $gruvbox.cyan   attr: b }
        shape_redirection: { fg: $gruvbox.purple attr: b }
        shape_signature:   { fg: $gruvbox.green  attr: b }
        shape_string:      $gruvbox.green
        shape_string_interpolation: { fg: $gruvbox.cyan attr: b }
        shape_table:       { fg: $gruvbox.blue   attr: b }
        shape_vardecl:     { fg: $gruvbox.purple attr: u }
        shape_variable:    $gruvbox.purple
      }

      # ---------------------------------------------------------------------------
      # Cursor style
      # ---------------------------------------------------------------------------
      cursor_shape: {
        emacs:  line
        vi_insert: line
        vi_normal: block
      }

      # ---------------------------------------------------------------------------
      # Vi mode (mirrors viBindings from ShellConfig)
      # ---------------------------------------------------------------------------
      edit_mode: ${if shellCfg.viBindings then "vi" else "emacs"}

      # ---------------------------------------------------------------------------
      # History
      # Atuin takes over history search (Ctrl-R), but nushell's own history
      # is kept as a fallback and for up-arrow navigation.
      # ---------------------------------------------------------------------------
      history: {
        max_size:        100_000
        sync_on_enter:   true
        file_format:     "sqlite"
        isolation:       false
      }

      # ---------------------------------------------------------------------------
      # Completions
      # ---------------------------------------------------------------------------
      completions: {
        case_sensitive: false
        quick:          true
        partial:        true
        algorithm:      "fuzzy"
        external: {
          enable:     true
          max_results: 100
        }
      }

      # ---------------------------------------------------------------------------
      # Table display
      # ---------------------------------------------------------------------------
      table: {
        mode:             rounded
        index_mode:       always
        show_empty:       true
        padding:          { left: 1, right: 1 }
        trim: {
          methodology:    wrapping
          wrapping_try_keep_words: true
          truncating_suffix: "..."
        }
        header_on_separator: false
      }

      # ---------------------------------------------------------------------------
      # Error style
      # ---------------------------------------------------------------------------
      error_style: "fancy"

      # ---------------------------------------------------------------------------
      # Hooks
      # ---------------------------------------------------------------------------
      hooks: {
        # Auto-cd to /workspace on container entry if not already there
        env_change: {
          PWD: [
            { ||
              if ($env.PWD != "/workspace") and (("/workspace" | path exists)) and (not ($env | get -o __NCL_WORKSPACE_CD_DONE | default false)) {
                $env.__NCL_WORKSPACE_CD_DONE = true
                cd /workspace
              }
            }
          ]
        }
      }

      # ---------------------------------------------------------------------------
      # Keybindings — supplement vi mode with convenience bindings
      # ---------------------------------------------------------------------------
      keybindings: [
        # Ctrl-R → atuin history search (atuin hook installs this, listed for clarity)
        # Ctrl-L → clear screen
        {
          name: clear_screen
          modifier: control
          keycode: char_l
          mode: [emacs, vi_normal, vi_insert]
          event: { send: ClearScreen }
        }

      ]
    }

    # ---------------------------------------------------------------------------
    # Commands — mirrors the vendor_functions available in the fish config
    # ---------------------------------------------------------------------------

    # lh: eza with icons and human-readable sizes (matches fish lh alias)
    def lh [...args] {
      if (which eza | is-not-empty) {
        ^eza --icons --long --all --group-directories-first ...$args
      } else {
        ls -la ...$args
      }
    }

    # ocd: cd then list
    def ocd [p: path] { cd $p; lh }

    # shorthands
    alias gst = git status
    alias ll  = ls -l
    alias la  = ls -la

    # bat as man pager
    def man [...args] {
      ^man ...$args | ^bat --language man --style plain
    }

    # lol: random cowsay figure + dotacat (matches fish lol_fig vendor function)
    def lol [...args] {
      let text = ($args | str join " ")
      let cows = (
        try {
          ^find ${pkgs.cowsay}/share/cowsay/cows -name "*.cow" | lines
        } catch { [] }
      )
      if ($cows | is-empty) {
        $text | ^cowsay | ^dotacat
      } else {
        let cow = ($cows | shuffle | first)
        $text | ^cowsay -f $cow -W 79 | ^dotacat
      }
    }

    # ---------------------------------------------------------------------------
    # SSH server management (Dropbear)
    # ---------------------------------------------------------------------------
    def ssh-start [] {
      let ssh_dir = ($env.HOME | path join ".ssh")
      let auth_keys = ($ssh_dir | path join "authorized_keys")
      let rsa_key = ($ssh_dir | path join "dropbear_rsa_host_key")
      let ed25519_key = ($ssh_dir | path join "dropbear_ed25519_host_key")

      if not ("/workspace/authorized_keys" | path exists) {
        print "❌ /workspace/authorized_keys not found. Copy your public key into the container."
        return
      }

      print "🔧 Fixing permissions..."
      mkdir $ssh_dir
      ^chmod 700 $ssh_dir
      ^cp /workspace/authorized_keys $auth_keys
      ^chmod 600 $auth_keys

      if not ($rsa_key | path exists) {
        print "🔑 Generating RSA host key..."
        ^dropbearkey -t rsa -f $rsa_key | ignore
      }
      if not ($ed25519_key | path exists) {
        print "🔑 Generating ED25519 host key..."
        ^dropbearkey -t ed25519 -f $ed25519_key | ignore
      }

      print "🚀 Starting Dropbear on 0.0.0.0:2223"
      ^dropbear -F -E -e -a -s -r $rsa_key -r $ed25519_key -p 0.0.0.0:2223 &
    }

    def ssh-stop [] {
      let pids = (^pgrep dropbear | lines)
      if ($pids | is-empty) {
        print "ℹ️  No Dropbear processes running."
        return
      }
      print "🛑 Stopping Dropbear..."
      for pid in $pids {
        print $"  Killing PID ($pid)"
        ^kill $pid
      }
      print "✔️ Dropbear stopped."
    }

    # ---------------------------------------------------------------------------
    # Greeting — equivalent of fish_greeting
    # Runs once at interactive startup. Uses lol (cowsay + dotacat) if available.
    # Falls back to a plain print if dotacat isn't present.
    # ---------------------------------------------------------------------------
    let container_name = ($env.CONTAINER_NAME? | default (^hostname | str trim))
    let greeting_phrases = [
      "Next stop: Bug-free code!"
      "Compiling dreams into reality."
      "Borrow checker approved. Proceed."
      "Your types are sound. Your logic is not. Good luck."
      "Fearless concurrency awaits."
      "No segfaults were harmed in the making of this shell."
      "cargo build: the optimistic button."
      "It compiles, therefore it is correct. Probably."
      "Lifetime annotations: nature's way of saying slow down."
      "Every unwrap() is a promise to yourself."
      "Move semantics: because sharing is overrated."
      "Rewriting it in Rust was always the answer."
      "Zero-cost abstractions, infinite-cost debugging."
      "async/await: because blocking is a character flaw."
      "If it compiles and the tests pass, ship it."
      "Undefined behavior? Not in this shell."
    ]

    if ("/root/license.txt" | path exists) {
      ^cat /root/license.txt | ^dotacat
    }

    # Display greeting with cowsay + dotacat if available, else plain
    let phrase = ($greeting_phrases | shuffle | first)
    if (which dotacat | is-not-empty) {
      lol $"Welcome to ($container_name)."
      $phrase | ^dotacat
    } else {
      print $"Welcome to ($container_name)."
      print $phrase
    }

    # ---------------------------------------------------------------------------
    # Auto-cd to /workspace
    # ---------------------------------------------------------------------------
    if ("/workspace" | path exists) {
      cd /workspace
    }
  '';

  # ---------------------------------------------------------------------------
  # Skeleton configs (copied to ~/.config/nushell/ by start.sh)
  # Kept minimal — sources system files, leaves room for user overrides.
  # ---------------------------------------------------------------------------
  nuSkelConfigText = ''
    # ~/.config/nushell/config.nu
    # Placed here by the container skeleton. Add personal tweaks below.

    source /etc/nushell/config.nu

    # Personal tweaks (uncomment and customize):
    # $env.config.edit_mode = "emacs"
    # alias gs = git status
  '';

  nuSkelEnvText = ''
    # ~/.config/nushell/env.nu
    # Placed here by the container skeleton. Add personal tweaks below.

    source /etc/nushell/env.nu

    # Personal tweaks (uncomment and customize):
    # $env.MY_VAR = "value"
  '';

in
  [
    (pkgs.writeTextFile {
      name        = "nu-config";
      destination = "/etc/nushell/config.nu";
      text        = nuConfigText;
    })
    (pkgs.writeTextFile {
      name        = "nu-env";
      destination = "/etc/nushell/env.nu";
      text        = nuEnvText;
    })
    (pkgs.writeTextFile {
      name        = "nu-skel-config";
      destination = "/etc/container-skel/config.nu";
      text        = nuSkelConfigText;
    })
    (pkgs.writeTextFile {
      name        = "nu-skel-env";
      destination = "/etc/container-skel/env.nu";
      text        = nuSkelEnvText;
    })
    pluginRegistry
  ]
