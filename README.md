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
  container.nix       # mkContainer: the primary entry point
  from-dhall.nix      # Dhall → internal Nix config translation
  packages.nix        # Package sets keyed by PackageLayer
  identity.nix        # Linux filesystem spine (passwd, shadow, group, etc.)
  nix-infra.nix       # Nix-in-Nix: daemon, DB, GC roots, registry
  entrypoint.nix      # start.sh generation (phase-based, mode-dispatched)
  shell.nix           # Shell dispatcher (Fish or Nushell)
  shell-fish.nix      # Fish shell environment
  shell-nu.nix        # Nushell environment
  pipeline.nix        # Pipeline runner and stage execution
  gc-roots.nix        # GC root registration
  dev-shell.nix       # Host-side nix develop shell
  gen-certs.nix       # TLS certificate generation
  container-help.nix  # container-help script generation
```

---

## The Ten Concepts

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
inputs = {
  nix-container-lib.url = "github:daveman1010221/nix-container-lib";
  nix-container-lib.inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Write your container config in Dhall

Import the prelude using a pinned URL with integrity hash:

```dhall
-- container.dhall
let Lib =
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/bc1246f3372fbb825de2a85e6f3ca9d0779975d5/dhall/prelude.dhall
        sha256:42b061b5cb6c7685afaf7e5bc6210640d2c245e67400b22c51e6bfdf85a89e06

let defaults = Lib.defaults

in defaults.devContainer //
  { name = "my-project"
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.Dev
      , Lib.PackageLayer.Toolchain
      , Lib.customLayer "my-extras"
          [ Lib.nixpkgs "postgresql" ]
      ]
  }
```

To get the hash values for a different revision:

```bash
nix-prefetch-git https://github.com/daveman1010221/nix-container-lib
# use the "rev" field from the output, then:
dhall hash <<< "https://raw.githubusercontent.com/daveman1010221/nix-container-lib/<rev>/dhall/prelude.dhall"
```

### 3. Pre-render the Dhall to Nix

The Nix sandbox has no network access, so Dhall cannot be evaluated at build
time. Pre-render it once at authoring time and commit the result alongside the
Dhall source:

```bash
# requires dhall-nix: nix shell nixpkgs#dhall-nix
dhall-to-nix < container.dhall > container.nix
git add container.dhall container.nix
```

Or use the Justfile recipe provided in every template:

```bash
just render-container
```

Re-run this step whenever you edit `container.dhall`.

### 4. Call mkContainer in your flake

```nix
container = nix-container-lib.lib.${system}.mkContainer {
  inherit system pkgs inputs;
  configNixPath = ./container.nix;  # pre-rendered from container.dhall
};
```

### 5. Bootstrap from a template

```bash
nix flake init -t github:daveman1010221/nix-container-lib#dev
# edit container.dhall, then:
just render-container
nix build .#devContainer
```

Available templates: `dev`, `ci`, `agent`, `minimal`.

---

## Package Layers

Layers are composed left to right. `Core` must always be first.

| Layer | Contents |
|-------|----------|
| `Core` | bash, coreutils, nix, ssl, fish, nushell |
| `CI` | git, curl, grype, syft, vulnix, skopeo, dhall, jq |
| `Dev` | editors, fzf, bat, eza, atuin, starship, direnv, man |
| `Toolchain` | LLVM 19, Rust nightly, cmake, clang-lld-wrapper |
| `Pipeline` | static analysis suite, pipeline runner tooling |
| `Agent` | minimal runtime for autonomous processes (evolving) |
| `Custom { name, packages }` | project-specific additions |

---

## Container Modes

| Mode | PID 1 | Session | vigild runs | Nix daemon |
|------|-------|---------|-------------|------------|
| `Dev` | the shell (vigild in the background); vigild when headless | the user from `CREATE_USER`/`CREATE_UID`/`CREATE_GID`, else root | nix-daemon, dropbear | Yes |
| `InfraAgent` | the shell; vigild when headless | root | the agent supervisor (its exit ends the container), dropbear | Optional |
| `AIAgent` | the shell; vigild when headless | the user from the environment, else root | the agent supervisor (restarted), dropbear | Optional |
| `System` | vigild | none | the config's `services` | No |
| `Minimal` | the named binary, directly | — | — | No |

`CONTAINER_HEADLESS=1` at run time makes a `Dev`, `InfraAgent` or `AIAgent` container headless: vigild is PID 1, and the shell is reached by a login over SSH.

## Startup and Services

How a non-minimal container starts is `startup`, in three independent parts. `startup = None` takes the mode's own, as in the table above.

```dhall
startup = Some
  { session = Lib.Session.None          -- None | FromEnv SessionFallback | Fixed { name, uid, gid }
  , boot =                              -- done once, at each start, before anything runs
    [ Lib.BootStep.DelegateCgroups      -- move to /init.scope, hand the cgroup controllers down
    , Lib.BootStep.Sysctls "/etc/sysctl.d/99-node.conf"
    , Lib.BootStep.NftRuleset "/etc/nftables/node.nft"
    , Lib.BootStep.Script { name = "prepare", command = "/bin/prepare-node", required = True }
    ]
  , launch = Lib.Launch.System          -- Interactive { allowHeadless } | Headless | System
  }
