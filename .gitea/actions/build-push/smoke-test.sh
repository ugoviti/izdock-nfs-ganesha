#!/bin/bash
# smoke-test.sh: start the image as the production StatefulSet does (same env and
# capabilities) and check that the NFS server works, before it is published.
#   IMAGE=<image> smoke-test.sh
# 1. NFSv4 only (the production env): server initialized without CRIT/MAJ/FATAL, NULL RPC
#    on NFSv4 (the liveness probe), the process is ganesha.nfsd under tini
#    (cleanup-stale-nfs.sh relies on it), kill -9 of ganesha.nfsd stops the container
#    (so kubelet restarts it clean).
# 2. NFSv3 + NFSv4 (PROTOCOLS="3, 4"): no CRIT/MAJ/FATAL, NULL RPC on NFS v3 and v4,
#    MOUNT v3, NLM v4 and rpc.statd registered on rpcbind, statd on its fixed port.
# /data is a docker volume: FSAL VFS ignores tmpfs since ganesha 15.
set -u
: "${IMAGE:?}"
name=ganesha-smoke-$$
vol=ganesha-smoke-$$

FAIL=0
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; FAIL=1; }
cleanup() { docker rm -f "$name" >/dev/null 2>&1; docker volume rm -f "$vol" >/dev/null 2>&1; }
trap cleanup EXIT

# start NAME_SUFFIX [extra docker run args]: run the server with the production env, wait for it
start() {
  cleanup
  docker volume create "$vol" >/dev/null
  docker run -d --name "$name" --cap-add DAC_READ_SEARCH --cap-add SYS_RESOURCE \
    -e EXPORT_PATH=/data -e PSEUDO_PATH=/ -e SQUASH_MODE=no_root_squash -e DISABLE_ACL=true \
    -e GRACELESS=true -e GRACE_PERIOD=180 -e LOG_LEVEL=DEBUG -e 'LOG_COMPONENT=ALL=INFO;CLIENTID=DEBUG;' \
    "$@" -v "$vol":/data "$IMAGE" >/dev/null || { ko "container did not start"; return 1; }
  for _ in $(seq 60); do
    docker logs "$name" 2>&1 | grep -q "NFS SERVER INITIALIZED" && break
    [ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ] || break
    sleep 1
  done
  logs=$(docker logs "$name" 2>&1)
  if grep -q "NFS SERVER INITIALIZED" <<< "$logs"; then ok "server initialized"; else ko "server not initialized"; fi
  errors=$(grep -E ":(CRIT|MAJ|FATAL) :" <<< "$logs" || true)
  if [ -z "$errors" ]; then ok "no CRIT/MAJ/FATAL in the log"; else ko "errors in the log:"; echo "$errors" | head -20; fi
  if grep -q "No export entries found" <<< "$logs"; then ko "export /data not created"; else ok "export /data created"; fi
}
# rpc PROGRAM VERSION LABEL [PORT]: NULL RPC over TCP, through rpcbind or on PORT
rpc() {
  if docker exec "$name" rpcinfo ${4:+-n "$4"} -t 127.0.0.1 "$1" "$2" >/dev/null 2>&1; then ok "$3"; else ko "no answer: $3"; fi
}
dump_logs() { [ "$FAIL" -eq 0 ] || { echo "---- last log lines"; docker logs "$name" 2>&1 | tail -30; }; }

echo "== NFSv4 only (production env)"
start
rpc 100003 4 "NULL RPC NFSv4 on 2049" 2049
pid1=$(docker exec "$name" cat /proc/1/comm 2>/dev/null)
gpid=$(docker exec "$name" pidof ganesha.nfsd 2>/dev/null)
comm=$(docker exec "$name" cat "/proc/$gpid/comm" 2>/dev/null)
ppid=$(docker exec "$name" ps -o ppid= -p "$gpid" 2>/dev/null | tr -d ' ')
if [ "$pid1" == tini ] && [ "$comm" == ganesha.nfsd ] && [ "$ppid" == 1 ]; then
  ok "process ganesha.nfsd (pid $gpid) child of tini"
else
  ko "process layout: pid1=$pid1 comm=$comm ppid=$ppid"
fi
if docker exec "$name" pidof rpc.statd >/dev/null 2>&1; then ko "rpc.statd running without NFSv3"; else ok "no rpc.statd without NFSv3"; fi
docker exec "$name" sh -c 'kill -9 $(pidof ganesha.nfsd)' >/dev/null 2>&1
for _ in $(seq 10); do [ "$(docker inspect -f '{{.State.Running}}' "$name")" == false ] && break; sleep 1; done
state=$(docker inspect -f '{{.State.Running}} {{.State.ExitCode}}' "$name")
if [ "$state" == "false 137" ]; then ok "kill -9 of ganesha.nfsd stops the container (exit 137)"; else ko "after kill -9: running/exit = $state"; fi
dump_logs

echo "== NFSv3 + NFSv4 (PROTOCOLS=\"3, 4\")"
start -e 'PROTOCOLS=3, 4'
rpc 100003 3 "NULL RPC NFSv3 on 2049" 2049
rpc 100003 4 "NULL RPC NFSv4 on 2049" 2049
rpc 100005 3 "MOUNT v3 (via rpcbind)"
rpc 100021 4 "NLM v4 (via rpcbind)"
rpc 100024 1 "rpc.statd (via rpcbind)"
statd=$(docker exec "$name" rpcinfo -p 127.0.0.1 2>/dev/null | awk '$1 == 100024 && $3 == "tcp" { print $4; exit }')
if [ "$statd" == 662 ]; then ok "rpc.statd on port 662"; else ko "rpc.statd on port '$statd', expected 662"; fi
dump_logs

exit $FAIL
