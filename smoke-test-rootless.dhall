-- smoke-test-rootless.dhall
--
-- A Dev container with a rootless session (Session.Rootless): the user `dev` (1000:1000) made at build, the image's User,
-- headless, with dropbear. It starts with no root, no capabilities and a read-only root filesystem, as a Kubernetes pod held
-- to runAsNonRoot does. Render with `just render-smoke-test-rootless`, build with `nix build .#smokeTestRootless`, load it and
-- run it so:
--
--   docker run --rm -d --name rootless --read-only --cap-drop ALL --security-opt no-new-privileges \
--     --tmpfs /run --tmpfs /tmp -v rootless-work:/home/dev/work \
--     -e CONTAINER_HEADLESS=1 -e DROPBEAR_ENABLE=1 -e AUTHORIZED_KEYS_B64="$(base64 < ~/.ssh/id_ed25519.pub)" \
--     -p 2223:2223 polar-container-lib-smoke-test-rootless:latest
--   ssh -p 2223 dev@localhost id
--
-- What to see: the start runs as dev (no chown, nothing written outside /run, /tmp and ~/work), vigild is PID 1 as dev, and
-- a login over SSH as dev succeeds.

let Lib = ./dhall/prelude.dhall

in  Lib.defaults.devContainer
    //  { name = "polar-container-lib-smoke-test-rootless"
        , packageLayers =
          [ Lib.PackageLayer.Micro
          , Lib.PackageLayer.Core
          -- dropbear is not in a layer of its own; a container that runs it names it.
          , Lib.PackageLayer.Custom
              { name = "ssh", packages = [ { attrPath = "dropbear", flakeInput = None Text } ] }
          ]
        , nix = Lib.defaults.devContainer.nix // { enableDaemon = False }
        , user = Lib.defaults.devContainer.user // { createUser = False }
        , startup = Some
            { session = Lib.Session.Rootless { name = "dev", uid = 1000, gid = 1000 }
            , boot = [] : List Lib.BootStep
            , launch = Lib.Launch.Headless
            }
        }
