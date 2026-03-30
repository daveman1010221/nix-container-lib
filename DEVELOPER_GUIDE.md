# Developer Guide

This guide provides detailed instructions for developers working on
nix-container-lib.

## Prerequisites

### Required Tools

1. **Nix** (version 2.16 or later)
   - Install: `curl https://nixos.org/nix/install | sh`

2. **dhall-nix** — for pre-rendering `.dhall` → `.nix`
   - Available in the dev shell: `nix develop`
   - Or: `nix shell nixpkgs#dhall-nix`

3. **just** — task runner for render and check recipes
   - Available in the dev shell

4. **Git**

### Easiest Setup

```bash
git clone https://github.com/daveman1010221/nix-container-lib.git
cd nix-container-lib
nix develop   # gives you dhall, dhall-nix, dhall-json, just, jq, git
```

---

## Build and Test

### Re-render the smoke test after editing smoke-test.dhall

```bash
just render-smoke-test
# produces smoke-test.nix — commit both files
```

### Build the smoke test image

```bash
nix build .#smokeTest
# or:
just smoke-test
```

### Run flake check

```bash
nix flake check
# or:
just check
```

---

## Development Workflow

### 1. Make Changes

Edit files in the appropriate directories:
- `dhall/` — Dhall type definitions and defaults
- `nix/` — Nix implementation files
- `templates/` — Template files

### 2. If you edited a `.dhall` file — re-render it

```bash
# For the smoke test:
just render-smoke-test

# For a template:
cd templates/dev && just render-container

# For all tracked .dhall files:
just render-all
```

Commit the `.dhall` source AND the `.nix` output together.

### 3. Type-check Dhall files

```bash
dhall type < dhall/types.dhall
dhall type < dhall/defaults.dhall
dhall type < dhall/prelude.dhall
dhall type < smoke-test.dhall
```

Or use `just check-dhall` which runs all of the above.

### 4. Build smoke test

```bash
nix build .#smokeTest
```

### 5. Run flake check

```bash
nix flake check
```

---

## Key Files

### Dhall Layer

| File | Purpose |
|------|---------|
| `dhall/types.dhall` | Type definitions — the contract |
| `dhall/defaults.dhall` | Default configurations |
| `dhall/prelude.dhall` | Public API (imports types + defaults) |
| `smoke-test.dhall` | Smoke test Dhall config |
| `smoke-test.nix` | Pre-rendered smoke test (committed alongside .dhall) |

### Nix Layer

| File | Purpose |
|------|---------|
| `nix/container.nix` | Main entry point (`mkContainer`) |
| `nix/from-dhall.nix` | Dhall → Nix translation |
| `nix/packages.nix` | Package sets by layer |
| `nix/entrypoint.nix` | start.sh generation (CRITICAL) |
| `nix/identity.nix` | Linux filesystem spine |
| `nix/nix-infra.nix` | Nix-in-Nix infrastructure |
| `nix/shell.nix` | Shell dispatcher (Fish or Nushell) |
| `nix/shell-fish.nix` | Fish shell environment |
| `nix/shell-nu.nix` | Nushell environment |
| `nix/pipeline.nix` | Pipeline runner |
| `nix/dev-shell.nix` | Host-side dev shell |
| `nix/gen-certs.nix` | TLS cert generation |
| `nix/container-help.nix` | container-help script |

### Templates

Each template directory contains:

| File | Purpose |
|------|---------|
| `container.dhall` | Dhall config — edit this |
| `container.nix` | Pre-rendered Nix — commit this |
| `flake.nix` | Consuming flake — references `container.nix` |
| `Justfile` | `render-container`, `check-dhall`, `build`, `load` |

---

## Important Patterns

### The Pre-Render Requirement

Nix sandbox builds have no network access. Dhall imports (including the
prelude) resolve over the network. Running `dhall-to-nix` inside a Nix build
fails.

**Rule:** Every `.dhall` file must have a companion `.nix` file committed
alongside it. Run `just render-*` after every Dhall edit.

### The EnvVar Placement Rule

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent. |
| `StartTime` | `start.sh` exports | Store paths allowed. |
| `UserProvided` | Docker run-time | Not emitted by library. |

### Mode-Driven Entrypoint

Container behavior changes based on mode:
- `Dev` → interactive shell
- `CI` / `Pipeline` → pipeline runner
- `Agent` → agent supervisor
- `Minimal` → exec named binary

### Runtime User Provisioning

User creation happens at container start, not build time. The UID/GID match
the host user via `CREATE_USER` / `CREATE_UID` / `CREATE_GID` env vars.

---

## Common Tasks

### Add a New Package Layer

1. Add variant to `dhall/types.dhall`
2. Add package list to `nix/packages.nix`
3. Add translation in `nix/from-dhall.nix`
4. Re-render affected `.dhall` files
5. Update templates if needed

### Add a New Configuration Field

1. Add field to `ContainerConfig` in `dhall/types.dhall`
2. Add translation in `nix/from-dhall.nix`
3. Use field in relevant Nix files
4. Re-render smoke test and templates

### Add a New Default Configuration

1. Add default in `dhall/defaults.dhall`
2. Re-render smoke test: `just render-smoke-test`
3. Update templates if needed
4. Document in README.md

### Pin to a New Revision

After pushing changes to nix-container-lib, update the pinned prelude in all
`container.dhall` files that reference it:

```bash
nix-prefetch-git https://github.com/daveman1010221/nix-container-lib
# note the "rev" from output

dhall hash <<< "https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall"
# note the hash

# Update the URL and sha256 in each container.dhall, then re-render:
just render-all
```

---

## Debugging

### Debug Dhall Files

```bash
# Type-check
dhall type < dhall/types.dhall

# Translate to JSON (for inspection)
dhall-to-json < dhall/prelude.dhall | jq .

# Translate to Nix
dhall-to-nix < smoke-test.dhall
```

### Debug Nix Expressions

```bash
# Build with verbose output
nix build .#smokeTest --verbose

# Build with trace output
nix build .#smokeTest --show-trace

# Inspect closure
nix build .#smokeTest
nix store ls result
nix store ls result --requisites
```

### Cross-Arch Builds

```bash
nix build .#smokeTest --system aarch64-linux
```

---

## Troubleshooting

### `dhall-to-nix` fails with "Unbound variable"

The `container.dhall` has a placeholder or relative import that can't be
resolved. Ensure the prelude import uses the pinned GitHub URL:

```dhall
let Lib =
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall
        sha256:<hash>
```

### `dhall type` reports `Invalid option '--file'`

`dhall type` reads from stdin. Use `<` instead of `--file`:

```bash
# Wrong:
dhall type --file dhall/types.dhall

# Correct:
dhall type < dhall/types.dhall
```

### `nix build` fails with `called without required argument 'configNixPath'`

The flake is passing `configPath` (old API). Update to `configNixPath`:

```nix
# Old:
configPath = ./container.dhall;

# New:
configNixPath = ./container.nix;
```

### `nix build` fails because `container.nix` doesn't exist

Run `just render-container` to generate it, then commit it.

---

## Resources

- `README.md` — Main documentation
- `docs/architecture.md` — Architecture documentation
- `CONTRIBUTING.md` — Contribution guidelines
- `dhall/` — Dhall configuration
- `nix/` — Nix implementation
- `templates/` — Template flakes
