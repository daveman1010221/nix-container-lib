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
        [ T.PackageLayer.Core
        , T.PackageLayer.CI
        , T.PackageLayer.Dev
        , T.PackageLayer.Toolchain
        , T.PackageLayer.Pipeline
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
      }

let ciContainer
    : T.ContainerConfig
    = { name = "unnamed-ci"
      , mode = T.Mode.CI
      , packageLayers =
        [ T.PackageLayer.Core, T.PackageLayer.CI, T.PackageLayer.Pipeline ]
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
      }

let agentContainer
    : T.ContainerConfig
    = { name = "unnamed-agent"
      , mode = T.Mode.Agent
      , packageLayers = [ T.PackageLayer.Core, T.PackageLayer.Agent ]
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
      }

let pipelineContainer
    : T.ContainerConfig
    = { name = "unnamed-pipeline"
      , mode = T.Mode.Pipeline
      , packageLayers =
        [ T.PackageLayer.Core, T.PackageLayer.CI, T.PackageLayer.Pipeline ]
      , shell = None T.Shell
      , pipeline = None T.PipelineConfig
      , ssh = None T.SSHConfig
      , tls = None T.TLSConfig
      , nix = defaultNix // { enableDaemon = False }
      , user = defaultUser // { createUser = False }
      , extraEnv = [] : List T.EnvVar
      , ai = None T.AiConfig
      , entrypoint = None Text
      , staticUid = Some 65532
      , staticGid = Some 65532
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
      }

in  { devContainer
    , ciContainer
    , agentContainer
    , pipelineContainer
    , minimalContainer
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
    -- Kept for backwards compatibility — same as defaultInteractiveFishShell
    , defaultShell = defaultInteractiveFishShell
    }
