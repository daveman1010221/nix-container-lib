-- polar-container-lib/dhall/defaults.dhall
--
-- Opinionated default configurations for common container archetypes.
--
-- Usage pattern:
--   let defaults = ./defaults.dhall
--   in  defaults.devContainer // { name = "my-project", ... }
--
-- The // operator performs a shallow record merge, so any field you
-- specify overrides the default. Fields you omit inherit the default.

let T = ./types.dhall

-- ---------------------------------------------------------------------------
-- Shell defaults
-- ---------------------------------------------------------------------------

-- Minimal POSIX shell (dash). Tiny, strict, no config beyond /etc/profile.
-- Use for init containers or any minimal container that needs a shell for
-- scripting but not interactive use.
let minimalDashShell
    : T.Shell
    = T.Shell.Minimal { shell = "/bin/sh" }

-- Minimal nushell. vi mode, show_banner false, basic completions.
-- No plugins, no themes, no atuin, no starship, no direnv.
-- Use for minimal containers where nushell's structured data handling
-- is useful but full interactive ergonomics are not required.
let minimalNuShell
    : T.Shell
    = T.Shell.Minimal { shell = "/bin/nu" }

-- Full interactive fish shell with bobthefish, atuin, starship, direnv.
let defaultInteractiveFishShell
    : T.Shell
    = T.Shell.Interactive
        { shell = "/bin/fish"
        , colorScheme = "gruvbox"
        , viBindings = True
        , plugins = [ "bobthefish", "bass", "grc" ]
        }

-- Full interactive nushell with plugins, atuin, starship, direnv.
let defaultInteractiveNuShell
    : T.Shell
    = T.Shell.Interactive
        { shell = "/bin/nu"
        , colorScheme = "gruvbox"
        , viBindings = True
        , plugins = [] : List Text
        }

-- ---------------------------------------------------------------------------
-- Infrastructure defaults (unchanged)
-- ---------------------------------------------------------------------------

let defaultNix
    : T.NixConfig
    = { enableDaemon = True
      , sandboxPolicy = T.SandboxPolicy.Auto
      , trustedUsers = [ "root" ]
      , buildUserCount = T.BuildUserCount.Dynamic
      }

let defaultTLS
    : T.TLSConfig
    = { enable = True, generateCerts = True, certsPath = None Text }

let defaultSSH
    : T.SSHConfig
    = { enable = False, port = 2223 }

let defaultUser
    : T.UserConfig
    = { createUser = True
      , defaultShell = "/bin/fish"
      , skeletonPath = "/etc/container-skel"
      , supplementalGroups = [] : List { name : Text, gid : Natural }
      }

let defaultAi
    : T.AiConfig
    = { enable = False, modelsPath = "/opt/llama-models", llamaPort = 8080 }

let defaultPipelineOutputs
    : T.PipelineOutputs
    = { artifacts = [] : List T.PipelineOutputArtifact
      , assertions = [] : List T.PipelineOutputAssertion
      }

-- ---------------------------------------------------------------------------
-- Container archetypes
-- ---------------------------------------------------------------------------

let devContainer
    : T.ContainerConfig
    = { name = "unnamed-dev"
      , mode = T.Mode.Dev
      , packageLayers =
        [ T.PackageLayer.Micro
        , T.PackageLayer.Core
        , T.PackageLayer.CI
        , T.PackageLayer.InteractiveDev
        ]
      , shell = Some defaultInteractiveFishShell
      , pipeline = None T.PipelineConfig
      , ssh = Some defaultSSH
      , tls = None T.TLSConfig
      , nix = defaultNix
      , user = defaultUser
      , extraEnv = [] : List T.EnvVar
      , ai = None T.AiConfig
      , entrypoint = None Text
      , staticUid = None Natural
      , staticGid = None Natural
      , startup = None T.Startup
      , services = [] : List T.Service
      }

let infraAgentContainer
    : T.ContainerConfig
    = { name = "unnamed-infra-agent"
      , mode = T.Mode.InfraAgent
      , packageLayers =
        [ T.PackageLayer.Micro
        , T.PackageLayer.Core
        , T.PackageLayer.Infrastructure
        ]
      , shell = None T.Shell
      , pipeline = None T.PipelineConfig
      , ssh = None T.SSHConfig
      , tls = Some defaultTLS
      , nix = defaultNix // { enableDaemon = False }
      , user = defaultUser // { createUser = False }
      , extraEnv = [] : List T.EnvVar
      , ai = None T.AiConfig
      , entrypoint = None Text
      , staticUid = None Natural
      , staticGid = None Natural
      , startup = None T.Startup
      , services = [] : List T.Service
      }

