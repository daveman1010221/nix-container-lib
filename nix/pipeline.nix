# polar-container-lib/nix/pipeline.nix
#
# Produces two derivations for inclusion in image contents:
#
#   pipelineManifest  → /etc/pipeline/pipeline.json
#   pipelineRunner    → /bin/pipeline-runner
#
# The manifest is the authoritative record of what this container's pipeline
# does. It is human-readable, inspectable with jq, and is the single source
# of truth the runner reads at execution time. Baking it into the image at
# build time means the pipeline definition and the tools that execute it
# are always in sync — there is no external config file to drift.
#
# The runner is a shell script that:
#   1. Reads the manifest via jq
#   2. Filters stages by condition (skips stages whose condition env var is unset)
#   3. Executes each stage in order
#   4. Applies the correct failure mode (FailFast or Collect)
#   5. Writes a summary report to the artifact directory
#   6. Exits with a non-zero code if any stage failed
#
# INVOCATION
# ----------
#   pipeline-runner             — run all non-gated stages
#   pipeline-runner all         — same as above (explicit)
#   pipeline-runner <stage>     — run a single named stage
#   CI_FULL=1 pipeline-runner   — run all stages including conditioned ones
#
# FAILURE SEMANTICS
# -----------------
#   FailFast  → non-zero exit from stage aborts the runner immediately.
#               Remaining stages do not run. Exit code mirrors the stage.
#
#   Collect   → non-zero exit from stage is recorded but execution continues.
#               All stages run. Runner exits non-zero at the end if any
#               stage failed. This is the right mode for analysis and audit
#               tools where you want the full picture, not just the first
#               finding.
#
# ARTIFACT DIRECTORY
# ------------------
# Each stage run produces a result file in the artifact directory:
#   <artifactDir>/<stage-name>.exit     — exit code
#   <artifactDir>/<stage-name>.log      — stdout + stderr
#   <artifactDir>/summary.json          — machine-readable run summary
#   <artifactDir>/summary.txt           — human-readable run summary
#
# CONDITION GATES
# ---------------
# A stage with condition = Some "CI_FULL" is skipped unless the env var
# CI_FULL is set in the environment. This implements the "developer runs
# fast stages, CI runs everything" invariant without two pipeline definitions.
# The condition value is the name of the env var to check, not a shell
# expression — this is intentional. Complex conditions belong in the stage
# command itself, not in the pipeline definition.

{ pkgs
, cfg     # Translated config from from-dhall.nix
}:

