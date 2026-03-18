# polar-container-lib/nix/shell.nix
#
# Assembles the interactive Fish shell environment.
# Returns a list of derivations for inclusion in image contents.
#
# This module is ONLY invoked when cfg.shell != null. CI containers,
# agent containers, and any other headless mode set shell = None and
# pay zero cost for this entire module.
#
# Outputs (a list of derivations):
#   - shellInitFile           → /etc/fish/shellInit.fish
#   - interactiveShellInitFile → /etc/fish/interactiveShellInit.fish
#   - fishConfig              → /etc/container-skel/config.fish
#   - vendorFuncs             → /etc/fish/vendor_functions.d/*
#
# Design notes on the init file split:
#
#   shellInit.fish        — sources once per shell session (login or interactive).
#                           Sets up vendor_functions.d path, CODE_ROOT, CURRENT_USER_HOME.
#                           Guards against re-sourcing with __fish_nixos_shell_config_sourced.
#                           Conditionally sources interactiveShellInit for login shells.
#
#   interactiveShellInit.fish — the full interactive experience: plugins, colors,
#                               theme, vi bindings, tool integrations (atuin, starship,
#                               direnv, kitty). Guards with __fish_nixos_interactive_config_sourced.
#                               Only runs in interactive sessions.
#
#   config.fish (skel)    — placed in /etc/container-skel/ and copied to
#                           ~/.config/fish/config.fish for each provisioned user
#                           by start.sh. Sources the two system init files.
#                           Kept minimal so user overrides are easy.
#
# Plugin sourcing order matters:
#   1. grc (generic colouriser) — must come before bobthefish or it gets overridden
#   2. bass (bash compat)
#   3. bobthefish — must load ALL its functions before any color/theme overrides
#   4. Color/theme settings — applied after bobthefish loads its defaults
#
# The LD_LIBRARY_PATH export that previously appeared at the end of
# interactiveShellInit is NOT here. It belongs in entrypoint.nix's
# store-path exports phase (StartTime placement) so it is set correctly
# for all processes, not just interactive shells.

{ pkgs
, cfg     # Translated config from from-dhall.nix
, devEnv  # The assembled package environment derivation
}:

