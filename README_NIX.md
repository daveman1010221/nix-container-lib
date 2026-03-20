# nix-container-lib Documentation

## Overview

This is the documentation for **nix-container-lib**, the Nix-based OCI container library in this repository.

**The `pi/` directory contains a separate project (the pi coding agent) that is not related to nix-container-lib.**

## Quick Start

### Build the Container

```bash
nix build .#devContainer    # Build dev container
nix build .#ciContainer     # Build CI container
nix build .#agentContainer  # Build agent container
```

### Enter Dev Shell

```bash
nix develop
```

### Type-Check Dhall Configs

```bash
dhall type --file dhall/types.dhall
dhall type --file dhall/defaults.dhall
dhall type --file dhall/prelude.dhall
```

### Run Smoke Test

```bash
nix build .#smokeTest
```

### Check the Flake

```bash
nix flake check
```

## Key Files

### Dhall Configuration Layer

| File | Purpose |
|------|---------|
| `dhall/types.dhall` | Type definitions for container configuration |
| `dhall/defaults.dhall` | Default configurations for dev, CI, agent modes |
| `dhall/prelude.dhall` | Single import point for consumers |

### Nix Implementation Layer

| File | Purpose |
|------|---------|
| `nix/container.nix` | Main entry point (`mkContainer`) |
| `nix/from-dhall.nix` | Dhall → Nix translation |
| `nix/packages.nix` | Package sets by layer |
| `nix/entrypoint.nix` | start.sh generation (runtime behavior) |
| `nix/identity.nix` | Linux filesystem spine |
| `nix/nix-infra.nix` | Nix-in-Nix infrastructure |
| `nix/shell.nix` | Fish shell environment |
| `nix/pipeline.nix` | Pipeline runner |
| `nix/dev-shell.nix` | Host-side dev shell |

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
                                      │ dhall-to-nix
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Nix Layer (Implementation)                       │
│  nix/                                                                       │
│  ├── container.nix      ← mkContainer entry point                           │
│  ├── from-dhall.nix     ← Dhall → Nix translation                           │
│  ├── packages.nix       ← Package sets by layer                             │
│  ├── identity.nix       ← Linux filesystem spine                           │
│  ├── nix-infra.nix      ← Nix-in-Nix infrastructure                        │
│  ├── entrypoint.nix     ← start.sh generation                              │
│  ├── shell.nix          ← Fish shell environment                          │
│  ├── pipeline.nix       ← Pipeline runner                                  │
│  ├── gc-roots.nix       ← GC root registration                             │
│  ├── dev-shell.nix      ← Host-side dev shell                              │
│  ├── gen-certs.nix      ← TLS cert generation                             │
│  └── vendor_functions/  ← Fish function library                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Patterns

1. **Two-Layer Architecture**: Dhall for interface, Nix for implementation
2. **Package Layers**: Composable, ordered package sets (Core must be first)
3. **EnvVar Placement Rule**: BuildTime vs StartTime enforcement
4. **Mode-Driven Entrypoint**: Behavior changes based on mode (Dev/CI/Agent/Pipeline)
5. **Runtime User Provisioning**: User creation happens at container start
6. **Architecture Self-Configuration**: Nix daemon auto-configures at runtime

## Documentation Files

| File | Purpose |
|------|---------|
| `README.md` | Main project documentation |
| `README_NIX.md` | This file - nix-container-lib documentation |
| `PROJECT_SUMMARY.md` | High-level project overview |
| `AGENTS.md` | Project context for AI agents |
| `CONTRIBUTING.md` | Contribution guidelines |
| `DEVELOPER_GUIDE.md` | Developer setup and workflow |
| `docs/architecture.md` | Detailed architecture documentation |

## Directory Structure

```
/workspace/
├── dhall/              # Dhall configuration layer
│   ├── types.dhall
│   ├── defaults.dhall
│   ├── prelude.dhall
│   └── AGENTS.md
├── nix/                # Nix implementation layer
│   ├── container.nix
│   ├── from-dhall.nix
│   ├── packages.nix
│   ├── entrypoint.nix
│   ├── identity.nix
│   ├── nix-infra.nix
│   ├── shell.nix
│   ├── pipeline.nix
│   ├── dev-shell.nix
│   ├── gc-roots.nix
│   ├── gen-certs.nix
│   ├── polar-help.nix
│   ├── AGENTS.md
│   └── vendor_functions/
│       ├── AGENTS.md
│       └── *.fish
├── templates/          # Template flakes
│   ├── dev/
│   ├── ci/
│   ├── agent/
│   └── AGENTS.md
├── docs/               # Documentation
│   ├── architecture.md
│   └── AGENTS.md
├── flake.nix           # Nix flake definition
├── smoke-test.dhall    # Smoke test configuration
├── AGENTS.md           # Project context for AI agents
├── PROJECT_SUMMARY.md  # High-level overview
├── CONTRIBUTING.md     # Contribution guidelines
└── DEVELOPER_GUIDE.md  # Developer setup and workflow
```

## Container Modes

| Mode | Description | Entrypoint |
|------|-------------|------------|
| `Dev` | Interactive developer container | Interactive fish shell |
| `CI` | Headless CI container | Pipeline runner |
| `Agent` | Autonomous agent container | Agent supervisor |
| `Pipeline` | Pipeline runner container | Pipeline runner |

## Package Layers

| Layer | Contents |
|-------|----------|
| `Core` | bash, coreutils, nix, ssl, fish |
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

## When Modifying This Project

1. **Read `nix/entrypoint.nix` first** - Contains critical runtime logic
2. **Check `dhall/types.dhall`** - For type definitions
3. **Verify with `dhall type`** on Dhall files
4. **Test with `nix build .#smokeTest`** for quick validation
5. **Use `nix develop`** to enter the dev shell with all tooling
6. **Don't modify `pi/` directory** - that's a separate project

## Related Documentation

- `README.md` - Main documentation
- `docs/architecture.md` - Architecture deep dive
- `PROJECT_SUMMARY.md` - Detailed project overview

## License

MIT - See LICENSE file for details.
