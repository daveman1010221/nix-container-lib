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
    dhall type < dhall/defaults.dhall
    @echo "Type-checking dhall/prelude.dhall..."
    dhall type < dhall/prelude.dhall
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

