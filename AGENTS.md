# Project Context for AI Agents

## Repository Overview

This is a **monorepo** containing two distinct projects:

### 1. `nix-container-lib` (Main Project)
A typed, composable library for building OCI dev containers with Nix.

**Key Philosophy:** The developer's container and the CI container are the same container, parameterized by invocation mode.

**What it does:**
- Builds reproducible OCI images from Dhall configurations
- Supports four container modes: `Dev` (interactive), `CI` (headless), `Agent` (autonomous), `Pipeline` (runner)
- Composable package layers (Core, CI, Dev, Toolchain, Pipeline, Agent, Custom)
- Automatic environment variable placement enforcement (BuildTime vs StartTime)
- Self-configuring Nix daemons and architecture detection
- mTLS certificate generation for agent containers

### 2. `pi/` (Separate Project - DO NOT ACCESS)
A minimal terminal coding harness. This directory is separate and should not be modified when working on nix-container-lib.

---

## Architecture

### Nix Container Library Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Dhall Layer (Interface)                        │
│  dhall/                                                                     │
│  ├── types.dhall        ← Type definitions (Mode, PackageLayer, etc.)       │
│  ├── defaults.dhall     ← Opinionated defaults (devContainer, ciContainer)  │
│  └── prelude.dhall      ← Single import point for consumers                 │
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
│  ├── polar-help.nix     ← Help script                                      │
│  └── vendor_functions/  ← Fish function library                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Patterns

1. **Two-Layer Architecture**: Dhall for interface (types, defaults), Nix for implementation
2. **Package Layers**: Composable, ordered package sets (Core must be first)
3. **EnvVar Placement Rule**: Enforces correct routing of environment variables
4. **Mode-Driven Entrypoint**: Container behavior changes based on mode (Dev/CI/Agent/Pipeline)
5. **Runtime User Provisioning**: User creation happens at container start, not build time
6. **Architecture Self-Configuration**: Nix daemon auto-configures based on detected architecture

---

## Important Files

### Core Library Files

| File | Purpose |
|------|---------|
| `dhall/types.dhall` | All type definitions for the container configuration contract |
| `dhall/defaults.dhall` | Opinionated defaults for dev, CI, agent, pipeline modes |
| `dhall/prelude.dhall` | Single import point exposing types + defaults |
| `nix/container.nix` | `mkContainer` entry point that assembles OCI images |
| `nix/from-dhall.nix` | Translates Dhall config to Nix structures |
| `nix/packages.nix` | Concrete package lists for each layer |
| `nix/entrypoint.nix` | Generates `start.sh` with mode-dispatched exec |
| `nix/identity.nix` | Creates minimal Linux filesystem spine |
| `nix/nix-infra.nix` | Nix daemon configuration and infrastructure |
| `nix/pipeline.nix` | Pipeline runner script and manifest |
| `nix/shell.nix` | Fish shell environment configuration |
| `nix/dev-shell.nix` | Host-side `nix develop` shell |
| `nix/gc-roots.nix` | GC root registration |
| `nix/gen-certs.nix` | TLS certificate generation |

### Template Files

| Directory | Purpose |
|-----------|---------|
| `templates/dev/` | Dev container template with full toolchain |
| `templates/ci/` | CI container template with pipeline runner |
| `templates/agent/` | Agent container template with mTLS |

### Documentation Files

| File | Purpose |
|------|---------|
| `README.md` | Main documentation for nix-container-lib |
| `docs/architecture.md` | Detailed architecture documentation |
| `CHANGELOG.md` | Version history |
| `PROJECT_SUMMARY.md` | High-level project overview |

---

## Quick Start Commands

### Build the container
```bash
nix build .#devContainer    # Build dev container
nix build .#ciContainer     # Build CI container
nix build .#agentContainer  # Build agent container
```

### Enter dev shell
```bash
nix develop
```

### Type-check Dhall configs
```bash
dhall type --file dhall/types.dhall
dhall type --file dhall/defaults.dhall
dhall type --file dhall/prelude.dhall
dhall type --file smoke-test.dhall
```

### Run smoke test
```bash
nix build .#smokeTest
```

### Check the flake
```bash
nix flake check
```

---

## Container Modes

| Mode | Description | Entrypoint |
|------|-------------|------------|
| `Dev` | Interactive developer container | Interactive fish shell |
| `CI` | Headless CI container | Pipeline runner |
| `Agent` | Autonomous agent container | Agent supervisor |
| `Pipeline` | Pipeline runner container | Pipeline runner |

---

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

---

## EnvVar Placement Rule

This is the most important invariant:

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent values only. |
| `StartTime` | `start.sh` exports | Store paths allowed. Script is a derivation, evaluated in target-arch context. |
| `UserProvided` | Caller's responsibility | Injected at `docker run` time via `-e`. |

---

## Directory Structure

```
/workspace/
├── dhall/              # Dhall configuration layer (types, defaults, prelude)
├── nix/                # Nix implementation layer (container, entrypoint, etc.)
├── templates/          # Template flakes (dev, ci, agent)
├── docs/               # Documentation
├── flake.nix           # Nix flake definition
├── smoke-test.dhall    # Smoke test configuration
├── AGENTS.md           # This file - project context for AI agents
└── PROJECT_SUMMARY.md  # High-level project overview
```

---

## Key Insights for AI Agents

1. **This is NOT the pi coding agent** - that's in the separate `pi/` directory
2. **The "secret sauce" is in `nix/entrypoint.nix`** - generates a shell script that handles mode dispatch, architecture detection, Nix daemon setup, and user creation at container runtime
3. **EnvVar Placement Rule** is critical - store paths must go in `start.sh`, not `config.Env`
4. **Dhall as Interface** - The Dhall layer provides type safety and self-documentation
5. **Package Layers** are composable and must include `Core` first
6. **Mode-Driven Entrypoint** - Container behavior changes based on mode (Dev/CI/Agent/Pipeline)
7. **Runtime User Provisioning** - User creation happens at container start, not build time

---

## When Modifying This Project

1. **Read `nix/entrypoint.nix`** first - it contains the critical runtime logic
2. **Check `dhall/types.dhall`** for type definitions before changing configs
3. **Verify with `dhall type`** on Dhall files before committing
4. **Test with `nix build .#smokeTest`** for quick validation
5. **Use `nix develop`** to enter the dev shell with all tooling available
6. **Don't modify `pi/` directory** - that's a separate project

---

## Related Documentation

- `README.md` - Main documentation
- `docs/architecture.md` - Architecture deep dive
- `PROJECT_SUMMARY.md` - Detailed project overview