let aiAgentContainer
    : T.ContainerConfig
    = { name = "unnamed-ai-agent"
      , mode = T.Mode.AIAgent
      , packageLayers =
          [ T.PackageLayer.Micro
          , T.PackageLayer.Core
          ]
      , shell = Some minimalNuShell
      , pipeline = None T.PipelineConfig
      , ssh = Some defaultSSH
      , tls = Some defaultTLS
      , nix = defaultNix // { enableDaemon = False }
      , user = defaultUser
      , extraEnv = [] : List T.EnvVar
      , ai = Some defaultAi
      , entrypoint = None Text
      , staticUid = None Natural
      , staticGid = None Natural
      , startup = None T.Startup
      , services = [] : List T.Service
      }

-- ---------------------------------------------------------------------------
-- defaultService
--
-- A service that starts with vigild and is restarted when it exits. Extend it:
--   defaults.defaultService //
--     { name = "etcd", summary = "etcd", command = "/bin/etcd-run"
--     , killDelay = Some "10s"
--     }
-- ---------------------------------------------------------------------------
let defaultService
    : T.Service
    = { name = "unnamed"
      , summary = ""
      , command = "/bin/false"
      , enabled = True
      , after = [] : List Text
      , onSuccess = T.ServiceExit.Restart
      , onFailure = T.ServiceExit.Restart
      , killDelay = None Text
      , logs = T.ServiceLogs.Enabled
      }

-- ---------------------------------------------------------------------------
-- systemContainer
--
-- A container that runs its services under vigild as PID 1, with no session
-- (no user, no shell in front, no SSH): an infrastructure node. List its
-- services, and what it must do once at each start:
--   defaults.systemContainer //
--     { name = "my-node"
--     , packageLayers = [ PackageLayer.Core, customLayer "node" [ ... ] ]
--     , startup = Some
--         { session = Session.None
--         , boot = [ BootStep.DelegateCgroups ]
--         , launch = Launch.System
--         }
--     , services = [ defaults.defaultService // { name = ..., command = ... } ]
--     }
-- ---------------------------------------------------------------------------
let systemContainer
    : T.ContainerConfig
    = { name = "unnamed-system"
      , mode = T.Mode.System
      , packageLayers = [ T.PackageLayer.Micro, T.PackageLayer.Core ]
      , shell = None T.Shell
      , pipeline = None T.PipelineConfig
      , ssh = None T.SSHConfig
      , tls = None T.TLSConfig
      , nix = defaultNix // { enableDaemon = False }
      , user = defaultUser // { createUser = False }
      , extraEnv = [] : List T.EnvVar
      , ai = None T.AiConfig
      , entrypoint = None Text
      , staticUid = None Natural
      , staticGid = None Natural
      , startup = None T.Startup
      , services = [] : List T.Service
      }

-- ---------------------------------------------------------------------------
-- minimalContainer
--
-- The smallest possible container. Uses Micro layer only.
-- shell = None → entrypoint binary is required.
-- shell = Some (Shell.Minimal ...) → that shell is the entrypoint.
--
-- No Nix daemon. No user creation. No start.sh. OCI Cmd is either:
--   - ["/bin/<entrypoint>"]  when entrypoint is set
--   - ["/bin/nu"]            when shell = Minimal { shell = "/bin/nu" }
--   - ["/bin/sh"]            when shell = Minimal { shell = "/bin/sh" }
--
-- Typical customization:
--   defaults.minimalContainer //
--     { name = "my-tool"
--     , entrypoint = Some "my-binary"
--     , packageLayers =
--         [ PackageLayer.Micro
--         , customLayer "my-tool" [ nixpkgs "my-package" ]
--         ]
--     }
-- ---------------------------------------------------------------------------
let minimalContainer
    : T.ContainerConfig
    = { name = "unnamed-minimal"
      , mode = T.Mode.Minimal
      , packageLayers = [ T.PackageLayer.Micro ]
      , shell = None T.Shell
      , pipeline = None T.PipelineConfig
      , ssh = None T.SSHConfig
      , tls = None T.TLSConfig
      , nix = defaultNix // { enableDaemon = False }
      , user = defaultUser // { createUser = False }
      , extraEnv = [] : List T.EnvVar
      , ai = None T.AiConfig
      , entrypoint = None Text
      , staticUid = None Natural
      , staticGid = None Natural
      , startup = None T.Startup
      , services = [] : List T.Service
      }

in  { devContainer
    , infraAgentContainer
    , aiAgentContainer
    , systemContainer
    , minimalContainer
    , defaultService
    , minimalDashShell
    , minimalNuShell
    , defaultInteractiveFishShell
    , defaultInteractiveNuShell
    , defaultNix
    , defaultTLS
    , defaultSSH
    , defaultUser
    , defaultAi
    , defaultPipelineOutputs
    }
