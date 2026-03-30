-- container.dhall
-- Minimal container configuration for my-project.
--
-- Minimal containers exec a single binary directly — no start.sh, no user
-- creation phase, no Nix daemon, no interactive shell. The OCI Cmd is set
-- to the binary named in `entrypoint`. The binary's package must be declared
-- in packageLayers (typically via a Custom layer).
--
-- Typical use cases:
--   - Kubernetes init containers (clone a repo, fetch a secret, seed a volume)
--   - Sidecar utilities (health check, log shipper)
--   - Build step containers (compile, test, publish)
--
-- Security notes:
--   - Set staticUid/staticGid to a non-root UID for production use.
--     UID 65532 is a conventional non-root UID for init containers.
--   - Keep packageLayers minimal — every package is attack surface.
--   - The entrypoint binary is responsible for its own credential handling.
--     Use environment variables injected by the orchestrator, not baked-in secrets.

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/bc1246f3372fbb825de2a85e6f3ca9d0779975d5/dhall/prelude.dhall
        sha256:42b061b5cb6c7685afaf7e5bc6210640d2c245e67400b22c51e6bfdf85a89e06
let defaults = Lib.defaults

in defaults.minimalContainer //
  { name       = "my-init-container"

  -- The binary to exec as the container entrypoint.
  -- Must be provided by one of the packages in packageLayers.
  , entrypoint = Some "my-entrypoint-binary"

  -- Run as a non-root user. UID 65532 is conventional for init containers.
  -- Remove these lines to run as root (not recommended for production).
  , staticUid  = Some 65532
  , staticGid  = Some 65532

  , packageLayers =
      [ Lib.PackageLayer.Core

      -- Declare exactly the packages your binary needs at runtime.
      -- Keep this list short — minimal containers should be minimal.
      , Lib.customLayer "my-entrypoint"
          [ Lib.flakePackage "myInput" "packages.default"
          -- , Lib.nixpkgs "git"
          -- , Lib.nixpkgs "cacert"
          ]
      ]

  -- Build-time environment variables (no store paths).
  -- Runtime values should be injected by the orchestrator, not baked in.
  , extraEnv =
      [ Lib.buildEnv "GIT_TERMINAL_PROMPT" "0"
      -- , Lib.buildEnv "MY_SETTING" "value"
      ]
  }
