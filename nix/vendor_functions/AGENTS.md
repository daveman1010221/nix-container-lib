# Vendor Functions Directory

## Purpose

This directory contains **Fish shell functions** that are shipped with the container and made available to users at runtime. These functions provide convenient tool integrations and workflow helpers.

## Two Categories

### 1. Static Functions

Plain `.fish` files shipped verbatim from the library. Examples:
- `pi-local.fish` - Run pi agent against local llama.cpp server
- `setup_git.fish` - Configure Git with credentials
- `ssh-start.fish` - Start Dropbear SSH server
- `ssh-stop.fish` - Stop Dropbear SSH server
- `nvimf.fish` - Open fzf to find a file, then open in neovim
- `fdfz.fish` - Pipe fd output to fzf
- `nvrun.fish` - Run with NVIDIA PRIME render offload

### 2. Templated Functions

`.nix` files that produce `.fish` files with store path interpolation:
- `lol.nix` - lolcat (dotacat) inside cowsay
- `man.nix` - man pages piped through bat

## How It Works

The functions are wrapped as Nix derivations so they become proper store paths:

```nix
staticFuncPaths =
  let
    entries   = builtins.readDir staticFuncDir;
    names     = builtins.attrNames entries;
    fishFiles = builtins.filter (n: lib.hasSuffix ".fish" n) names;
  in
    map (n: pkgs.writeText n (builtins.readFile (staticFuncDir + "/${n}")))
      fishFiles;
```

This ensures each file lands in its own store path that IS registered in `closureInfo` and present in the image layers.

## Available Functions

### Tool Integration

| Function | Purpose |
|----------|---------|
| `pi-local` | Run pi agent against local llama.cpp server |
| `nvimf` | Open fzf to find a file, then open in neovim |
| `fdfz` | Pipe fd output to fzf |
| `nvrun` | Run with NVIDIA PRIME render offload |
| `nvim_goto_files` | Find files with fzf and open in neovim |
| `nvim_goto_line` | Open file at specific line in neovim |

### Setup Helpers

| Function | Purpose |
|----------|---------|
| `setup_git` | Configure Git with credentials |
| `ssh-start` | Start Dropbear SSH server |
| `ssh-stop` | Stop Dropbear SSH server |
| `start-llama` | Start local llama-server instance |

### Display Functions

| Function | Purpose |
|----------|---------|
| `lol.fish` | lolcat (dotacat) inside cowsay |
| `man.fish` | Man pages piped through bat |
| `lol_fig.fish` | Display ASCII art |
| `lh.fish` | List files with human-readable sizes |
| `lht.fish` | Tree view with human-readable sizes |
| `display_fzf_files` | Display files for fzf selection |
| `display_rg_piped_fzf` | Pipe rg output to fzf |

### Utility Functions

| Function | Purpose |
|----------|---------|
| `filename_get_random` | Get random filename |
| `files_compare` | Compare two files |
| `files_compare_verbose` | Compare two files verbosely |
| `path_exists` | Check if path exists |
| `is_a_directory` | Check if path is a directory |
| `is_valid_argument` | Validate argument |
| `is_valid_dir` | Validate directory |
| `json_validate` | Validate JSON |
| `yaml_to_json` | Convert YAML to JSON |
| `hash_get` | Get hash of file |
| `var_erase` | Clear environment variable |
| `export.fish` | Export helper |
| `prettyjson.fish` | Pretty print JSON |
| `myps.fish` | Show process tree |
| `ocd.fish` | Open current directory |

## Usage in Container

Functions are made available via the `vendor_functions.d` directory:

```fish
# Functions are available in /etc/fish/vendor_functions.d/
# They are automatically loaded when Fish starts
```

## Customization

Users can override or extend functions in their personal config:

```fish
# ~/.config/fish/config.fish
# Add personal tweaks after the source lines

# Override a vendor function
function my-custom-function
    echo "Custom implementation"
end
```

## When Modifying

1. **Static functions** - Edit `.fish` files directly
2. **Templated functions** - Edit `.nix` files, which produce `.fish` files
3. **Test in dev shell** - Use `nix develop` to test changes
4. **Check closure** - Verify functions are in image contents
5. **Document new functions** - Add to this file

## Related Files

- `nix/shell.nix` - How vendor functions are packaged
- `nix/identity.nix` - Filesystem spine
- `nix/entrypoint.nix` - User creation and shell setup
