# Architecture

This document captures the design decisions behind `polar-container-lib` —
the *why* behind the structure, not just the *what*. It should be updated
when a decision changes, not just when code changes.

---

## The Core Thesis

> The developer's container and the CI container are the same container,
> parameterized by invocation mode.

This is not a convenience claim. It is a correctness claim. If the tools
that run in CI are different from the tools available to the developer, you
have two systems that produce different results on the same code. That gap
is where "it passed locally" lives.

The library enforces this by making the pipeline definition a first-class
part of the container configuration — not a separate CI YAML file, not a
Makefile, not a shell script checked in separately. The container carries
its own automation.

---

## The Two-Layer Design

```
┌─────────────────────────────────────────────┐
│  Dhall (interface layer)                    │
│  types.dhall · defaults.dhall · prelude.dhall│
│                                             │
│  What a project author writes.              │
│  Type-safe. Self-documenting. No Nix needed.│
└────────────────────┬────────────────────────┘
                     │ dhall-to-nix
┌────────────────────▼────────────────────────┐
│  Nix (implementation layer)                 │
│  from-dhall · packages · entrypoint · ...   │
│                                             │
│  How the container is actually built.       │
│  All substrate knowledge lives here.        │
│  Project authors never touch this directly. │
└─────────────────────────────────────────────┘
```

The seam between layers is `from-dhall.nix`. It is a pure translation
function — no policy, only structural mapping. Policy lives in Dhall
defaults. Mechanism lives in Nix functions.

---

## The Ten Organizational Concepts

Every line of code in this library belongs to one of these ten concepts.
When adding a feature, identify which concept it belongs to before deciding
where the code goes.

### 1. Identity & Filesystem Spine
*File: `nix/identity.nix`*

What makes a container a valid Linux system before any tools are installed.
Synthesized from Nix rather than copied from a base image — we know exactly
what is in it because we built it.

Parameterized by: user list, system type, shell list.

### 2. Nix-in-Nix Infrastructure
*File: `nix/nix-infra.nix`*

The most arcane cluster of knowledge in the library. Handles:
- `nix.conf` generation
- Nix DB seeding and runtime materialization
- GC root registration
- Flake registry pinning
- nixbld user provisioning

**The Nix DB problem**: The pre-built DB lives in the read-only Nix store.
The Nix daemon requires a writable DB. `start.sh` copies the DB from the
store into writable upper-layer files on first boot. This is the same
split NixOS itself uses.

**The GC root problem**: Without explicit GC roots outside the store,
`nix-collect-garbage` sees no live roots and deletes the container's own
environment. Every derivation in the image contents is registered as a
GC root via symlinks in `/nix/var/nix/gcroots/`.

### 3. Package Environment Assembly
*File: `nix/packages.nix`, `nix/from-dhall.nix`*

Named, composable layers that are merged by `from-dhall.nix`. Layers are
NOT cumulative in `packages.nix` — each is a standalone list. Composition
happens at the call site. This keeps each layer independently inspectable.

Layer ordering is enforced: `Core` must be first. `from-dhall.nix` asserts
this.

### 4. Shell Environment
*File: `nix/shell.nix`*

Entirely optional. CI containers and agent containers set `shell = None`
and pay zero cost for this concept. When present, handles:
- Plugin sourcing order (bobthefish must load before color overrides)
- The `interactiveShellInit` vs `shellInit` split
- Templated function generation (`.nix` → `.fish` with store path interpolation)
- Completion path management

### 5. Runtime Environment Variables
*File: `nix/from-dhall.nix`, `nix/entrypoint.nix`*

The most important invariant the library enforces. See **The EnvVar
Placement Rule** below.

### 6. Entrypoint Composition
*File: `nix/entrypoint.nix`*

`start.sh` is generated as a `pkgs.writeShellScriptBin` derivation — it is
evaluated in the target-arch context, so all interpolated store paths are
arch-correct. This is intentionally different from `config.Env`.

The script is composed from discrete named phases. Each phase is a string
fragment that is conditionally included. This makes the phase composition
readable and testable independently.

Phase order is fixed: preamble → store-path exports → user creation →
arch config → nix daemon → cargo cache → ssh → banner → exec handoff.

The exec handoff is mode-dispatched: `Dev` → interactive shell, `CI`/
`Pipeline` → pipeline runner, `Agent` → supervisor process.

### 7. TLS / Secret Material
*File: `nix/gen-certs.nix`, `nix/dev-shell.nix`*

