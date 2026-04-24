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
--
-- SHELL MIGRATION (if upgrading from an earlier version):
--
--   OLD:  shell = Some { shell = "/bin/fish", colorScheme = "gruvbox", ... }
--   NEW:  shell = Some (Lib.Shell.Interactive { shell = "/bin/fish", colorScheme = "gruvbox", ... })
--
--   OLD:  shell = None T.ShellConfig
--   NEW:  shell = None Lib.Shell
--
--   Convenience constructors are provided:
--     Lib.defaults.minimalDashShell       → Shell.Minimal { shell = "/bin/sh" }
--     Lib.defaults.minimalNuShell         → Shell.Minimal { shell = "/bin/nu" }
--     Lib.defaults.defaultInteractiveFishShell → Shell.Interactive { ... }
--     Lib.defaults.defaultInteractiveNuShell   → Shell.Interactive { ... }

let T        = ./types.dhall
let defaults = ./defaults.dhall

in
  -- ---------------------------------------------------------------------------
  -- Types (re-exported flat for ergonomic access)
  -- ---------------------------------------------------------------------------
  { ContainerConfig        = T.ContainerConfig
  , Mode                   = T.Mode
  , FailureMode            = T.FailureMode
  , EnvVarPlacement        = T.EnvVarPlacement
  , EnvVar                 = T.EnvVar
  , PackageRef             = T.PackageRef
  , PackageLayer           = T.PackageLayer

  -- Shell types
  , Shell                  = T.Shell
  , MinimalShellConfig     = T.MinimalShellConfig
  , InteractiveShellConfig = T.InteractiveShellConfig

  , TaskInput      = T.TaskInput
  , TaskOutput     = T.TaskOutput
  , Task           = T.Task
  , PipelineConfig  = T.PipelineConfig
  , SSHConfig       = T.SSHConfig
  , TLSConfig       = T.TLSConfig
  , SandboxPolicy   = T.SandboxPolicy
  , BuildUserCount  = T.BuildUserCount
  , NixConfig       = T.NixConfig
  , UserConfig      = T.UserConfig
  , AiConfig        = T.AiConfig

  -- ---------------------------------------------------------------------------
  -- Defaults (the opinionated starting points)
  -- ---------------------------------------------------------------------------
  , defaults = defaults

  -- ---------------------------------------------------------------------------
  -- Convenience constructors
  -- ---------------------------------------------------------------------------

  -- Package references
  , nixpkgs = \(attrPath : Text) ->
      { attrPath = attrPath, flakeInput = None Text } : T.PackageRef

  , flakePackage = \(input : Text) -> \(attrPath : Text) ->
      { attrPath = attrPath, flakeInput = Some input } : T.PackageRef

  , customLayer = \(name : Text) -> \(packages : List T.PackageRef) ->
      T.PackageLayer.Custom { name = name, packages = packages }

  -- ---------------------------------------------------------------------------
  -- Shell constructors
  --
  -- Lib.minimalShell "/bin/sh"   → Shell.Minimal { shell = "/bin/sh" }
  -- Lib.minimalShell "/bin/nu"   → Shell.Minimal { shell = "/bin/nu" }
  --
  -- Lib.interactiveShell "/bin/fish" "gruvbox" True ["bobthefish","bass","grc"]
  --   → Shell.Interactive { shell = "/bin/fish", colorScheme = "gruvbox", ... }
  -- ---------------------------------------------------------------------------
  , minimalShell = \(shell : Text) ->
      T.Shell.Minimal { shell = shell }

  , interactiveShell =
      \(shell : Text)
      -> \(colorScheme : Text)
      -> \(viBindings : Bool)
      -> \(plugins : List Text)
      -> T.Shell.Interactive
           { shell       = shell
           , colorScheme = colorScheme
           , viBindings  = viBindings
           , plugins     = plugins
           }

  -- ---------------------------------------------------------------------------
  -- Task constructors (unchanged)
  -- ---------------------------------------------------------------------------
  , simpleTask =
      \(name : Text)
      -> \(command : Text)
      -> \(failureMode : T.FailureMode)
      ->  { name           = name
          , command        = command
          , failureMode    = failureMode
          , inputs         = [ T.TaskInput.Workspace ]
          , outputs        = [ T.TaskOutput.None ]
          , pure           = True
          , impurityReason = None Text
          , condition      = None Text
          } : T.Task

  , conditionalTask =
      \(name : Text)
      -> \(command : Text)
      -> \(failureMode : T.FailureMode)
      -> \(condition : Text)
      ->  { name           = name
          , command        = command
          , failureMode    = failureMode
          , inputs         = [ T.TaskInput.Workspace ]
          , outputs        = [ T.TaskOutput.None ]
          , pure           = False
          , impurityReason = Some "Cannot guarantee environment variable is set"
          , condition      = Some condition
          } : T.Task

  -- ---------------------------------------------------------------------------
  -- EnvVar constructors (unchanged)
  -- ---------------------------------------------------------------------------
  , buildEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.BuildTime }
        : T.EnvVar

  , startEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.StartTime }
        : T.EnvVar

  , runtimeEnv = \(name : Text) -> \(value : Text) ->
      { name = name, value = value, placement = T.EnvVarPlacement.UserProvided }
        : T.EnvVar
  }
