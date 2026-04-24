-- templates/agent/container.dhall
--
-- AI agent container configuration template.
--
-- AI agent containers are interactive autonomous processes with operator access.
-- Key properties:
--   - Minimal nushell for operator interaction
--   - vigild supervises the agent-supervisor process
--   - mTLS enabled (agents authenticate via cert)
--   - Nix daemon disabled (agents don't run builds)
--   - Package set is minimal — declare exactly what the agent needs
--   - Add a toolchain layer if your agent needs to build code:
--       , Lib.PackageLayer.RustToolchain
--       , Lib.PackageLayer.PythonToolchain
--       , Lib.PackageLayer.NodeToolchain
--   - Add Infrastructure if your agent needs cluster tools:
--       , Lib.PackageLayer.Infrastructure

let Lib =
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/15c8b759495d15124fc9e45520c4dd16f303a1ea/dhall/prelude.dhall
        sha256:f75818ad203cb90a5e5921b75cd60bcb66ac5753cf7eba976538bf71e855378c

let defaults = Lib.defaults

in defaults.aiAgentContainer //
  { name = "my-project-agent"

  , packageLayers =
      [ Lib.PackageLayer.Micro
      , Lib.PackageLayer.Core
      -- Add agent-specific packages here:
      -- , Lib.customLayer "agent-runtime"
      --     [ Lib.flakePackage "myAgentBinary" "packages.default"
      --     , Lib.nixpkgs "sqlite"
      --     ]
      ]

  , shell = Some defaults.minimalNuShell

  , tls = Some
      ( defaults.defaultTLS //
        { generateCerts = True
        -- Production: set generateCerts = False and certsPath to mounted PKI path
        -- , certsPath = Some "/run/secrets/tls"
        }
      )

  , nix = defaults.defaultNix //
      { enableDaemon = False }

  , extraEnv =
      [ Lib.buildEnv "AGENT_MODE" "production"
      -- , Lib.runtimeEnv "AGENT_API_KEY"  ""
      -- , Lib.runtimeEnv "AGENT_ENDPOINT" ""
      ]
  }
