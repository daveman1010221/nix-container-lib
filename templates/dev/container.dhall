-- container.dhall
-- Dev container configuration for my-project.
-- Edit this file. Do not edit flake.nix unless you need new flake inputs.
--
-- Full type reference: nix-container-lib/dhall/types.dhall
-- Available defaults:  nix-container-lib/dhall/defaults.dhall

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/4ca82a1f8074b5d2084b54bcb82c8d45da58f3ad/dhall/prelude.dhall
        sha256:f75818ad203cb90a5e5921b75cd60bcb66ac5753cf7eba976538bf71e855378c
let defaults = Lib.defaults

let FailureMode = Lib.FailureMode
let Input       = Lib.StageInput
let Output      = Lib.StageOutput


in defaults.devContainer //
  { name = "my-project-dev"

  -- Add package layers. Core is always required and must be first.
  -- Remove layers you don't need (e.g. Toolchain if not using Rust/C++).
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.CI
      , Lib.PackageLayer.InteractiveDev
      --, Lib.PackageLayer.RustToolchain

      -- Add project-specific packages here:
      -- , Lib.customLayer "my-extras"
      --     [ Lib.flakePackage "myTool" "packages.default"
      --     , Lib.nixpkgs "postgresql"
      --     ]
      ]

  -- Define your pipeline stages.
  -- Remove this block entirely if you don't need a pipeline.
  , pipeline = Some
        { name        = "my-project-pipeline"
        , artifactDir = "/workspace/pipeline-out"
        , workingDir  = "/workspace/src"
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
              , command        = "cargo build --workspace --locked"
              , failureMode    = FailureMode.FailFast
              , condition      = Some "previous_success"
              , pure           = True
              , impurityReason = None Text
              , inputs         = [ Input.Workspace, Input.Lockfile, Input.Toolchain ]
              , outputs        =
                  [ Output.Artifact { name = "bin", content_type = Some "elf-binary-set" }
                  ]
              }
            ]
        }
  -- TLS: uncomment to enable mTLS certificate generation
  -- , tls = Some (defaults.defaultTLS // { generateCerts = True })

  -- SSH: uncomment to enable Dropbear (start manually with ssh-start)
  -- , ssh = Some (defaults.defaultSSH // { enable = False })

  -- Extra environment variables
  -- Use Lib.buildEnv for arch-independent values (no store paths)
  -- Use Lib.startEnv for store-path-bearing values
  , extraEnv =
      [ Lib.buildEnv "MY_PROJECT_ENV" "development"
      ]
  }
