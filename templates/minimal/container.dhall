-- templates/minimal/container.dhall
--
-- Minimal container configuration template.
--
-- Minimal containers exec a single binary or shell directly.
-- No start.sh, no user creation, no Nix daemon.
-- The OCI Cmd is one of:
--   - ["/bin/<entrypoint>"]  when entrypoint is set and shell is None
--   - ["/bin/nu"]            when shell = Shell.Minimal { shell = "/bin/nu" }
--   - ["/bin/sh"]            when shell = Shell.Minimal { shell = "/bin/sh" }
--
-- Base layer is Micro — the absolute minimum for OCI compliance:
--   cacert, coreutils (minimal subset), getent, openssl
--
-- Use cases:
--   - Kubernetes init containers
--   - Sidecar utilities
--   - Build step containers
--   - Any container where size and attack surface matter
--
-- Security:
--   - UID 65532 is the conventional non-root UID for init containers
--   - Keep packageLayers short — every package is attack surface
--   - Inject runtime secrets via env vars, never bake them in

let Lib = https://raw.githubusercontent.com/daveman1010221/nix-container-lib/def722f6e36b649f8f6fb3f8b875e1f4d7140d5b/dhall/prelude.dhall
        sha256:f75818ad203cb90a5e5921b75cd60bcb66ac5753cf7eba976538bf71e855378c
let defaults = Lib.defaults

in defaults.minimalContainer //
  { name = "my-init-container"

  -- ── Entrypoint (option A: binary) ──────────────────────────────────────────
  -- Set entrypoint and leave shell = None.
  -- OCI Cmd becomes ["/bin/my-entrypoint-binary"].
  , entrypoint = None Text

  -- The implied default is:
  -- , shell = None Lib.Shell
  , shell      = Some Lib.defaults.minimalNuShell

  -- ── Shell (option B: minimal shell as entrypoint) ──────────────────────────
  -- Comment out entrypoint above and uncomment one of these.
  -- OCI Cmd becomes ["/bin/nu"] or ["/bin/sh"].
  --
  -- Minimal nushell — vi mode, show_banner false, basic completions.
  -- No plugins, no themes, no atuin, no starship.
  -- , shell = Some Lib.defaults.minimalNuShell
  --
  -- Minimal POSIX sh (dash) — tiny, strict, no config.
  -- , shell = Some Lib.defaults.minimalDashShell
  --
  -- Or construct directly:
  -- , shell = Some (Lib.minimalShell "/bin/nu")
  -- , shell = Some (Lib.minimalShell "/bin/sh")

  -- Run as a non-root user. UID 65532 is conventional for init containers.
  , staticUid = Some 65532
  , staticGid = Some 65532

  -- ── Package layers ─────────────────────────────────────────────────────────
  -- Start with Micro (not Core) for truly minimal containers.
  -- Micro = cacert + minimal uutils + getent + openssl. Nothing else.
  -- Add only what your binary actually needs at runtime.
  , packageLayers =
    [ Lib.PackageLayer.Micro
    -- Add only what your binary actually needs at runtime:
    -- , Lib.customLayer "my-entrypoint"
    --     [ Lib.flakePackage "myInput" "packages.default"
    --     -- , Lib.nixpkgs "git"
    --     -- , Lib.nixpkgs "curl"
    --     ]
    ]

  -- Build-time env vars (no store paths — safe for OCI config.Env)
  , extraEnv =
      [ Lib.buildEnv "GIT_TERMINAL_PROMPT" "0"
      -- , Lib.buildEnv "MY_SETTING" "value"
      ]
  }