```

- **session**: `None` creates no user; a shell or a login is root, with home `/root`. `FromEnv Root` creates the user `CREATE_USER`/`CREATE_UID`/`CREATE_GID` name, and runs as root when they are not set; `FromEnv Refuse` does not start without them. `Fixed` creates the user it names.
- **boot**: `DelegateCgroups` is for a container that runs containers (a Kubernetes node): it needs `--cgroupns=private` and a writable cgroup filesystem (`--privileged`), and fails the start without them. A sysctl or a ruleset that does not apply is a warning; a `Script` fails the start when `required`.
- **launch**: `System` runs vigild as PID 1 and sets nothing up for a shell or a login.

`services` are vigild services, written into its layer beside the mode's own:

```dhall
services =
  [ Lib.defaults.defaultService //
      { name = "etcd", summary = "etcd", command = "/bin/etcd-run", killDelay = Some "10s" }
  , Lib.defaults.defaultService //
      { name = "kube-apiserver", summary = "API server", command = "/bin/apiserver-run"
      , after = [ "etcd" ]
      }
  ]
```

A service starts once those it is `after` are running, not once they are done: one that needs another's output waits for it itself. `onSuccess`/`onFailure` are `Restart`, `Ignore`, `Shutdown`, `SuccessShutdown` or `FailureShutdown`; `logs` is `Enabled` (vigild's buffer and its stdout), `Disabled` (the buffer only: `vigil logs`) or `Passthrough`. `smoke-test-system.dhall` is a complete `System` container.

---

## The EnvVar Placement Rule

`config.Env` in an OCI image is evaluated once on the build host. Store paths
interpolated there contain the build host's architecture hash — wrong on
cross-arch builds.

| Placement | Goes in | Rule |
|-----------|---------|------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent values only. |
| `StartTime` | `start.sh` exports | Store paths allowed. Evaluated in target-arch context. |
| `UserProvided` | `docker run -e` | Injected at runtime by the caller. |

`from-dhall.nix` routes every `EnvVar` to its correct destination automatically.

---

## Design Decisions

### Why Dhall for configuration?

Dhall is a typed, total, importable configuration language. It gives exhaustive
union types, record defaults, and a schema that IS the documentation — without
requiring consumers to understand Nix internals to write a valid config.

### Why pre-render Dhall to Nix rather than evaluate at build time?

The Nix sandbox has no network access. Dhall's import system resolves
dependencies over the network, so `pkgs.dhallToNix` fails inside a sandbox
build when the Dhall file imports from a URL.

Pre-rendering moves Dhall evaluation to authoring time where network access is
available. The resulting `.nix` file is pure Nix — sandbox-safe, deterministic,
and diffable in PRs. You still get full Dhall type safety at authoring time;
the committed `.nix` is the validated, normalized output.

### Why not devenv or devshell?

Those tools optimize for host-side dev shells. This library optimizes for
**containerized** environments where the container is also the CI runner and
agent runtime.

### Why is the pipeline owned by the container?

Because the container IS the pipeline runtime. The tools, the runner, and the
stage definitions are co-deployed. What runs locally and what runs in CI are
provably identical because they are the same artifact.

---

## Repository Layout

```
nix-container-lib/
  flake.nix               # Library flake: exports lib, templates, dhall paths
  Justfile                # render-smoke-test, check-dhall, render-all
  smoke-test.dhall        # Smoke test Dhall config
  smoke-test.nix          # Pre-rendered smoke test (committed)
  smoke-test-system.dhall # A System-mode container: boot steps, services
  smoke-test-system.nix   # Pre-rendered (committed)
  dhall/
    types.dhall           # All type definitions
    defaults.dhall        # Opinionated starting points
    prelude.dhall         # Single consumer import point
  nix/
    container.nix         # mkContainer (primary entry point)
    from-dhall.nix        # Dhall → Nix translation
    packages.nix          # Package sets by layer
    identity.nix          # Linux filesystem spine
    nix-infra.nix         # Nix-in-Nix infrastructure
    entrypoint.nix        # start.nu generation: boot steps, session, launch
    shell.nix             # Shell dispatcher
    shell-fish.nix        # Fish shell environment
    shell-nu.nix          # Nushell environment
    pipeline.nix          # Pipeline runner
    gc-roots.nix          # GC root registration
    dev-shell.nix         # Host-side dev shell
    gen-certs.nix         # TLS cert generation
    container-help.nix    # Help script
  templates/
    dev/                  # nix flake init -t ...#dev
      container.dhall     # Dhall config (edit this)
      container.nix       # Pre-rendered Nix (commit this)
      flake.nix
      Justfile            # render-container recipe
    ci/                   # nix flake init -t ...#ci
    agent/                # nix flake init -t ...#agent
    minimal/              # nix flake init -t ...#minimal
```
