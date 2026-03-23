-- polar-container-lib/dhall/defaults.dhall
--
-- Opinionated default configurations for common container archetypes.
-- These encode the accumulated decisions from the polar dev container
-- so they don't have to be re-derived per project.
--
-- Usage pattern:
--   let defaults = ./defaults.dhall
--   in  defaults.devContainer // { name = "my-project", ... }
--
-- The // operator performs a shallow record merge, so any field you
-- specify overrides the default. Fields you omit inherit the default.

let T = ./types.dhall

-- ---------------------------------------------------------------------------
-- Default subsystem configurations
-- Export these so consumers can use them as override bases too:
--   defaults.defaultTLS // { generateCerts = False, certsPath = Some "/certs" }
-- ---------------------------------------------------------------------------

let defaultShell : T.ShellConfig =
  { shell       = "/bin/fish"
  , colorScheme = "gruvbox"
  , viBindings  = True
    -- bobthefish: prompt theme
    -- bass:       bash compatibility in fish
    -- grc:        generic colouriser for common CLI tools
  , plugins     = [ "bobthefish", "bass", "grc" ]
  }

let defaultNix : T.NixConfig =
  { enableDaemon   = True
    -- Auto: detect qemu-user via CPU implementer at runtime,
    -- disable sandbox only when running under emulation.
    -- On native hardware (x86, Apple Silicon, Graviton) sandbox runs normally.
  , sandboxPolicy  = T.SandboxPolicy.Auto
  , trustedUsers   = [ "root" ]
    -- Dynamic: provision nixbld1..N at startup based on nproc.
    -- This correctly sizes the build pool for the host machine without
    -- baking in a number that's wrong on a different host.
  , buildUserCount = T.BuildUserCount.Dynamic
  }

let defaultTLS : T.TLSConfig =
  { enable        = True
  , generateCerts = True
    -- No override path by default; gen-certs.nix produces fresh certs.
    -- Set generateCerts = False and certsPath = Some "/path" to bring
    -- your own certificates (e.g. from a secrets manager mount).
  , certsPath     = None Text
  }

let defaultSSH : T.SSHConfig =
  { enable = False   -- present but not auto-started; run ssh-start manually
  , port   = 2223    -- non-standard port avoids collision with host sshd
  }

let defaultUser : T.UserConfig =
  { createUser   = True
    -- When CREATE_USER / CREATE_UID / CREATE_GID are set in the environment,
    -- start.sh provisions a matching user so bind-mounted files have correct
    -- ownership. Falls back to root when vars are absent.
  , defaultShell         = "/bin/fish"
  , skeletonPath         = "/etc/container-skel"
  , supplementalGroups   = [] : List { name : Text, gid : Natural }
  }

let defaultAi : T.AiConfig =
  { enable     = False
  , modelsPath = "/opt/llama-models"
  , llamaPort  = 8080
  }

-- ---------------------------------------------------------------------------
-- Container archetypes
-- ---------------------------------------------------------------------------

-- Dev container: full interactive experience, all layers, optional SSH/TLS.
-- This is the baseline from which most project configs are derived.
let devContainer : T.ContainerConfig =
  { name = "unnamed-dev"
  , mode = T.Mode.Dev
  , packageLayers =
      [ T.PackageLayer.Core
      , T.PackageLayer.CI
      , T.PackageLayer.Dev
      , T.PackageLayer.Toolchain
      , T.PackageLayer.Pipeline
      ]
  , shell    = Some defaultShell
  , pipeline = None T.PipelineConfig
  , ssh      = Some defaultSSH       -- present, not auto-started
  , tls      = None T.TLSConfig      -- opt in per-project
  , nix      = defaultNix
  , user     = defaultUser
  , extraEnv = [] : List T.EnvVar
  , ai       = None T.AiConfig
  , entrypoint = None Text
  , staticUid  = None Natural
  , staticGid  = None Natural
  }

