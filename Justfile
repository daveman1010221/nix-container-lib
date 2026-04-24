# nix-container-lib Justfile
#
# Primary workflow:
#   1. Edit a .dhall file
#   2. just render-<name>   to produce the .nix file
#   3. Commit both
#   4. nix build            uses the .nix file, no Dhall at build time
#
# WHY RENDER SEPARATELY?
# The Nix sandbox has no network access. Dhall's import system resolves
# dependencies (including the nix-container-lib prelude) over the network
# or from the filesystem. Running dhall-to-nix inside nix build fails.
# Pre-rendering produces a pure .nix file that Nix can import safely.

# Render smoke-test.dhall → smoke-test.nix
render-smoke-test:
    @echo "Rendering smoke-test.dhall → smoke-test.nix..."
    dhall-to-nix < smoke-test.dhall > smoke-test.nix
    @echo "Done. Commit smoke-test.nix alongside smoke-test.dhall."

# Type-check all .dhall files without rendering
check-dhall:
    @echo "Type-checking dhall/types.dhall..."
    dhall type < dhall/types.dhall
    @echo "Type-checking dhall/defaults.dhall..."
    cd dhall && dhall type < defaults.dhall
    @echo "Type-checking dhall/prelude.dhall..."
    cd dhall && dhall type < prelude.dhall
    @echo "Type-checking smoke-test.dhall..."
    dhall type < smoke-test.dhall
    @echo "All Dhall files type-check OK."

# Render all .dhall files that have a companion .nix target
render-all: render-smoke-test
    @echo "All Dhall files rendered."

# Build the smoke test container image
smoke-test:
    nix build .#smokeTest -L

# Run nix flake check
check:
    nix flake check

# Enter the dev shell
dev:
    nix develop


# Update all template pins to the current HEAD commit.
# Run after pushing a new commit to main.
update-pins:
    #!/usr/bin/env bash
    set -euo pipefail
    COMMIT=$(git rev-parse HEAD)
    DHALL_HASH=$(dhall hash --file dhall/prelude.dhall)
    ROOT=$(git rev-parse --show-toplevel)
    echo "Commit:     $COMMIT"
    echo "Dhall hash: $DHALL_HASH"
    echo "Updating container.dhall pins..."
    for f in templates/*/container.dhall; do
        sed -i "s|/nix-container-lib/[a-f0-9]*/dhall/prelude.dhall|/nix-container-lib/$COMMIT/dhall/prelude.dhall|" "$f"
        sed -i "s|sha256:[a-f0-9]*|$DHALL_HASH|" "$f"
    done
    echo "Updating flake.nix pins..."
    for f in templates/*/flake.nix; do
        sed -i "s|nix-container-lib/[a-f0-9]*\"|nix-container-lib/$COMMIT\"|" "$f"
    done
    echo "Rendering container.nix files..."
    for f in templates/*/container.dhall; do
        dhall-to-nix < "$f" > "$(dirname $f)/container.nix"
    done
    echo "Updating flake locks..."
    nix flake update
    for dir in templates/minimal templates/ci templates/agent templates/dev; do
        (cd "$ROOT/$dir" && nix flake update)
    done
    echo "Done. Review with: git diff"
    echo "Then: git add -A && git commit -m 'chore: update pins to $COMMIT'"
