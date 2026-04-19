# polar-container-lib/nix/banner.nix
#
# Generates /etc/container-info — a build-time file containing information
# about the container's configuration, available tools, and key file locations.
#
# In minimal containers this file is displayed by the shell's config on
# first startup (or can be cat'd manually). In interactive containers it
# supplements the existing greeting.
#
# The file is plain text so it works regardless of shell: dash can cat it,
# nushell can open it, fish can cat it. No ANSI codes — those don't render
# well in all contexts and this is informational, not decorative.
#
# Contents:
#   - Container name, mode, shell type
#   - Available shell and its path
#   - Entrypoint (if set)
#   - SBOM location
#   - Key environment variables set at build time
#   - Brief "what's in this container" summary

{ pkgs
, cfg
, packageSets   # from packages.nix — for tool list generation
}:

let
  lib = pkgs.lib;

  shellLine =
    if cfg.shell == null then
      "shell:       none (entrypoint only)"
    else if cfg.shell.type == "minimal-dash" then
      "shell:       /bin/sh (dash, POSIX minimal)"
    else if cfg.shell.type == "minimal-nu" then
      "shell:       /bin/nu (nushell, minimal config)"
    else if cfg.shell.type == "interactive-fish" then
      "shell:       /bin/fish (interactive, full experience)"
    else if cfg.shell.type == "interactive-nu" then
      "shell:       /bin/nu (interactive, full experience)"
    else
      "shell:       ${cfg.shell.type}";

  entrypointLine =
    if cfg.entrypoint != null then
      "entrypoint:  /bin/${cfg.entrypoint}"
    else if cfg.shell != null then
      "entrypoint:  ${cfg.shell.shell} (shell is the entrypoint)"
    else
      "entrypoint:  (none set)";

  # Tool list varies by shell type — match what packages.nix provides
  toolsLine =
    if cfg.shell == null then
      "tools:       (container-specific — see entrypoint)"
    else if cfg.shell.type == "minimal-dash" then
      "tools:       basename cat chmod chown cp cut date dirname echo env\n" +
      "             head id install ln ls mkdir mv printf pwd rm sleep\n" +
      "             sort stat tail test touch tr wc"
    else if cfg.shell.type == "minimal-nu" then
      "tools:       all dash tools + comm csplit dd df du expand fold\n" +
      "             join nl od paste seq shuf split tac tee tsort uniq"
    else
      "tools:       full uutils-coreutils + layer-specific packages";

  containerInfoText = ''
    ────────────────────────────────────────────────────────────────────────────
     container: ${cfg.name}
     mode:      ${cfg.mode}
     ${shellLine}
     ${entrypointLine}

     ${toolsLine}

     sbom:      /_manifest/spdx.json  (SPDX 2.3 format)
     info:      /etc/container-info   (this file)

     ssl certs: /etc/ssl/certs/ca-bundle.crt
    ────────────────────────────────────────────────────────────────────────────
  '';

in
  pkgs.writeTextFile {
    name        = "container-info";
    destination = "/etc/container-info";
    text        = containerInfoText;
  }
