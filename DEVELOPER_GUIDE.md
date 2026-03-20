# Developer Guide

This guide provides detailed instructions for developers who want to work on nix-container-lib.

## Prerequisites

### Required Tools

1. **Nix** (version 2.16 or later)
   - Package manager for building and managing dependencies
   - Install: `curl https://nixos.org/nix/install | sh`

2. **Dhall** (version 19.1 or later)
   - Configuration language with type safety
   - Install: `nix-env -iA dhall-json`

3. **Git**
   - Version control
   - Install via your package manager or `brew install git`

### Optional Tools

1. **jq** - JSON inspection
   - Install: `nix-env -iA jq` or `brew install jq`

2. **fd** - Fast file finder
   - Install: `nix-env -iA fd` or `brew install fd`

3. **ripgrep** - Fast text search
   - Install: `nix-env -iA ripgrep` or `brew install ripgrep`

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/daveman1010221/nix-container-lib.git
cd nix-container-lib
```

### Enter Development Environment

```bash
nix develop
```

This gives you access to all development tools in the correct versions.

### Verify Installation

```bash
# Check Nix version
nix --version

# Check Dhall version
dhall --version

# Check jq (if installed)
jq --version
```

## Build and Test

### Build Smoke Test

The smoke test exercises the full build chain:

```bash
nix build .#smokeTest
```

This validates:
- Dhall parsing and type-checking
- Type translation from Dhall to Nix
- Package resolution
- Image assembly
- All ten organizational concepts

### Run Flake Check

```bash
nix flake check
```

This runs all checks defined in the flake.

### Build Container Images

```bash
# Build dev container
nix build .#devContainer

# Build CI container
nix build .#ciContainer

# Build agent container
nix build .#agentContainer
```

### Enter Dev Shell

```bash
nix develop
```

This gives you access to development tools:
- `dhall` - Type-checking and translation
- `dhall-json` - JSON translation
- `dhall-nix` - Nix translation
- `nix` - Building and evaluation
- `jq` - JSON inspection
- `git` - Version control

## Development Workflow

### 1. Make Changes

Edit files in the appropriate directories:
- `dhall/` - Dhall configuration files
- `nix/` - Nix implementation files
- `templates/` - Template files

### 2. Type-Check Dhall Files

```bash
# Type-check all Dhall files
dhall type --file dhall/types.dhall
dhall type --file dhall/defaults.dhall
dhall type --file dhall/prelude.dhall
dhall type --file smoke-test.dhall
```

### 3. Build Smoke Test

```bash
nix build .#smokeTest
```

### 4. Run Flake Check

```bash
nix flake check
```

### 5. Build Container (Optional)

```bash
nix build .#devContainer
```

## Key Files to Understand

### Dhall Layer

| File | Purpose |
|------|---------|
| `dhall/types.dhall` | Type definitions - the contract |
| `dhall/defaults.dhall` | Default configurations |
| `dhall/prelude.dhall` | Public API (imports types + defaults) |

### Nix Layer

| File | Purpose |
|------|---------|
| `nix/container.nix` | Main entry point (`mkContainer`) |
| `nix/from-dhall.nix` | Dhall → Nix translation |
| `nix/packages.nix` | Package sets by layer |
| `nix/entrypoint.nix` | start.sh generation (CRITICAL) |
| `nix/identity.nix` | Linux filesystem spine |
| `nix/nix-infra.nix` | Nix-in-Nix infrastructure |
| `nix/shell.nix` | Fish shell environment |
| `nix/pipeline.nix` | Pipeline runner |
| `nix/dev-shell.nix` | Host-side dev shell |

### Templates

| Directory | Purpose |
|-----------|---------|
| `templates/dev/` | Dev container template |
| `templates/ci/` | CI container template |
| `templates/agent/` | Agent container template |

## Important Patterns

### The EnvVar Placement Rule

This is the most important invariant:

| Placement | Destination | Constraint |
|-----------|-------------|-----------|
| `BuildTime` | `config.Env` | No store paths. Arch-independent. |
| `StartTime` | `start.sh` exports | Store paths allowed. |
| `UserProvided` | Docker run-time | Not emitted by library. |

### Mode-Driven Entrypoint

Container behavior changes based on mode:
- `Dev` → interactive shell
- `CI` → pipeline runner
- `Agent` → agent supervisor

### Runtime User Provisioning

User creation happens at container start, not build time.

## Common Tasks

### Add a New Package Layer

1. Add variant to `dhall/types.dhall`
2. Add package list to `nix/packages.nix`
3. Add translation in `nix/from-dhall.nix`
4. Update templates if needed

### Add a New Configuration Field

1. Add field to `ContainerConfig` in `dhall/types.dhall`
2. Add translation in `nix/from-dhall.nix`
3. Use field in relevant Nix files

### Add a New Default Configuration

1. Add default in `dhall/defaults.dhall`
2. Update templates to use default
3. Document in README.md

## Debugging

### Debug Dhall Files

```bash
# Type-check and print
dhall type --file dhall/types.dhall

# Translate to JSON
dhall-to-json --file dhall/prelude.dhall

# Translate to YAML
dhall-to-yaml --file dhall/prelude.dhall
```

### Debug Nix Expressions

```bash
# Evaluate and print
nix eval --json .#lib

# Build with verbose output
nix build .#smokeTest --verbose

# Build with debug output
nix build .#smokeTest --show-trace
```

### Inspect Build Outputs

```bash
# Build and inspect
nix build .#smokeTest
nix store ls result

# Check closure
nix store ls result --requisites
```

### Cross-Arch Builds

```bash
# Build for aarch64 on x86
nix build .#devContainer --system aarch64-linux
```

## Testing

### Automated Tests

```bash
# Run flake check
nix flake check

# Build smoke test
nix build .#smokeTest
```

### Manual Testing

```bash
# Test dev container
nix build .#devContainer
docker load < result

# Test CI container
nix build .#ciContainer
docker load < result

# Test agent container
nix build .#agentContainer
docker load < result
```

## Documentation

### Update Documentation

When adding features, update relevant documentation:
- `README.md` - Main documentation
- `docs/architecture.md` - Architecture docs
- `CONTRIBUTING.md` - Contribution guidelines
- `DEVELOPER_GUIDE.md` - This file

### Documentation Style

1. **Be clear** - Write for the reader
2. **Be complete** - Cover all relevant aspects
3. **Be accurate** - Match the implementation
4. **Use examples** - Show usage patterns
5. **Keep updated** - Update when code changes

## Troubleshooting

### Type-Check Errors

```bash
# Check specific file
dhall type --file dhall/types.dhall

# Check for parse errors
dhall type --file dhall/types.dhall --hash-deterministic
```

### Build Errors

```bash
# Build with verbose output
nix build .#smokeTest --verbose

# Build with debug output
nix build .#smokeTest --show-trace
```

### Cross-Arch Build Issues

```bash
# Build for specific architecture
nix build .#devContainer --system aarch64-linux
```

## Resources

- `README.md` - Main documentation
- `docs/architecture.md` - Architecture documentation
- `CONTRIBUTING.md` - Contribution guidelines
- `dhall/` - Dhall configuration
- `nix/` - Nix implementation
- `templates/` - Template flakes

## Next Steps

1. **Read the architecture document** - Understand the design
2. **Examine template files** - See usage examples
3. **Review existing code** - Follow patterns
4. **Start small** - Make small changes first
5. **Test thoroughly** - Use smoke test and manual testing

## Getting Help

- Check existing documentation
- Look at existing code
- Review the architecture document
- Examine template files
