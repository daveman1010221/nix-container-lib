# polar-container-lib/nix/from-dhall.nix
#
# Bridges the Dhall ContainerConfig type to the Nix structures that the
# container library functions expect.
#
# This is the seam between the typed configuration layer (Dhall) and the
# Nix implementation layer. It should contain NO policy — only translation.
# Policy lives in the Dhall defaults and in the individual nix/* functions.

{ pkgs
, cfg
, inputs
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Mode translation
  # ---------------------------------------------------------------------------
  resolveMode = mode: mode {
    Dev      = "dev";
    CI       = "ci";
    Agent    = "agent";
    Pipeline = "pipeline";
    Minimal  = "minimal";
  };

  mode = resolveMode cfg.mode;

  # ---------------------------------------------------------------------------
  # PackageRef resolution
  # ---------------------------------------------------------------------------
  resolvePackageRef = ref:
    let
      source =
        if ref.flakeInput == null
        then pkgs
        else
          let inputName = ref.flakeInput;
          in
            if inputs ? ${inputName}
            then
              let inp = inputs.${inputName};
              in if inp ? packages && inp.packages ? ${pkgs.system}
                 then inp.packages.${pkgs.system}
                 else inp
            else throw "from-dhall: flake input '${inputName}' not found in inputs";

      attrParts = lib.splitString "." ref.attrPath;
      resolved  = lib.getAttrFromPath attrParts source;
    in
      resolved;

  # ---------------------------------------------------------------------------
  # PackageLayer resolution
  # ---------------------------------------------------------------------------
  packageSets = import ./packages.nix { inherit pkgs inputs; };

  resolveLayer = layer:
    let
      sentinel = layer {
        Micro     = "Micro";
        Core      = "Core";
        CI        = "CI";
        Dev       = "Dev";
        Toolchain = "Toolchain";
        Pipeline  = "Pipeline";
        Agent     = "Agent";
        Custom    = payload: { _custom = payload; };
      };
    in
      if sentinel == "Micro"     then packageSets.micro
      else if sentinel == "Core" then packageSets.core
      else if sentinel == "CI"   then packageSets.ci
      else if sentinel == "Dev"  then packageSets.dev
      else if sentinel == "Toolchain" then packageSets.toolchain
      else if sentinel == "Pipeline"  then packageSets.pipeline
      else if sentinel == "Agent"     then packageSets.agent
      else if sentinel ? _custom then
        map resolvePackageRef sentinel._custom.packages
      else throw "from-dhall: unknown PackageLayer variant";

  resolvedPackages =
    let
      # Base packages from declared layers
      layerPkgs = lib.concatMap resolveLayer cfg.packageLayers;

      # Shell packages — added based on shell config, NOT from any PackageLayer.
      # This ensures shell binaries only appear when explicitly requested.
      shellPkgs =
        if cfg.shell == null
        then []
        else
          cfg.shell {
            Minimal = payload:
              if payload.shell == "/bin/sh"  then packageSets.shellDash
              else if payload.shell == "/bin/nu" then packageSets.shellNuMinimal
              else throw "from-dhall: unsupported minimal shell '${payload.shell}'. Use /bin/sh or /bin/nu";
            Interactive = payload:
              if payload.shell == "/bin/fish" then packageSets.shellFishInteractive
              else if payload.shell == "/bin/nu"  then packageSets.shellNuInteractive
              else throw "from-dhall: unsupported interactive shell '${payload.shell}'. Use /bin/fish or /bin/nu";
          };

      allPkgs = layerPkgs ++ shellPkgs;

      # Deduplicate by store path
      seen = builtins.foldl'
        (acc: p:
          if acc.paths ? ${builtins.unsafeDiscardStringContext p.outPath}
          then acc
          else {
            paths = acc.paths // { ${builtins.unsafeDiscardStringContext p.outPath} = true; };
            list  = acc.list ++ [ p ];
          }
        )
        { paths = {}; list = []; }
        allPkgs;
    in seen.list;

  # ---------------------------------------------------------------------------
  # EnvVar split
  # ---------------------------------------------------------------------------
  resolvePlacement = placement: placement {
    BuildTime    = "BuildTime";
    StartTime    = "StartTime";
    UserProvided = "UserProvided";
  };

  isPlacement = tag: ev:
    (resolvePlacement ev.placement) == tag;

  buildTimeEnv =
    map (ev: "${ev.name}=${ev.value}")
      (builtins.filter (isPlacement "BuildTime") cfg.extraEnv);

  startTimeEnv =
    builtins.filter (isPlacement "StartTime") cfg.extraEnv;

  # ---------------------------------------------------------------------------
  # Shell config translation
  #
  # Produces a normalized shell descriptor for downstream nix modules:
  #   null                         → no shell
  #   { type = "minimal-dash";  shell = "/bin/sh"; }
  #   { type = "minimal-nu";    shell = "/bin/nu"; }
  #   { type = "interactive-fish"; shell = "/bin/fish"; colorScheme = ...; ... }
  #   { type = "interactive-nu";   shell = "/bin/nu";  colorScheme = ...; ... }
  # ---------------------------------------------------------------------------
  resolveShell =
    if cfg.shell == null
    then null
    else
      cfg.shell {
        Minimal = payload:
          if payload.shell == "/bin/sh" then
            { type = "minimal-dash"; shell = "/bin/sh"; }
          else if payload.shell == "/bin/nu" then
            { type = "minimal-nu"; shell = "/bin/nu"; }
          else
            throw "from-dhall: unsupported minimal shell '${payload.shell}'";

        Interactive = payload:
          if payload.shell == "/bin/fish" then
            { type        = "interactive-fish";
              shell       = "/bin/fish";
              colorScheme = payload.colorScheme;
              viBindings  = payload.viBindings;
              plugins     = payload.plugins;
            }
          else if payload.shell == "/bin/nu" then
            { type        = "interactive-nu";
              shell       = "/bin/nu";
              colorScheme = payload.colorScheme;
              viBindings  = payload.viBindings;
              plugins     = payload.plugins;
            }
          else
            throw "from-dhall: unsupported interactive shell '${payload.shell}'";
      };

  # ---------------------------------------------------------------------------
  # NixConfig translation
  # ---------------------------------------------------------------------------
  resolveSandboxPolicy = policy: policy {
    Enabled  = "enabled";
    Disabled = "disabled";
    Auto     = "auto";
  };

  resolveBuildUserCount = count: count {
    Dynamic = { dynamic = true;  fixed = null; };
    Fixed   = n: { dynamic = false; fixed = n; };
  };

  resolvedNix = {
    enableDaemon   = cfg.nix.enableDaemon;
    sandboxPolicy  = resolveSandboxPolicy cfg.nix.sandboxPolicy;
    trustedUsers   = cfg.nix.trustedUsers;
    buildUserCount = resolveBuildUserCount cfg.nix.buildUserCount;
  };

  # ---------------------------------------------------------------------------
  # Pipeline translation
  # ---------------------------------------------------------------------------
  resolveFailureMode = fm: fm {
    FailFast = "fail-fast";
    Collect  = "collect";
  };

  resolveStageInput = si: si {
    Workspace   = { type = "workspace"; };
    Lockfile    = { type = "lockfile"; };
    Toolchain   = { type = "toolchain"; };
    Artifact    = name: { type = "artifact"; inherit name; };
    StageOutput = payload: {
      type  = "artifact";
      name  = payload.artifact;
      stage = payload.stage;
    };
    Environment = payload: {
      type        = "environment";
      name        = payload.name;
      description = payload.description;
    };
  };

  resolveStageOutput = so: so {
    Artifact  = payload: { type = "artifact"; name = payload.name; }
      // (lib.optionalAttrs (payload.content_type != null) { content_type = payload.content_type; });
    Assertion = payload: { type = "assertion"; name = payload.name; }
      // (lib.optionalAttrs (payload.description != null) { description = payload.description; });
    Report    = payload: { type = "report"; }
      // (lib.optionalAttrs (payload.name != null) { name = payload.name; });
    None      = { type = "none"; };
  };

  resolveStage = stage: {
    name           = stage.name;
    command        = stage.command;
    failureMode    = resolveFailureMode stage.failureMode;
    condition      = stage.condition;
    pure           = stage.pure;
    impurityReason = stage.impurityReason;
    inputs         = map resolveStageInput stage.inputs;
    outputs        = map resolveStageOutput stage.outputs;
  };

  resolvePipelineOutputs = outputs:
    if outputs == null then null
    else {
      artifacts  = map (a: { name = a.name; fromStage = a.fromStage; artifact = a.artifact; attestation = a.attestation; verifyMethod = a.verifyMethod; }) outputs.artifacts;
      assertions = map (a: { name = a.name; fromStage = a.fromStage; }) outputs.assertions;
    };

  resolvedPipeline =
    if cfg.pipeline == null then null
    else {
      name        = cfg.pipeline.name;
      artifactDir = cfg.pipeline.artifactDir;
      workingDir  = cfg.pipeline.workingDir or "/workspace";
      stages      = map resolveStage cfg.pipeline.stages;
      outputs     = resolvePipelineOutputs (cfg.pipeline.outputs or null);
    };

  # ---------------------------------------------------------------------------
  # TLS translation
  # ---------------------------------------------------------------------------
  resolvedTLS =
    if cfg.tls == null then null
    else {
      enable        = cfg.tls.enable;
      generateCerts = cfg.tls.generateCerts;
      certsPath     = cfg.tls.certsPath;
    };

  # ---------------------------------------------------------------------------
  # SSH / User / AI translation
  # ---------------------------------------------------------------------------
  resolvedSSH =
    if cfg.ssh == null then null
    else { enable = cfg.ssh.enable; port = cfg.ssh.port; };

  resolvedUser = {
    createUser         = cfg.user.createUser;
    defaultShell       = cfg.user.defaultShell;
    skeletonPath       = cfg.user.skeletonPath;
    supplementalGroups = cfg.user.supplementalGroups or [];
  };

  resolvedAi =
    if !(cfg ? ai) || cfg.ai == null
    then { enable = false; modelsPath = "/opt/llama-models"; llamaPort = 8080; }
    else { enable = cfg.ai.enable; modelsPath = cfg.ai.modelsPath or "/opt/llama-models"; llamaPort = cfg.ai.llamaPort or 8080; };

  resolvedEntrypoint = cfg.entrypoint or null;
  resolvedStaticUid  = cfg.staticUid  or null;
  resolvedStaticGid  = cfg.staticGid  or null;

  # ---------------------------------------------------------------------------
  # Assertions
  # ---------------------------------------------------------------------------
  tlsAssertion =
    if resolvedTLS != null && resolvedTLS.generateCerts && resolvedTLS.certsPath != null
    then throw "from-dhall: TLSConfig: generateCerts = true and certsPath is set. Choose one."
    else true;

  # Micro OR Core must be present — one or the other is required as a base.
  baseLayerAssertion =
    let
      hasBase = layer: layer {
        Micro = true; Core = true;
        CI = false; Dev = false; Toolchain = false;
        Pipeline = false; Agent = false; Custom = _: false;
      };
    in
    if builtins.any hasBase cfg.packageLayers
    then true
    else throw "from-dhall: ContainerConfig '${cfg.name}': packageLayers must include Micro or Core";

  # CI and Pipeline modes require pipeline to be set — pipeline-runner won't exist otherwise
  pipelineRequiredAssertion =
    if (mode == "ci" || mode == "pipeline") && cfg.pipeline == null
    then throw "from-dhall: ContainerConfig '${cfg.name}': mode = CI or Pipeline requires pipeline to be set. Add pipeline = Some { ... } to your container.dhall."
    else true;

  # In minimal mode: either entrypoint OR shell must be set (shell acts as entrypoint)
  minimalAssertion =
    if mode == "minimal" && resolvedEntrypoint == null && cfg.shell == null
    then throw "from-dhall: ContainerConfig '${cfg.name}': mode = Minimal requires either entrypoint or shell to be set"
    else true;

  # Interactive shell is not valid in minimal mode
  interactiveInMinimalAssertion =
    if mode == "minimal" && cfg.shell != null then
      cfg.shell {
        Minimal     = _: true;
        Interactive = _: throw "from-dhall: ContainerConfig '${cfg.name}': Shell.Interactive is not valid in Minimal mode. Use Shell.Minimal instead.";
      }
    else true;

in
  assert tlsAssertion;
  assert baseLayerAssertion;
  assert pipelineRequiredAssertion;
  assert minimalAssertion;
  assert interactiveInMinimalAssertion;

  {
    name         = cfg.name;
    mode         = mode;
    packages     = resolvedPackages;
    buildTimeEnv = buildTimeEnv;
    startTimeEnv = startTimeEnv;
    shell        = resolveShell;
    nix          = resolvedNix;
    pipeline     = resolvedPipeline;
    tls          = resolvedTLS;
    ssh          = resolvedSSH;
    user         = resolvedUser;
    ai           = resolvedAi;
    entrypoint   = resolvedEntrypoint;
    staticUid    = resolvedStaticUid;
    staticGid    = resolvedStaticGid;
  }
