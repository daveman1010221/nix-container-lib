-- smoke-test.dhall
-- Self-contained: no relative imports so dhallToNix can copy this file
-- in isolation without needing the rest of the source tree.
-- The ciContainer default is inlined rather than imported.

{ name          = "polar-container-lib-smoke-test"
, mode          = < Dev | CI | Agent | Pipeline >.CI
, packageLayers = [ < Core | CI | Dev | Toolchain | Pipeline | Agent | Custom : { name : Text, packages : List { attrPath : Text, flakeInput : Optional Text } } >.Core
                  , < Core | CI | Dev | Toolchain | Pipeline | Agent | Custom : { name : Text, packages : List { attrPath : Text, flakeInput : Optional Text } } >.CI
                  ]
, shell         = None { shell : Text, colorScheme : Text, viBindings : Bool, plugins : List Text }
, pipeline      = None { name : Text, artifactDir : Text, stages : List { name : Text, command : Text, failureMode : < FailFast | Collect >, inputs : List < Workspace | Artifact : Text | Environment >, outputs : List < Artifact : Text | Report | None >, condition : Optional Text } }
, ssh           = None { enable : Bool, port : Natural }
, tls           = None { enable : Bool, generateCerts : Bool, certsPath : Optional Text }
, nix           = { enableDaemon = True, sandboxPolicy = < Enabled | Disabled | Auto >.Auto, trustedUsers = [ "root" ], buildUserCount = < Dynamic | Fixed : Natural >.Dynamic }
, user          = { createUser = False, defaultShell = "/bin/fish", skeletonPath = "/etc/container-skel" }
, extraEnv      = [] : List { name : Text, value : Text, placement : < BuildTime | StartTime | UserProvided > }
}
