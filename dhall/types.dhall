-- polar-container-lib/dhall/types.dhall
--
-- Canonical type definitions for the polar container library.
-- All types are defined here and re-exported via prelude.dhall.
-- Consumers should import prelude.dhall, not this file directly.

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
let Mode = < Dev | CI | InfraAgent | AIAgent | Minimal >

let FailureMode = < FailFast | Collect >

let EnvVarPlacement = < BuildTime | StartTime | UserProvided >

let EnvVar = { name : Text, value : Text, placement : EnvVarPlacement }

let PackageRef = { attrPath : Text, flakeInput : Optional Text }

let PackageLayer =
      < Micro
      | Core
      | CI
      | InteractiveDev
      | RustToolchain
      | PythonToolchain
      | NodeToolchain
      | Infrastructure
      | Custom : { name : Text, packages : List PackageRef }
      >

let TaskInput =
      < Workspace
      | Lockfile
      | Toolchain
      | Artifact : Text
      | TaskOutput : { task : Text, artifact : Text }
      | Environment : { name : Text, description : Text }
      >

let TaskOutput =
      < Artifact : { name : Text, content_type : Optional Text }
      | Assertion : { name : Text, description : Optional Text }
      | Report : { name : Optional Text }
      | None
      >

let Task =
      { name : Text
      , command : Text
      , failureMode : FailureMode
      , inputs : List TaskInput
      , outputs : List TaskOutput
      , condition : Optional Text
      , pure : Bool
      , impurityReason : Optional Text
      }

let PipelineOutputArtifact =
      { name : Text
      , fromTask : Text
      , artifact : Text
      , attestation : Optional Text
      , verifyMethod : Optional Text
      }

let PipelineOutputAssertion = { name : Text, fromTask : Text }

let PipelineOutputs =
      { artifacts : List PipelineOutputArtifact
      , assertions : List PipelineOutputAssertion
      }

let PipelineConfig =
      { name : Text
      , tasks : List Task
      , artifactDir : Text
      , workingDir : Text
      , outputs : Optional PipelineOutputs
      }

-- ---------------------------------------------------------------------------
-- Shell
--
-- Two variants:
--   Minimal     — just the shell binary + a minimal config. No plugins,
--                 no themes, no tool integrations. Suitable for minimal
--                 containers where a shell is needed for scripting but
--                 interactive ergonomics are not the goal.
--                 Supported shells: "/bin/sh" (dash), "/bin/nu" (nushell)
--
--   Interactive — full interactive experience: plugins, color themes,
--                 atuin history, starship prompt, direnv integration.
--                 Only valid in Dev mode containers.
--                 Supported shells: "/bin/fish", "/bin/nu"
-- ---------------------------------------------------------------------------
let MinimalShellConfig =
      { shell : Text
      -- ^ Path to the shell binary. Currently supported:
      --   "/bin/sh"  → dash (POSIX, tiny)
      --   "/bin/nu"  → nushell (minimal config, vi mode)
      }

let InteractiveShellConfig =
      { shell : Text
      -- ^ Path to the shell binary. Currently supported:
      --   "/bin/fish" → fish with bobthefish, atuin, starship, direnv
      --   "/bin/nu"   → nushell with plugins, atuin, starship, direnv
      , colorScheme : Text
      , viBindings : Bool
      , plugins : List Text
      }

let Shell =
      < Minimal     : MinimalShellConfig
      | Interactive : InteractiveShellConfig
      >

let SSHConfig = { enable : Bool, port : Natural }

let TLSConfig =
      { enable : Bool, generateCerts : Bool, certsPath : Optional Text }

let SandboxPolicy = < Enabled | Disabled | Auto >

let BuildUserCount = < Dynamic | Fixed : Natural >

let NixConfig =
      { enableDaemon : Bool
      , sandboxPolicy : SandboxPolicy
      , trustedUsers : List Text
      , buildUserCount : BuildUserCount
      }

let UserConfig =
      { createUser : Bool
      , defaultShell : Text
      , skeletonPath : Text
      , supplementalGroups : List { name : Text, gid : Natural }
      }

let AiConfig = { enable : Bool, modelsPath : Text, llamaPort : Natural }

let ContainerConfig =
      { name : Text
      , mode : Mode
      , packageLayers : List PackageLayer
      -- ^ shell = None          → no shell in the image (entrypoint required)
      --   shell = Some (Shell.Minimal ...)     → shell binary + minimal config
      --   shell = Some (Shell.Interactive ...) → full interactive experience
      , shell : Optional Shell
      , pipeline : Optional PipelineConfig
      , ssh : Optional SSHConfig
      , tls : Optional TLSConfig
      , nix : NixConfig
      , user : UserConfig
      , extraEnv : List EnvVar
      , ai : Optional AiConfig
      , entrypoint : Optional Text
      , staticUid : Optional Natural
      , staticGid : Optional Natural
      }

in  { Mode
    , FailureMode
    , EnvVarPlacement
    , EnvVar
    , PackageRef
    , PackageLayer
    , TaskInput
    , TaskOutput
    , Task
    , PipelineOutputArtifact
    , PipelineOutputAssertion
    , PipelineOutputs
    , PipelineConfig
    , MinimalShellConfig
    , InteractiveShellConfig
    , Shell
    , SSHConfig
    , TLSConfig
    , SandboxPolicy
    , BuildUserCount
    , NixConfig
    , UserConfig
    , ContainerConfig
    , AiConfig
    }
