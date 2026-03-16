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
  resolveMode = mode:
    if mode ? Dev      then "dev"
    else if mode ? CI  then "ci"
    else if mode ? Agent then "agent"
    else if mode ? Pipeline then "pipeline"
    else throw "from-dhall: unknown Mode variant: ${builtins.toJSON mode}";

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

  resolveLayer = layer:
    if      layer ? Core     then packageSets.core
    else if layer ? CI       then packageSets.ci
    else if layer ? Dev      then packageSets.dev
    else if layer ? Toolchain then packageSets.toolchain
    else if layer ? Pipeline then packageSets.pipeline
    else if layer ? Agent    then packageSets.agent
    else if layer ? Custom   then
      map resolvePackageRef layer.Custom.packages
    else throw "from-dhall: unknown PackageLayer variant: ${builtins.toJSON layer}";

  # Flatten all resolved layers into a single deduplicated package list
  resolvedPackages =
    lib.unique (lib.concatMap resolveLayer cfg.packageLayers);

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
  resolveSandboxPolicy = policy:
    if policy ? Enabled  then "enabled"
    else if policy ? Disabled then "disabled"
    else if policy ? Auto then "auto"
    else throw "from-dhall: unknown SandboxPolicy: ${builtins.toJSON policy}";

  resolveBuildUserCount = count:
    if count ? Dynamic then { dynamic = true; fixed = null; }
    else if count ? Fixed then { dynamic = false; fixed = count.Fixed; }
    else throw "from-dhall: unknown BuildUserCount: ${builtins.toJSON count}";

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
  resolveFailureMode = fm:
    if fm ? FailFast then "fail-fast"
    else if fm ? Collect then "collect"
    else throw "from-dhall: unknown FailureMode: ${builtins.toJSON fm}";

  resolveStageInput = si:
    if si ? Workspace   then { type = "workspace"; }
    else if si ? Artifact then { type = "artifact"; name = si.Artifact; }
    else if si ? Environment then { type = "environment"; }
    else throw "from-dhall: unknown StageInput: ${builtins.toJSON si}";

  resolveStageOutput = so:
    if so ? Artifact  then { type = "artifact"; name = so.Artifact; }
    else if so ? Report  then { type = "report"; }
    else if so ? None    then { type = "none"; }
    else throw "from-dhall: unknown StageOutput: ${builtins.toJSON so}";

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
    if builtins.any (l: l ? Core) cfg.packageLayers
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
    createUser   = cfg.user.createUser;
    defaultShell = cfg.user.defaultShell;
    skeletonPath = cfg.user.skeletonPath;
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
  }
