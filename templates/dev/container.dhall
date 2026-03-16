-- container.dhall
-- Dev container configuration for my-project.
-- Edit this file. Do not edit flake.nix unless you need new flake inputs.
--
-- Full type reference: polar-container-lib/dhall/types.dhall
-- Available defaults:  polar-container-lib/dhall/defaults.dhall

let Lib      = (builtins.getFlake "polar-container-lib").dhall.prelude
let defaults = Lib.defaults

in defaults.devContainer //
  { name = "my-project-dev"

  -- Add package layers. Core is always required and must be first.
  -- Remove layers you don't need (e.g. Toolchain if not using Rust/C++).
  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.CI
      , Lib.PackageLayer.Dev
      , Lib.PackageLayer.Toolchain
      , Lib.PackageLayer.Pipeline

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
      , stages      =
          -- Fast gates: fail immediately on error
          [ Lib.simpleStage "fmt"  "cargo fmt --check"           Lib.FailureMode.FailFast
          , Lib.simpleStage "lint" "cargo clippy -- -D warnings" Lib.FailureMode.FailFast

          -- Full test suite: only runs when CI_FULL is set
          -- Developer: pipeline-runner           (skips this stage)
          -- CI server: CI_FULL=1 pipeline-runner (runs this stage)
          , Lib.conditionalStage
              "test"
              "cargo test --workspace"
              Lib.FailureMode.FailFast
              "CI_FULL"
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

