#!/bin/bash
# Helpers shared by build/compile.sh (inside the image build) and by tools/ and
# .gitea/ (outside it). Source it, do not run it.
#
# load_versions [FILE]          export the KEY=value lines of versions.env
# base_image                    base image reference from versions.env (DEBIAN_SUITE, DEBIAN_DIGEST)
# download URL SHA256 DEST      download over https and verify the sha256 (fails on mismatch)
# ganesha_url VERSION           GitHub archive URL of nfs-ganesha tag V<VERSION>
# ntirpc_url VERSION            GitHub archive URL of ntirpc tag v<VERSION>
# prometheus_url COMMIT         GitHub archive URL of a prometheus-cpp-lite commit

build_die() { echo "build: $*" >&2; exit 1; }

# load_versions [FILE]: export every KEY=value of versions.env (no shell code runs)
load_versions() {
  local file=${1:-$(dirname "${BASH_SOURCE[0]}")/../versions.env} line
  [ -r "$file" ] || build_die "cannot read $file"
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=([^[:space:]]+)$ ]] || build_die "bad line in $file: $line"
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
  done < "$file"
}

# base_image: docker.io/library/debian:<SUITE>-slim@<DIGEST> (versions.env loaded)
base_image() {
  [ -n "${DEBIAN_SUITE:-}" ] && [ -n "${DEBIAN_DIGEST:-}" ] ||
    build_die "DEBIAN_SUITE and DEBIAN_DIGEST must be set in versions.env"
  printf 'docker.io/library/debian:%s-slim@%s\n' "$DEBIAN_SUITE" "$DEBIAN_DIGEST"
}

ganesha_url() { printf 'https://github.com/nfs-ganesha/nfs-ganesha/archive/V%s.tar.gz\n' "${1:?version}"; }
ntirpc_url() { printf 'https://github.com/nfs-ganesha/ntirpc/archive/v%s.tar.gz\n' "${1:?version}"; }
prometheus_url() { printf 'https://github.com/biaks/prometheus-cpp-lite/archive/%s.tar.gz\n' "${1:?commit}"; }

download() {
  local url=${1:?url} sha=${2:-} dest=${3:?dest}
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || build_die "no valid sha256 for $url"
  curl -fsSL --proto '=https' --connect-timeout 30 --retry 3 --retry-delay 2 -o "$dest" "$url" ||
    build_die "download failed: $url"
  echo "$sha  $dest" | sha256sum -c --quiet - || { rm -f "$dest"; build_die "sha256 mismatch: $url"; }
  echo "ok $url"
}
