-- polar-container-lib/dhall/lib/types.dhall
--
-- Canonical type definitions for the polar container library.
-- All types are defined here and re-exported via prelude.dhall.
-- Consumers should import prelude.dhall, not this file directly.

-- ---------------------------------------------------------------------------
-- Mode
-- The primary dispatch axis for the container. Determines which entrypoint
-- phases run, what the container hands off to at startup, and informs which
-- default package layers are sensible.
--
--   Dev      → interactive shell, nix-daemon, full user setup
--   CI       → headless, pipeline runner, minimal init, exit with code
--   Agent    → supervised process, mTLS required, no interactive shell
--   Pipeline → explicit pipeline runner mode, dev-adjacent but non-interactive
-- ---------------------------------------------------------------------------
let Mode = < Dev | CI | Agent | Pipeline >

-- ---------------------------------------------------------------------------
-- FailureMode
-- Controls how a pipeline stage handles a non-zero exit.
--
--   FailFast  → abort the pipeline immediately on failure
--   Collect   → record the failure, continue remaining stages, fail at end
-- ---------------------------------------------------------------------------
let FailureMode = < FailFast | Collect >

-- ---------------------------------------------------------------------------
-- EnvVarPlacement
-- Encodes WHERE an environment variable should be materialized.
-- This enforces the critical boundary between config.Env (build-time,
-- no store paths) and start.sh exports (start-time, store-path-bearing).
--
--   BuildTime     → safe for config.Env: no store paths, arch-independent
--   StartTime     → must go in start.sh: store paths or arch-sensitive values
--   UserProvided  → project-specific, injected at container run time
-- ---------------------------------------------------------------------------
let EnvVarPlacement = < BuildTime | StartTime | UserProvided >

let EnvVar =
  { name      : Text
  , value     : Text
  , placement : EnvVarPlacement
  }

-- ---------------------------------------------------------------------------
-- PackageRef
-- A reference to a package in nixpkgs or a flake input.
--
--   attrPath    → dot-separated attribute path, e.g. "llvmPackages_19.clang"
--   flakeInput  → None means nixpkgs; Some "myOverlay" means that flake input
-- ---------------------------------------------------------------------------
let PackageRef =
  { attrPath   : Text
  , flakeInput : Optional Text
  }

-- ---------------------------------------------------------------------------
-- PackageLayer
-- Named, composable package set categories. The library provides a concrete
-- package list for each named layer. Custom lets a project author define
-- additional packages without needing to fork the library.
--
-- Layer composition model:
--   Core      → minimum viable Linux container (coreutils, bash, ssl, nix)
--   CI        → Core + audit/scan tools (grype, syft, vulnix, skopeo)
--   Dev       → CI + interactive tools (editors, shell, git, fzf, bat, eza)
--   Toolchain → compiler stack (LLVM, Rust nightly, cmake, pkg-config)
--   Pipeline  → pipeline runner + stage-specific tools (static analysis)
--   Agent     → agent runtime tooling (to be defined as the pattern matures)
--   Custom    → project-specific additions, named for traceability
-- ---------------------------------------------------------------------------
let PackageLayer
  = < Core
    | CI
    | Dev
    | Toolchain
    | Pipeline
    | Agent
    | Custom : { name : Text, packages : List PackageRef }
    >

-- ---------------------------------------------------------------------------
-- Stage I/O
-- Explicit input and output declarations for pipeline stages.
-- These drive pipeline validation (is Artifact "sbom" actually produced
-- before it is consumed?) and future parallelism decisions.
-- ---------------------------------------------------------------------------
let StageInput
  = < Workspace        -- the /workspace bind mount
    | Artifact : Text  -- named artifact produced by a prior stage
    | Environment      -- the container's environment variables
    >

let StageOutput
  = < Artifact : Text  -- named artifact available to downstream stages
    | Report           -- findings/results written to artifactDir
    | None             -- side-effect only (e.g. format in place)
    >

-- ---------------------------------------------------------------------------
-- Stage
-- A single unit of pipeline work.
--
--   name        → human-readable identifier, used in logging and artifact refs
--   command     → the shell command to execute (runs in /workspace)
--   failureMode → FailFast or Collect
--   inputs      → declared inputs (for validation and documentation)
--   outputs     → declared outputs (for chaining and artifact tracking)
--   condition   → optional env var name; stage is skipped if var is unset.
--                 Enables "developer runs fast stages, CI runs everything"
--                 without maintaining two pipeline definitions.
-- ---------------------------------------------------------------------------
let Stage =
  { name        : Text
  , command     : Text
  , failureMode : FailureMode
  , inputs      : List StageInput
  , outputs     : List StageOutput
  , condition   : Optional Text
  }

-- ---------------------------------------------------------------------------
-- PipelineConfig
-- A named, ordered sequence of stages with a shared artifact output directory.
-- Owned by ContainerConfig for now — the container is the pipeline runtime.
-- ---------------------------------------------------------------------------
let PipelineConfig =
  { name        : Text
  , stages      : List Stage
  , artifactDir : Text
  , workingDir  : Text
  -- workingDir: the directory stages run in. Defaults to /workspace.
  -- Set to a subdirectory for projects where Cargo.toml is not at the
  -- workspace root (e.g. "src/agents" for a mono-repo layout).
  }

