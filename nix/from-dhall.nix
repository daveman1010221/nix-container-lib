# polar-container-lib/nix/from-dhall.nix
#
# Bridges the Dhall ContainerConfig type to the Nix structures that the
# container library functions expect.
#
# This is the seam between the typed configuration layer (Dhall) and the
# Nix implementation layer. It should contain NO policy — only translation.
# Policy lives in the Dhall defaults and in the individual nix/* functions.
#
# Usage:
#   let cfg = (pkgs.dhallToNix ./my-container.dhall).result;
#   let translated = import ./from-dhall.nix { inherit pkgs cfg inputs; };
#
# The `inputs` argument carries flake inputs so PackageRef { flakeInput = Some "x" }
# can be resolved to the correct derivation.

{ pkgs
, cfg       # The Dhall ContainerConfig, evaluated to a Nix attrset
, inputs    # Flake inputs attrset for resolving PackageRef.flakeInput
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Mode translation
  # Dhall union tags arrive as attrsets: { Dev = null } | { CI = null } | ...
  # We normalize to a simple string for downstream consumers.
  # ---------------------------------------------------------------------------
  resolveMode = mode: mode {
    Dev      = "dev";
    CI       = "ci";
    Agent    = "agent";
    Pipeline = "pipeline";
  };

  mode = resolveMode cfg.mode;

  # ---------------------------------------------------------------------------
  # PackageRef resolution
  # Resolves a { attrPath, flakeInput } to an actual derivation.
  # attrPath is a dot-separated string: "llvmPackages_19.clang"
  # flakeInput = null means nixpkgs; otherwise it names a flake input.
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
              # Try .packages.${system} first, then the input root
              let inp = inputs.${inputName};
              in if inp ? packages && inp.packages ? ${pkgs.system}
                 then inp.packages.${pkgs.system}
                 else inp
            else throw "from-dhall: flake input '${inputName}' not found in inputs";

      # Walk the dot-separated attrPath
      attrParts = lib.splitString "." ref.attrPath;
      resolved  = lib.getAttrFromPath attrParts source;
    in
      resolved;

  # ---------------------------------------------------------------------------
  # PackageLayer resolution
  # Each named layer maps to the concrete package list defined in packages.nix.
  # Custom layers are resolved by walking their PackageRef list.
  # ---------------------------------------------------------------------------
  packageSets = import ./packages.nix { inherit pkgs inputs; };

  # Dhall unions compile to Nix as functions: PackageLayer.Core = (u: u.Core)
  # To dispatch on which variant we have, apply the layer function to a
  # handler record where each field returns a recognizable sentinel, then
  # match on the result.
  resolveLayer = layer:
    let
      sentinel = layer {
        Core     = "Core";
        CI       = "CI";
        Dev      = "Dev";
        Toolchain = "Toolchain";
        Pipeline = "Pipeline";
        Agent    = "Agent";
        Custom   = payload: { _custom = payload; };
      };
    in
      if sentinel == "Core"     then packageSets.core
      else if sentinel == "CI"  then packageSets.ci
      else if sentinel == "Dev" then packageSets.dev
      else if sentinel == "Toolchain" then packageSets.toolchain
      else if sentinel == "Pipeline"  then packageSets.pipeline
      else if sentinel == "Agent"     then packageSets.agent
      else if sentinel ? _custom then
        map resolvePackageRef sentinel._custom.packages
      else throw "from-dhall: unknown PackageLayer variant";

  # Flatten all resolved layers into a single deduplicated package list
  # Deduplicate by outPath to avoid lib.unique's structural equality check.
  # lib.unique deeply evaluates every element, triggering the NixOS module
  # system on derivations like neovim that carry plugin configs as attributes.
  resolvedPackages =
    let
      allPkgs = lib.concatMap resolveLayer cfg.packageLayers;
      seen    = builtins.foldl'
        (acc: p:
          if acc.paths ? ${builtins.unsafeDiscardStringContext p.outPath}
          then acc
          else { paths = acc.paths // { ${builtins.unsafeDiscardStringContext p.outPath} = true; }; list = acc.list ++ [ p ]; }
        )
        { paths = {}; list = []; }
        allPkgs;
    in seen.list;

  # ---------------------------------------------------------------------------
  # EnvVar split
  # Route extraEnv entries to their correct destination based on placement.
  # BuildTime  → config.Env list  (safe: no store paths)
  # StartTime  → start.sh exports (store-path-bearing or arch-sensitive)
  # UserProvided → documented but not emitted by the library; caller's concern
  # ---------------------------------------------------------------------------
  isPlacement = tag: ev:
    ev.placement ? ${tag};

  buildTimeEnv =
    map (ev: "${ev.name}=${ev.value}")
      (builtins.filter (isPlacement "BuildTime") cfg.extraEnv);

  startTimeEnv =
    builtins.filter (isPlacement "StartTime") cfg.extraEnv;

  # ---------------------------------------------------------------------------
  # Shell config translation
  # Optional ShellConfig → the arguments interactiveShellInit.nix expects.
  # Returns null when shell = None, signalling no shell setup required.
  # ---------------------------------------------------------------------------
  resolveShell =
    if cfg.shell == null
    then null
    else
      let s = cfg.shell;
      in {
        shell       = s.shell;
        colorScheme = s.colorScheme;
        viBindings  = s.viBindings;
        plugins     = s.plugins;
      };

  # ---------------------------------------------------------------------------
  # NixConfig translation
  # Produces the fragments that become /etc/nix/nix.conf entries and the
  # runtime arch-detection block in start.sh.
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
  # Optional PipelineConfig → the arguments pipeline.nix expects.
  # ---------------------------------------------------------------------------
  resolveFailureMode = fm: fm {
    FailFast = "fail-fast";
    Collect  = "collect";
  };

  resolveStageInput = si: si {
    Workspace   = { type = "workspace"; };
    Artifact    = name: { type = "artifact"; inherit name; };
    Environment = { type = "environment"; };
  };

  resolveStageOutput = so: so {
    Artifact = name: { type = "artifact"; inherit name; };
    Report   = { type = "report"; };
    None     = { type = "none"; };
  };

  resolveStage = stage: {
    name        = stage.name;
    command     = stage.command;
    failureMode = resolveFailureMode stage.failureMode;
    inputs      = map resolveStageInput stage.inputs;
    outputs     = map resolveStageOutput stage.outputs;
    condition   = stage.condition; # null or string
  };

  resolvedPipeline =
    if cfg.pipeline == null
    then null
    else {
      name        = cfg.pipeline.name;
      stages      = map resolveStage cfg.pipeline.stages;
      artifactDir = cfg.pipeline.artifactDir;
      workingDir  = cfg.pipeline.workingDir;
    };

  # ---------------------------------------------------------------------------
  # TLS translation
  # ---------------------------------------------------------------------------
  resolvedTLS =
    if cfg.tls == null
    then null
    else {
      enable        = cfg.tls.enable;
      generateCerts = cfg.tls.generateCerts;
      certsPath     = cfg.tls.certsPath; # null or string
    };

  # Assertion: generateCerts = true and certsPath set is a configuration error
  tlsAssertion =
    if resolvedTLS != null
       && resolvedTLS.generateCerts
       && resolvedTLS.certsPath != null
    then throw "from-dhall: TLSConfig error: generateCerts = true and certsPath is set. Choose one."
    else true;

  # Assertion: Core layer must be present
  coreAssertion =
    let
      isCore = layer: (layer {
        Core = true; CI = false; Dev = false; Toolchain = false;
        Pipeline = false; Agent = false; Custom = _: false;
      });
    in
    if builtins.any isCore cfg.packageLayers
    then true
    else throw "from-dhall: ContainerConfig '${cfg.name}': packageLayers must include Core";

  # ---------------------------------------------------------------------------
  # SSH translation
  # ---------------------------------------------------------------------------
  resolvedSSH =
    if cfg.ssh == null
    then null
    else {
      enable = cfg.ssh.enable;
      port   = cfg.ssh.port;
    };

  # ---------------------------------------------------------------------------
  # User config translation
  # ---------------------------------------------------------------------------
  resolvedUser = {
    createUser         = cfg.user.createUser;
    defaultShell       = cfg.user.defaultShell;
    skeletonPath       = cfg.user.skeletonPath;
    supplementalGroups = cfg.user.supplementalGroups or [];
  };

  # ---------------------------------------------------------------------------
  # AI tooling translation
  # ---------------------------------------------------------------------------
  resolvedAi =
      if !(cfg ? ai) || cfg.ai == null
      then { enable = false; modelsPath = "/opt/llama-models"; llamaPort = 8080; }
    else {
      enable      = cfg.ai.enable;
      modelsPath  = cfg.ai.modelsPath or "/opt/llama-models";
      llamaPort   = cfg.ai.llamaPort  or 8080;
    };

in
  assert tlsAssertion;
  assert coreAssertion;

  # ---------------------------------------------------------------------------
  # The translated configuration record.
  # This is what container.nix, entrypoint.nix, shell.nix, etc. consume.
  # Each downstream function receives only the slice it needs.
  # ---------------------------------------------------------------------------
  {
    # Scalar metadata
    name = cfg.name;
    mode = mode;

    # Resolved package list (flat, deduplicated)
    packages = resolvedPackages;

    # Environment variable split
    buildTimeEnv = buildTimeEnv;   # List of "NAME=value" strings → config.Env
    startTimeEnv = startTimeEnv;   # List of EnvVar records → start.sh exports

    # Subsystem configs (null = disabled)
    shell    = resolveShell;
    nix      = resolvedNix;
    pipeline = resolvedPipeline;
    tls      = resolvedTLS;
    ssh      = resolvedSSH;
    user     = resolvedUser;
    ai       = resolvedAi;
  }