let
  lib = pkgs.lib;
  pipeline = cfg.pipeline;  # guaranteed non-null by caller (container.nix)

  # ---------------------------------------------------------------------------
  # Pipeline manifest (JSON)
  #
  # Serializes the full pipeline definition to JSON for runtime consumption
  # and human inspection. The structure mirrors the Dhall PipelineConfig
  # type closely so that reading the JSON feels familiar to anyone who has
  # read the Dhall types.
  #
  # Stage inputs/outputs are included for documentation purposes — the runner
  # does not currently enforce them, but they are available for future tooling
  # (dependency analysis, parallelism, artifact tracking).
  # ---------------------------------------------------------------------------
  manifestData = {
    name        = pipeline.name;
    artifactDir = pipeline.artifactDir;
    stages      = map (stage: {
      inherit (stage) name command failureMode condition;
      inputs  = map (i:
        if i.type == "workspace"    then { type = "workspace"; }
        else if i.type == "artifact" then { type = "artifact"; name = i.name; }
        else                             { type = "environment"; }
      ) stage.inputs;
      outputs = map (o:
        if o.type == "artifact" then { type = "artifact"; name = o.name; }
        else if o.type == "report" then { type = "report"; }
        else                          { type = "none"; }
      ) stage.outputs;
    }) pipeline.stages;
  };

  pipelineManifest = pkgs.writeTextFile {
    name        = "pipeline.json";
    destination = "/etc/pipeline/pipeline.json";
    text        = builtins.toJSON manifestData;
  };

  # ---------------------------------------------------------------------------
  # Pipeline runner script
  #
  # Reads /etc/pipeline/pipeline.json and executes stages.
  # jq is used for all JSON parsing — it is always present in the CI layer.
  #
  # The script uses a local variable `failures` (an array of stage names)
  # to track Collect-mode failures, and `exit_code` to accumulate the
  # final exit status.
  # ---------------------------------------------------------------------------
  runnerScript = ''
    #!/usr/bin/env bash
    set -uo pipefail
    # Note: -e is intentionally omitted. We handle errors explicitly so that
    # Collect-mode stages can fail without aborting the runner.

    ##############################################################################
    # Configuration
    ##############################################################################
    MANIFEST="/etc/pipeline/pipeline.json"
    PIPELINE_NAME=$(jq -r '.name' "$MANIFEST")
    ARTIFACT_DIR=$(jq -r '.artifactDir' "$MANIFEST")
    TARGET_STAGE="''${1:-all}"

    mkdir -p "$ARTIFACT_DIR"

    ##############################################################################
    # Helpers
    ##############################################################################
    log()  { echo "[pipeline] $*"; }
    fail() { echo "[pipeline] ERROR: $*" >&2; exit 1; }

    # Test whether a stage's condition is satisfied.
    # condition is null (always run) or a string (env var name that must be set).
    condition_satisfied() {
      local condition="$1"
      if [ "$condition" = "null" ] || [ -z "$condition" ]; then
        return 0  # no condition — always run
      fi
      # Check if the named env var is set and non-empty
      if [ -n "''${!condition:-}" ]; then
        return 0  # condition satisfied
      fi
      return 1  # condition not satisfied — skip stage
    }

    # Run a single stage. Returns the stage's exit code.
    run_stage() {
      local name="$1"
      local command="$2"
      local failure_mode="$3"

      log "━━━━ Stage: $name ━━━━"
      log "Command: $command"

      local log_file="$ARTIFACT_DIR/$name.log"
      local exit_file="$ARTIFACT_DIR/$name.exit"

      # Run the stage command in /workspace, capturing output
      (cd /workspace && eval "$command") 2>&1 | tee "$log_file"
      local stage_exit="''${PIPESTATUS[0]}"

      echo "$stage_exit" > "$exit_file"

      if [ "$stage_exit" -eq 0 ]; then
        log "✅ Stage '$name' passed"
      else
        log "❌ Stage '$name' failed (exit $stage_exit)"
      fi

      return "$stage_exit"
    }

    ##############################################################################
    # Stage execution loop
    ##############################################################################
    log "════════════════════════════════════════════════════════════════"
    log " Pipeline: $PIPELINE_NAME"
    log " Target:   $TARGET_STAGE"
    log " Artifacts: $ARTIFACT_DIR"
    log "════════════════════════════════════════════════════════════════"

    START_TIME=$(date +%s)
    failures=()
    skipped=()
    passed=()
    final_exit=0

    stage_count=$(jq '.stages | length' "$MANIFEST")

    for i in $(seq 0 $(( stage_count - 1 ))); do
      name=$(        jq -r ".stages[$i].name"        "$MANIFEST")
      command=$(     jq -r ".stages[$i].command"     "$MANIFEST")
      failure_mode=$(jq -r ".stages[$i].failureMode" "$MANIFEST")
      condition=$(   jq -r ".stages[$i].condition"   "$MANIFEST")

      # Single-stage invocation: skip non-matching stages
      if [ "$TARGET_STAGE" != "all" ] && [ "$TARGET_STAGE" != "$name" ]; then
        continue
      fi

      # Condition gate
      if ! condition_satisfied "$condition"; then
        log "⏭  Stage '$name' skipped (condition: $condition not set)"
        skipped+=("$name")
        continue
      fi

      # Execute the stage
      run_stage "$name" "$command" "$failure_mode"
      stage_exit=$?

      if [ "$stage_exit" -eq 0 ]; then
        passed+=("$name")
      else
        case "$failure_mode" in
          fail-fast)
            failures+=("$name")
            final_exit=$stage_exit
            log "Pipeline aborted (FailFast on stage '$name')"
            break
            ;;
          collect)
            failures+=("$name")
            final_exit=1
            # Continue to next stage
            ;;
          *)
            # Unknown failure mode: treat as FailFast
            failures+=("$name")
            final_exit=$stage_exit
            log "Pipeline aborted (unknown failure mode '$failure_mode' on stage '$name')"
            break
            ;;
        esac
      fi
    done

    END_TIME=$(date +%s)
    DURATION=$(( END_TIME - START_TIME ))

    ##############################################################################
    # Summary report
    ##############################################################################
    log "════════════════════════════════════════════════════════════════"
    log " Pipeline complete in ''${DURATION}s"
    log " Passed:  ''${#passed[@]}"
    log " Failed:  ''${#failures[@]}"
    log " Skipped: ''${#skipped[@]}"
    [ $final_exit -eq 0 ] && log " Result:  ✅ PASS" || log " Result:  ❌ FAIL"
    log "════════════════════════════════════════════════════════════════"

    # Machine-readable summary
    cat > "$ARTIFACT_DIR/summary.json" << JSON
    {
      "pipeline": "$PIPELINE_NAME",
      "target": "$TARGET_STAGE",
      "duration_seconds": $DURATION,
      "result": "$([ $final_exit -eq 0 ] && echo pass || echo fail)",
      "passed":  $(printf '%s\n' "''${passed[@]+"''${passed[@]}"}"  | jq -R . | jq -s .),
      "failed":  $(printf '%s\n' "''${failures[@]+"''${failures[@]}"}" | jq -R . | jq -s .),
      "skipped": $(printf '%s\n' "''${skipped[@]+"''${skipped[@]}"}" | jq -R . | jq -s .)
    }
    JSON

    # Human-readable summary
    {
      echo "Pipeline: $PIPELINE_NAME"
      echo "Duration: ''${DURATION}s"
      echo "Result:   $([ $final_exit -eq 0 ] && echo PASS || echo FAIL)"
      echo ""
      echo "Passed  (''${#passed[@]}):  $(IFS=', '; echo "''${passed[*]:-none}")"
      echo "Failed  (''${#failures[@]}): $(IFS=', '; echo "''${failures[*]:-none}")"
      echo "Skipped (''${#skipped[@]}): $(IFS=', '; echo "''${skipped[*]:-none}")"
    } > "$ARTIFACT_DIR/summary.txt"

    exit $final_exit
  '';

  pipelineRunner = pkgs.writeShellScriptBin "pipeline-runner" runnerScript;

in
  # Return a list of derivations for container.nix to include in pipelineFiles
  [ pipelineManifest pipelineRunner ]

