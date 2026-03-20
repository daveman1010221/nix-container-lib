# Dhall Configuration Layer

## Purpose

This directory contains the **typed interface** for the nix-container-lib. Dhall provides:
- Type safety: configuration errors surface before Nix evaluation
- Completeness: union types are exhaustive
- Composability: record override pattern makes configs concise
- Self-documentation: types ARE the documentation

## Files

| File | Purpose |
|------|---------|
| `types.dhall` | All type definitions (Mode, PackageLayer, ContainerConfig, etc.) |
| `defaults.dhall` | Opinionated defaults for dev, CI, agent, pipeline modes |
| `prelude.dhall` | Single import point exposing types + defaults |

## Usage Pattern

```dhall
-- Import the library
let Lib = (builtins.getFlake "polar-container-lib").dhall.prelude
let defaults = Lib.defaults

-- Extend defaults with project-specific configuration
defaults.devContainer //
  { name = "my-project"
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.Dev
      , Lib.customLayer "my-extras" [ Lib.nixpkgs "postgresql" ]
      ]
  }
```

## Type Reference

### Mode
The primary dispatch axis for the container. Determines entrypoint behavior.

- `Dev` → interactive shell, nix-daemon, full user setup
- `CI` → headless, pipeline runner, minimal init, exit with code
- `Agent` → supervised process, mTLS required, no interactive shell
- `Pipeline` → explicit pipeline runner mode, dev-adjacent but non-interactive

### PackageLayer
Named, composable package set categories.

- `Core` → minimum viable Linux container
- `CI` → audit/scan tools
- `Dev` → interactive tools
- `Toolchain` → compiler stack
- `Pipeline` → pipeline runner + tools
- `Agent` → agent runtime tooling
- `Custom { name, packages }` → project-specific additions

### EnvVarPlacement
Encodes WHERE an environment variable should be materialized.

- `BuildTime` → safe for config.Env (no store paths)
- `StartTime` → must go in start.sh (store paths)
- `UserProvided` → injected at container run time

## Important Rules

1. **Always import `prelude.dhall`** - not individual files
2. **Use `//` record override** - makes configs concise
3. **PackageLayers must include Core first** - library asserts this
4. **EnvVar placement matters** - BuildTime vs StartTime has critical implications

## Key Functions in Prelude

| Function | Purpose |
|----------|---------|
| `nixpkgs attrPath` | Build a PackageRef pointing at nixpkgs |
| `flakePackage input attrPath` | Build a PackageRef pointing at a flake input |
| `customLayer name packages` | Build a Custom PackageLayer |
| `simpleStage name command failureMode` | Build a simple Stage |
| `conditionalStage name command failureMode condition` | Build a conditional Stage |
| `buildEnv name value` | Build a BuildTime EnvVar |
| `startEnv name value` | Build a StartTime EnvVar |
| `runtimeEnv name value` | Build a UserProvided EnvVar |

## Debugging

```bash
# Type-check a Dhall file
dhall type --file types.dhall
dhall type --file defaults.dhall
dhall type --file prelude.dhall

# Translate to JSON
dhall-to-json --file prelude.dhall

# Translate to YAML
dhall-to-yaml --file prelude.dhall
```

## When Modifying

1. **Types are contract** - changing types requires updating consumers
2. **Defaults are opinionated** - they encode accumulated wisdom
3. **Prelude is public API** - add convenience constructors here, not to types
4. **Use `//` for overrides** - this is the pattern consumers expect

## Related Files

- `nix/from-dhall.nix` - Dhall → Nix translation
- `nix/container.nix` - Main entry point using Dhall configs
- `templates/*/container.dhall` - Example Dhall configs
