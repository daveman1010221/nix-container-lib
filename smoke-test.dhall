-- smoke-test.dhall
--
-- Self-contained: no relative imports so dhall-to-nix can copy this file
-- in isolation without needing the rest of the source tree.
--
-- Validates that the ContainerConfig type is well-formed and that a
-- representative CI container config type-checks correctly.
-- CI mode requires pipeline to be set — this uses a minimal stub pipeline.

{ name = "polar-container-lib-smoke-test"
, mode = < Dev | CI | InfraAgent | AIAgent | Minimal >.CI
, packageLayers =
    [ < Micro | Core | CI | InteractiveDev | RustToolchain | PythonToolchain | NodeToolchain | Infrastructure
      | Custom : { name : Text, packages : List { attrPath : Text, flakeInput : Optional Text } }
      >.Micro
    , < Micro | Core | CI | InteractiveDev | RustToolchain | PythonToolchain | NodeToolchain | Infrastructure
      | Custom : { name : Text, packages : List { attrPath : Text, flakeInput : Optional Text } }
      >.Core
    , < Micro | Core | CI | InteractiveDev | RustToolchain | PythonToolchain | NodeToolchain | Infrastructure
      | Custom : { name : Text, packages : List { attrPath : Text, flakeInput : Optional Text } }
      >.CI
    ]
, shell =
    None
      < Minimal     : { shell : Text }
      | Interactive : { shell : Text, colorScheme : Text, viBindings : Bool, plugins : List Text }
      >
, pipeline = Some
    { name        = "smoke-test-pipeline"
    , artifactDir = "/workspace/pipeline-out"
    , workingDir  = "/workspace"
    , outputs     = None
        { artifacts  : List { name : Text, fromStage : Text, artifact : Text, attestation : Optional Text, verifyMethod : Optional Text }
        , assertions : List { name : Text, fromStage : Text }
        }
    , stages =
        [ { name           = "check"
          , command        = "echo smoke-test-ok"
          , failureMode    = < FailFast | Collect >.Collect
          , condition      = None Text
          , pure           = True
          , impurityReason = None Text
          , inputs         =
              [ < Workspace
                | Lockfile
                | Toolchain
                | Artifact : Text
                | StageOutput : { stage : Text, artifact : Text }
                | Environment : { name : Text, description : Text }
                >.Workspace
              ]
          , outputs        =
              [ < Artifact : { name : Text, content_type : Optional Text }
                | Assertion : { name : Text, description : Optional Text }
                | Report : { name : Optional Text }
                | None
                >.None
              ]
          }
        ]
    }
, ssh = None { enable : Bool, port : Natural }
, tls = None { enable : Bool, generateCerts : Bool, certsPath : Optional Text }
, nix =
    { enableDaemon   = False
    , sandboxPolicy  = < Enabled | Disabled | Auto >.Auto
    , trustedUsers   = [ "root" ]
    , buildUserCount = < Dynamic | Fixed : Natural >.Dynamic
    }
, user =
    { createUser         = False
    , defaultShell       = "/bin/sh"
    , skeletonPath       = "/etc/container-skel"
    , supplementalGroups = [] : List { name : Text, gid : Natural }
    }
, extraEnv =
    [] : List { name : Text, value : Text, placement : < BuildTime | StartTime | UserProvided > }
, ai         = None { enable : Bool, modelsPath : Text, llamaPort : Natural }
, entrypoint = None Text
, staticUid  = None Natural
, staticGid  = None Natural
}
