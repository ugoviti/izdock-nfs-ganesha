#!/usr/bin/env bash
# Image tags of a version (the scheme of .gitea/actions/image-tags), one full
# reference per line. Environment:
#   IMAGES         image names, newline separated
#   VERSION        15.11 | 15.11.1 | 15.11-rc1 | anything else (used as-is)
#   BUILD_NUMBER   optional: adds <version>-<build-number>
#   LATEST         true | false
# Scheme (the same of the old Drone pipeline):
#   15.11         -> 15.11, 15 [, 15.11-<build>] [, latest]
#   15.11.1       -> 15.11.1, 15.11, 15 [, 15.11.1-<build>] [, latest]
#   15.11-rc1     -> 15.11-rc1 [, 15.11-rc1-<build>]    (prerelease: never X.Y, X, latest)
#   ci-test       -> ci-test                            (not a version: as-is, never latest)
set -euo pipefail
: "${IMAGES:?}" "${VERSION:?}"
latest=${LATEST:-false}
tags=("$VERSION")
if [[ "$VERSION" =~ ^v?([0-9]+)\.([0-9]+)(\.([0-9]+))?(-[0-9A-Za-z.-]+)?$ ]]; then
  ver=${VERSION#v}
  if [ -n "${BASH_REMATCH[5]}" ]; then
    tags=("$ver") latest=false
  elif [ -n "${BASH_REMATCH[3]}" ]; then
    tags=("$ver" "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}")
  else
    tags=("$ver" "${BASH_REMATCH[1]}")
  fi
  [ -z "${BUILD_NUMBER:-}" ] || tags+=("$ver-$BUILD_NUMBER")
else
  latest=false
fi
[ "$latest" != true ] || tags+=(latest)
while IFS= read -r image; do
  [ -n "$image" ] || continue
  for t in "${tags[@]}"; do printf '%s:%s\n' "$image" "$t"; done
done <<< "$IMAGES"
