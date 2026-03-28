-- polar-container-lib/dhall/prelude.dhall
--
-- Single import point for library consumers.
-- Import this file and you have everything you need:
--
--   let Lib = https://raw.githubusercontent.com/.../prelude.dhall
--             sha256:...
--
--   or locally:
--
--   let Lib = ./prelude.dhall
--
--   in Lib.defaults.devContainer // { name = "my-project", ... }

let T        = ./types.dhall
let defaults = ./defaults.dhall

in
  -- ---------------------------------------------------------------------------
  -- Types (re-exported flat for ergonomic access)
  -- Lib.ContainerConfig, Lib.Mode.Dev, Lib.PackageLayer.Core, etc.
  -- ---------------------------------------------------------------------------
  { ContainerConfig = T.ContainerConfig
  , Mode            = T.Mode
  , FailureMode     = T.FailureMode
  , EnvVarPlacement = T.EnvVarPlacement
  , EnvVar          = T.EnvVar
  , PackageRef      = T.PackageRef
  , PackageLayer    = T.PackageLayer
  , StageInput      = T.StageInput
  , StageOutput     = T.StageOutput
  , Stage           = T.Stage
  , PipelineConfig  = T.PipelineConfig
  , ShellConfig     = T.ShellConfig
  , SSHConfig       = T.SSHConfig
  , TLSConfig       = T.TLSConfig
  , SandboxPolicy   = T.SandboxPolicy
  , BuildUserCount  = T.BuildUserCount
  , NixConfig       = T.NixConfig
  , UserConfig      = T.UserConfig
  , AiConfig        = T.AiConfig

  -- ---------------------------------------------------------------------------
  -- Defaults (the opinionated starting points)
  -- Lib.defaults.devContainer, Lib.defaults.defaultNix, etc.
  -- ---------------------------------------------------------------------------
  , defaults = defaults

  -- ---------------------------------------------------------------------------
  -- Convenience constructors
  -- Reduce boilerplate for the most common patterns.
  -- ---------------------------------------------------------------------------

  -- Build a PackageRef pointing at a nixpkgs attribute
  , nixpkgs = \(attrPath : Text) ->
      { attrPath = attrPath, flakeInput = None Text } : T.PackageRef

  -- Build a PackageRef pointing at a flake input's package
  , flakePackage = \(input : Text) -> \(attrPath : Text) ->
      { attrPath = attrPath, flakeInput = Some input } : T.PackageRef

  -- Build a Custom PackageLayer with a name and list of refs
  , customLayer = \(name : Text) -> \(packages : List T.PackageRef) ->
      T.PackageLayer.Custom { name = name, packages = packages }

  -- Build a simple, pure stage with no declared I/O and no condition
  --
  , simpleStage =
      \(name : Text)
      -> \(command : Text)
      -> \(failureMode : T.FailureMode)
      ->  { name        = name
          , command     = command
          , failureMode = failureMode
          , inputs      = [ T.StageInput.Workspace ]
          , outputs     = [ T.StageOutput.None ]
          , pure        = True
          , impurityReason = None Text
          , condition   = None Text
          } : T.Stage

  -- Build a Stage that only runs when a given env var is set
  , conditionalStage =
      \(name : Text)
      -> \(command : Text)
      -> \(failureMode : T.FailureMode)
      -> \(condition : Text)
      ->  { name        = name
          , command     = command
          , failureMode = failureMode
          , inputs      = [ T.StageInput.Workspace ]
          , outputs     = [ T.StageOutput.None ]
          , pure = False
          , impurityReason = Some "Cannot guarantee environment variable is set"
          , condition   = Some condition
          } : T.Stage

  -- Build a BuildTime EnvVar (safe for config.Env, no store paths)
  , buildEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.BuildTime }
        : T.EnvVar

  -- Build a StartTime EnvVar (store-path-bearing, goes in start.sh)
  , startEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.StartTime }
        : T.EnvVar

  -- Build a UserProvided EnvVar (injected at container run time)
  , runtimeEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.UserProvided }
        : T.EnvVar
  }
