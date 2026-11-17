#!/usr/bin/env bash
#
# check-docker-trust-store.sh - Fail when an affected emSign root is trusted.
#
# Usage: check-docker-trust-store.sh [BUNDLE [TRUST_SOURCE...]]
#
# BUNDLE defaults to $SSL_CERT_FILE. TRUST_SOURCE defaults to the p11-kit
# bundles in /nix/store, which is how the audit image finds its trust source.
#
# AFFECTED_EMSIGN_FINGERPRINTS must list the affected roots as SHA256
# fingerprints in lowercase hex without separators, separated by spaces.
#
# An affected root fails the check when it appears in the PEM bundle, or when
# it appears in a p11-kit trust source without "x-distrusted: true". p11-kit
# keeps blocked certificates in its store and marks them distrusted, so trust
# state, not presence, is what matters there.

set -euo pipefail

affected_roots_raw="${AFFECTED_EMSIGN_FINGERPRINTS:-}"
if [[ -z $affected_roots_raw ]]; then
  echo "error: AFFECTED_EMSIGN_FINGERPRINTS is not set" >&2
  exit 2
fi
read -r -a affected_roots <<<"$affected_roots_raw"

bundle="${1:-${SSL_CERT_FILE:-}}"
if [[ -z $bundle ]]; then
  echo "error: no bundle given and SSL_CERT_FILE is unset" >&2
  exit 2
fi
if [[ ! -f $bundle ]]; then
  echo "error: bundle not found: $bundle" >&2
  exit 2
fi
shift || true

trust_sources=("$@")
if [[ ${#trust_sources[@]} -eq 0 ]]; then
  while IFS= read -r path; do
    trust_sources+=("$path")
  done < <(compgen -G '/nix/store/*-nss-cacert-*-p11kit/etc/ssl/trust-source/ca-bundle.trust.p11-kit' || true)
fi
if [[ ${#trust_sources[@]} -eq 0 ]]; then
  echo "FAIL: no p11-kit trust source found" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failed=0

is_affected() {
  local fingerprint="$1" root
  for root in "${affected_roots[@]}"; do
    if [[ $fingerprint == "$root" ]]; then
      return 0
    fi
  done
  return 1
}

pem_subject() {
  openssl x509 -noout -subject -in "$1"
}

pem_fingerprint() {
  openssl x509 -noout -fingerprint -sha256 -in "$1" |
    cut -d= -f2 |
    tr -d ':' |
    tr 'A-F' 'a-f'
}

# PEM bundle: an affected root must be absent.
mkdir -p "$tmp/bundle"
awk -v dir="$tmp/bundle" '
  BEGIN { n = 0 }
  /-----BEGIN CERTIFICATE-----/ { n++; file = sprintf("%s/cert-%04d.pem", dir, n) }
  n { print > file }
' "$bundle"

shopt -s nullglob
bundle_count=0
bundle_failed=0
for cert in "$tmp/bundle"/*.pem; do
  bundle_count=$((bundle_count + 1))
  fingerprint="$(pem_fingerprint "$cert")"
  if is_affected "$fingerprint"; then
    echo "FAIL: affected root in $bundle: $(pem_subject "$cert") ($fingerprint)" >&2
    bundle_failed=1
    failed=1
  fi
done
if [[ $bundle_count -eq 0 ]]; then
  echo "FAIL: no certificates found in $bundle" >&2
  exit 1
fi
if [[ $bundle_failed -eq 0 ]]; then
  echo "OK: $bundle has $bundle_count certificates and no affected root"
fi

# p11-kit trust sources: an affected root must be absent or distrusted.
for source in "${trust_sources[@]}"; do
  if [[ ! -f $source ]]; then
    echo "FAIL: trust source not found: $source" >&2
    failed=1
    continue
  fi

  objects="$tmp/objects"
  rm -rf "$objects"
  mkdir -p "$objects"
  awk -v dir="$objects" '
    /^\[p11-kit-object-v1\]$/ { n++; file = sprintf("%s/object-%04d", dir, n); next }
    n { print >> file }
  ' "$source"

  object_count=0
  source_failed=0
  for object in "$objects"/object-*; do
    grep -q -- '-----BEGIN CERTIFICATE-----' "$object" || continue
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$object" >"$tmp/object.pem"
    object_count=$((object_count + 1))
    fingerprint="$(pem_fingerprint "$tmp/object.pem")"
    if is_affected "$fingerprint"; then
      if grep -qE '^x-distrusted:[[:space:]]*true[[:space:]]*$' "$object"; then
        echo "OK: $source marks an affected root as distrusted ($fingerprint)"
      else
        echo "FAIL: affected root is trusted in $source: $(pem_subject "$tmp/object.pem") ($fingerprint)" >&2
        source_failed=1
        failed=1
      fi
    fi
  done
  if [[ $object_count -eq 0 ]]; then
    echo "FAIL: no certificates found in $source" >&2
    exit 1
  fi
  if [[ $source_failed -eq 0 ]]; then
    echo "OK: $source has $object_count certificates"
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi
