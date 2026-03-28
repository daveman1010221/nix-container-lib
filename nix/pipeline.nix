
# polar-container-lib/nix/pipeline.nix
#
# Produces derivations for inclusion in pipeline container images:
#
#   pipelineManifest   → /etc/pipeline/pipeline.json          (derivation-style)
#   toolchainManifest  → /etc/pipeline/toolchain.json         (store path inventory)
#   pipelineRunner     → /etc/pipeline/pipeline_runner.nu     (nushell runner)
#   attestedBuild      → /etc/pipeline/cargo-attested-build.nu
#   entrypoint         → /bin/pipeline-runner                 (thin wrapper)
#
# CONTRACT
# --------
# Called by container.nix with { pkgs, cfg } — same as every other module.
# cfg.packages is the fully-resolved package list (Core + CI + Toolchain + Pipeline
# + extraPackages, already composed by from-dhall.nix). cfg.pipeline is the
# pipeline definition from the Dhall config.
#
# This module does NOT select packages — packages.nix and the Dhall config do that.
# What this module does is:
#   1. Introspect cfg.packages to build a toolchain manifest (store paths + versions)
#   2. Generate the derivation-style pipeline manifest with input pin slots
#   3. Import the nushell runner and attested build scripts from the source tree
#   4. Wire up the entrypoint
#
# TOOLCHAIN MANIFEST
# ------------------
# toolchain.json records the Nix store path of every package in cfg.packages.
# This is NOT a package selection mechanism — it's an introspection of what
# was already selected. The runner reads it at startup and hashes it to produce
# the toolchain input pin. A verifier can compare these store paths against
# a rebuild from the same flake.lock to confirm the pipeline ran with the
# expected tools.
#
# MANIFEST FORMAT
# ---------------
# The pipeline manifest follows the "derivation-style" pattern:
#   - Top-level `inputs` with `pin: null` slots (filled at runtime by the runner)
#   - Stages reference inputs by name via { ref: "source" }
#   - Each stage declares `pure: true|false`
#   - Cross-stage artifact references via { type: "stage-output", stage, artifact }
#   - Reproducibility metadata auto-collected from stage purity flags

{ pkgs
, cfg
}:

