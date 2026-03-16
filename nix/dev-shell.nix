# polar-container-lib/nix/dev-shell.nix
#
# Produces the host-side `nix develop` shell — the environment a developer
# uses on their local machine, distinct from the container itself.
#
# This shares package sets and TLS logic with the container but has
# different constraints:
#
#   - Runs on the host, not inside a container
#   - Store paths in shellHook are safe (shellHook runs in target-arch
#     `nix develop` context, not at flake evaluation time on the build host)
#   - set -euo pipefail is intentionally NOT used in shellHook — it runs
#     in the user's interactive shell and set -e would exit the entire
#     shell session on any non-zero return, including innocuous operations
#     like grep with no matches. Errors are handled explicitly instead.
#   - TLS certs are built lazily on first `nix develop` via the need_certs
#     pattern — not on every shell entry, and not at flake evaluation time
#
# The dev shell is only meaningful for Dev mode containers. CI, Agent, and
# Pipeline containers may still produce a dev shell (for debugging the
# container config itself) but it won't have the full interactive setup.

{ pkgs
, cfg           # Translated config from from-dhall.nix
, inputs        # Flake inputs for resolving extra packages
, tlsDerivation # The gen-certs derivation, or null if TLS disabled
}:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # Package set for the dev shell
  # Reuses the same resolved packages as the container, minus the container-
  # specific infrastructure (start.sh, polar-help, etc.) which don't make
  # sense on the host.
  # ---------------------------------------------------------------------------
  devShellPackages = cfg.packages ++ [ pkgs.pkg-config pkgs.openssl ];

  # ---------------------------------------------------------------------------
  # TLS environment setup
  # The need_certs / lazy build pattern from the original polar shellHook.
  # Only included when TLS is configured.
  # ---------------------------------------------------------------------------
  tlsHook =
    if cfg.tls == null || !cfg.tls.enable
    then ""
    else
      let
        # When generateCerts = true, the result link is a nix build output.
        # When certsPath is set, we use that path directly.
        certsLink =
          if cfg.tls.generateCerts
          then ''"$PROJECT_ROOT/result-tlsCerts"''
          else ''"${cfg.tls.certsPath}"'';

        buildBlock =
          if cfg.tls.generateCerts
          then ''
            if need_certs; then
              echo "[polar] TLS certs missing -> building .#tlsCerts"
              nix build -L .#tlsCerts -o "$CERTS_LINK" || {
                echo "[polar] ERROR: failed to build TLS certs. Check nix build output above."
                return 1
              }
            fi
          ''
          else ''
            if need_certs; then
              echo "[polar] TLS certs missing at ${cfg.tls.certsPath}"
              echo "[polar] ERROR: certsPath is set but certs not found. Check your configuration."
              return 1
            fi
          '';
      in ''
        # ---------------------------------------------------------------------------
        # TLS auto-setup
        # NOTE: set -euo pipefail is intentionally NOT used here.
        # See module header comment for explanation.
        # ---------------------------------------------------------------------------
        PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
        CERTS_LINK=${certsLink}

        need_certs() {
          [ ! -e "$CERTS_LINK/ca_certificates/ca_certificate.pem"  ] || \
          [ ! -e "$CERTS_LINK/server/server_"*"_certificate.pem"   ] || \
          [ ! -e "$CERTS_LINK/server/server_"*"_key.pem"           ] || \
          [ ! -e "$CERTS_LINK/client/client_"*"_certificate.pem"   ] || \
          [ ! -e "$CERTS_LINK/client/client_"*"_key.pem"           ]
        }

        ${buildBlock}

        CA_CERT="$CERTS_LINK/ca_certificates/ca_certificate.pem"
        SERVER_CERT=$(ls "$CERTS_LINK/server/"*"_certificate.pem" 2>/dev/null | head -1)
        SERVER_KEY=$(ls  "$CERTS_LINK/server/"*"_key.pem"         2>/dev/null | head -1)
        CLIENT_CERT=$(ls "$CERTS_LINK/client/"*"_certificate.pem" 2>/dev/null | head -1)
        CLIENT_KEY=$(ls  "$CERTS_LINK/client/"*"_key.pem"         2>/dev/null | head -1)

        SSL_DIR="$PROJECT_ROOT/var/ssl"
        mkdir -p "$SSL_DIR"

        # Build the cert chain: server cert + CA cert
        SERVER_CHAIN="$SSL_DIR/server_cert_chain.pem"
        cat "$SERVER_CERT" "$CA_CERT" > "$SERVER_CHAIN"

        # Export TLS vars — use existing value if already set (: syntax)
        : "''${TLS_CA_CERT:=$CA_CERT}"
        : "''${TLS_SERVER_CERT_CHAIN:=$SERVER_CHAIN}"
        : "''${TLS_SERVER_KEY:=$SERVER_KEY}"
        : "''${TLS_CLIENT_CERT:=$CLIENT_CERT}"
        : "''${TLS_CLIENT_KEY:=$CLIENT_KEY}"
        export TLS_CA_CERT TLS_SERVER_CERT_CHAIN TLS_SERVER_KEY TLS_CLIENT_CERT TLS_CLIENT_KEY

        echo "[polar] TLS env configured:"
        echo "  TLS_CA_CERT=$TLS_CA_CERT"
        echo "  TLS_SERVER_CERT_CHAIN=$TLS_SERVER_CERT_CHAIN"
        echo "  TLS_SERVER_KEY=$TLS_SERVER_KEY"
        echo "  TLS_CLIENT_CERT=$TLS_CLIENT_CERT"
        echo "  TLS_CLIENT_KEY=$TLS_CLIENT_KEY"
      '';

  # ---------------------------------------------------------------------------
  # OpenSSL environment (for Rust crates that link against OpenSSL)
  # ---------------------------------------------------------------------------
  opensslHook = ''
    export OPENSSL_DIR="${pkgs.openssl.dev}"
    export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
    export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include"
    export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
  '';

  # ---------------------------------------------------------------------------
  # Compiler environment
  # Mirrors the container's toolchain setup so that builds on the host
  # produce the same results as builds inside the container.
  # ---------------------------------------------------------------------------
  toolchainHook = ''
    export CC=clang
    export CXX=clang++
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.glibc pkgs.llvmPackages_19.clang ]}"
    export LIBCLANG_PATH="${pkgs.llvmPackages_19.libclang.lib}/lib"
  '';

  # ---------------------------------------------------------------------------
  # SSL certificate path for tools that need it (cargo, git, curl)
  # ---------------------------------------------------------------------------
  sslCertHook = ''
    : "''${SSL_CERT_FILE:=''${NIX_SSL_CERT_FILE:-''${SYSTEM_CERTIFICATE_PATH:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}}}"
    export SSL_CERT_FILE
    export CARGO_HTTP_CAINFO="$SSL_CERT_FILE"
    export GIT_SSL_CAINFO="$SSL_CERT_FILE"
    export CARGO_NET_GIT_FETCH_WITH_CLI=true
  '';

  # ---------------------------------------------------------------------------
  # User-supplied extra env vars (UserProvided placement)
  # ---------------------------------------------------------------------------
  userEnvHook =
    let
      userProvided = builtins.filter
        (ev: ev.placement ? UserProvided)
        cfg.extraEnv;
    in
      lib.concatMapStrings
        (ev: "export ${ev.name}=${lib.escapeShellArg ev.value}\n")
        userProvided;

  # ---------------------------------------------------------------------------
  # Full shellHook assembly
  # ---------------------------------------------------------------------------
  shellHook =
    opensslHook
    + toolchainHook
    + sslCertHook
    + tlsHook
    + userEnvHook;

in
  pkgs.mkShell {
    name     = "${cfg.name}-devshell";
    packages = devShellPackages;
    inherit shellHook;
  }
