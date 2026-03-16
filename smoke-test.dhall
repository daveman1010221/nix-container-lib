-- smoke-test.dhall
-- Minimal ContainerConfig for the library's own smoke test.
-- Lives at the repo root alongside flake.nix.

let defaults = ./dhall/defaults.dhall

in defaults.ciContainer //
  { name = "polar-container-lib-smoke-test" }
