# Contributing to nix-container-lib

Thank you for your interest in contributing to nix-container-lib! This document provides guidelines for contributing to the project.

## Quick Start

1. **Read the documentation** - Start with `README.md` and `docs/architecture.md`
2. **Set up development environment** - See below
3. **Make your changes** - Follow the coding standards
4. **Test your changes** - Run the smoke test and type-checks
5. **Submit a PR** - Follow the PR guidelines

## Setting Up Development Environment

### Prerequisites

- **Nix** - The package manager (version 2.16 or later)
- **Dhall** - The configuration language (version 19.1 or later)
- **Git** - Version control

### Install Nix

```bash
# On Linux
curl https://nixos.org/nix/install | sh

# On macOS
curl https://nixos.org/nix/install | sh
```

### Install Dhall

```bash
# Using Nix
nix-env -iA dhall-json

# Using Homebrew (macOS)
brew install dhall-json

# Using Nix (for development)
nix develop
```

### Enter Dev Shell

```bash
nix develop
```

This gives you access to:
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
- `docs/` - Documentation files

### 2. Type-Check Dhall Files

```bash
# Type-check all Dhall files
dhall type --file dhall/types.dhall
dhall type --file dhall/defaults.dhall
dhall type --file dhall/prelude.dhall
dhall type --file smoke-test.dhall
```

### 3. Build the Smoke Test

```bash
nix build .#smokeTest
```

This exercises the full build chain and validates your changes.

### 4. Run Flake Check

```bash
nix flake check
```

This runs all checks and validates the flake.

### 5. Enter Dev Shell (Optional)

```bash
nix develop
```

This gives you access to all development tools.

## Coding Standards

### Dhall Style

1. **Follow existing patterns** - Match the style of existing files
2. **Use type annotations** - Add types to all definitions
3. **Document types** - Document all public types
4. **Use // for overrides** - This is the expected pattern
5. **Keep it simple** - Avoid unnecessary complexity

### Nix Style

1. **Follow existing patterns** - Match the style of existing files
2. **Document functions** - Add header comments to all functions
3. **Use lib functions** - Use `pkgs.lib` functions when available
4. **Keep it pure** - Avoid side effects when possible
5. **Be arch-aware** - Consider x86 vs aarch64 differences

### Documentation Style

1. **Be clear** - Write for the reader
2. **Be complete** - Cover all relevant aspects
3. **Be accurate** - Match the implementation
4. **Use examples** - Show usage patterns
5. **Keep updated** - Update when code changes

## Pull Request Guidelines

### PR Checklist

- [ ] Code follows existing patterns
- [ ] Type-checks pass
- [ ] Smoke test passes
- [ ] Documentation updated
- [ ] Examples added (if applicable)
- [ ] Changelog updated (if applicable)

### PR Title Format

```
<type>: <description>

Types:
  feat: New feature
  fix: Bug fix
  docs: Documentation changes
  refactor: Code refactoring
  test: Test changes
  chore: Chore changes
```

### PR Example

```
feat: Add custom package layer support

This adds support for custom package layers via a new PackageLayer.Custom
variant. This allows projects to add their own packages without forking
the library.

Closes #123
```

## Testing

### Smoke Test

The smoke test exercises the full build chain:

```bash
nix build .#smokeTest
```

This validates:
- Dhall parsing
- Type translation
- Package resolution
- Image assembly

### Manual Testing

Test your changes manually:

```bash
# Build a dev container
nix build .#devContainer

# Build a CI container
nix build .#ciContainer

# Build an agent container
nix build .#agentContainer
```

### Type-Checking

Type-check all Dhall files:

```bash
dhall type --file dhall/types.dhall
dhall type --file dhall/defaults.dhall
dhall type --file dhall/prelude.dhall
dhall type --file smoke-test.dhall
```

## Debugging

### Debug Dhall Files

```bash
# Print Dhall expression
dhall-to-json --file dhall/prelude.dhall

# Type-check and print
dhall type --file dhall/types.dhall
```

### Debug Nix Expressions

```bash
# Evaluate and print
nix eval --json .#lib

# Build and inspect
nix build .#smokeTest
nix store ls result
```

### Enter Dev Shell

```bash
nix develop
```

This gives you access to development tools.

## Common Tasks

### Add a New Package to a Layer

Edit `nix/packages.nix`:

```nix
# Add to the appropriate layer
core = with pkgs; [
  # ... existing packages
  new-package
]
```

### Add a New Type

Edit `dhall/types.dhall`:

```dhall
let NewType = < Variant1 | Variant2 : { field : Text } >
```

### Add a New Default

Edit `dhall/defaults.dhall`:

```dhall
let newDefault : T.ContainerConfig =
  { name = "unnamed-new"
  , mode = T.Mode.Dev
  , # ... configuration
  }
```

### Add a New Template

Create `templates/new/`:

```
templates/new/
├── flake.nix
└── container.dhall
```

## Troubleshooting

### Type-Check Errors

```bash
# Check the specific file
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

### Cross-Arch Builds

```bash
# Build for aarch64 on x86
nix build .#devContainer --system aarch64-linux
```

## Resources

- `README.md` - Main documentation
- `docs/architecture.md` - Architecture documentation
- `dhall/` - Dhall configuration
- `nix/` - Nix implementation
- `templates/` - Template flakes

## Getting Help

- Check existing documentation
- Look at existing code
- Review the architecture document
- Examine template files

## Code of Conduct

Be respectful and considerate. We're all learning and growing together.

## License

MIT - See LICENSE file for details.
