#!/bin/bash
# Local build with the versions of versions.env (the same build args as CI).
#
#   tools/build.sh [docker build args...]     eg. tools/build.sh --no-cache
#
# The image is tagged izdock/nfs-ganesha:local (override with IMAGE=name:tag).
# BUILDER=podman uses podman build (eg. --dns 1.1.1.1 when the docker containers cannot resolve).
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=build/lib.sh
. "$root/build/lib.sh"
load_versions "$root/versions.env"
from=$(base_image)
image=${IMAGE:-izdock/nfs-ganesha:local}
echo "building $image from $from (nfs-ganesha $GANESHA_VER, ntirpc $NTIRPC_VER)"
exec "${BUILDER:-docker}" build \
  --build-arg IMAGE_FROM="$from" \
  --build-arg APP_VER="$GANESHA_VER" \
  --build-arg NTIRPC_VER="$NTIRPC_VER" \
  --build-arg OS_UPDATE_STAMP="$(date -u +%G-W%V)" \
  --build-arg APP_BUILD_COMMIT="$(git -C "$root" rev-parse --short=7 HEAD 2>/dev/null || echo local)" \
  --build-arg APP_BUILD_DATE="$(date +%s)" \
  -t "$image" "$@" "$root"
