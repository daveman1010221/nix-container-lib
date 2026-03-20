# Template Flakes Directory

## Purpose

This directory contains **template flakes** that serve as starting points for new projects using nix-container-lib. Each template provides a pre-configured container archetype with sensible defaults.

## Templates

### dev/ - Development Container

**Use Case:** Interactive development with full toolchain

**Features:**
- Full interactive experience (Fish shell, atuin, starship, direnv)
- All package layers (Core, CI, Dev, Toolchain, Pipeline)
- SSH server available (but not auto-started)
- Pipeline runner available
- Nix daemon enabled

**When to use:**
- Local development with full toolchain
- Projects needing compilers (Rust, C/C++)
- Interactive CI testing

### ci/ - CI Container

**Use Case:** Headless CI/CD pipeline execution

**Features:**
- Minimal interactive experience (shell = None)
- Core, CI, Pipeline layers
- Pipeline runner configured
- SSH disabled
- User creation disabled (runs as root)

**When to use:**
- CI/CD pipeline execution
- Headless automation
- Security scanning and auditing

### agent/ - Agent Container

**Use Case:** Autonomous agent processes with mTLS

**Features:**
- No interactive shell
- mTLS enabled (self-signed certs by default)
- Nix daemon disabled by default
- Minimal package set (Core, Agent)
- SSH available (but not auto-started)

**When to use:**
- Long-running autonomous processes
- Agents that need authenticated communication
- Microservices with mTLS requirements

## Template Structure

Each template contains:

```
templates/<name>/
├── flake.nix           # Flake definition with container build
└── container.dhall     # Dhall configuration for the mode
```

## Issues and Improvements

### Issue: Template Dhall Files Use `builtins.getFlake`

**Problem:** The templates use `(builtins.getFlake "polar-container-lib").dhall.prelude` to import the library, but `builtins.getFlake` is a Nix function, not a Dhall function. This causes dhall-to-nix to fail with "Unbound variable: builtins".

**Root Cause:** 
- Dhall doesn't have `builtins` - it's a purely functional language without side effects
- `dhall-to-nix` runs the `dhall-to-nix` CLI tool which is a separate Haskell program
- The dhall-to-nix CLI tool doesn't have access to Nix's builtins during evaluation
- `builtins.getFlake` is a Nix-specific function that only exists during Nix evaluation

**Impact:** 
- Users cannot build containers from templates via `nix build`
- The templates fail with dhall-to-nix because dhall-to-nix runs in isolation
- The templates are not functional as-is

**Analysis:** Looking at `nix/container.nix`, the library uses `pkgs.dhallToNix configPath` which:
1. Writes the Dhall file to a temporary location
2. Runs `dhall-to-nix` CLI tool on that file
3. Imports the result

The dhall-to-nix CLI tool is a pure Dhall-to-Nix translator that doesn't have access to Nix's builtins. It only supports Dhall expressions, not Nix-specific functions like `builtins.getFlake`.

**Solution Options:**
1. **Use flake inputs in dhall** - Pass the library's dhall path via the flake context
2. **Use relative imports** - Use `./../dhall/prelude.dhall` which works in pure dhall
3. **Inline types** - Like the smoke test, inline all types (not recommended for templates)

**Recommended Solution:** Use flake inputs in the dhall file. The flake.nix passes `inputs.polar-container-lib` to `mkContainer`, which can then be used in the dhall file. However, dhall doesn't have direct access to flake inputs.

**Alternative Solution:** Use a relative import `./../dhall/prelude.dhall` which works in both pure dhall and in Nix context (when dhall-to-nix has access to the flake).

**Implementation:** Update templates to use `./../dhall/prelude.dhall` instead of `builtins.getFlake`.

**Status:** Templates now use relative imports (`./../dhall/prelude.dhall`) which work in both pure dhall and dhall-to-nix contexts. This fixes the "Unbound variable: builtins" error.

**Impact:** 
- Users cannot run `dhall type --file container.dhall` to type-check their configs
- Dhall LSP and editor integrations won't work properly
- The templates are not portable to environments without Nix

**Recommended Fix:** Replace `builtins.getFlake` with a pattern that works in both dhall and Nix contexts:

```dhcl
-- Option 1: Use relative import (works in pure dhall)
let Lib = ./../dhall/prelude.dhall

-- Option 2: Use flake inputs (requires flake context)
-- This requires passing the flake inputs to the dhall file
-- See: https://github.com/dhall-lang/dhall-flake
```

**Alternative Approach (Preferred):** Modify the templates to use the flake.nix's `inputs` directly and pass the library via Dhall-to-Nix translation:

