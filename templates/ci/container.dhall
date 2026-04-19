
-- container.dhall
-- CI container configuration for a Rust project.
--
-- This produces a pipeline container that runs quality gates, builds
-- binaries with attested provenance, and optionally pushes OCI images.
-- The derivation-style manifest pins all inputs at runtime so the build
-- is reproducible: same container image + same source = same outputs
-- for all pure stages.
--
-- The Toolchain layer is included because this pipeline compiles Rust.
-- If your pipeline only runs pre-built tools (linting configs, SBOM
-- scanners), drop Toolchain and the build/push stages.

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/b8b418e/dhall/prelude.dhall
        sha256:18acbbb5708565905ab9522fa77a81eb402851f06870a34a22f6c979001c4571
let defaults = Lib.defaults

let FailureMode = Lib.FailureMode
let Input       = Lib.StageInput
let Output      = Lib.StageOutput

let artifactDir = "/workspace/pipeline-out"

in defaults.pipelineContainer //
  { name = "my-project-ci"
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.CI
      , Lib.PackageLayer.Pipeline
      ]
  , pipeline = Some
      { name        = "my-project-pipeline"
      , artifactDir
      , workingDir  = "/workspace/src"
      -- , scripts     = defaults.defaultPipelineScripts
      , outputs     = Some
          { artifacts =
              [ { name         = "binaries"
                , fromStage    = "build"
                , artifact     = "bin"
                , attestation  = Some "build-manifest.json"
                , verifyMethod = Some "Recompute binding hash from input pins + binary hash"
                }
              ]
          , assertions =
              [ { name = "formatted",  fromStage = "fmt" }
              , { name = "lint-clean", fromStage = "lint" }
              , { name = "tests-pass", fromStage = "test-unit" }
              , { name = "audit-clean", fromStage = "audit" }
              ]
          }
      , stages =
          [ { name           = "fmt"
            , command        = "cargo fmt --check"
            , failureMode    = FailureMode.Collect
            , condition      = None Text
            , pure           = True
            , impurityReason = None Text
            , inputs         = [ Input.Workspace ]
            , outputs        = [ Output.Assertion { name = "formatted", description = Some "Source passes rustfmt" } ]
            }
          , { name           = "build"
            , command        = "nu /etc/pipeline/cargo-attested-build.nu --release --artifact-dir ${artifactDir}"
            , failureMode    = FailureMode.FailFast
            , condition      = Some "previous_success"
            , pure           = True
            , impurityReason = None Text
            , inputs         = [ Input.Workspace, Input.Lockfile, Input.Toolchain ]
            , outputs        =
                [ Output.Artifact { name = "bin", content_type = Some "elf-binary-set" }
                , Output.Artifact { name = "build-manifest.json", content_type = Some "attestation-manifest" }
                ]
            }
          ]
      }
  , ai = None Lib.AiConfig
  }
