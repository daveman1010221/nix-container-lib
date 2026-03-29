#!/usr/bin/env nu
# cargo-attested-build.nu
#
# Attested cargo build helper. Wraps `cargo build` with provenance event
# emission so the pipeline runner can track inputs, outputs, and timing
# through the Cassini event stream.
#
# Designed to be invoked from a pipeline stage command:
#
#   cargo-attested-build --package my-crate --release
#
# Environment (set by pipeline runner):
#   POLAR_BUILD_ID        — pipeline-level build identifier
#   POLAR_EXEC_ID         — parent stage execution identifier
#   POLAR_ARTIFACT_DIR    — where to write manifests and output records
#   POLAR_WORKING_DIR     — workspace root
#
# Exits with cargo's exit code so the pipeline runner's failure mode logic
# applies correctly.

const SUBJECT_PREFIX = "polar.builds.provenance"

# ---------------------------------------------------------------------------
# Logging (mirrors pipeline_runner.nu)
# ---------------------------------------------------------------------------

def log [level: string, msg: string, --component: string = "attested-build"] {
    let ts = (date now | format date "%Y-%m-%dT%H:%M:%S%.3fZ")
    print $"($ts) [($level)] ($component) — ($msg)"
}

def log-info  [msg: string, --component: string = "attested-build"] { log "INFO"  $msg --component $component }
def log-warn  [msg: string, --component: string = "attested-build"] { log "WARN"  $msg --component $component }
def log-error [msg: string, --component: string = "attested-build"] { log "ERROR" $msg --component $component }

# ---------------------------------------------------------------------------
# Provenance emission (mirrors pipeline_runner.nu)
# ---------------------------------------------------------------------------

def emit [subject_suffix: string, payload: record] {
    let subject = $"($SUBJECT_PREFIX).($subject_suffix)"
    let envelope = {
        build_id:  ($env.POLAR_BUILD_ID? | default "00000000-0000-0000-0000-000000000000")
        timestamp: (date now | format date "%Y-%m-%dT%H:%M:%S%.fZ")
        payload:   ($payload | merge { type: $subject_suffix })
    }
    try {
        $envelope | to json --raw | cassini-client publish $subject $in
    } catch {|e|
        log-warn $"failed to emit ($subject): ($e.msg)"
    }
}

# ---------------------------------------------------------------------------
# Artifact discovery
#
# After a successful cargo build, walk the target directory and collect
# all produced ELF binaries (or .rlib/.rmeta for library crates).
# Returns a list of { name, path, hash, size_bytes }.
# ---------------------------------------------------------------------------

def discover-artifacts [target_dir: string, profile: string]: nothing -> list<record> {
    let profile_dir = ($target_dir | path join $profile)
    if not ($profile_dir | path exists) {
        log-warn $"target profile dir not found: ($profile_dir)"
        return []
    }

    # Collect all files directly under the profile dir (not subdirs like
    # .fingerprint, deps, build). These are the final outputs.
    let files = (
        ls $profile_dir
        | where type == "file"
        | where { |f|
            let name = ($f.name | path basename)
            # Exclude dot-files, .d dependency files, and .rmeta
            not ($name | str starts-with ".") and
            not ($name | str ends-with ".d")
        }
    )

    $files | each {|f|
        let hash = (open $f.name --raw | hash sha256 | $"sha256:($in)")
        {
            name:       ($f.name | path basename)
            path:       $f.name
            hash:       $hash
            size_bytes: $f.size
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [
    ...cargo_args: string   # Passed through verbatim to cargo build
    --package: string = ""  # --package flag value (for logging)
    --release               # Build in release mode
    --target-dir: string = "target"  # cargo target directory
] {
    let exec_id      = (random uuid)
    let parent_id    = ($env.POLAR_EXEC_ID?    | default "")
    let artifact_dir = ($env.POLAR_ARTIFACT_DIR? | default "./pipeline-out")
    let working_dir  = ($env.POLAR_WORKING_DIR?  | default ".")
    let profile      = if $release { "release" } else { "debug" }

    let build_args = (
        ["build"]
        ++ (if $release { ["--release"] } else { [] })
        ++ (if $package != "" { ["--package", $package] } else { [] })
        ++ $cargo_args
    )

    let command_str = $"cargo ($build_args | str join ' ')"
    log-info $"starting attested build: ($command_str)"
    log-info $"exec_id: ($exec_id)"

    # ── Emit build observed ─────────────────────────────────────────────────
    let base_observed = {
        execution_id: $exec_id
        command:      $command_str
        working_dir:  $working_dir
    }
    let observed_payload = if $parent_id != "" {
        $base_observed | merge { parent_execution_id: $parent_id }
    } else {
        $base_observed
    }
    emit "build.observed" $observed_payload

    # ── Run cargo ───────────────────────────────────────────────────────────
    let start = (date now)

    let result = (
        do { ^cargo ...$build_args } | complete
    )

    let duration_ms = (((date now) - $start) / 1_000_000 | into int)
    let exit_code   = $result.exit_code

    # Forward cargo's stdout/stderr (already printed live by cargo itself,
    # but capture any remainder).
    if ($result.stdout | str length) > 0 { print $result.stdout }
    if ($result.stderr | str length) > 0 { print --stderr $result.stderr }

    # ── Emit build completed ────────────────────────────────────────────────
    emit "build.completed" {
        execution_id: $exec_id
        exit_code:    $exit_code
        duration_ms:  $duration_ms
    }

    if $exit_code != 0 {
        log-error $"cargo build failed (exit $exit_code) after ($duration_ms)ms"
        exit $exit_code
    }

    log-info $"cargo build succeeded in ($duration_ms)ms"

    # ── Discover and attest artifacts ───────────────────────────────────────
    let artifacts = (discover-artifacts $target_dir $profile)
    log-info $"discovered ($artifacts | length) artifact(s)"

    for artifact in $artifacts {
        emit "artifact.produced" {
            execution_id: $exec_id
            artifact_id:  $artifact.hash
            artifact_type: "elf-binary"
            name:          $artifact.name
            path:          $artifact.path
            size_bytes:    $artifact.size_bytes
        }
        log-info $"attested: ($artifact.name) -> ($artifact.hash)"
    }

    # ── Write artifact record ───────────────────────────────────────────────
    # Saved to the artifact dir so the pipeline runner can register outputs.
    mkdir $artifact_dir
    let record = {
        schema:       "polar.attested-build/v1"
        exec_id:      $exec_id
        command:      $command_str
        profile:      $profile
        duration_ms:  $duration_ms
        exit_code:    $exit_code
        artifacts:    $artifacts
    }
    let record_path = ($artifact_dir | path join $"attested-build-($exec_id).json")
    $record | to json --indent 2 | save -f $record_path
    log-info $"wrote artifact record to ($record_path)"

    exit 0
}
