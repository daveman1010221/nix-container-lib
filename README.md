# nix-container-lib

A typed, composable library for building OCI dev containers with Nix.

The library encodes a specific thesis:

> **The developer's container and the CI container are the same container,
> parameterized by invocation mode.**

A developer runs it interactively. CI runs it headlessly. An agent runs
autonomously inside it. The container, the tools, and the pipeline definition
are identical in all three cases. The context changes; the container doesn't.

---

## Architecture

The library is organized in two layers with a clean seam between them.

### Layer 1: Dhall (the interface)

`dhall/` contains the type definitions and opinionated defaults that a
project author writes against. Dhall gives us:

- **Type safety**: configuration errors surface before Nix evaluation
- **Completeness**: union types (Mode, PackageLayer, FailureMode) are exhaustive
- **Composability**: the `//` record override pattern makes project configs concise
- **Self-documentation**: the types ARE the documentation

```
dhall/
  types.dhall     # All type definitions — the contract
  defaults.dhall  # Opinionated starting points — the accumulated wisdom
  prelude.dhall   # Single import point for consumers
```

### Layer 2: Nix (the implementation)

`nix/` contains the functions that translate a `ContainerConfig` into actual
derivations. Each file corresponds to one organizational concept:

```
nix/
  container.nix     # mkContainer: the primary entry point
  from-dhall.nix    # Dhall → internal Nix config translation
  packages.nix      # Package sets keyed by PackageLayer
  identity.nix      # Linux filesystem spine (passwd, shadow, group, etc.)
  nix-infra.nix     # Nix-in-Nix: daemon, DB, GC roots, registry
  entrypoint.nix    # start.sh generation (phase-based, mode-dispatched)
  shell.nix         # Interactive shell configuration (Fish, plugins, theme)
  pipeline.nix      # Pipeline runner and stage execution
  gc-roots.nix      # GC root registration
  dev-shell.nix     # Host-side nix develop shell
  gen-certs.nix     # TLS certificate generation (tls-gen / RabbitMQ)
  polar-help.nix    # polar-help script generation
```

---

## The Ten Concepts

The library is organized around ten orthogonal concerns. Each maps to one or
more files in `nix/`.

| # | Concept | Files |
|---|---------|-------|
| 1 | Identity & Filesystem Spine | `identity.nix` |
| 2 | Nix-in-Nix Infrastructure | `nix-infra.nix` |
| 3 | Package Environment Assembly | `packages.nix`, `from-dhall.nix` |
| 4 | Shell Environment | `shell.nix` |
| 5 | Runtime Environment Variables | `from-dhall.nix`, `entrypoint.nix` |
| 6 | Entrypoint Composition | `entrypoint.nix` |
| 7 | TLS / Secret Material | `gen-certs.nix`, `dev-shell.nix` |
| 8 | Image Assembly | `container.nix` |
| 9 | Developer Shell (Host-Side) | `dev-shell.nix` |
| 10 | Automation Pipelines | `pipeline.nix`, Dhall `PipelineConfig` |

---

## Usage

### 1. Add the library as a flake input

```nix
# your-project/flake.nix
inputs = {
  nix-container-lib.url = "github:daveman1010221/nix-container-lib";
  nix-container-lib.inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Write your container config in Dhall

```dhall
-- your-project/container.dhall
let Lib      = inputs:nix-container-lib/dhall/prelude.dhall
let defaults = Lib.defaults

in defaults.devContainer //
  { name = "my-project"
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.Dev
      , Lib.PackageLayer.Toolchain
      , Lib.PackageLayer.Custom
          { name = "my-extras"
          , packages = [ Lib.nixpkgs "postgresql" ]
          }
      ]
  , pipeline = Some
      { name        = "my-pipeline"
      , artifactDir = "/workspace/out"
      , stages      =
          [ Lib.simpleStage "test" "cargo test" Lib.FailureMode.FailFast ]
      }
  }
```

### 3. Call mkContainer in your flake

```nix
# your-project/flake.nix
outputs = { self, nixpkgs, nix-container-lib, ... }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      container = nix-container-lib.lib.${system}.mkContainer {
        inherit system pkgs inputs;
        configPath = ./container.dhall;
      };
    in {
      packages.devContainer  = container.image;
      devShells.default      = container.devShell;
    }
  );
