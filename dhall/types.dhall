-- polar-container-lib/dhall/types.dhall
--
-- Canonical type definitions for the polar container library.
-- All types are defined here and re-exported via prelude.dhall.
-- Consumers should import prelude.dhall, not this file directly.

-- ---------------------------------------------------------------------------
-- Mode
-- ---------------------------------------------------------------------------
-- System: a container that runs a set of services under vigild (PID 1), with no
-- session: an infrastructure node, a daemon set. See Startup and Service below.
let Mode = < Dev | InfraAgent | AIAgent | System | Minimal >

let FailureMode = < FailFast | Collect >

let EnvVarPlacement = < BuildTime | StartTime | UserProvided >

let EnvVar = { name : Text, value : Text, placement : EnvVarPlacement }

let PackageRef = { attrPath : Text, flakeInput : Optional Text }

let PackageLayer =
      < Micro
      | Core
      | CI
      | InteractiveDev
      | RustToolchain
      | PythonToolchain
      | NodeToolchain
      | Infrastructure
      | Custom : { name : Text, packages : List PackageRef }
      >

let StageInput =
      < Workspace
      | Lockfile
      | Toolchain
      | Artifact : Text
      | StageOutput : { stage : Text, artifact : Text }
      | Environment : { name : Text, description : Text }
      >

let StageOutput =
      < Artifact : { name : Text, content_type : Optional Text }
      | Assertion : { name : Text, description : Optional Text }
      | Report : { name : Optional Text }
      | None
      >

let Stage =
      { name : Text
      , command : Text
      , failureMode : FailureMode
      , inputs : List StageInput
      , outputs : List StageOutput
      , condition : Optional Text
      , pure : Bool
      , impurityReason : Optional Text
      }

let PipelineOutputArtifact =
      { name : Text
      , fromStage : Text
      , artifact : Text
      , attestation : Optional Text
      , verifyMethod : Optional Text
      }

let PipelineOutputAssertion = { name : Text, fromStage : Text }

let PipelineOutputs =
      { artifacts : List PipelineOutputArtifact
      , assertions : List PipelineOutputAssertion
      }

let PipelineConfig =
      { name : Text
      , stages : List Stage
      , artifactDir : Text
      , workingDir : Text
      , outputs : Optional PipelineOutputs
      }

-- ---------------------------------------------------------------------------
-- Shell
--
-- Two variants:
--   Minimal     — just the shell binary + a minimal config. No plugins,
--                 no themes, no tool integrations. Suitable for minimal
--                 containers where a shell is needed for scripting but
--                 interactive ergonomics are not the goal.
--                 Supported shells: "/bin/sh" (dash), "/bin/nu" (nushell)
--
--   Interactive — full interactive experience: plugins, color themes,
--                 atuin history, starship prompt, direnv integration.
--                 Only valid in Dev mode containers.
--                 Supported shells: "/bin/fish", "/bin/nu"
-- ---------------------------------------------------------------------------
let MinimalShellConfig =
      { shell : Text
      -- ^ Path to the shell binary. Currently supported:
      --   "/bin/sh"  → dash (POSIX, tiny)
      --   "/bin/nu"  → nushell (minimal config, vi mode)
      }

let InteractiveShellConfig =
      { shell : Text
      -- ^ Path to the shell binary. Currently supported:
      --   "/bin/fish" → fish with bobthefish, atuin, starship, direnv
      --   "/bin/nu"   → nushell with plugins, atuin, starship, direnv
      , colorScheme : Text
      , viBindings : Bool
      , plugins : List Text
      }

let Shell =
      < Minimal     : MinimalShellConfig
      | Interactive : InteractiveShellConfig
      >

let SSHConfig = { enable : Bool, port : Natural }

let TLSConfig =
      { enable : Bool, generateCerts : Bool, certsPath : Optional Text }

let SandboxPolicy = < Enabled | Disabled | Auto >

let BuildUserCount = < Dynamic | Fixed : Natural >

let NixConfig =
      { enableDaemon : Bool
      , sandboxPolicy : SandboxPolicy
      , trustedUsers : List Text
      , buildUserCount : BuildUserCount
      }

let UserConfig =
      { createUser : Bool
      , defaultShell : Text
      , skeletonPath : Text
      , supplementalGroups : List { name : Text, gid : Natural }
      }

let AiConfig = { enable : Bool, modelsPath : Text, llamaPort : Natural }

-- ---------------------------------------------------------------------------
-- Startup
--
-- How a non-minimal container starts, in three parts, each independent of
-- the others:
--
--   session — who a shell or a login runs as
--   boot    — what is done once, at each start, before anything else runs
--   launch  — what PID 1 is
--
-- ContainerConfig.startup = None takes each mode's own (from-dhall.nix), which
-- is how these containers started before Startup existed:
--   Dev, InfraAgent, AIAgent
--           → session FromEnv Root with user.createUser, else None;
--             no boot steps; launch Interactive { allowHeadless = True }
--   System  → session None, no boot steps, launch System
-- ---------------------------------------------------------------------------

