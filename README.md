# Description
NFS-Ganesha is a user-mode file server for NFS (v3, 4.0, 4.1, 4.1 pNFS, 4.2)

# Supported tags
| Tags | nfs-ganesha | Base |
|---|---|---|
| `15.X-BUILD`, `15.X`, `15`, `latest` | 15.X | Debian 13 (trixie) slim |
| `3.4-BUILD`, `3.4` (old, unmaintained) | 3.4 | Debian 10 (buster) slim |

**X** is the nfs-ganesha minor version, **BUILD** the build number: see the
[tags page](https://hub.docker.com/r/izdock/nfs-ganesha/tags) for the latest ones.
Images are rebuilt every week with the latest OS security updates, so the `15.X`, `15` and `latest`
tags always point to a patched image; `15.X-BUILD` never changes.

Architecture: `amd64`.

# Dockerfile
- https://github.com/ugoviti/izdock-nfs-ganesha/blob/main/Dockerfile

# Features
- Small image footprint based on [Debian 13 (trixie) Slim](https://hub.docker.com/_/debian/), multi-stage build
- NFS Ganesha binaries are compiled from the upstream official repository (FSAL VFS only, jemalloc allocator)
- Every downloaded source (nfs-ganesha, ntirpc, prometheus-cpp-lite) is pinned and verified by sha256 at build time
- Upstream uses a rolling release model since V8.0: every non-prerelease `Vx.y` tag is a stable release
- Using [tini](https://github.com/krallin/tini) as init process
- Many customizable variables to use

# What is nfs-ganesha?
Nfs-ganesha is a user-mode file server for NFS (v3, 4.0, 4.1, 4.1 pNFS, 4.2) and for 9P from the Plan9 operating system. It can support all these protocols concurrently.
This is an Open Source project with an active community of both company sponsored and independent developers.

# How to use this image.

This image only contains nfs-ganesha from [official home page](https://github.com/nfs-ganesha/nfs-ganesha)
and from [official download repository](https://download.nfs-ganesha.org/)

# Requirements
- `CAP_SYS_RESOURCE` (`--cap-add SYS_RESOURCE`): ganesha sets `PR_SET_IO_FLUSHER` at startup to avoid
  kernel deadlocks when NFS clients run on the same node and memory is low. Without the capability
  ganesha refuses to start, unless `ALLOW_SET_IO_FLUSHER_FAIL=true` (protection disabled).
- `CAP_DAC_READ_SEARCH` (`--cap-add DAC_READ_SEARCH`): needed by FSAL VFS (`open_by_handle_at`).
- The process is `ganesha.nfsd`, child of `tini` (PID 1): if ganesha dies the container exits and restarts.

# Environment variables
You can change the default behaviour using the following variables (with default values):

```
: ${EXPORT_PATH:="/exports"}
: ${PSEUDO_PATH:="/exports"}
: ${EXPORT_ID:=1}
: ${PROTOCOLS:=4}                     # "3, 4" to enable NFSv3 too
: ${TRANSPORTS:="TCP"}
: ${NFSV4_MINOR_VERSIONS:="0, 1, 2"}
: ${SEC_TYPE:="sys"}
: ${SQUASH_MODE:="No_Root_Squash"}
: ${GRACELESS:=false}
: ${GRACE_PERIOD:=90}
: ${LEASE_LIFETIME:=60}
: ${RECOVERY_BACKEND:="fs"}           # fs (state in /var/lib/nfs/ganesha, mount a volume to keep it) | none
: ${ACCESS_TYPE:="RW"}
: ${CLIENT_LIST:="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"}
: ${DISABLE_ACL:=false}
: ${ANON_USER:="nobody"}
: ${ANON_GROUP:="nogroup"}
: ${GANESHA_CONFIG:="/etc/ganesha/ganesha.conf"}
: ${GANESHA_LOGFILE:="/dev/stdout"}
: ${LOG_LEVEL:="INFO"}
: ${LOG_COMPONENT:="ALL=INFO;"}
: ${ENABLE_NLM:=false}                # true by default only if PROTOCOLS contains 3
: ${ENABLE_RQUOTA:=false}
: ${STATD_PORT:=662}                  # rpc.statd (NFSv3 locks) on fixed ports, to expose them with a Service
: ${STATD_OUTGOING_PORT:=2020}
: ${IDMAPPING_ACTIVE:=false}          # AUTH_SYS with numeric owners: no name lookups (true with sec=krb5)
: ${MALLOC_CONF:="background_thread:true"}   # jemalloc: give freed memory back to the OS also when idle
: ${ALLOW_SET_IO_FLUSHER_FAIL:=false}
: ${ENABLE_METRICS:=true}             # prometheus metrics on http://<host>:9587/metrics
: ${MONITORING_PORT:=9587}

# metadata cache (MDCACHE) limits
: ${MDCACHE_ENTRIES_HWMARK:=50000}
: ${MDCACHE_ENTRIES_RELEASE_SIZE:=100}
: ${MDCACHE_CHUNKS_HWMARK:=1000}
: ${MDCACHE_CHUNKS_LWMARK:=500}
: ${MDCACHE_DIR_CHUNK:=128}
: ${MDCACHE_LRU_RUN_INTERVAL:=90}
```

# NFSv3
NFSv4 (4.0, 4.1, 4.2) is the default. To serve NFSv3 too set `PROTOCOLS="3, 4"`: rpc.statd and NLM
(NFSv3 locks) are started, every service on a fixed port so that it can be published by a Service:

| Service | Port |
|---|---|
| rpcbind (portmapper) | 111 |
| nfs (v3 and v4) | 2049 |
| mountd | 20048 |
| nlockmgr (NLM) | 32803 |
| status (rpc.statd) | 662 |
| prometheus metrics | 9587 |

rpcbind always runs, also with NFSv4 only: without it ganesha logs `Cannot register NFS V4` at
startup and `rpcinfo` (eg. a liveness probe `rpcinfo -n 2049 -t 127.0.0.1 100003 4`) does not work.

# Upgrading from 3.x
- `TRANSPORTS` default is now `TCP` (NFSv4 is TCP only; ganesha >= 14 does not listen for NFS on UDP).
- The `RPC` log component no longer exists (replaced by `XPRT`); `CACHE_INODE*` are now `MDCACHE*`.
- `Chunks_HWMark` upstream default went from 100000 to 1000 (V5.4): directory chunks no longer pin the cache.
- NLM, rquota and `rpc.statd` are disabled when `PROTOCOLS` does not include 3.
- A log component written twice (e.g. a default plus `LOG_COMPONENT=CLIENTID=DEBUG;`) is a fatal config
  error since ganesha 6: the entrypoint now lets `LOG_COMPONENT` replace the defaults.
- FSAL VFS ignores `tmpfs` exports since ganesha 15 (use a real filesystem for `EXPORT_PATH`).

# Build
Every component version and its sha256 is in
[versions.env](https://github.com/ugoviti/izdock-nfs-ganesha/blob/main/versions.env), the single source
of truth of the build: nfs-ganesha, the ntirpc and prometheus-cpp-lite of its git submodules, the
Debian base image pinned by digest.
```
git clone https://github.com/ugoviti/izdock-nfs-ganesha.git && cd izdock-nfs-ganesha
tools/build.sh          # -> izdock/nfs-ganesha:local
```

Check upstream for new versions and update versions.env (versions and sha256):
```
tools/make-updates.sh           # report only
tools/make-updates.sh --apply   # update versions.env, then build and test
```
nfs-ganesha stays on its major version: a new major is only reported. ntirpc and prometheus-cpp-lite
always follow the submodules of the chosen nfs-ganesha release. To keep nfs-ganesha on a given
version add `GANESHA_PIN=<version>` next to `GANESHA_VER` in versions.env and run
`tools/make-updates.sh --apply`.

Build args (`docker build --build-arg`, or after `tools/build.sh`):
- `ALLOCATOR=jemalloc|libc|tcmalloc` (default `jemalloc`).
- `ENABLE_ACL=OFF|ON` (default `OFF`, as in 3.4): NFSv4 ACLs and the NFSACL protocol of NFSv3. With
  `ON` `ls -l` issues one ACL request per file, even with `DISABLE_ACL=true`: about 10x slower on large
  directories with NFSv4, about 5x with NFSv3.

### Create a `Dockerfile` in your project

```dockerfile
FROM izdock/nfs-ganesha
# your commands here
```

Then, run the commands to build and run the Docker image:

```console
$ docker build -t nfs-ganesha .
$ docker run -dit --name nfs-ganesha --cap-add SYS_RESOURCE --cap-add DAC_READ_SEARCH -p 2049:2049 nfs-ganesha
```

### Without a `Dockerfile`

If you don't want to include a `Dockerfile` in your project, it is sufficient to do the following:

```$ docker run -dit --name my-nfs --cap-add SYS_RESOURCE --cap-add DAC_READ_SEARCH -p 2049:2049 -v "/tmp/testvolme":/data -e EXPORT_PATH=/data izdock/nfs-ganesha```

### Configuration

To customize the configuration of nfs-ganesha, just change the default variables:

```docker run -dit --name my-nfs --cap-add SYS_RESOURCE --cap-add DAC_READ_SEARCH -p 2049:2049 -v "/tmp/testvolme":/data -e EXPORT_PATH=/data -e CLIENT_LIST="192.168.1.1, 192.168.1.23" -e LOG_LEVEL=DEBUG izdock/nfs-ganesha```

# Quick reference

-	**Where to get help**:
	[InitZero Corporate Support](https://www.initzero.it/)

-	**Where to file issues**:
	[https://github.com/ugoviti](https://github.com/ugoviti)

-	**Maintained by**:
	[Ugo Viti](https://github.com/ugoviti)

-	**Supported architectures**:
	[`amd64`]

-	**Supported Docker versions**:
	[the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)

# License

View [Apache license information](https://www.apache.org/licenses/) and [PHP license information](http://php.net/license/index.php) and for the software contained in this image.

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

Some additional license information which was able to be auto-detected might be found in [the `repo-info` repository's `httpd/` directory](https://github.com/docker-library/repo-info/tree/master/repos/httpd).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.
