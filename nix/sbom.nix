# polar-container-lib/nix/sbom.nix
#
# Generates an SPDX 2.3 Software Bill of Materials from the container's
# Nix closure, embedded in the image at /_manifest/spdx.json.
#
# WHY BUILD-TIME SBOM?
# --------------------
# Standard SBOM scanners (Syft, Grype, Trivy) scrape container layers
# looking for dpkg/rpm/pip databases. Nix containers have none of these.
# The correct approach: generate the SBOM at build time from closureInfo,
# which knows the complete and exact set of store paths in the closure.
#
# FORMAT: SPDX 2.3 JSON.
# LOCATION: /_manifest/spdx.json — emerging OCI SBOM convention.
#
# IMPLEMENTATION NOTES
# --------------------
# We write each package as a NDJSON line (one JSON object per line) to a
# temp file, then use jq -s to slurp them into an array. This avoids:
#   - "Argument list too long" from building a massive shell variable
#   - Glob expansion limits from passing hundreds of files to jq
#   - grep flag interpretation issues from embedded regex patterns

{ pkgs
, cfg
, closureInfo
}:

let
  documentNamespace =
    "https://spdx.org/spdxdocs/${cfg.name}";

  spdxDocument = pkgs.runCommand "sbom-spdx" {
    nativeBuildInputs = [ pkgs.jq pkgs.perl ];
  } ''
    set -euo pipefail

    STORE_PATHS="${closureInfo}/store-paths"
    NDJSON=$(mktemp)

    # Process each store path, writing one SPDX package JSON per line.
    # Using while-read (not mapfile) to work correctly with structuredAttrs.
    # Using perl for name/version extraction — avoids grep flag/quoting issues.
    while IFS= read -r path; do
      BASENAME=$(basename "$path")

      # Store path: <32-char-hash>-<name>[-<version>]
      HASH="''${BASENAME:0:32}"
      WITHOUT_HASH="''${BASENAME:33}"
      SPDX_ID="SPDXRef-$HASH"

      # Use perl to split name/version — reliable across all store path formats
      NAME=$(perl -e '
        my $s = $ARGV[0];
        # Version segment starts with digit after a dash
        if ($s =~ /^(.*?)-(\d[^-]*)(-.*)?$/) {
          print $1;
        } else {
          print $s;
        }
      ' -- "$WITHOUT_HASH")

      VERSION=$(perl -e '
        my $s = $ARGV[0];
        if ($s =~ /^.*?-(\d[^\s]*)$/) {
          print $1;
        } else {
          print "unknown";
        }
      ' -- "$WITHOUT_HASH")

      # Write one JSON object per line (NDJSON)
      jq -cn \
        --arg spdxId    "$SPDX_ID" \
        --arg name      "$NAME" \
        --arg version   "$VERSION" \
        --arg path      "$path" \
        --arg hash      "$HASH" \
        '{
          SPDXID:           $spdxId,
          name:             $name,
          versionInfo:      $version,
          downloadLocation: "NOASSERTION",
          filesAnalyzed:    false,
          externalRefs: [{
            referenceCategory: "PACKAGE-MANAGER",
            referenceType:     "nix",
            referenceLocator:  $path
          }],
          checksums: [{
            algorithm:     "SHA256",
            checksumValue: $hash
          }]
        }' >> "$NDJSON"
    done < "$STORE_PATHS"

    # Slurp all package lines into an array, build the full SPDX document
    jq -s \
      --arg name    "${cfg.name}" \
      --arg ns      "${documentNamespace}" \
      '{
        spdxVersion:       "SPDX-2.3",
        dataLicense:       "CC0-1.0",
        SPDXID:            "SPDXRef-DOCUMENT",
        name:              $name,
        documentNamespace: $ns,
        creationInfo: {
          created:  "1970-01-01T00:00:00Z",
          creators: ["Tool: nix-container-lib", "Tool: Nix"]
        },
        packages: .,
        relationships: [{
          spdxElementId:      "SPDXRef-DOCUMENT",
          relationshipType:   "DESCRIBES",
          relatedSpdxElement: (.[0].SPDXID // "SPDXRef-DOCUMENT")
        }]
      }' < "$NDJSON" > spdx.json

    mkdir -p $out/_manifest
    cp spdx.json $out/_manifest/spdx.json
    rm -f "$NDJSON"
  '';

in
  spdxDocument
