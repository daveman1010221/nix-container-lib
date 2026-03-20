# Nix Implementation Layer

## Purpose

This directory contains the **Nix implementation** that translates Dhall configurations into actual OCI image derivations. This is where the "secret sauce" lives - the runtime behavior, architecture detection, and container assembly logic.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Nix Implementation Files                          │
│                                                                             │
│  container.nix     ← Main entry point (mkContainer)                         │
│  from-dhall.nix    ← Dhall → Nix translation                                │
│  packages.nix      ← Package sets by layer                                  │
│  identity.nix      ← Linux filesystem spine                                │
│  nix-infra.nix     ← Nix-in-Nix infrastructure                             │
│  entrypoint.nix    ← start.sh generation (CRITICAL)                         │
│  shell.nix         ← Fish shell environment                                │
│  pipeline.nix      ← Pipeline runner                                         │
│  gc-roots.nix      ← GC root registration                                   │
│  dev-shell.nix     ← Host-side dev shell                                    │
│  gen-certs.nix     ← TLS cert generation                                    │
│  polar-help.nix    ← Help script                                             │
│                                                                             │
│  vendor_functions/ ← Fish function library                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Files

### Critical Files

| File | Purpose | Why It's Important |
|------|---------|-------------------|
| `container.nix` | `mkContainer` entry point | Main API surface, assembles OCI image |
| `from-dhall.nix` | Dhall → Nix translation | Bridge between typed config and implementation |
| `entrypoint.nix` | start.sh generation | **CRITICAL**: Runtime behavior, mode dispatch, architecture detection |
| `packages.nix` | Package sets by layer | Defines what each layer contains |
| `identity.nix` | Linux filesystem spine | Creates valid Linux system (passwd, shadow, etc.) |
| `nix-infra.nix` | Nix-in-Nix infrastructure | Nix daemon, DB, GC roots, registry |
| `shell.nix` | Fish shell environment | Interactive dev experience |
| `pipeline.nix` | Pipeline runner | Automation execution |
| `dev-shell.nix` | Host-side dev shell | `nix develop` shell |
| `gen-certs.nix` | TLS cert generation | mTLS certificates |
| `gc-roots.nix` | GC root registration | Protects derivations from garbage collection |

### Important Pattern: Entrypoint Phases

The `entrypoint.nix` file generates `start.sh` as a composition of discrete phases:

1. **Preamble** - `set -euo pipefail`, helpers
2. **Store-path exports** - StartTime env vars (arch-correct!)
3. **User creation** - Optional, reads CREATE_USER/CREATE_UID/CREATE_GID
4. **Nix daemon** - Optional, provisions nixbld users, starts daemon
5. **Arch config** - aarch64 sandbox/seccomp detection
6. **Cargo cache** - Writable target dir
7. **SSH server** - Optional, Dropbear
8. **Banner** - Summary of what started
9. **Exec handoff** - Mode-specific: shell/pipeline/agent

**CRITICAL:** Store paths in `start.sh` are evaluated in the target-arch derivation context, so they're always correct. This is why `start.sh` is a `pkgs.writeShellScriptBin` derivation.

## The EnvVar Placement Rule (CRITICAL)

This rule exists because of a Nix/OCI interaction that's easy to get wrong:

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent only. |
| `StartTime` | `start.sh` exports | Store paths allowed. |
| `UserProvided` | `docker run -e` | Not emitted by library. |

**Why?** `config.Env` is evaluated once on the build host at flake evaluation time. Any Nix store path interpolated there contains the build host's architecture-specific hash. On cross-arch builds (x86 host building arm64 image), these paths are wrong for the target architecture.

`start.sh` is a derivation evaluated in the **target-arch context**, so interpolated store paths are correct.

## Design Patterns

### 1. Mode-Driven Entrypoint

Container behavior changes based on mode:

```nix
phaseExec =
  if cfg.mode == "dev" then shell-handoff
  else if cfg.mode == "ci" || cfg.mode == "pipeline" then pipeline-runner-handoff
  else if cfg.mode == "agent" then agent-supervisor-handoff
```

### 2. Runtime User Provisioning

User creation happens at **container start**, not build time:

```nix
phaseUserCreation =
  if cfg.user.createUser then ''
    # Reads CREATE_USER/CREATE_UID/CREATE_GID from environment
    # Creates matching user so bind-mounted files have correct ownership
  ''
```

This allows developers on different machines to use the same container image with their own UIDs.

### 3. Architecture Self-Configuration

Nix daemon auto-configures based on detected architecture:

```nix
phaseArchConfig =
  if cfg.nix.enableDaemon then ''
    # Detect qemu-user via CPU implementer field
    # Disable sandbox when running under emulation
  ''
```

### 4. Two-Layer Package Composition

Package layers are NOT cumulative in `packages.nix` - each is standalone. Composition happens at call site:

```nix
resolvedPackages =
  let
    allPkgs = lib.concatMap resolveLayer cfg.packageLayers;
    # Deduplicate by outPath
  in seen.list;
```

## The Nix-in-Nix Problem

The most arcane cluster of knowledge in the library. Handles:

1. **Dynamic linker stub** - `/lib64/ld-linux-x86-64.so.2` or `/lib/ld-linux-aarch64.so.1`
2. **/usr/bin/env stub** - Makes `#!/usr/bin/env` shebangs work
3. **Flake registry pin** - Registers exact nixpkgs revision at build time
4. **Container policy** - `/etc/containers/policy.json` for skopeo/podman
5. **nix.conf base** - Static config; dynamic config added at runtime
6. **FHS directory scaffolding** - `/var/tmp`, `/tmp`, `/workspace`

## Important Invariants

1. **Core layer must be first** - Library asserts this in `from-dhall.nix`
2. **Store paths in start.sh, not config.Env** - EnvVar placement rule
3. **User creation at runtime, not build time** - Allows different UIDs per developer
4. **Architecture detection at runtime** - Works for cross-arch builds
5. **GC roots for all image contents** - Prevents garbage collection

## When Modifying

1. **Read `nix/entrypoint.nix` first** - Contains critical runtime logic
2. **Check `nix/from-dhall.nix`** - For type translation
3. **Verify with `nix build .#smokeTest`** - Quick validation
4. **Test with `nix develop`** - Enter dev shell with tooling
5. **Consider architecture** - Will this work on aarch64, x86, cross-arch?

## Related Documentation

- `docs/architecture.md` - Detailed architecture documentation
- `dhall/types.dhall` - Type definitions
- `dhall/defaults.dhall` - Default configurations
- `templates/*/container.dhall` - Example configurations

## Key Functions

| Function | Purpose |
|----------|---------|
| `mkContainer` | Main entry point, returns `{ image, devShell }` |
| `fromDhall` | Translate Dhall config to Nix |
| `packages` | Access package sets by layer |
| `entrypoint` | Generate start.sh |
| `identity` | Generate filesystem spine |
| `nixInfra` | Generate Nix infrastructure |
| `shell` | Generate shell environment |
| `pipeline` | Generate pipeline runner |
| `gcRoots` | Generate GC roots |
| `devShell` | Generate host-side dev shell |
