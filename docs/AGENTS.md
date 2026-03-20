# Documentation Directory

## Purpose

This directory contains **comprehensive documentation** for the nix-container-lib project. Each file documents a specific aspect of the library.

## Documentation Files

### Core Documentation

| File | Purpose |
|------|---------|
| `architecture.md` | Detailed architecture documentation, design decisions, and patterns |

### Existing Documentation

#### `architecture.md`

**Purpose:** Detailed architecture documentation covering:

**Key Sections:**
- The Core Thesis: Developer's container and CI container are the same
- The Two-Layer Design: Dhall interface + Nix implementation
- The Ten Organizational Concepts: Each maps to one or more files in `nix/`
- The EnvVar Placement Rule: Critical invariant for environment variables
- What Belongs in the Library vs. in a Project
- Versioning Strategy
- Known Gaps

**Why It's Important:** This document contains the "why" behind the structure, not just the "what". It should be updated when a decision changes, not just when code changes.

**Key Concepts:**
1. **Identity & Filesystem Spine** (`nix/identity.nix`) - Valid Linux system
2. **Nix-in-Nix Infrastructure** (`nix/nix-infra.nix`) - Nix daemon, DB, GC roots
3. **Package Environment Assembly** (`nix/packages.nix`) - Package sets by layer
4. **Shell Environment** (`nix/shell.nix`) - Interactive Fish shell
5. **Runtime Environment Variables** (`nix/from-dhall.nix`, `nix/entrypoint.nix`) - EnvVar placement
6. **Entrypoint Composition** (`nix/entrypoint.nix`) - start.sh generation
7. **TLS / Secret Material** (`nix/gen-certs.nix`) - mTLS certificates
8. **Image Assembly** (`nix/container.nix`) - OCI image construction
9. **Developer Shell** (`nix/dev-shell.nix`) - Host-side nix develop shell
10. **Automation Pipelines** (`nix/pipeline.nix`) - Pipeline runner

### Missing Documentation

The following documentation should be added to the repo:

#### Proposed: `CONTRIBUTING.md`

**Purpose:** Guidelines for contributors

**Contents:**
- How to set up development environment
- How to run tests
- How to submit PRs
- Code style and conventions
- Review process

#### Proposed: `DEVELOPER_GUIDE.md`

**Purpose:** Setup instructions for developers

**Contents:**
- Prerequisites (Nix, Dhall, etc.)
- Getting started with development
- Building the library
- Testing changes
- Debugging techniques

#### Proposed: `MIGRATION_GUIDE.md`

**Purpose:** Migration path from older versions

**Contents:**
- Breaking changes between versions
- Migration steps
- Example transformations

#### Proposed: `SECURITY.md`

**Purpose:** Security considerations

**Contents:**
- Security model
- Known vulnerabilities
- Reporting security issues
- Best practices

#### Proposed: `EXAMPLES.md`

**Purpose:** Comprehensive examples

**Contents:**
- Common patterns
- Real-world examples
- Best practices
- Anti-patterns

## Documentation Guidelines

### What Goes in This Directory?

1. **Architecture documentation** - Design decisions and patterns
2. **API documentation** - Type definitions, function signatures
3. **Usage documentation** - How to use the library
4. **Contributor documentation** - How to contribute
5. **Migration documentation** - Version upgrades

### What Goes in README.md?

1. **High-level overview** - What the project does
2. **Quick start** - Minimal getting started guide
3. **Key features** - What makes this project unique
4. **Installation instructions** - How to install
5. **Basic examples** - Simple usage examples

### What Goes in Dhall/Docs?

1. **Type documentation** - Dhall type definitions
2. **Default documentation** - Available defaults
3. **Prelude documentation** - Convenience functions

### What Goes in Nix/Docs?

1. **Implementation details** - Nix-specific documentation
2. **Advanced patterns** - Complex usage patterns
3. **Internal APIs** - Internal function documentation

## Documentation Quality Standards

### Good Documentation

- **Clear** - Easy to understand
- **Complete** - Covers all relevant aspects
- **Accurate** - Matches the actual implementation
- **Current** - Updated when code changes
- **Concise** - No unnecessary details

### Bad Documentation

- **Outdated** - Doesn't match implementation
- **Incomplete** - Missing key information
- **Confusing** - Hard to understand
- **Inaccurate** - Contains errors
- **Verbose** - Contains unnecessary details

## Documentation Maintenance

### When to Update

1. **New features** - Document new functionality
2. **Breaking changes** - Document breaking changes
3. **Bug fixes** - Document fixes if relevant
4. **Performance improvements** - Document if it affects usage

### How to Update

1. **Update relevant docs** - Update existing documentation
2. **Add new docs** - Add documentation for new features
3. **Update examples** - Add/update examples as needed
4. **Update README** - Update main documentation if needed

## Related Directories

- `dhall/` - Dhall configuration
- `nix/` - Nix implementation
- `templates/` - Template flakes
- `pi/` - Pi coding agent (separate project)

## Documentation Tools

### Dhall

- `dhall type` - Type-check Dhall files
- `dhall-to-json` - Convert Dhall to JSON
- `dhall-to-yaml` - Convert Dhall to YAML

### Nix

- `nix build` - Build derivations
- `nix develop` - Enter dev shell
- `nix flake check` - Check flake
- `nix eval` - Evaluate expressions
- `nix store ls` - List store contents

## Documentation Patterns

### Type Documentation

```dhall
-- Types should be documented with:
-- 1. Purpose
-- 2. Fields
-- 3. Usage examples
-- 4. Constraints
```

### Function Documentation

```nix
# Functions should be documented with:
# 1. Purpose
# 2. Arguments
# 3. Return values
# 4. Usage examples
# 5. Edge cases
```

### API Documentation

```markdown
## Function Name

**Purpose:** What the function does

**Arguments:**
- `arg1` - Description
- `arg2` - Description

**Returns:** Description

**Usage:**
```nix
# Example usage
```

**Errors:**
- Error 1 - When it occurs
```

## Documentation Examples

### Good Type Documentation

```dhall
-- EnvVarPlacement
-- Encodes WHERE an environment variable should be materialized.
-- This enforces the critical boundary between config.Env (build-time,
-- no store paths) and start.sh exports (start-time, store-path-bearing).
--
--   BuildTime     → safe for config.Env: no store paths, arch-independent
--   StartTime     → must go in start.sh: store paths or arch-sensitive values
--   UserProvided  → project-specific, injected at container run time
```

### Good Function Documentation

```nix
# mkContainer: the library's primary entry point.
#
# Takes a Dhall ContainerConfig (as a Nix path), resolves it through
# from-dhall.nix, and produces a complete OCI image derivation plus
# a host-side devShell.
#
# Usage in a project flake:
#
#   let
#     lib = inputs.polar-container-lib;
#     container = lib.mkContainer {
#       inherit system pkgs inputs;
#       config = ./my-container.dhall;
#     };
#   in {
#     packages.devContainer = container.image;
#     devShells.default     = container.devShell;
#   }
```

## Documentation Links

- `README.md` - Main documentation
- `dhall/` - Dhall configuration
- `nix/` - Nix implementation
- `templates/` - Template flakes
- `docs/architecture.md` - Architecture documentation
