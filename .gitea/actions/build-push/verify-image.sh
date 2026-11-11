#!/bin/bash
# verify-image.sh: post-build checks run INSIDE the image, before it is published.
#   docker run -i --rm --entrypoint "" IMAGE bash -s < verify-image.sh
# The expected versions are read from the versions.env shipped in the image.
# Prints one OK/FAIL line per check, exit 1 if any check fails.
set -u

FAIL=0
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; FAIL=1; }
has() { if [ -e "$1" ]; then ok "${2:-$1}"; else ko "${2:-$1} missing"; fi; }

versions=/usr/src/izdock/versions.env
[ -r "$versions" ] || { ko "$versions missing"; exit 1; }
while IFS='=' read -r k v; do
  [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] && export "$k=$v"
done < "$versions"

# versions: binary, APP_VER and ntirpc agree with versions.env
release=$(/usr/bin/ganesha.nfsd -v 2>&1 | sed -n 's/^NFS-Ganesha Release = V//p')
if [ "$release" == "$GANESHA_VER" ]; then ok "nfs-ganesha $release"; else ko "nfs-ganesha release '$release', expected $GANESHA_VER"; fi
if [ "${APP_VER:-}" == "$GANESHA_VER" ]; then ok "APP_VER=$APP_VER"; else ko "APP_VER='${APP_VER:-}', expected $GANESHA_VER"; fi
if ldd /usr/bin/ganesha.nfsd | grep -q "libntirpc.so.$NTIRPC_VER "; then ok "libntirpc $NTIRPC_VER"; else ko "ganesha.nfsd is not linked to libntirpc.so.$NTIRPC_VER"; fi

# libraries, FSAL and tools
missing=$(ldd /usr/bin/ganesha.nfsd /usr/lib/ganesha/*.so 2>&1 | grep "not found" || true)
if [ -z "$missing" ]; then ok "all libraries resolved"; else ko "missing libraries: $missing"; fi
has /usr/lib/ganesha/libfsalvfs.so "FSAL VFS"
has /etc/dbus-1/system.d/org.ganesha.nfsd.conf
has /usr/bin/tini
has /entrypoint.sh
has /entrypoint-hooks.sh
for c in rpcinfo rpcbind dbus-daemon pidof; do
  if command -v "$c" >/dev/null; then ok "command $c"; else ko "command $c missing"; fi
done
if ldd /usr/bin/ganesha.nfsd | grep -q libjemalloc; then ok "allocator jemalloc"; else ok "allocator libc"; fi

# generated configuration with the env of the production StatefulSet: every parameter once
# (a parameter set twice is a fatal error since ganesha 6), MDCACHE block present
conf=$(EXPORT_PATH=/data PSEUDO_PATH=/ SQUASH_MODE=no_root_squash DISABLE_ACL=true GRACELESS=true \
  GRACE_PERIOD=180 LOG_LEVEL=DEBUG LOG_COMPONENT='ALL=INFO;CLIENTID=DEBUG;' \
  GANESHA_CONFIG=/tmp/ganesha.conf sh -c '. /entrypoint-hooks.sh >/dev/null 2>&1; cat /tmp/ganesha.conf')
components=$(sed -n '/Components {/,/^    }/p' <<< "$conf" | tr ';' '\n' | grep -oE '^ *[A-Z_0-9]+ *=' | tr -d ' =')
dups=$(sort <<< "$components" | uniq -d)
if [ -z "$components" ]; then ko "no log components in the generated configuration (entrypoint-hooks.sh failed?)"
elif [ -z "$dups" ]; then ok "log components set once ($(paste -sd' ' <<< "$components"))"
else ko "log components set twice: $dups"; fi
if grep -q '^MDCACHE {' <<< "$conf"; then ok "MDCACHE block"; else ko "MDCACHE block missing"; fi
if grep -q 'Transports = TCP;' <<< "$conf"; then ok "Transports = TCP"; else ko "Transports is not TCP"; fi

exit $FAIL