let
  lib = pkgs.lib;
  pipeline = cfg.pipeline;  # guaranteed non-null by caller (container.nix)




  # ---------------------------------------------------------------------------
  # Toolchain manifest
  #
  # Walks cfg.packages and records each derivation's store path, name, and
  # version. This captures the exact closure that container.nix assembled —
  # no separate tool list to maintain.
  # ---------------------------------------------------------------------------

  toolchainEntries = map (drv:
    let
      name = drv.pname or drv.name or "unknown";
      version = drv.version or null;
    in {
      inherit name version;
      store_path = "${drv}";
    }
  ) cfg.packages;

  toolchainData = {
    packages = toolchainEntries;
    _meta = {
      package_count = builtins.length cfg.packages;
      generated_by  = "polar-container-lib/nix/pipeline.nix";
    };
  };

  toolchainManifest = pkgs.writeTextFile {
    name        = "toolchain.json";
    destination = "/etc/pipeline/toolchain.json";
    text        = builtins.toJSON toolchainData;
  };

  # ---------------------------------------------------------------------------
  # Pipeline manifest (derivation-style JSON)
  # ---------------------------------------------------------------------------

  mapStageInput = i:
    if i.type == "workspace"    then { ref = "source"; }
    else if i.type == "lockfile"  then { ref = "lockfile"; }
    else if i.type == "toolchain" then { ref = "toolchain"; }
    else if i.type == "artifact"  then
      if i ? stage
      then { type = "stage-output"; stage = i.stage; artifact = i.name; }
      else { ref = i.name; }
    else if i.type == "environment" then {
      type = "environment";
      name = i.name or "unnamed";
      description = i.description or "";
    }
    else { ref = i.type; };

  mapStageOutput = o:
    if o.type == "artifact" then
      { type = "artifact"; name = o.name; }
      // (lib.optionalAttrs (o ? content_type) { content_type = o.content_type; })
    else if o.type == "assertion" then
      { type = "assertion"; name = o.name or "unnamed"; }
      // (lib.optionalAttrs (o ? description) { description = o.description; })
    else if o.type == "report" then
      { type = "report"; }
      // (lib.optionalAttrs (o ? name) { name = o.name; })
    else
      { type = "none"; };

  manifestData = {
    "$schema"   = "polar.pipeline/v1";
    name        = pipeline.name;
    artifactDir = pipeline.artifactDir;
    workingDir  = pipeline.workingDir;

    # Top-level input declarations. Pins are null at image build time —
    # the runner fills them at execution time from the actual filesystem.
    inputs = {
      source = {
        type = "git-tree";
        description = "Workspace source tree, pinned by git tree hash";
        pin = null;
      };
      toolchain = {
        type = "nix-closure";
        description = "Build environment, pinned by toolchain.json content hash";
        pin = null;
      };
      lockfile = {
        type = "file";
        path = "Cargo.lock";
        description = "Dependency resolution, pinned by content hash";
        pin = null;
      };
    };

    stages = map (stage:
      {
        inherit (stage) name command failureMode condition;
        pure    = stage.pure or true;
        inputs  = map mapStageInput stage.inputs;
        outputs = map mapStageOutput stage.outputs;
      }
      // (lib.optionalAttrs (stage ? impurity_reason) {
        impurity_reason = stage.impurity_reason;
      })
    ) pipeline.stages;

    # Pipeline-level output declarations (if specified in Dhall config).
    outputs = lib.optionalAttrs (pipeline ? outputs) pipeline.outputs;

    reproducibility = {
      strategy = "content-addressed-inputs";
      known_impurities = lib.pipe pipeline.stages [
        (builtins.filter (s: !(s.pure or true)))
        (map (s: "${s.name}: ${s.impurity_reason or "unspecified"}"))
      ];
    };
  };

  pipelineManifest = pkgs.writeTextFile {
    name        = "pipeline.json";
    destination = "/etc/pipeline/pipeline.json";
    text        = builtins.toJSON manifestData;
  };

  # ---------------------------------------------------------------------------
  # Pipeline runner (nushell — imported from source tree)
  #
  # The runner is a normal file in the repo at scripts/pipeline_runner.nu.
  # Nix reads it at build time.
  # Edit it with syntax highlighting and tooling — no inline
  # heredoc nonsense.
  #
  # If the .nu files don't exist yet (bootstrapping), fall back to a stub
  # that prints an error. This prevents the Nix build from failing during
  # the transition period.
  # ---------------------------------------------------------------------------

  runnerSource =
    let path = ./scripts/pipeline_runner.nu;
    in if builtins.pathExists path
       then builtins.readFile path
       else ''
         #!/usr/bin/env nu
         print "[pipeline_runner] ERROR: runner script not found at build time"
         print "[pipeline_runner] Expected: ${toString path}"
         print "[pipeline_runner] This is a stub — the real runner has not been baked in."
         exit 1
       '';



  pipelineRunner = pkgs.writeTextFile {
    name        = "pipeline_runner.nu";
    destination = "/etc/pipeline/pipeline_runner.nu";
    text        = runnerSource;
    executable  = true;
  };


  # ---------------------------------------------------------------------------
  # Entrypoint wrapper
  #
  # Thin shell script at /bin/pipeline-runner that execs nushell with the
  # runner. The orchestrator's k8s Job can specify command args that pass
  # through (manifest path, target stage).
  # ---------------------------------------------------------------------------

  # Find nushell in cfg.packages. If it's not there (shouldn't happen for
  # pipeline containers, but defensive), fall back to PATH lookup.
  nuBin =
    let
      nuPkg = lib.findFirst
        (p: (p.pname or "") == "nushell" || (p.name or "") == "nushell")
        null
        cfg.packages;
    in
      if nuPkg != null
      then "${nuPkg}/bin/nu"
      else "/bin/nu";

  entrypoint = pkgs.writeShellScriptBin "pipeline-runner" ''
    exec ${nuBin} /etc/pipeline/pipeline_runner.nu "$@"
  '';

in
  [ pipelineManifest toolchainManifest pipelineRunner attestedBuild entrypoint ]