-- ---------------------------------------------------------------------------
-- ShellConfig
-- Interactive shell configuration. Omitting this (None ShellConfig) produces
-- a container with no interactive shell setup — appropriate for CI and agents.
-- ---------------------------------------------------------------------------
let ShellConfig =
  { shell       : Text        -- absolute path, e.g. "/bin/fish"
  , colorScheme : Text        -- theme name understood by the shell/prompt
  , viBindings  : Bool
  , plugins     : List Text   -- plugin names resolved by the library
  }

-- ---------------------------------------------------------------------------
-- SSHConfig
-- Dropbear SSH server configuration.
-- enable = False means the binary is still present but the server does not
-- start at container init. This lets developers start it manually via
-- ssh-start without needing a different image.
-- ---------------------------------------------------------------------------
let SSHConfig =
  { enable : Bool
  , port   : Natural
  }

-- ---------------------------------------------------------------------------
-- TLSConfig
-- mTLS certificate configuration.
--
--   generateCerts → invoke gen-certs.nix at build time (tls-gen / RabbitMQ)
--   certsPath     → override: use certs from this path instead of generating
--
-- generateCerts = True and certsPath = Some path is an error; the library
-- will assert against this combination.
-- ---------------------------------------------------------------------------
let TLSConfig =
  { enable        : Bool
  , generateCerts : Bool
  , certsPath     : Optional Text
  }

-- ---------------------------------------------------------------------------
-- NixConfig
-- Controls how the Nix daemon and build infrastructure are configured inside
-- the container. These settings are materialized into /etc/nix/nix.conf
-- at start.sh time (not at image build time) so they can be arch-correct.
--
--   sandboxPolicy   Auto  → detect qemu-user at runtime, disable if found
--                   Enabled → always sandbox (native hardware only)
--                   Disabled → never sandbox (trusted environments)
--
--   buildUserCount  Dynamic → provision nixbld1..N based on nproc at startup
--                   Fixed N → provision exactly N build users (baked in)
-- ---------------------------------------------------------------------------
let SandboxPolicy = < Enabled | Disabled | Auto >

let BuildUserCount = < Dynamic | Fixed : Natural >

let NixConfig =
  { enableDaemon   : Bool
  , sandboxPolicy  : SandboxPolicy
  , trustedUsers   : List Text
  , buildUserCount : BuildUserCount
  }

-- ---------------------------------------------------------------------------
-- UserConfig
-- Controls the runtime user provisioning phase in start.sh.
-- When createUser = True, the entrypoint reads CREATE_USER / CREATE_UID /
-- CREATE_GID from the environment and provisions a matching user.
-- When False, the container runs as root.
--
-- supplementalGroups: additional groups to add the user to at container
-- startup. Used for GPU access (video, render), audio, etc. Each entry
-- is a { name : Text, gid : Natural } pair. The group is created if it
-- does not already exist in /etc/group.
-- ---------------------------------------------------------------------------
let UserConfig =
  { createUser         : Bool
  , defaultShell       : Text
  , skeletonPath       : Text   -- path to skeleton config, e.g. /etc/container-skel
  , supplementalGroups : List { name : Text, gid : Natural }
  }

-- ---------------------------------------------------------------------------
-- AiConfig
-- Local LLM tooling configuration.
-- When enabled, the entrypoint symlinks modelsPath into the user's
-- ~/.cache/llama.cpp and writes the pi agent models.json config.
--
--   enable      → whether to perform AI tooling setup at container start
--   modelsPath  → container path where the models volume is mounted
--   llamaPort   → port llama-server listens on
-- ---------------------------------------------------------------------------
let AiConfig =
  { enable      : Bool
  , modelsPath  : Text
  , llamaPort   : Natural
  }

-- ---------------------------------------------------------------------------
-- ContainerConfig
-- The top-level type. This is what a project author writes.
--
-- Design notes:
--   - packageLayers is ordered; layers are merged left to right.
--     Core should always be first. The library asserts this.
--   - extraEnv entries are routed to config.Env or start.sh based on
--     their EnvVarPlacement. The library handles the split automatically.
--   - The //-style Dhall record override pattern works cleanly against
--     the defaults in defaults.dhall:
--       defaults.devContainer // { name = "my-project", ... }
-- ---------------------------------------------------------------------------
let ContainerConfig =
  { name          : Text
  , mode          : Mode
  , packageLayers : List PackageLayer
  , shell         : Optional ShellConfig
  , pipeline      : Optional PipelineConfig
  , ssh           : Optional SSHConfig
  , tls           : Optional TLSConfig
  , nix           : NixConfig
  , user          : UserConfig
  , extraEnv      : List EnvVar
  , ai            : Optional AiConfig
  }

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
in
  { Mode            = Mode
  , FailureMode     = FailureMode
  , EnvVarPlacement = EnvVarPlacement
  , EnvVar          = EnvVar
  , PackageRef      = PackageRef
  , PackageLayer    = PackageLayer
  , StageInput      = StageInput
  , StageOutput     = StageOutput
  , Stage           = Stage
  , PipelineConfig  = PipelineConfig
  , ShellConfig     = ShellConfig
  , SSHConfig       = SSHConfig
  , TLSConfig       = TLSConfig
  , SandboxPolicy   = SandboxPolicy
  , BuildUserCount  = BuildUserCount
  , NixConfig       = NixConfig
  , UserConfig      = UserConfig
  , ContainerConfig = ContainerConfig
  , AiConfig        = AiConfig
  }
