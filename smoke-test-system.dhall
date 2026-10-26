-- smoke-test-system.dhall
--
-- A System-mode container: vigild is PID 1 and runs the services below, after
-- the boot steps, with no session. Render with `just render-smoke-test-system`,
-- build with `nix build .#smokeTestSystem`, and run it with its own writable
-- cgroup namespace (DelegateCgroups needs it):
--
--   podman run --rm --privileged --cgroupns=private polar-container-lib-smoke-test-system:latest
--
-- What to see: /run/booted (the boot script ran), /init.scope holding every
-- process, `vigil services list` with marker inactive (a one-shot that
-- succeeded) and ticker active, and a stop that takes well under a second.

let Lib = ./dhall/prelude.dhall

in  Lib.defaults.systemContainer
    //  { name = "polar-container-lib-smoke-test-system"
        , startup = Some
            { session = Lib.Session.None
            , boot =
              [ Lib.BootStep.DelegateCgroups
              , Lib.BootStep.Script
                  { name = "booted", command = "/bin/touch /run/booted", required = True }
              ]
            , launch = Lib.Launch.System
            }
        , services =
          [ Lib.defaults.defaultService
            //  { name = "marker"
                , summary = "a one-shot: leaves /run/marker"
                , command = "/bin/touch /run/marker"
                , onSuccess = Lib.ServiceExit.Ignore
                , logs = Lib.ServiceLogs.Disabled
                }
          , Lib.defaults.defaultService
            //  { name = "ticker"
                , summary = "a daemon, started once marker runs"
                , command = "/bin/sleep 100000"
                , after = [ "marker" ]
                , killDelay = Some "2s"
                }
          ]
        }
