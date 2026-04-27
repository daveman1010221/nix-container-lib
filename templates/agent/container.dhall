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
      https://raw.githubusercontent.com/daveman1010221/nix-container-lib/8fce6f3d2b3ef376a8af29c2877a24e9e6a0d70f/dhall/prelude.dhall
        sha256:b81e69ef2fe811bc853a8a9a0202c0af802f7cd53c78f95f67083bf3dceee86b

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
