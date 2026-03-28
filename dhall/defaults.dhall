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

let defaultShell
    : T.ShellConfig
    = { shell = "/bin/fish"
      , colorScheme = "gruvbox"
      , viBindings = True
      , plugins = [ "bobthefish", "bass", "grc" ]
      }

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
      , shell = Some defaultShell
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
    =     devContainer
      //  { name = "unnamed-ci"
          , mode = T.Mode.CI
          , packageLayers =
            [ T.PackageLayer.Core, T.PackageLayer.CI, T.PackageLayer.Pipeline ]
          , shell = None T.ShellConfig
          , ssh = None T.SSHConfig
          , user = defaultUser // { createUser = False }
          , entrypoint = None Text
          , staticUid = None Natural
          , staticGid = None Natural
          }

let agentContainer
    : T.ContainerConfig
    =     devContainer
      //  { name = "unnamed-agent"
          , mode = T.Mode.Agent
          , packageLayers = [ T.PackageLayer.Core, T.PackageLayer.Agent ]
          , shell = None T.ShellConfig
          , ssh = None T.SSHConfig
          , tls = Some defaultTLS
          , user = defaultUser // { createUser = False }
          , nix = defaultNix // { enableDaemon = False }
          , entrypoint = None Text
          , staticUid = None Natural
          , staticGid = None Natural
          }

let pipelineContainer
    : T.ContainerConfig
    =     ciContainer
      //  { name = "unnamed-pipeline"
          , mode = T.Mode.Pipeline
          , entrypoint = None Text
          , staticUid = Some 65532
          , staticGid = Some 65532
          }

let minimalContainer
    : T.ContainerConfig
    = { name = "unnamed-minimal"
      , mode = T.Mode.Minimal
      , packageLayers = [ T.PackageLayer.Core ]
      , shell = None T.ShellConfig
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
    , defaultShell
    , defaultNix
    , defaultTLS
    , defaultSSH
    , defaultUser
    , defaultAi
    , defaultPipelineOutputs
    }