mTLS certificates generated at build time via the RabbitMQ `tls-gen` tool.
The `need_certs` lazy-generation pattern from the dev shell is preserved:
certs are built on first `nix develop`, not on every shell entry.

The assertion `generateCerts = true AND certsPath = Some path` is an error.
Choose one or the other.

### 8. Image Assembly
*File: `nix/container.nix`*

`mkContainer` assembles the final OCI image. Key decisions:
- `maxLayers = 100` for fine-grained layer caching
- `closureInfo` registers ALL derivations in image contents, not just `devEnv`
- `config.Env` receives only `BuildTime` env vars (no store paths)
- `config.Cmd = [ "/bin/start.sh" ]` — stable path via `buildEnv` symlink

### 9. Developer Shell (Host-Side)
*File: `nix/dev-shell.nix`*

The `nix develop` shell a human uses on their host machine. Shares package
sets and TLS logic with the container but has different constraints:
- `set -euo pipefail` is intentionally NOT used in `shellHook`
- Store paths are safe here (shellHook runs in target-arch `nix develop`)
- TLS env vars are exported after cert generation

### 10. Automation Pipelines
*File: `nix/pipeline.nix`, Dhall `PipelineConfig`*

The pipeline runner interprets `PipelineConfig` at container runtime.
It is not a static script — it reads the stage list and executes each
stage with the correct failure semantics (`FailFast` vs `Collect`).

The `condition` field on a stage enables the "developer runs fast stages,
CI runs everything" pattern without two pipeline definitions. A stage with
`condition = Some "CI_FULL"` is skipped unless `CI_FULL` is set in the
environment.

---

## The EnvVar Placement Rule

This rule exists because of a Nix/OCI interaction that is easy to get wrong
and hard to debug when you do.

`config.Env` in a `dockerTools.buildLayeredImage` call is evaluated **once,
on the build host**, at flake evaluation time. Any Nix store path
interpolated there contains the build host's architecture-specific hash.
When you build an arm64 image on an x86 host (or vice versa), those hashes
are wrong for the target architecture — the paths don't exist in the image.

`start.sh` is a `pkgs.writeShellScriptBin` derivation. It is evaluated in
the **target-arch derivation context**. Store paths interpolated there are
correct for the architecture being built.

The rule:

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent only. |
| `StartTime` | `start.sh` exports | Store paths allowed. |
| `UserProvided` | `docker run -e` | Library does not emit these. |

`from-dhall.nix` routes automatically. Declare intent in Dhall; the library
enforces placement.

---

## What Belongs in the Library vs. in a Project

**In the library:**
- The ten concept implementations
- Named package layers and their contents
- Default configurations for the four archetypes
- The `EnvVar` placement enforcement
- The Nix DB materialization pattern
- GC root registration
- The arch self-configuration logic

**In a project config (Dhall):**
- Container name
- Which layers to include
- Extra packages (via `Custom` layer)
- Pipeline stage definitions and commands
- Project-specific env vars
- Whether TLS/SSH are enabled
- Any overrides to defaults

**Never in either:**
- Secrets (passwords, API keys, private keys)
- Host-specific paths
- User-specific preferences that don't affect reproducibility

---

## Versioning Strategy

The library uses semantic versioning on the flake tag.

- **Patch**: bug fixes, documentation, adding packages to existing layers
- **Minor**: new optional fields in `ContainerConfig`, new named layers,
  new convenience constructors in `prelude.dhall`
- **Major**: breaking changes to `ContainerConfig` field names or types,
  removal of named layers, changes to `EnvVar` placement semantics

Dhall's type system means breaking changes are caught at `dhall-to-nix`
time in consuming projects, not at container build time. This is intentional.

---

## Known Gaps (as of initial implementation)

These are tracked here until they have implementations:

- `nix/identity.nix`: passwd/shadow/group generation
- `nix/nix-infra.nix`: nix.conf, ldLinker, usrBinEnv, fhsDirs, nixRegistry
- `nix/shell.nix`: Fish plugin sourcing, interactiveShellInit/shellInit
- `nix/pipeline.nix`: runtime pipeline runner script
- `nix/gc-roots.nix`: GC root symlink tree
- `nix/dev-shell.nix`: host-side mkShell with TLS wiring
- `nix/polar-help.nix`: help script generation
- `nix/gen-certs.nix`: TLS cert generation (port from polar gen-certs.nix)
- Template flake.nix files for dev/ci/agent
- CI pipeline configuration for the library itself

