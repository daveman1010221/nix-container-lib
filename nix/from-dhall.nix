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
    Dev       = "dev";
    InfraAgent = "infra-agent";
    AIAgent   = "ai-agent";
    System    = "system";
    Minimal   = "minimal";
  };

  mode = resolveMode cfg.mode;

  # ---------------------------------------------------------------------------
  # PackageRef resolution
  # ---------------------------------------------------------------------------
  # Packages the library builds its own way when a config names them from nixpkgs. dropbear with AES-GCM, which its
  # default build leaves out (DROPBEAR_ENABLE_GCM_MODE 0; its options are #ifndef-guarded, so a -D sets one): a client
  # under a FIPS policy (a managed Mac's /etc/ssh/ssh_config.d) takes only AES-GCM ciphers, and refused every
  # connection to chacha20-poly1305 and AES-CTR.
  nixpkgsOverrides = {
    dropbear = pkgs.dropbear.overrideAttrs (old: {
      env = (old.env or { }) // { CFLAGS = (old.env.CFLAGS or "") + " -DDROPBEAR_ENABLE_GCM_MODE=1"; };
    });
  };

  resolvePackageRef = ref:
    let
      source =
        if ref.flakeInput == null
        then pkgs // nixpkgsOverrides
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
      Micro          = "Micro";
      Core           = "Core";
      CI             = "CI";
      InteractiveDev = "InteractiveDev";
      RustToolchain  = "RustToolchain";
      PythonToolchain = "PythonToolchain";
      NodeToolchain  = "NodeToolchain";
      Infrastructure = "Infrastructure";
      Custom         = payload: { _custom = payload; };
    };
  in
    if sentinel == "Micro"           then packageSets.micro
    else if sentinel == "Core"       then packageSets.core
    else if sentinel == "CI"         then packageSets.ci
    else if sentinel == "InteractiveDev"  then packageSets.interactiveDev
    else if sentinel == "RustToolchain"   then packageSets.rustToolchain
    else if sentinel == "PythonToolchain" then packageSets.pythonToolchain
    else if sentinel == "NodeToolchain"   then packageSets.nodeToolchain
    else if sentinel == "Infrastructure"  then packageSets.infrastructure
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

      # What start.nu runs on, in every non-minimal container, so that one need not take the Core layer for it.
      runtimePkgs = lib.optionals (mode != "minimal") packageSets.startRuntime;

      allPkgs = layerPkgs ++ shellPkgs ++ runtimePkgs;

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
  # Startup translation
  #
  # Normalized for entrypoint.nix:
  #   session = { kind = "none" | "from-env" | "fixed"; fallback = "root" | "refuse"; user = { name; uid; gid; } | null; }
  #   boot    = [ { kind = "delegate-cgroups"; } | { kind = "sysctls"; path; } | { kind = "nft-ruleset"; path; }
  #             | { kind = "script"; name; command; required; } ]
  #   launch  = { kind = "interactive" | "headless" | "system"; allowHeadless; }
  #
  # A config without startup (startup = None, or rendered before Startup existed) starts as its mode always did.
  # ---------------------------------------------------------------------------
  resolveSession = session: session {
    None    = { kind = "none"; fallback = "root"; user = null; };
    FromEnv = fallback: {
      kind = "from-env";
      fallback = fallback { Root = "root"; Refuse = "refuse"; };
      user = null;
    };
    Fixed   = user: { kind = "fixed"; fallback = "root"; user = { inherit (user) name uid gid; }; };
  };

  resolveBootStep = step: step {
    DelegateCgroups = { kind = "delegate-cgroups"; };
    Sysctls         = path: { kind = "sysctls"; inherit path; };
    NftRuleset      = path: { kind = "nft-ruleset"; inherit path; };
    Script          = s: { kind = "script"; inherit (s) name command required; };
  };

  resolveLaunch = launch: launch {
    Interactive = p: { kind = "interactive"; allowHeadless = p.allowHeadless; };
    Headless    = { kind = "headless"; allowHeadless = false; };
    System      = { kind = "system"; allowHeadless = false; };
  };

  modeStartup =
    if mode == "system" then {
      session = { kind = "none"; fallback = "root"; user = null; };
      boot    = [];
      launch  = { kind = "system"; allowHeadless = false; };
    } else {
      session =
        if cfg.user.createUser
        then { kind = "from-env"; fallback = "root"; user = null; }
        else { kind = "none"; fallback = "root"; user = null; };
      boot    = [];
      launch  = { kind = "interactive"; allowHeadless = true; };
    };

  resolvedStartup =
    if (cfg.startup or null) == null then modeStartup
    else {
      session = resolveSession cfg.startup.session;
      boot    = map resolveBootStep cfg.startup.boot;
      launch  = resolveLaunch cfg.startup.launch;
    };

  # ---------------------------------------------------------------------------
  # Services translation: one vigil layer service each (entrypoint.nix writes the layer)
  # ---------------------------------------------------------------------------
  resolveServiceExit = e: e {
    Restart         = "restart";
    Ignore          = "ignore";
    Shutdown        = "shutdown";
    SuccessShutdown = "success-shutdown";
    FailureShutdown = "failure-shutdown";
  };

  resolveService = s: {
    inherit (s) name summary command after killDelay;
    startup   = if s.enabled then "enabled" else "disabled";
    onSuccess = resolveServiceExit s.onSuccess;
    onFailure = resolveServiceExit s.onFailure;
    logs      = s.logs { Enabled = "enabled"; Disabled = "disabled"; Passthrough = "passthrough"; };
  };

  resolvedServices = map resolveService (cfg.services or []);

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
        CI = false; InteractiveDev = false; RustToolchain = false;
        PythonToolchain = false; NodeToolchain = false; Infrastructure = false;
        Custom = _: false;
      };

    in
    if builtins.any hasBase cfg.packageLayers
    then true
    else throw "from-dhall: ContainerConfig '${cfg.name}': packageLayers must include Micro or Core";

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

  # Services: names unique, and every `after` one of them or one of the mode's own (vigild refuses the layer otherwise,
  # at start).
  modeServiceNames = [ "nix-daemon" "dropbear" "agent-supervisor" "socket-permissions" ];
  serviceNames = map (s: s.name) resolvedServices;
  servicesAssertion =
    let
      dup = lib.findFirst (n: lib.count (m: m == n) serviceNames > 1) null serviceNames;
      unknownAfter = lib.concatMap
        (s: map (a: "${s.name} → ${a}")
          (builtins.filter (a: !(builtins.elem a (serviceNames ++ modeServiceNames))) s.after))
        resolvedServices;
    in
      if mode == "minimal" && resolvedServices != []
      then throw "from-dhall: ContainerConfig '${cfg.name}': mode = Minimal has no vigild to run services"
      else if dup != null
      then throw "from-dhall: ContainerConfig '${cfg.name}': two services are named '${dup}'"
      else if unknownAfter != []
      then throw "from-dhall: ContainerConfig '${cfg.name}': a service is ordered after one that does not exist: ${lib.concatStringsSep ", " unknownAfter}"
      else true;

  # A container that runs as a non-root user (staticUid) cannot create one at start.
  sessionAssertion =
    if resolvedStartup.session.kind != "none" && resolvedStaticUid != null && resolvedStaticUid != 0
    then throw "from-dhall: ContainerConfig '${cfg.name}': a session user is created at start, as root; with staticUid the container does not start as root. Use session = Session.None."
    else true;

  hasToolchain = builtins.any (layer: layer {
    Micro          = false;
    Core           = false;
    CI             = false;
    InteractiveDev = false;
    RustToolchain  = true;
    PythonToolchain = true;
    NodeToolchain  = true;
    Infrastructure = false;
    Custom         = _: false;
  }) cfg.packageLayers;
in
  assert tlsAssertion;
  assert baseLayerAssertion;
  assert minimalAssertion;
  assert interactiveInMinimalAssertion;
  assert servicesAssertion;
  assert sessionAssertion;

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
    startup      = resolvedStartup;
    services     = resolvedServices;
    hasToolchain = hasToolchain;
  }