-- What FromEnv does when CREATE_USER, CREATE_UID and CREATE_GID are not all
-- set: run as root (home /root), or refuse to start.
let SessionFallback = < Root | Refuse >

let SessionUser = { name : Text, uid : Natural, gid : Natural }

let Session =
      < None
      -- ^ No user is created; a shell or a login is root, home /root.
      | FromEnv : SessionFallback
      -- ^ The user from CREATE_USER / CREATE_UID / CREATE_GID, created at
      --   start (podman --userns=keep-id passes the host user's).
      | Fixed : SessionUser
      -- ^ This user, created at start.
      >

let BootStep =
      < DelegateCgroups
      -- ^ Moves every process into /init.scope and enables every cgroup v2
      --   controller for the root's children, so that a runtime in the
      --   container (containerd, runc) can create cgroups under it. Needs the
      --   container's own cgroup namespace, writable (--cgroupns=private,
      --   --privileged). Fails the start when it cannot.
      | Sysctls : Text
      -- ^ A sysctl.conf in the image, applied with sysctl -p. A setting the
      --   kernel refuses is a warning.
      | NftRuleset : Text
      -- ^ An nftables ruleset in the image, loaded with nft -f. A failure is
      --   a warning.
      | Script : { name : Text, command : Text, required : Bool }
      -- ^ A command (an executable and its arguments, no shell), run once.
      --   A failure fails the start when required, else is a warning.
      >

let Launch =
      < Interactive : { allowHeadless : Bool }
      -- ^ vigild in the background, the session's shell in front (PID 1).
      --   With allowHeadless, CONTAINER_HEADLESS=1 at run time gives Headless.
      | Headless
      -- ^ vigild is PID 1; the shell is reached by a login over SSH.
      | System
      -- ^ vigild is PID 1 and runs the container's services; nothing is set
      --   up for a shell or a login.
      >

let Startup = { session : Session, boot : List BootStep, launch : Launch }

-- ---------------------------------------------------------------------------
-- Service
--
-- A service vigild runs, beside the mode's own (nix-daemon, dropbear, the
-- agent supervisor). Written into vigild's layer at start.
-- ---------------------------------------------------------------------------
let ServiceExit =
      < Restart | Ignore | Shutdown | SuccessShutdown | FailureShutdown >

let ServiceLogs =
      < Enabled
      -- ^ Kept in vigild's log buffer and printed to its stdout.
      | Disabled
      -- ^ Kept in vigild's log buffer only (vigil logs).
      | Passthrough
      -- ^ Written straight to the container's stdout/stderr.
      >

let Service =
      { name : Text
      , summary : Text
      , command : Text
      -- ^ An executable and its arguments, split on whitespace (no shell).
      , enabled : Bool
      -- ^ Started when vigild starts.
      , after : List Text
      -- ^ Started once these services are running (not once they are done).
      , onSuccess : ServiceExit
      , onFailure : ServiceExit
      , killDelay : Optional Text
      -- ^ How long a stop waits before SIGKILL, e.g. "10s" (vigild: 5s).
      , logs : ServiceLogs
      }

let ContainerConfig =
      { name : Text
      , mode : Mode
      , packageLayers : List PackageLayer
      -- ^ shell = None          → no shell in the image (entrypoint required)
      --   shell = Some (Shell.Minimal ...)     → shell binary + minimal config
      --   shell = Some (Shell.Interactive ...) → full interactive experience
      , shell : Optional Shell
      , pipeline : Optional PipelineConfig
      , ssh : Optional SSHConfig
      , tls : Optional TLSConfig
      , nix : NixConfig
      , user : UserConfig
      , extraEnv : List EnvVar
      , ai : Optional AiConfig
      , entrypoint : Optional Text
      , staticUid : Optional Natural
      , staticGid : Optional Natural
      , startup : Optional Startup
      -- ^ None: the mode's own (see Startup above).
      , services : List Service
      }

in  { Mode
    , FailureMode
    , EnvVarPlacement
    , EnvVar
    , PackageRef
    , PackageLayer
    , StageInput
    , StageOutput
    , Stage
    , PipelineOutputArtifact
    , PipelineOutputAssertion
    , PipelineOutputs
    , PipelineConfig
    , MinimalShellConfig
    , InteractiveShellConfig
    , Shell
    , SSHConfig
    , TLSConfig
    , SandboxPolicy
    , BuildUserCount
    , NixConfig
    , UserConfig
    , ContainerConfig
    , AiConfig
    , SessionFallback
    , SessionUser
    , Session
    , BootStep
    , Launch
    , Startup
    , ServiceExit
    , ServiceLogs
    , Service
    }
