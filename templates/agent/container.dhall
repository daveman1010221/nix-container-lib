-- container.dhall
-- Agent container configuration for my-project.
--
-- Agent containers are long-running autonomous processes.
-- Key differences from dev/CI containers:
--   - No interactive shell
--   - mTLS enabled and required
--   - Nix daemon disabled by default (agents don't run builds)
--   - Package set is minimal — declare exactly what the agent needs
--   - The entrypoint execs an agent supervisor process, not a shell
--
-- The Agent package layer is intentionally sparse — it will grow as the
-- agent container pattern matures. Use a Custom layer for agent-specific
-- tooling in the meantime.

let Lib = ../../dhall/prelude.dhall
let defaults = Lib.defaults

in defaults.agentContainer //
  { name = "my-project-agent"

  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.Agent

      -- Declare exactly what your agent process needs.
      -- Keep this list short — agents should be small and auditable.
      , Lib.customLayer "agent-runtime"
          [ Lib.nixpkgs "curl"
          -- , Lib.flakePackage "myAgentBinary" "packages.default"
          ]
      ]

  -- mTLS is required for agents. generateCerts = True produces
  -- self-signed certs suitable for local dev and testing.
  -- For production, set generateCerts = False and certsPath to
  -- a path where your PKI certs are mounted.
  , tls = Some
      ( defaults.defaultTLS //
        { generateCerts = True
        -- , certsPath = Some "/run/secrets/tls"   -- production override
        }
      )

  -- Nix daemon: disabled by default for agents.
  -- Enable if your agent needs to run nix builds.
  , nix = defaults.defaultNix //
      { enableDaemon = False }

  -- Agent-specific environment variables
  , extraEnv =
      [ Lib.buildEnv   "AGENT_MODE"     "production"
      -- Runtime values injected by your orchestrator at container start:
      -- , Lib.runtimeEnv "AGENT_API_KEY"  ""
      -- , Lib.runtimeEnv "AGENT_ENDPOINT" ""
      ]
  }

