-- polar-container-lib/dhall/lib/types.dhall
--
-- Canonical type definitions for the polar container library.
-- All types are defined here and re-exported via prelude.dhall.
-- Consumers should import prelude.dhall, not this file directly.

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
let Mode = < Dev | CI | Agent | Pipeline | Minimal >

let FailureMode = < FailFast | Collect >

let EnvVarPlacement = < BuildTime | StartTime | UserProvided >

let EnvVar = { name : Text, value : Text, placement : EnvVarPlacement }

let PackageRef = { attrPath : Text, flakeInput : Optional Text }

let PackageLayer =
      < Core
      | CI
      | Dev
      | Toolchain
      | Pipeline
      | Agent
      | Custom : { name : Text, packages : List PackageRef }
      >

let StageInput =
      < Workspace
      | Lockfile
      | Toolchain
      | Artifact : Text
      | StageOutput : { stage : Text, artifact : Text }
      | Environment : { name : Text, description : Text }
      >

let StageOutput =
      < Artifact : { name : Text, content_type : Optional Text }
      | Assertion : { name : Text, description : Optional Text }
      | Report : { name : Optional Text }
      | None
      >

let Stage =
      { name : Text
      , command : Text
      , failureMode : FailureMode
      , inputs : List StageInput
      , outputs : List StageOutput
      , condition : Optional Text
      , pure : Bool
      , impurityReason : Optional Text
      }

let PipelineOutputArtifact =
      { name : Text
      , fromStage : Text
      , artifact : Text
      , attestation : Optional Text
      , verifyMethod : Optional Text
      }

let PipelineOutputAssertion = { name : Text, fromStage : Text }

-- TODO: Make each of these fields optional, we dojn't always need assertiosn, and some pipelines don't always produce artifacts
let PipelineOutputs =
      { artifacts : List PipelineOutputArtifact
      , assertions : List PipelineOutputAssertion
      }

let PipelineScripts = { runner : Text, attestedBuild : Text }

let PipelineConfig =
      { name : Text
      , stages : List Stage
      , artifactDir : Text
      , workingDir : Text
      , outputs : Optional PipelineOutputs
      }

let ShellConfig =
      { shell : Text
      , colorScheme : Text
      , viBindings : Bool
      , plugins : List Text
      }

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
      , shell : Optional ShellConfig
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
    , StageInput
    , StageOutput
    , Stage
    , PipelineOutputArtifact
    , PipelineOutputAssertion
    , PipelineOutputs
    , PipelineConfig
    , ShellConfig
    , SSHConfig
    , TLSConfig
    , SandboxPolicy
    , BuildUserCount
    , NixConfig
    , UserConfig
    , ContainerConfig
    , AiConfig
    }
