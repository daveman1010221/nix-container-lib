#!/usr/bin/env nu
# example-build-pipeline.nu
#
# Example project-specific pipeline for nix-container-lib itself.
# Demonstrates how to write a custom build pipeline using core.nu.
#
# Tasks:
#   fmt        — check dhall formatting
#   check-dhall — type-check all dhall files
#   build      — build the smoke test container image

#since the smoketest runs this inside the container:
#use ./core.nu *
use /etc/pipeline/core.nu *

const COMPONENT = "nix-container-lib"

def main [
    --artifact-dir: path = "pipeline-out"
    --target: string = "all"
] {
    let cassini_job_id = start-cassini-daemon

    mkdir $artifact_dir

    let repo_root = ($env.PWD)

    let tasks = [
        {
            name: "fmt"
            run: {
                let files = (glob $"($repo_root)/dhall/**/*.dhall")
                let results = ($files | each { |f|
                    let r = (^dhall format --check $f | complete)
                    if $r.exit_code != 0 {
                        log-warn $"($f | path basename): not formatted" --component $COMPONENT
                    }
                    $r.exit_code
                })
                if ($results | any { $in != 0 }) { 1 } else { 0 }
            }
        }
        {
            name: "check-dhall"
            run: {
                let files = (glob $"($repo_root)/dhall/**/*.dhall")
                let results = ($files | each { |f|
                    let r = (^dhall type $f | complete)
                    if $r.exit_code != 0 {
                        log-warn $"($f | path basename): type error" --component $COMPONENT
                    }
                    $r.exit_code
                })
                if ($results | any { $in != 0 }) { 1 } else { 0 }
            }
        }
        {
            name: "build"
            run: {
                let r = (^nix build $"($repo_root)#smokeTest" --no-link | complete)
                if $r.exit_code != 0 {
                    log-warn $"nix build failed: ($r.stderr | str trim)" --component $COMPONENT
                }
                $r.exit_code
            }
        }
    ]

    let active_tasks = if $target == "all" {
        $tasks
    } else {
        let matched = ($tasks | where name == $target)
        if ($matched | is-empty) {
            log-error $"no task named '($target)' — available: ($tasks | get name | str join ', ')"
            exit 1
        }
        $matched
    }

    mut passed = []
    mut failed = []

    for task in $active_tasks {
        log-info $"=== Task: ($task.name) ===" --component $COMPONENT
        let start = (date now)
        let exit_code = (do $task.run)
        let duration_ms = (((date now) - $start) / 1_000_000 | into int)

        if $exit_code == 0 {
            log-info $"($task.name): passed (($duration_ms)ms)" --component $COMPONENT
            $passed = ($passed | append $task.name)
        } else {
            log-warn $"($task.name): failed (($duration_ms)ms) — continuing" --component $COMPONENT
            $failed = ($failed | append $task.name)
        }
    }

    log-info "════════════════════════════════════════════════════" --component $COMPONENT
    log-info $"passed:  ($passed | str join ', ' | default 'none')" --component $COMPONENT
    log-info $"failed:  ($failed | str join ', ' | default 'none')" --component $COMPONENT
    log-info "════════════════════════════════════════════════════" --component $COMPONENT

    stop-cassini-daemon $cassini_job_id

    if ($failed | is-not-empty) { exit 1 }
}
