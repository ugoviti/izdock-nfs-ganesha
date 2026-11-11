#!/bin/bash
# install.sh: runtime stage of the image (OS packages and layout), before the
# compiled files of the build stage are copied in.
#   EXPORT_PATH                  default export directory (Dockerfile ENV)
#   OS_UPDATE_STAMP (build arg)  changes every week in CI, so this layer (apt upgrade) is rebuilt
set -Eeuo pipefail
: "${EXPORT_PATH:?}"

echo "---------- OS packages (OS_UPDATE_STAMP=${OS_UPDATE_STAMP:-none})"
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  tini netbase procps psmisc rsync e2fsprogs acl nfs-common rpcbind dbus \
  libjemalloc2 liburcu8t64 libnfsidmap1 libcap2 libblkid1 libuuid1 libacl1 \
  libdbus-1-3 libssl3t64
rm -rf /var/lib/apt/lists/* /tmp/*

echo "---------- layout"
mkdir -p "$EXPORT_PATH" /var/run/ganesha /var/lib/nfs/ganesha
# ganesha reads the mounted filesystems from /etc/mtab
rm -f /etc/mtab
ln -s /proc/mounts /etc/mtab