-- CI container: headless, pipeline-focused, no interactive shell.
-- Shares the same pipeline definition as the dev container — the invariant
-- core of the "right-sized devsecops" story.
let ciContainer : T.ContainerConfig =
  devContainer //
  { name = "unnamed-ci"
  , mode = T.Mode.CI
  , packageLayers =
      [ T.PackageLayer.Core
      , T.PackageLayer.CI
      , T.PackageLayer.Pipeline
      ]
  , shell = None T.ShellConfig
  , ssh   = None T.SSHConfig
  , user  = defaultUser // { createUser = False }
  , entrypoint = None Text
  , staticUid  = None Natural
  , staticGid  = None Natural
  }

-- Agent container: autonomous process runtime.
-- mTLS required (agents communicate over authenticated channels).
-- No interactive shell. Pipeline optional (agents may run pipelines).
-- Package set TBD as the agent pattern matures — Custom layer for now.
let agentContainer : T.ContainerConfig =
  devContainer //
  { name = "unnamed-agent"
  , mode = T.Mode.Agent
  , packageLayers =
      [ T.PackageLayer.Core
      , T.PackageLayer.Agent
      ]
  , shell = None T.ShellConfig
  , ssh   = None T.SSHConfig
  , tls   = Some defaultTLS
  , user  = defaultUser // { createUser = False }
  , nix   = defaultNix //
      -- Agents typically don't need to run builds; daemon is optional.
      -- Override to True in specific agent configs that do need it.
      { enableDaemon = False }
  , entrypoint = None Text
  , staticUid  = None Natural
  , staticGid  = None Natural
  }

-- Pipeline container: explicit pipeline runner, non-interactive.
-- Identical to CI but semantically distinct — this mode is for
-- containers that ARE the pipeline runner, not containers that
-- participate in a pipeline as a build step.
let pipelineContainer : T.ContainerConfig =
  ciContainer //
  { name = "unnamed-pipeline"
  , mode = T.Mode.Pipeline
  , entrypoint = None Text
  , staticUid  = None Natural
  , staticGid  = None Natural
  }

-- ---------------------------------------------------------------------------
-- Minimal container archetype
--
-- For single-binary containers that exec one process and exit.
-- The binary named in `entrypoint` is set directly as the OCI Cmd —
-- no start.sh, no user creation, no nix daemon, no cargo cache.
--
-- Typical use: Kubernetes init containers, sidecar utilities, build tools.
--
-- Usage pattern:
--   defaults.minimalContainer //
--     { name       = "my-init-container"
--     , entrypoint = Some "my-binary"
--     , staticUid  = Some 65532
--     , staticGid  = Some 65532
--     , packageLayers =
--         [ Lib.PackageLayer.Core
--         , Lib.customLayer "my-binary"
--             [ Lib.flakePackage "myInput" "packages.default" ]
--         ]
--     }
-- ---------------------------------------------------------------------------
let minimalContainer : T.ContainerConfig =
  { name = "unnamed-minimal"
  , mode = T.Mode.Minimal
  , packageLayers =
      [ T.PackageLayer.Core ]
  , shell      = None T.ShellConfig
  , pipeline   = None T.PipelineConfig
  , ssh        = None T.SSHConfig
  , tls        = None T.TLSConfig
  , nix        = defaultNix // { enableDaemon = False }
  , user       = defaultUser // { createUser = False }
  , extraEnv   = [] : List T.EnvVar
  , ai         = None T.AiConfig
  , entrypoint = None Text
  , staticUid  = None Natural
  , staticGid  = None Natural
  }

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
in
  { devContainer       = devContainer
  , ciContainer        = ciContainer
  , agentContainer     = agentContainer
  , pipelineContainer  = pipelineContainer
  , minimalContainer   = minimalContainer
  , defaultShell       = defaultShell
  , defaultNix         = defaultNix
  , defaultTLS         = defaultTLS
  , defaultSSH         = defaultSSH
  , defaultUser        = defaultUser
  , defaultAi          = defaultAi
  }
