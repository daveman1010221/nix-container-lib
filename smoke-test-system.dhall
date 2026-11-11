-- smoke-test-system.dhall
--
-- A System-mode container: vigild is PID 1 and runs the services below, after
-- the boot steps, with no session. Render with `just render-smoke-test-system`,
-- build with `nix build .#smokeTestSystem`, and run it with its own writable
-- cgroup namespace (DelegateCgroups needs it):
--
--   podman run --rm --privileged --cgroupns=private --env PROBE_FROM_RUN=yes \
--     --env SECRET_FROM_RUN=no polar-container-lib-smoke-test-system:latest
--
-- What to see: /run/booted (the boot script ran), /init.scope holding every
-- process, `vigil services list` with marker done (a one-shot that
-- succeeded) and ticker active, `vigil logs env-probe` with PROBE_FROM_RUN and
-- PROBE_SET but not SECRET_FROM_RUN (with vigil-rs 4), and a stop that takes
-- well under a second.

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
          [ Lib.defaults.defaultOneshot
            //  { name = "marker"
                , summary = "a one-shot: leaves /run/marker"
                , command = "/bin/touch /run/marker"
                , runTimeout = Some "10s"
                , logs = Lib.ServiceLogs.Disabled
                }
          , Lib.defaults.defaultService
            //  { name = "ticker"
                , summary = "a daemon, started once marker is done"
                , command = "/bin/sleep 100000"
                , after = [ "marker" ]
                , killDelay = Some "2s"
                }
          , Lib.defaults.defaultOneshot
            //  { name = "env-probe"
                , summary = "prints the environment it gets"
                , command = "/bin/env"
                , environment = toMap { PROBE_SET = "yes" }
                , passEnvGlob = [ "PROBE_*" ]
                }
          ]
        }