let
  lib = pkgs.lib;
  shellCfg = cfg.shell;  # guaranteed non-null by caller (container.nix)

  # ---------------------------------------------------------------------------
  # Resolve plugin derivations from cfg.shell.plugins list
  # Plugin names map to pkgs.fishPlugins.<name>
  # Unknown plugin names produce a clear error rather than a silent omission.
  # ---------------------------------------------------------------------------
  resolvePlugin = name:
    if pkgs.fishPlugins ? ${name}
    then pkgs.fishPlugins.${name}
    else throw "shell.nix: unknown fish plugin '${name}'. Check pkgs.fishPlugins for available plugins.";

  plugins = map resolvePlugin shellCfg.plugins;

  # Convenience bindings for the plugins we have specific sourcing knowledge of
  fisheyGrc  = pkgs.fishPlugins.grc;
  bass       = pkgs.fishPlugins.bass;
  bobthefish = pkgs.fishPlugins.bobthefish;

  # Tool store paths — used in the init file for direct invocation
  starshipBin = "${pkgs.starship}/bin/starship";
  atuinBin    = "${pkgs.atuin}/bin/atuin";
  editorBin   = "${devEnv}/bin/nvim";
  fishShellBin = "${pkgs.fish}/bin/fish";

  # ldLibraryPath for interactive shells — kept here because it's shell-config
  # adjacent, but note: this is a StartTime concern. It's set in interactiveShellInit
  # for interactive processes only, not in config.Env where it would affect everything.
  ldLibraryPath = pkgs.lib.makeLibraryPath [
    devEnv
    pkgs.stdenv.cc.cc.lib
  ];

  # ---------------------------------------------------------------------------
  # Color scheme resolution
  # Currently only gruvbox is supported. The colorScheme field in ShellConfig
  # is reserved for future expansion (solarized, catppuccin, etc.).
  # Adding a new scheme means adding a branch here and a palette block below.
  # ---------------------------------------------------------------------------
  colorPalette =
    if shellCfg.colorScheme == "gruvbox" then {
      foreground = "ebdbb2";
      selection  = "282828";
      comment    = "928374";
      red        = "fb4934";
      orange     = "fe8019";
      yellow     = "fabd2f";
      green      = "b8bb26";
      cyan       = "8ec07c";
      blue       = "83a598";
      purple     = "d3869b";
    }
    else throw "shell.nix: unknown colorScheme '${shellCfg.colorScheme}'. Supported: gruvbox";

  # ---------------------------------------------------------------------------
  # interactiveShellInit.fish
  # The full interactive experience. Evaluated as a Nix derivation so that
  # all store path interpolations are arch-correct.
  # ---------------------------------------------------------------------------
  interactiveShellInitText = ''
    # Only source once per interactive session
    if status is-interactive; and not set -q __fish_nixos_interactive_config_sourced
        set -g __fish_nixos_interactive_config_sourced 1

        # Used for updatedb PRUNEPATHS
        set -gx PRUNEPATHS /dev /proc /sys /media /mnt /lost+found /nix /sys /tmp

        # Plugin sourcing order is load-order sensitive. Do not reorder.
        # GRC must come before bobthefish.
        source ${fisheyGrc}/share/fish/vendor_conf.d/grc.fish
        source ${fisheyGrc}/share/fish/vendor_functions.d/grc.wrap.fish

        # Bass: bash function compatibility in fish
        source ${bass}/share/fish/vendor_functions.d/bass.fish

        # Bobthefish: must load ALL functions before any color/theme overrides
        source ${bobthefish}/share/fish/vendor_functions.d/__bobthefish_glyphs.fish
        source ${bobthefish}/share/fish/vendor_functions.d/fish_mode_prompt.fish
        source ${bobthefish}/share/fish/vendor_functions.d/fish_right_prompt.fish
        source ${bobthefish}/share/fish/vendor_functions.d/__bobthefish_colors.fish
        source ${bobthefish}/share/fish/vendor_functions.d/fish_title.fish
        source ${bobthefish}/share/fish/vendor_functions.d/__bobthefish_display_colors.fish
        source ${bobthefish}/share/fish/vendor_functions.d/fish_prompt.fish
        source ${bobthefish}/share/fish/vendor_functions.d/bobthefish_display_colors.fish

        # Atuin: shell history
        ${atuinBin} init fish | source

        # Starship: prompt (loads after bobthefish; they coexist via bobthefish right prompt)
        source (${starshipBin} init fish --print-full-init | psub)

        # ---------------------------------------------------------------------------
        # Color palette: ${shellCfg.colorScheme}
        # ---------------------------------------------------------------------------
        set -l foreground ${colorPalette.foreground}
        set -l selection  ${colorPalette.selection}
        set -l comment    ${colorPalette.comment}
        set -l red        ${colorPalette.red}
        set -l orange     ${colorPalette.orange}
        set -l yellow     ${colorPalette.yellow}
        set -l green      ${colorPalette.green}
        set -l cyan       ${colorPalette.cyan}
        set -l blue       ${colorPalette.blue}
        set -l purple     ${colorPalette.purple}

        # Syntax highlighting
        set -g fish_color_normal        $foreground
        set -g fish_color_command       $cyan
        set -g fish_color_keyword       $blue
        set -g fish_color_quote         $yellow
        set -g fish_color_redirection   $foreground
        set -g fish_color_end           $orange
        set -g fish_color_error         $red
        set -g fish_color_param         $purple
        set -g fish_color_comment       $comment
        set -g fish_color_selection     --background=$selection
        set -g fish_color_search_match  --background=$selection
        set -g fish_color_operator      $green
        set -g fish_color_escape        $blue
        set -g fish_color_autosuggestion $comment

        # Completion pager
        set -g fish_pager_color_progress    $comment
        set -g fish_pager_color_prefix      $cyan
        set -g fish_pager_color_completion  $foreground
        set -g fish_pager_color_description $comment

        # ---------------------------------------------------------------------------
        # Bobthefish theme settings
        # ---------------------------------------------------------------------------
        # Requires a Nerd Font patched for powerline glyphs.
        # Recommended: 'UbuntuMono Nerd Font 13'
        set -gx theme_nerd_fonts         yes
        set -gx theme_color_scheme       ${shellCfg.colorScheme}
        set -gx theme_display_vi         yes
        set -gx theme_display_sudo_user  yes
        set -gx theme_show_exit_status   yes
        set -gx theme_display_jobs_verbose yes

        # ---------------------------------------------------------------------------
        # Key bindings
        # ---------------------------------------------------------------------------
        ${if shellCfg.viBindings
          then "set -gx fish_key_bindings fish_vi_key_bindings"
          else "# vi bindings disabled (viBindings = false)"}

        # ---------------------------------------------------------------------------
        # LS_COLORS and EZA_COLORS
        # These are long strings — keeping them verbatim from the original.
        # They encode gruvbox-aligned colors for file types in ls/eza output.
        # ---------------------------------------------------------------------------
        set -gx LS_COLORS 'rs=0:di=00;34:ln=00;36:mh=00:pi=40;33:so=00;35:do=00;35:bd=40;33;00:cd=40;33;00:or=40;31;00:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=38;5;196:*.yaml=38;5;226:*.yml=38;5;226:*.json=38;5;226:*.csv=38;5;226:*.tar=38;5;207:*.tgz=38;5;207:*.arc=38;5;207:*.arj=38;5;207:*.taz=38;5;207:*.lha=38;5;207:*.lz4=38;5;207:*.lzh=38;5;207:*.lzma=38;5;207:*.tlz=38;5;207:*.txz=38;5;207:*.tzo=38;5;207:*.t7z=38;5;207:*.zip=38;5;207:*.z=38;5;207:*.dz=38;5;207:*.gz=38;5;207:*.lrz=38;5;207:*.lz=38;5;207:*.lzo=38;5;207:*.xz=38;5;207:*.zst=38;5;207:*.tzst=38;5;207:*.bz2=38;5;207:*.bz=38;5;207:*.tbz=38;5;207:*.tbz2=38;5;207:*.tz=38;5;207:*.deb=38;5;207:*.rpm=38;5;207:*.jar=38;5;207:*.war=38;5;207:*.ear=38;5;207:*.sar=38;5;207:*.rar=38;5;207:*.alz=38;5;207:*.ace=38;5;207:*.zoo=38;5;207:*.cpio=38;5;207:*.7z=38;5;207:*.rz=38;5;207:*.cab=38;5;207:*.wim=38;5;207:*.swm=38;5;207:*.dwm=38;5;207:*.esd=38;5;207:*.jpg=00;35:*.jpeg=00;35:*.mjpg=00;35:*.mjpeg=00;35:*.gif=00;35:*.bmp=00;35:*.pbm=00;35:*.pgm=00;35:*.ppm=00;35:*.tga=00;35:*.xbm=00;35:*.xpm=00;35:*.tif=00;35:*.tiff=00;35:*.png=00;35:*.svg=00;35:*.svgz=00;35:*.mng=00;35:*.pcx=00;35:*.mov=00;35:*.mpg=00;35:*.mpeg=00;35:*.m2v=00;35:*.mkv=00;35:*.webm=00;35:*.webp=00;35:*.ogm=00;35:*.mp4=00;35:*.m4v=00;35:*.mp4v=00;35:*.vob=00;35:*.qt=00;35:*.nuv=00;35:*.wmv=00;35:*.asf=00;35:*.rm=00;35:*.rmvb=00;35:*.flc=00;35:*.avi=00;35:*.fli=00;35:*.flv=00;35:*.gl=00;35:*.dl=00;35:*.xcf=00;35:*.xwd=00;35:*.yuv=00;35:*.cgm=00;35:*.emf=00;35:*.ogv=00;35:*.ogx=00;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:'

        set -gx EZA_COLORS '*.tar=38;5;203:*.tgz=38;5;203:*.arc=38;5;203:*.arj=38;5;203:*.taz=38;5;203:*.lha=38;5;203:*.lz4=38;5;203:*.lzh=38;5;203:*.lzma=38;5;203:*.tlz=38;5;203:*.txz=38;5;203:*.tzo=38;5;203:*.t7z=38;5;203:*.zip=38;5;203:*.z=38;5;203:*.dz=38;5;203:*.gz=38;5;203:*.lrz=38;5;203:*.lz=38;5;203:*.lzo=38;5;203:*.xz=38;5;203:*.zst=38;5;203:*.tzst=38;5;203:*.bz2=38;5;203:*.bz=38;5;203:*.tbz=38;5;203:*.tbz2=38;5;203:*.tz=38;5;203:*.deb=38;5;203:*.rpm=38;5;203:*.jar=38;5;203:*.war=38;5;203:*.ear=38;5;203:*.sar=38;5;203:*.rar=38;5;203:*.alz=38;5;203:*.ace=38;5;203:*.zoo=38;5;203:*.cpio=38;5;203:*.7z=38;5;203:*.rz=38;5;203:*.cab=38;5;203:*.wim=38;5;203:*.swm=38;5;203:*.dwm=38;5;203:*.esd=38;5;203:*.doc=38;5;109:*.docx=38;5;109:*.pdf=38;5;109:*.txt=38;5;109:*.md=38;5;109:*.rtf=38;5;109:*.odt=38;5;109:*.yaml=38;5;172:*.yml=38;5;172:*.json=38;5;172:*.toml=38;5;172:*.conf=38;5;172:*.config=38;5;172:*.ini=38;5;172:*.env=38;5;172:*.jpg=38;5;132:*.jpeg=38;5;132:*.png=38;5;132:*.gif=38;5;132:*.bmp=38;5;132:*.tiff=38;5;132:*.svg=38;5;132:*.mp3=38;5;72:*.wav=38;5;72:*.aac=38;5;72:*.flac=38;5;72:*.ogg=38;5;72:*.m4a=38;5;72:*.mp4=38;5;72:*.avi=38;5;72:*.mov=38;5;72:*.mkv=38;5;72:*.flv=38;5;72:*.wmv=38;5;72:*.c=38;5;142:*.cpp=38;5;142:*.py=38;5;142:*.java=38;5;142:*.js=38;5;142:*.ts=38;5;142:*.go=38;5;142:*.rs=38;5;142:*.php=38;5;142:*.html=38;5;142:*.css=38;5;142::*.nix=38;5;142:*.rs=38;5;142di=38;5;109:ur=38;5;223:uw=38;5;203:ux=38;5;142:ue=38;5;142:gr=38;5;223:gw=38;5;203:gx=38;5;142:tr=38;5;223:tw=38;5;203:tx=38;5;142:su=38;5;208:sf=38;5;208:xa=38;5;108:nb=38;5;244:nk=38;5;108:nm=38;5;172:ng=38;5;208:nt=38;5;203:ub=38;5;244:uk=38;5;108:um=38;5;172:ug=38;5;208:ut=38;5;203:lc=38;5;208:lm=38;5;208:uu=38;5;223:gu=38;5;223:un=38;5;223:gn=38;5;223:da=38;5;109:ga=38;5;108:gm=38;5;109:gd=38;5;203:gv=38;5;142:gt=38;5;108:gi=38;5;244:gc=38;5;203:Gm=38;5;108:Go=38;5;172:Gc=38;5;142:Gd=38;5;203:xx=38;5;237'

        # ---------------------------------------------------------------------------
        # Tool integrations
        # ---------------------------------------------------------------------------

        # Kitty terminal integration (no-op if not running in kitty)
        if set -q KITTY_INSTALLATION_DIR
            set --global KITTY_SHELL_INTEGRATION enabled no-sudo
            source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
            set --prepend fish_complete_path "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_completions.d"
        end

        set -gx EDITOR ${editorBin}
        set -gx SHELL  ${fishShellBin}
        set -gx TERM   xterm-256color

        set -gx BAT_THEME gruvbox-dark

        set -gx MANPAGER "sh -c 'col -bx | bat --language man --style plain'"

        set -xg FZF_CTRL_T_COMMAND "fd --type file --hidden 2>/dev/null | sed 's#^\./##'"
        set -xg FZF_DEFAULT_OPTS   '--prompt="🔭 " --height 80% --layout=reverse --border'
        set -xg FZF_DEFAULT_COMMAND 'rg --files --no-ignore --hidden --follow --glob "!.git/"'

        set -gx NIXOS_OZONE_WL 1

        # LD_LIBRARY_PATH for interactive shells
        # Allows dynamically-linked binaries (e.g. compiled Rust projects) to find
        # their libraries without nix-shell wrapping. Set here rather than in
        # config.Env because it should only affect interactive processes, not
        # every process the container spawns.
        set -gx LD_LIBRARY_PATH "${ldLibraryPath}"

        # ---------------------------------------------------------------------------
        # Completion path management
        #
        # Ensures /etc/fish/generated_completions is always in fish_complete_path,
        # inserted at the correct position relative to any existing generated_completions
        # entry. This is required because fish's completion generation writes to a
        # user-specific path, but we want the system-wide completions available
        # without regenerating them on first run.
        # ---------------------------------------------------------------------------
        begin
          set -l prev (string join0 $fish_complete_path | \
              string match --regex "^.*?(?=\x00[^\x00]*generated_completions.*)" | \
              string split0 | string match -er ".")

          set -l post (string join0 $fish_complete_path | \
              string match --regex "[^\x00]*generated_completions.*" | \
              string split0 | string match -er ".")

          set fish_complete_path $prev "/etc/fish/generated_completions" $post
        end

        # Prevent fish from generating completions on first run by ensuring
        # the target directory exists before fish checks for it.
        if not test -d $__fish_user_data_dir/generated_completions
          $COREUTILS/bin/mkdir $__fish_user_data_dir/generated_completions
        end

        # Clear PATH if NixOS has already set the environment, to avoid
        # accumulating duplicate entries across nested shells.
        if test -n "$__NIXOS_SET_ENVIRONMENT_DONE"
            set -el PATH
            set -eg PATH
            set -eU PATH
        end

        # Direnv hook — must come after PATH is settled
        direnv hook fish | source

        # Auto-cd to /workspace on container entry if not already there
        if test (pwd) != "/workspace"
          cd /workspace
        end
    end
  '';

  # ---------------------------------------------------------------------------
  # shellInit.fish
  # Sources once per session (login or interactive).
  # Minimal: path setup, user home detection, CODE_ROOT.
  # Conditionally sources interactiveShellInit for login shells.
  # ---------------------------------------------------------------------------
  shellInitText = ''
    # Guard to avoid re-sourcing
    if not set -q __fish_nixos_shell_config_sourced
        set -g __fish_nixos_shell_config_sourced 1

        if not contains /etc/fish/vendor_functions.d $fish_function_path
            set --prepend fish_function_path /etc/fish/vendor_functions.d
        end

        # Determine current user's home even when elevated via doas/sudo
        if set -q DOAS_USER
            set -gx CURRENT_USER_HOME /home/$DOAS_USER
        else
            set -gx CURRENT_USER_HOME $HOME
        end

        # Root for code automation scripting tasks
        set -gx CODE_ROOT $CURRENT_USER_HOME/Documents/projects/codes
    end

    # Source the interactive init for login shells
    status is-login; and not set -q __fish_nixos_login_config_sourced
    and begin
        source /etc/fish/interactiveShellInit.fish
        set -g __fish_nixos_login_config_sourced 1
    end
  '';

  # ---------------------------------------------------------------------------
  # config.fish (skeleton — copied to ~/.config/fish/config.fish by start.sh)
  # Kept minimal: sources the two system init files, then leaves room for
  # user-specific overrides. The comment block is intentional — it tells
  # the developer exactly where to add personal configuration.
  # ---------------------------------------------------------------------------
  configFishText = ''
    # ~/.config/fish/config.fish
    # This file was placed here by the container skeleton.
    # Add personal tweaks below the source lines.
  
    # Ensure /usr/bin is in PATH for setuid binaries (e.g. sudo for GPU workloads)
    fish_add_path /usr/bin
  
    source /etc/fish/shellInit.fish
    source /etc/fish/interactiveShellInit.fish
  
    # Personal tweaks (uncomment and customize as needed):
    # set -gx EDITOR nvim
    # alias gs 'git status'
  '';

  # ---------------------------------------------------------------------------
  # Vendor functions
  #
  # Two categories:
  #   static   — plain .fish files shipped verbatim from the library
  #   templated — .nix files that produce .fish files with store path interpolation
  #
  # The library ships its own static functions (the polar function library).
  # Projects can extend via their own Custom package layer — they add fish
  # functions as normal packages, not via this mechanism.
  #
  # Naming: symlinks in vendor_functions.d strip the nix hash prefix from
  # the filename so the function name is clean: "lol.fish" not "abc123-lol.fish"
  # ---------------------------------------------------------------------------
  staticFuncDir = ./vendor_functions;

  # Wrap each static function file as a pkgs.writeText derivation so it
  # becomes a proper Nix store path that is tracked as a closure dependency.
  # Raw path literals (./vendor_functions/lh.fish) resolve to the library
  # source tree store path, which is NOT included in the container image
  # closure — causing dangling symlinks inside the container.
  # Wrapping as derivations ensures each file lands in its own store path
  # that IS registered in closureInfo and present in the image layers.
  staticFuncPaths =
    let
      entries   = builtins.readDir staticFuncDir;
      names     = builtins.attrNames entries;
      fishFiles = builtins.filter (n: lib.hasSuffix ".fish" n) names;
    in
      map (n: pkgs.writeText n (builtins.readFile (staticFuncDir + "/${n}")))
        fishFiles;

  # Templated functions: lol.nix and man.nix from the original polar
  lolFunc = pkgs.writeText "lol.fish" ''
    function lol --description="lolcat (dotacat) inside cowsay"
        printf "%s\n" $argv | \
            cowsay -n -f (set cows (ls ${pkgs.cowsay}/share/cowsay/cows); \
            set total_cows (count $cows); \
            set random_cow (random 1 $total_cows); \
            set my_cow $cows[$random_cow]; \
            echo -n $my_cow | \
            cut -d '.' -f 1) -W 79 | \
            dotacat
    end
  '';

  manFunc = pkgs.writeText "man.fish" ''
    function man --description="Get the page, man"
        ${pkgs.man}/bin/man $argv | bat --language man --style plain
    end
  '';

  templatedFuncs = [ lolFunc manFunc ];

  vendorFuncs = pkgs.runCommand "fish-vendor-funcs" {}
    (let
       allPaths = staticFuncPaths ++ templatedFuncs;
       list     = lib.concatStringsSep " " (map toString allPaths);
     in ''
       mkdir -p $out/etc/fish/vendor_functions.d
       for f in ${list}; do
         clean=$(basename "$f" | sed -E 's/^[0-9a-z]{32,}-//')
         ln -s "$f" "$out/etc/fish/vendor_functions.d/$clean"
       done
     '');

  # ---------------------------------------------------------------------------
  # Assembled derivations
  # ---------------------------------------------------------------------------
  interactiveShellInitFile = pkgs.writeTextFile {
    name        = "interactiveShellInit.fish";
    destination = "/etc/fish/interactiveShellInit.fish";
    text        = interactiveShellInitText;
  };

  shellInitFile = pkgs.writeTextFile {
    name        = "shellInit.fish";
    destination = "/etc/fish/shellInit.fish";
    text        = shellInitText;
  };

  fishConfig = pkgs.writeTextFile {
    name        = "fish-config";
    destination = "/etc/container-skel/config.fish";
    text        = configFishText;
  };

  # ---------------------------------------------------------------------------
  # /etc/fish/conf.d entry
  # Fish automatically sources all *.fish files in /etc/fish/conf.d/ at
  # startup — for every shell, before any user config. This is the correct
  # mechanism to ensure shellInit.fish (which adds vendor_functions.d to
  # $fish_function_path) runs before direnv, before the greeting, and before
  # any interactive input. Without this, vendor functions are not available
  # until direnv loads the dev shell.
  # ---------------------------------------------------------------------------
  fishConfD = pkgs.writeTextFile {
    name        = "polar-init.fish";
    destination = "/etc/fish/conf.d/polar-init.fish";
    text        = ''
      # Sourced automatically by Fish at startup via conf.d mechanism.
      # Loads vendor_functions.d into $fish_function_path and sources
      # interactiveShellInit for login shells.
      source /etc/fish/shellInit.fish
    '';
  };

in
  # Return a list of derivations for container.nix to include in shellFiles
  [ interactiveShellInitFile shellInitFile fishConfig vendorFuncs fishConfD ]