```

### 4. Bootstrap from a template

```bash
# New project from scratch
nix flake init -t github:daveman1010221/nix-container-lib#dev
```

---

## Package Layers

Layers are composed left to right. `Core` must always be first.

| Layer | Contents |
|-------|----------|
| `Core` | bash, coreutils, nix, ssl, fish |
| `CI` | git, curl, grype, syft, vulnix, skopeo, dhall, jq |
| `Dev` | editors, fzf, bat, eza, atuin, starship, direnv, man |
| `Toolchain` | LLVM 19, Rust nightly, cmake, clang-lld-wrapper |
| `Pipeline` | static analysis suite, pipeline runner tooling |
| `Agent` | minimal runtime for autonomous processes (evolving) |
| `Custom { name, packages }` | project-specific additions |

---

## Container Modes

| Mode | Entrypoint behavior | Shell | Nix daemon |
|------|--------------------|----|---|
| `Dev` | User creation → shell | Fish (interactive) | Yes |
| `CI` | Minimal init → pipeline runner → exit | None | Yes |
| `Pipeline` | Same as CI, semantically distinct | None | Yes |
| `Agent` | Minimal init → agent supervisor | None | Optional |

---

## The EnvVar Placement Rule

This is the most important invariant the library enforces.

`config.Env` in an OCI image is evaluated **once on the build host**. Any
store path interpolated there will contain the build host's architecture hash.
On a cross-arch build (x86 host building arm64 image) this produces wrong paths.

The library enforces a hard split:

| Placement | Goes in | Rule |
|-----------|---------|------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent values only. |
| `StartTime` | `start.sh` exports | Store paths allowed. Script is a derivation, evaluated in target-arch context. |
| `UserProvided` | Caller's responsibility | Injected at `docker run` time via `-e`. |

`from-dhall.nix` routes every `EnvVar` to its correct destination automatically.
You declare intent in Dhall; the library enforces placement.

---

## Design Decisions

### Why Dhall for configuration?

Dhall is a typed, total, importable configuration language that compiles to
Nix via `dhall-to-nix`. It gives us exhaustive union types, record defaults,
and a schema that IS the documentation — without requiring consumers to
understand Nix internals to write a valid config.

### Why not devenv or devshell?

Those tools optimize for host-side dev shells. This library optimizes for
**containerized** environments where the container is also the CI runner and
agent runtime. The goals are different enough to warrant a different tool.

### Why is the pipeline owned by the container?

Because the container IS the pipeline runtime. The tools, the runner, and
the stage definitions are co-deployed. This is the "right-sized devsecops"
guarantee: what runs locally and what runs in CI are provably identical
because they are the same artifact.

### Why is Agent a separate mode and not just a CI variant?

Agents have different trust requirements (mTLS mandatory), different lifecycle
(long-running supervised process vs. exit-with-code), and will likely need
different package compositions as the pattern matures. Keeping them separate
now avoids conflating two things that only superficially look the same.

---

## Repository Layout

```
nix-container-lib/
  flake.nix               # Library flake: exports lib, templates, dhall paths
  dhall/
    lib/
      types.dhall         # All type definitions
      defaults.dhall      # Opinionated starting points
      prelude.dhall       # Single consumer import point
  nix/
    container.nix         # mkContainer (primary entry point)
    from-dhall.nix        # Dhall → Nix translation
    packages.nix          # Package sets by layer
    identity.nix          # Linux filesystem spine
    nix-infra.nix         # Nix-in-Nix infrastructure
    entrypoint.nix        # start.sh generation
    shell.nix             # Shell environment assembly
    pipeline.nix          # Pipeline runner
    gc-roots.nix          # GC root registration
    dev-shell.nix         # Host-side dev shell
    gen-certs.nix         # TLS cert generation
    polar-help.nix        # Help script
  templates/
    dev/                  # nix flake init -t ...#dev
    ci/                   # nix flake init -t ...#ci
    agent/                # nix flake init -t ...#agent
```

