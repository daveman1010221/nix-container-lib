
-- container.dhall
-- CI container configuration for a Rust project.
--
-- This produces a pipeline container that runs quality gates, builds
-- binaries with attested provenance, and optionally pushes OCI images.
-- The derivation-style manifest pins all inputs at runtime so the build
-- is reproducible: same container image + same source = same outputs
-- for all pure tasks.
--
-- The Toolchain layer is included because this pipeline compiles Rust.
-- If your pipeline only runs pre-built tools (linting configs, SBOM
-- scanners), drop Toolchain and the build/push tasks.

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/49af3817a5197ab7bd95ce1b46c487af1dce424d/dhall/prelude.dhall
        sha256:f75818ad203cb90a5e5921b75cd60bcb66ac5753cf7eba976538bf71e855378c
let defaults = Lib.defaults

let FailureMode = Lib.FailureMode
let Input       = Lib.TaskInput
let Output      = Lib.TaskOutput

let artifactDir = "/workspace/pipeline-out"

in defaults.ciContainer //
  { name = "my-project-ci"
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.CI
      , 
      ]
  , pipeline = Some
      { name        = "my-project-pipeline"
      , artifactDir
      , workingDir  = "/workspace/src"
      -- , scripts     = defaults.defaultPipelineScripts
      , outputs     = Some
          { artifacts =
              [ { name         = "binaries"
                , fromTask    = "build"
                , artifact     = "bin"
                , attestation  = Some "build-manifest.json"
                , verifyMethod = Some "Recompute binding hash from input pins + binary hash"
                }
              ]
          , assertions =
              [ { name = "formatted",  fromTask = "fmt" }
              , { name = "lint-clean", fromTask = "lint" }
              , { name = "tests-pass", fromTask = "test-unit" }
              , { name = "audit-clean", fromTask = "audit" }
              ]
          }
      , tasks =
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
