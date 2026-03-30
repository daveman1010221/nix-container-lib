# nix-container-lib Documentation

## Overview

**nix-container-lib** is a typed, composable OCI container library built on
Nix and Dhall. Project authors write container configs in Dhall, pre-render
them to Nix at authoring time, and the Nix build consumes the rendered output.

## Quick Start

### Build the Smoke Test

```bash
nix build .#smokeTest
```

### Enter Dev Shell

```bash
nix develop
# or:
just dev
```

### Type-Check Dhall Configs

```bash
dhall type < dhall/types.dhall
dhall type < dhall/defaults.dhall
dhall type < dhall/prelude.dhall
```

### Re-render Dhall → Nix

Run this after editing any `.dhall` file:

```bash
just render-smoke-test   # smoke-test.dhall → smoke-test.nix
just render-all          # all tracked .dhall files
```

### Run Flake Check

```bash
nix flake check
# or:
just check
```

---

## Key Concepts

### Why Pre-Render Dhall?

The Nix sandbox has no network access. Dhall's import system fetches
dependencies (including the nix-container-lib prelude) over the network.
Running `dhall-to-nix` inside a Nix build fails with a sandbox violation.

**Solution:** Evaluate Dhall outside the sandbox using `dhall-to-nix`, commit
the resulting `.nix` file, and have the Nix build `import` it directly.

```
container.dhall  →  just render-container  →  container.nix  →  nix build
   (author)            (authoring time,            (committed,      (sandbox-safe)
                         network OK)               pure Nix)
```

### Pinning the Prelude

Template `container.dhall` files import the prelude from a pinned GitHub URL
with a Dhall integrity hash:

```dhall
let Lib =
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall
        sha256:<hash>
```

To get values for a new revision:

```bash
nix-prefetch-git https://github.com/daveman1010221/nix-container-lib
dhall hash <<< "https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall"
```

---

## Key Files

### Dhall Configuration Layer

| File | Purpose |
|------|---------|
| `dhall/types.dhall` | Type definitions for container configuration |
| `dhall/defaults.dhall` | Default configurations for dev, CI, agent, pipeline, minimal modes |
| `dhall/prelude.dhall` | Single import point for consumers |

### Nix Implementation Layer

| File | Purpose |
|------|---------|
| `nix/container.nix` | Main entry point (`mkContainer`) — imports pre-rendered `.nix` |
| `nix/from-dhall.nix` | Translates Dhall-to-Nix output to internal config structure |
| `nix/packages.nix` | Package sets by layer |
| `nix/entrypoint.nix` | start.sh generation (runtime behavior) |
| `nix/identity.nix` | Linux filesystem spine |
| `nix/nix-infra.nix` | Nix-in-Nix infrastructure |
| `nix/shell.nix` | Shell dispatcher (Fish or Nushell) |
| `nix/shell-fish.nix` | Fish shell environment |
| `nix/shell-nu.nix` | Nushell environment |
| `nix/pipeline.nix` | Pipeline runner |
| `nix/dev-shell.nix` | Host-side dev shell |
| `nix/gen-certs.nix` | TLS certificate generation |
| `nix/container-help.nix` | container-help script |

---

## Architecture

### Two-Layer Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Dhall Layer (Interface)                        │
│  dhall/                                                                     │
│  ├── types.dhall        ← Type definitions                                  │
│  ├── defaults.dhall     ← Opinionated defaults                              │
│  └── prelude.dhall      ← Single import point                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                              dhall-to-nix (authoring time, outside sandbox)
                                      │
                              container.nix (committed)
                                      │
                                  import
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Nix Layer (Implementation)                       │
│  nix/                                                                       │
│  ├── container.nix      ← mkContainer entry point                           │
│  ├── from-dhall.nix     ← Dhall → Nix translation                           │
│  ├── packages.nix       ← Package sets by layer                             │
│  ├── identity.nix       ← Linux filesystem spine                            │
│  ├── nix-infra.nix      ← Nix-in-Nix infrastructure                        │
│  ├── entrypoint.nix     ← start.sh generation                               │
│  ├── shell.nix          ← Shell dispatcher                                  │
│  ├── shell-fish.nix     ← Fish shell environment                            │
│  ├── shell-nu.nix       ← Nushell environment                               │
│  ├── pipeline.nix       ← Pipeline runner                                   │
│  ├── gc-roots.nix       ← GC root registration                              │
│  ├── dev-shell.nix      ← Host-side dev shell                               │
│  ├── gen-certs.nix      ← TLS cert generation                               │
│  └── container-help.nix ← Help script                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Patterns

1. **Pre-rendered Dhall**: Dhall evaluated at authoring time, Nix imports the result
2. **Two-Layer Architecture**: Dhall for interface, Nix for implementation
3. **Package Layers**: Composable, ordered package sets (Core must be first)
4. **EnvVar Placement Rule**: BuildTime vs StartTime enforcement
5. **Mode-Driven Entrypoint**: Behavior changes based on mode (Dev/CI/Agent/Pipeline/Minimal)
6. **Runtime User Provisioning**: User creation happens at container start
7. **Architecture Self-Configuration**: Nix daemon auto-configures at runtime

---

## Container Modes

| Mode | Description | Entrypoint |
|------|-------------|------------|
| `Dev` | Interactive developer container | Interactive shell (Fish or Nushell) |
| `CI` | Headless CI container | Pipeline runner |
| `Pipeline` | Pipeline runner container | Pipeline runner |
| `Agent` | Autonomous agent container | Agent supervisor |
| `Minimal` | Single-binary container | Named binary directly |

## Package Layers

| Layer | Contents |
|-------|----------|
| `Core` | bash, coreutils, nix, ssl, fish, nushell |
| `CI` | git, curl, grype, syft, vulnix, skopeo, dhall, jq |
| `Dev` | editors, fzf, bat, eza, atuin, starship, direnv, man |
| `Toolchain` | LLVM 19, Rust nightly, cmake, clang-lld-wrapper |
| `Pipeline` | Static analysis suite, pipeline runner tooling |
| `Agent` | Minimal runtime for autonomous processes |
| `Custom` | Project-specific additions |

## EnvVar Placement Rule

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent. |
| `StartTime` | `start.sh` exports | Store paths allowed. |
| `UserProvided` | Docker run-time | Not emitted by library. |

---

## When Modifying This Project

1. **Read `nix/entrypoint.nix` first** — contains critical runtime logic
2. **Check `dhall/types.dhall`** — for type definitions
3. **Edit `.dhall` files**, then **run `just render-*`** to update the `.nix` files
4. **Verify with `dhall type <`** on Dhall files
5. **Test with `nix build .#smokeTest`** for quick validation
6. **Use `nix develop`** to enter the dev shell with all tooling

## Related Documentation

- `README.md` — Main documentation
- `docs/architecture.md` — Architecture deep dive
- `CONTRIBUTING.md` — Contribution guidelines
- `DEVELOPER_GUIDE.md` — Developer setup and workflow
