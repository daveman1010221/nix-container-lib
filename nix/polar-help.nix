# polar-container-lib/nix/polar-help.nix
#
# Generates the polar-help script — a container usage reference that is
# always available at /bin/polar-help regardless of what the container
# is used for.
#
# The script is mode-aware: it shows different information depending on
# whether the container is a dev, CI, agent, or pipeline container.
# This means a developer running polar-help in a dev container sees
# developer-relevant information, while a CI operator sees CI-relevant
# information.
#
# The script is a pkgs.writeShellScriptBin derivation so it lands in
# /bin/polar-help via the devEnv buildEnv symlink tree — a stable,
# arch-correct path that can be referenced from container documentation
# without knowing any store paths.

{ pkgs
, cfg     # Translated config from from-dhall.nix
}:

let
  # Mode-specific sections appended to the common help text
  modeHelp =
    if cfg.mode == "dev" then ''
      DEVELOPMENT CONTAINER
      ─────────────────────
      This is an interactive development container with a full toolchain.

      Getting started:
        • Your source code should be mounted at /workspace
        • The Nix daemon is running — use 'nix shell', 'nix build', etc.
        • Fish shell is configured with vi key bindings (press Escape to enter normal mode)
        • Type 'direnv allow' in /workspace to activate the project's .envrc

      Shell tools:
        • lh          — eza with icons and human-readable sizes
        • ocd <dir>   — cd + list contents
        • nvimf       — open file from fzf picker in nvim
        • nviml       — open file+line from rg+fzf picker in nvim
        • rgk <term>  — ripgrep with fzf preview
        • lol <text>  — cowsay + dotacat (important)

      SSH access (if enabled):
        • ssh-start   — start the Dropbear SSH server
        • ssh-stop    — stop the Dropbear SSH server
        • Default port: 2223

      Nix:
        • The nixpkgs registry is pinned to the build-time revision
        • 'nix shell nixpkgs#<pkg>' works offline — no network needed
        • 'nix-collect-garbage' is safe — GC roots protect container tools
    ''
    else if cfg.mode == "ci" || cfg.mode == "pipeline" then ''
      CI / PIPELINE CONTAINER
      ───────────────────────
      This is a headless container for running automated pipelines.

      Running the pipeline:
        • /bin/pipeline-runner [stage]   — run all stages, or a specific stage
        • CI_FULL=1 /bin/pipeline-runner — include stages gated on CI_FULL
        • Pipeline artifacts: ${if cfg.pipeline != null then cfg.pipeline.artifactDir else "/workspace/out"}

      Pipeline stages are defined in the container's Dhall configuration.
      Stage failure modes: FailFast (abort immediately) or Collect (run all, fail at end).
    ''
    else if cfg.mode == "agent" then ''
      AGENT CONTAINER
      ───────────────
      This is an autonomous agent container.

      The agent supervisor process is PID 1 (or running as the main process).
      mTLS is ${if cfg.tls != null && cfg.tls.enable then "enabled" else "disabled"}.

      To inspect the running agent:
        • Check logs via your container runtime (docker logs / podman logs)
        • Attach with: docker exec -it <container> /bin/sh
    ''
    else
      "# Unknown mode: ${cfg.mode}\n";

  helpText = ''
    #!/usr/bin/env bash
    cat << 'HELP'
    ────────────────────────────────────────────────────────────────────────────
     polar-container-lib — Container: ${cfg.name}  Mode: ${cfg.mode}
    ────────────────────────────────────────────────────────────────────────────

    ${modeHelp}
    COMMON COMMANDS
    ───────────────
    polar-help              — show this message
    nix-collect-garbage     — safe inside this container (GC roots protect tools)

    ENVIRONMENT
    ───────────
    Container name:  ${cfg.name}
    Mode:            ${cfg.mode}
    Shell:           ${if cfg.shell != null then cfg.shell.shell else "none (headless)"}
    Pipeline:        ${if cfg.pipeline != null then cfg.pipeline.name else "none"}
    TLS:             ${if cfg.tls != null && cfg.tls.enable then "enabled" else "disabled"}
    SSH:             ${if cfg.ssh != null && cfg.ssh.enable then "enabled (port ${toString cfg.ssh.port})" else "disabled"}

    Built with polar-container-lib — https://github.com/daveman1010221/nix-container-lib
    ────────────────────────────────────────────────────────────────────────────
    HELP
  '';

in
  pkgs.writeShellScriptBin "polar-help" helpText

