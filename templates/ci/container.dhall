-- container.dhall
-- CI container configuration for my-project.
--
-- This container shares its pipeline definition with the dev container.
-- That identity is the guarantee: what runs in CI is exactly what the
-- developer can run locally. Do not create a separate pipeline here.
-- Import the shared pipeline definition instead.
--
-- Typical usage:
--   Import the pipeline from a shared file:
--     let pipeline = ./pipeline.dhall
--   Or define it inline if this is a standalone CI container.

let Lib      = PRELUDE_PATH
let defaults = Lib.defaults

-- If you have a shared pipeline definition, import it:
-- let sharedPipeline = ./pipeline.dhall

in defaults.ciContainer //
  { name = "my-project-ci"

  , packageLayers =
      [ Lib.PackageLayer.Core
      , Lib.PackageLayer.CI
      , Lib.PackageLayer.Pipeline

      -- Add only what CI genuinely needs beyond the standard CI layer.
      -- Do NOT add Dev or Toolchain unless your pipeline builds code.
      -- , Lib.PackageLayer.Toolchain
      ]

  , pipeline = Some
      { name        = "my-project-pipeline"
      , artifactDir = "/workspace/pipeline-out"
      , stages      =
          -- In CI all stages run, including those gated on CI_FULL.
          -- Invoke as: CI_FULL=1 pipeline-runner
          [ Lib.simpleStage "fmt"  "cargo fmt --check"           Lib.FailureMode.FailFast
          , Lib.simpleStage "lint" "cargo clippy -- -D warnings" Lib.FailureMode.FailFast

          , { name        = "audit"
            , command     = "run-audit"
            , failureMode = Lib.FailureMode.Collect
            , inputs      = [ Lib.StageInput.Workspace ]
            , outputs     = [ Lib.StageOutput.Report ]
            , condition   = None Text
            }

          , Lib.conditionalStage
              "test"
              "cargo test --workspace"
              Lib.FailureMode.FailFast
              "CI_FULL"
          ]
      }
  , ai = None Lib.AiConfig    -- ← opt out explicitly

  -- CI containers typically do not need TLS unless your pipeline
  -- tests services that require it.
  -- , tls = Some (defaults.defaultTLS // { generateCerts = True })
  }

