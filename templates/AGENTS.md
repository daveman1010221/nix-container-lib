# Template Flakes Directory

## Purpose

This directory contains **template flakes** that serve as starting points for
new projects using nix-container-lib. Each template provides a pre-configured
container archetype with sensible defaults.

---

## Templates

### dev/ — Development Container

**Use Case:** Interactive development with full toolchain

**Features:**
- Full interactive experience (Fish or Nushell, atuin, starship, direnv)
- All package layers (Core, CI, Dev, Toolchain, Pipeline)
- SSH server available (start manually with `ssh-start`)
- Pipeline runner available
- Nix daemon enabled

**When to use:**
- Local development with full toolchain
- Projects needing compilers (Rust, C/C++)
- Interactive CI testing

### ci/ — CI Container

**Use Case:** Headless CI/CD pipeline execution

**Features:**
- No interactive shell
- Core, CI, Pipeline layers
- Pipeline runner configured
- SSH disabled
- User creation disabled (runs as root)

**When to use:**
- CI/CD pipeline execution
- Headless automation
- Security scanning and auditing

### agent/ — Agent Container

**Use Case:** Autonomous agent processes with mTLS

**Features:**
- No interactive shell
- mTLS enabled (self-signed certs by default)
- Nix daemon disabled by default
- Minimal package set (Core, Agent)

**When to use:**
- Long-running autonomous processes
- Agents that need authenticated communication
- Microservices with mTLS requirements

### minimal/ — Minimal Single-Binary Container

**Use Case:** Init containers, sidecar utilities, single-purpose tools

**Features:**
- No interactive shell, no start.sh, no user creation
- Execs a single named binary as the OCI Cmd
- Configurable static UID/GID (default: 65532)
- Minimal package set (Core + Custom)

**When to use:**
- Kubernetes init containers
- Sidecar utilities
- Build step containers

---

## Template Structure

Each template directory contains:

```
templates/<name>/
├── container.dhall   # Dhall config — edit this to customize
├── container.nix     # Pre-rendered Nix — commit this alongside container.dhall
├── flake.nix         # Flake definition — references container.nix
└── Justfile          # render-container, check-dhall, build, load
```

---

## Authoring Workflow

```
1. nix flake init -t github:daveman1010221/nix-container-lib#dev
2. edit container.dhall
3. just render-container   →  regenerates container.nix
4. git add container.dhall container.nix && git commit
5. nix build .#devContainer
```

**Why the render step?** The Nix sandbox has no network access. Dhall's import
system fetches dependencies (including the nix-container-lib prelude) over the
network. Rendering outside the sandbox produces a pure `.nix` file that Nix
can import safely.

---

## Prelude Import

All template `container.dhall` files import the prelude using a pinned GitHub
URL with a Dhall integrity hash:

```dhall
let Lib =
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/bc1246f3372fbb825de2a85e6f3ca9d0779975d5/dhall/prelude.dhall
        sha256:42b061b5cb6c7685afaf7e5bc6210640d2c245e67400b22c51e6bfdf85a89e06
```

This works from any filesystem location — inside or outside the
nix-container-lib repo — because it's a URL import, not a relative path.

To update to a new revision after a nix-container-lib release:

```bash
nix-prefetch-git https://github.com/daveman1010221/nix-container-lib
# note the "rev" field

dhall hash <<< "https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall"
# note the hash

# update the URL and sha256 in container.dhall, then re-render:
just render-container
```

---

## Quick Start

```bash
# Initialize from template
nix flake init -t github:daveman1010221/nix-container-lib#dev

# Render the pre-baked container.nix (requires dhall-nix)
just render-container

# Build the container image
nix build .#devContainer

# Load into Docker or Podman
docker load < result
# or:
podman load -i result

# Run
docker run -it --volume $PWD:/workspace my-project-dev
```

---

## Template Customization

### Adding Package Layers

```dhall
packageLayers =
  [ Lib.PackageLayer.Core
  , Lib.PackageLayer.CI
  , Lib.PackageLayer.Dev
  , Lib.customLayer "my-extras"
      [ Lib.nixpkgs "postgresql"
      , Lib.flakePackage "myTool" "packages.default"
      ]
  ]
```

### Adding Pipeline Stages

```dhall
pipeline = Some
  { name        = "my-pipeline"
  , artifactDir = "/workspace/pipeline-out"
  , workingDir  = "/workspace"
  , outputs     = None { ... }
  , stages      =
      [ Lib.simpleStage "fmt"  "cargo fmt --check"           Lib.FailureMode.Collect
      , Lib.simpleStage "lint" "cargo clippy -- -D warnings" Lib.FailureMode.Collect
      , Lib.conditionalStage "test" "cargo test" Lib.FailureMode.FailFast "CI_FULL"
      ]
  }
```

### Enabling SSH

```dhall
ssh = Some (defaults.defaultSSH // { enable = True, port = 2223 })
```

### Enabling TLS

```dhall
tls = Some (defaults.defaultTLS // { generateCerts = True })
```

### Environment Variables

```dhall
extraEnv =
  [ Lib.buildEnv "MY_PROJECT_ENV" "development"   -- arch-independent, goes in config.Env
  , Lib.startEnv "MY_STORE_PATH"  "/store/path"   -- store paths, goes in start.sh
  ]
```

---

## Related Documentation

- `README.md` — Main documentation with full usage guide
- `DEVELOPER_GUIDE.md` — Workflow for working on the library itself
- `docs/architecture.md` — Architecture details
- `dhall/types.dhall` — Full type reference
- `dhall/defaults.dhall` — All available defaults
