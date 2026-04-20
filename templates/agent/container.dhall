-- templates/agent/container.dhall
--
-- Agent container configuration template.
--
-- Agent containers are long-running autonomous processes.
-- Key properties:
--   - No interactive shell (shell = None)
--   - mTLS enabled (agents authenticate via cert)
--   - Nix daemon disabled (agents don't run builds)
--   - Package set is minimal — declare exactly what the agent needs
--   - start.sh runs, then execs your agent binary
--
-- For truly size-critical agents, consider using Micro instead of Core
-- as the base layer — see the comment in packageLayers below.

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/9da4924831c8e0d81d57448425d6cd10820b71d2/dhall/prelude.dhall
        sha256:18acbbb5708565905ab9522fa77a81eb402851f06870a34a22f6c979001c4571
let defaults = Lib.defaults

in defaults.agentContainer //
  { name = "my-project-agent"

  , packageLayers =
      [ -- Core: coreutils, cacert, openssl, getent, gnutar, gzip, locales, nix.
        -- Micro: cacert, minimal uutils, getent, openssl. Smaller but no Nix or locales.
        -- Use Micro if your agent doesn't need nix or compression tools.
        Lib.PackageLayer.Core
      , Lib.PackageLayer.Agent

      , Lib.customLayer "agent-runtime"
          [ Lib.nixpkgs "curl"
          -- , Lib.flakePackage "myAgentBinary" "packages.default"
          ]
      ]

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