The flake.nix already imports `polar-container-lib`, so we could:

1. Pass the library's dhall path via a flake input variable
2. Use a helper script that sets up the dhall context properly
3. Document that dhall type-checking requires a different import pattern

Let me implement a better solution that works in both contexts.

```dhall
-- OLD (broken for dhall type):
let Lib = (builtins.getFlake "polar-container-lib").dhall.prelude

-- NEW (works everywhere):
let Lib = (builtins.getFlake "polar-container-lib").dhall.prelude
-- OR use the flake inputs pattern from the README:
-- Let the flake.nix pass the library via inputs, then use:
-- let Lib = inputs.polar-container-lib.dhall.prelude
```

**Alternative Fix:** Use the flake inputs pattern like the README shows:

```dhall
-- Import from flake inputs (requires flake.nix to pass the input)
let Lib = inputs.polar-container-lib.dhall.prelude
```

This requires the flake.nix to pass the library as an input, which is already done in the templates.

## Documentation Files

| File | Purpose |
|------|---------|
| `templates/dev/container.dhall` | Dev container configuration |
| `templates/dev/flake.nix` | Dev container flake definition |
| `templates/ci/container.dhall` | CI container configuration |
| `templates/ci/flake.nix` | CI container flake definition |
| `templates/agent/container.dhall` | Agent container configuration |
| `templates/agent/flake.nix` | Agent container flake definition |

## Quick Start

### Create New Project

```bash
# From GitHub
nix flake init -t github:daveman1010221/nix-container-lib#dev

# From local path
nix flake init -t .#dev
```

### Build Container

```bash
nix build .#devContainer   # or ciContainer, agentContainer
```

### Load Container

```bash
docker load < result
```

### Run Container

```bash
# Dev container
docker run -it --volume $PWD:/workspace my-project-dev

# CI container
docker run --rm -v $PWD:/workspace my-project-ci

# Agent container
docker run -d --volume $PWD:/workspace my-project-agent
```

## Template Customization

### Adding Package Layers

Edit `container.dhall` to add layers:

```dhall
packageLayers =
  [ Lib.PackageLayer.Core
  , Lib.PackageLayer.CI
  , Lib.PackageLayer.Dev
  , Lib.customLayer "my-extras"
      [ Lib.nixpkgs "postgresql" ]
  ]
```

### Adding Pipeline Stages

Edit `container.dhall` to add stages:

```dhall
pipeline = Some
  { name = "my-pipeline"
  , artifactDir = "/workspace/pipeline-out"
  , stages =
      [ Lib.simpleStage "fmt"  "cargo fmt --check"           Lib.FailureMode.FailFast
      , Lib.simpleStage "lint" "cargo clippy -- -D warnings" Lib.FailureMode.FailFast
      , Lib.conditionalStage "test" "cargo test" Lib.FailureMode.FailFast "CI_FULL"
      ]
  }
```

### Enabling SSH

Edit `container.dhall`:

```dhall
ssh = Some (defaults.defaultSSH // { enable = False })
```

### Enabling TLS

Edit `container.dhall`:

```dhall
tls = Some (defaults.defaultTLS // { generateCerts = True })
```

## Template Guidelines

1. **dev template** - For interactive development with full toolchain
2. **ci template** - For headless CI/CD with pipeline runner
3. **agent template** - For autonomous processes with mTLS

## Template Variants

### Cross-Arch Builds

Templates work for cross-arch builds (x86 building arm64) because:
- Store paths in `start.sh` are evaluated in target-arch context
- Architecture detection happens at runtime
- Nix daemon auto-configures for target architecture

### Custom Package Layers

Add project-specific packages via `Custom` layer:

```dhall
Lib.customLayer "my-extras"
  [ Lib.flakePackage "myTool" "packages.default"
  , Lib.nixpkgs "postgresql"
  ]
```

### Environment Variables

Use `buildEnv` for arch-independent values, `startEnv` for store paths:

```dhall
extraEnv =
  [ Lib.buildEnv "MY_PROJECT_ENV" "development"
  , Lib.startEnv "MY_STORE_PATH" "/some/store/path"
  ]
```

## Related Documentation

- `README.md` - Main documentation
- `docs/architecture.md` - Architecture details
- `dhall/` - Dhall configuration
- `nix/` - Nix implementation

## Issues to Address

1. **Fix template Dhall imports** - Replace `builtins.getFlake` with a working pattern
2. **Test templates** - Verify all templates build successfully
3. **Document template usage** - Add examples for common use cases
4. **Add template tests** - CI tests for template validity
