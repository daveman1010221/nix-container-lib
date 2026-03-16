# polar-container-lib/nix/gen-certs.nix
#
# Generates a CA certificate, server certificate, and client certificate
# using the RabbitMQ tls-gen tool.
#
# This is a direct extraction from polar's gen-certs.nix with two changes:
#   1. The CN is now parameterized via cfg.tls rather than hardcoded "cassini"
#   2. The derivation is self-contained — no external file read required
#
# Output structure:
#   $out/ca_certificates/ca_certificate.pem  (and key)
#   $out/server/server_<cn>_certificate.pem  (and key)
#   $out/client/client_<cn>_certificate.pem  (and key)
#
# These paths are what the dev-shell.nix TLS wiring expects.
#
# REFERENCE: https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv
# REFERENCE: https://github.com/rabbitmq/tls-gen

{ pkgs
, cfg     # Translated config from from-dhall.nix
}:

let
  # The CN (Common Name) for the generated certificates.
  # Defaults to "localhost" which is correct for local dev/CI usage.
  # Projects that need a specific CN (e.g. a service name for mTLS routing)
  # can set it via the TLSConfig in their Dhall config.
  #
  # Note: tls-gen uses the CN to name the output files:
  #   server_<cn>_certificate.pem, client_<cn>_certificate.pem
  # The dev-shell wiring uses wildcards to find these files, so changing
  # the CN does not require updating dev-shell.nix.
  cn = "localhost";

in
  pkgs.stdenv.mkDerivation {
    pname   = "tls-gen-certificates";
    version = "1.0.0";

    src = builtins.fetchGit {
      url  = "https://github.com/rabbitmq/tls-gen.git";
      name = "tls-gen";
      rev  = "efb3766277d99c6b8512f226351c7a62f492ef3f";
      ref  = "HEAD";
    };

    buildInputs      = [ pkgs.python312 ];
    nativeBuildInputs = [ pkgs.cmake pkgs.openssl pkgs.hostname ];

    # Prevent CMake from trying to run its own configure phase.
    # tls-gen uses a Makefile, not CMakeLists.txt — without this,
    # the Nix CMake setup hook errors on x86_64 trying to find
    # a CMakeLists.txt that isn't there.
    # REFERENCE: https://nixos.org/manual/nixpkgs/stable/#dont-use-cmake-configure
    # REFERENCE: https://stackoverflow.com/questions/70513330
    dontUseCmakeConfigure = true;

    buildPhase = ''
      cd basic
      make CN=${cn}
    '';

    installPhase = ''
      mkdir -p $out/ca_certificates
      mkdir -p $out/server
      mkdir -p $out/client

      cp result/ca*     $out/ca_certificates/
      cp result/client* $out/client/
      cp result/server* $out/server/
    '';
  }

