#!/bin/bash
# compile.sh: build stage of the image. Downloads nfs-ganesha, ntirpc and prometheus-cpp-lite
# (versions and sha256 from versions.env only), compiles and installs into DESTDIR (/out).
#   APP_VER (build arg, optional)  expected nfs-ganesha version: the build fails if versions.env differs
#   ALLOCATOR                      jemalloc | libc | tcmalloc
#   ENABLE_ACL                     OFF | ON (NFSv4 ACLs on FSAL VFS and the NFSACL side protocol of NFSv3)
set -Eeuo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=build/lib.sh
. "$src/build/lib.sh"
load_versions "$src/versions.env"

: "${ALLOCATOR:?}" "${ENABLE_ACL:?}"
if [ -n "${APP_VER:-}" ] && [ "$APP_VER" != "$GANESHA_VER" ]; then
  build_die "APP_VER=$APP_VER but versions.env has GANESHA_VER=$GANESHA_VER"
fi

echo "---------- build packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl build-essential cmake pkg-config bison flex libfl-dev \
  libcap-dev libnfsidmap-dev libdbus-1-dev libblkid-dev uuid-dev liburcu-dev \
  libacl1-dev libjemalloc-dev libssl-dev libboost-dev
rm -rf /var/lib/apt/lists/*

echo "---------- sources: nfs-ganesha $GANESHA_VER, ntirpc $NTIRPC_VER, prometheus-cpp-lite ${PROMETHEUS_CPP_LITE_COMMIT::7}"
tree=/usr/src/nfs-ganesha
tmp=$(mktemp -d)
download "$(ganesha_url "$GANESHA_VER")" "$GANESHA_SHA256" "$tmp/ganesha.tar.gz"
download "$(ntirpc_url "$NTIRPC_VER")" "$NTIRPC_SHA256" "$tmp/ntirpc.tar.gz"
download "$(prometheus_url "$PROMETHEUS_CPP_LITE_COMMIT")" "$PROMETHEUS_CPP_LITE_SHA256" "$tmp/prometheus.tar.gz"
mkdir -p "$tree" "$tree/src/libntirpc" "$tree/src/libntirpc/src/monitoring/prometheus-cpp-lite"
# the github archives do not include the git submodules: unpack them in place
tar xzf "$tmp/ganesha.tar.gz" --strip-components=1 -C "$tree"
tar xzf "$tmp/ntirpc.tar.gz" --strip-components=1 -C "$tree/src/libntirpc"
tar xzf "$tmp/prometheus.tar.gz" --strip-components=1 -C "$tree/src/libntirpc/src/monitoring/prometheus-cpp-lite"
rm -rf "$tmp"

echo "---------- cmake (FSAL VFS only, allocator $ALLOCATOR, ACL $ENABLE_ACL)"
# process metrics (procps) are not available: ganesha looks for libprocps, missing in trixie
# upstream bug (V15.11): src/os/linux/acl.c is always built, but libacl is linked only when
# ENABLE_VFS_POSIX_ACL or USE_NFSACL3 is on; with both off link libacl explicitly
acl_link=''
[ "$ENABLE_ACL" == ON ] || acl_link='-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-as-needed,-lacl'
mkdir -p "$tree/build"
cd "$tree/build"
cmake -DCMAKE_BUILD_TYPE=Release -Wno-dev \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DUSE_FSAL_CEPH=OFF \
  -DUSE_FSAL_GLUSTER=OFF \
  -DUSE_FSAL_LUSTRE=OFF \
  -DUSE_FSAL_LIZARDFS=OFF \
  -DUSE_FSAL_SAUNAFS=OFF \
  -DUSE_FSAL_XFS=OFF \
  -DUSE_FSAL_GPFS=OFF \
  -DUSE_FSAL_RGW=OFF \
  -DUSE_FSAL_KVSFS=OFF \
  -DUSE_FSAL_PROXY_V3=OFF \
  -DUSE_FSAL_PROXY_V4=OFF \
  -DRADOS_URLS=OFF \
  -DUSE_RADOS_RECOV=OFF \
  -D_MSPAC_SUPPORT=OFF \
  -DUSE_GSS=OFF \
  -DUSE_LTTNG=OFF \
  -DUSE_ADMIN_TOOLS=OFF \
  -DUSE_GUI_ADMIN_TOOLS=OFF \
  -DUSE_MAN_PAGE=OFF \
  -DUSE_UNWIND=OFF \
  -DUSE_MONITORING=ON \
  -DALLOCATOR="$ALLOCATOR" \
  -DENABLE_VFS_POSIX_ACL="$ENABLE_ACL" \
  -DENABLE_RFC_ACL="$ENABLE_ACL" \
  -DUSE_NFSACL3="$ENABLE_ACL" \
  $acl_link \
  ../src/

echo "---------- make"
make -j"$(nproc)"
make install DESTDIR=/out
install -D -m644 ../src/scripts/ganeshactl/org.ganesha.nfsd.conf /out/etc/dbus-1/system.d/org.ganesha.nfsd.conf
rm -rf /out/usr/include /out/usr/share/doc /out/usr/lib/systemd /out/etc/sysconfig /out/etc/logrotate.d
