## [unreleased]

### 🐛 Bug Fixes

- Correct usage of the rust overlay
- Call gen-certs.nix with import not callPackage
- Remove .result regression from dhallToNix call
- Move neovim to packages for the lib
- Move neovim to packages for the lib
- Dev-shell uses startTimeEnv not cfg.extraEnv
- Address some issues with the running container
- Vendor functions and OpenSSL env at container startup
- Wrap static vendor functions as writeText derivations

### ⚙️ Miscellaneous Tasks

- Add cliff.toml for changelog generation
- Add initial CHANGELOG.md
## [0.1.0] - 2026-03-16

### 🚀 Features

- Initial library skeleton
- Implement identity, nix-infra, gc-roots
- Implement shell.nix and vendor function library
- Implement gen-certs, polar-help, dev-shell
- Implement pipeline runner
- Add dev, ci, and agent flake templates

### 🐛 Bug Fixes

- Correct stale dhall/lib/ path references
- Remove smoke test from nix flake check
- Dhall union representation and smoke test
- Update placeholder URLs to actual github repository
