# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# (IMAGE_FROM is always passed, no default on purpose)
# izdock/nfs-ganesha: NFS-Ganesha userspace NFS server, compiled from the upstream sources.
# https://github.com/nfs-ganesha/nfs-ganesha
#
# Versions and sha256: versions.env (single source of truth). Build logic: build/compile.sh
# (build stage) and build/install.sh (runtime stage).
# IMAGE_FROM, APP_VER and NTIRPC_VER have no default: they come from versions.env.
#   tools/build.sh          local build
# CI: .gitea/workflows/build.yml

ARG IMAGE_FROM

#### build stage
FROM ${IMAGE_FROM} AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# APP_VER: expected nfs-ganesha version, the build fails if versions.env differs
ARG APP_VER
# allocator: jemalloc (default upstream) | libc | tcmalloc
ARG ALLOCATOR=jemalloc
# NFSv4 ACLs on FSAL VFS: OFF as in 3.4. With ON the server advertises ACLs and "ls -l"
# issues one GETACL per file (20000 files: 3.2s instead of 0.3s), even with Disable_ACL=true
ARG ENABLE_ACL=OFF

COPY versions.env /usr/src/izdock/versions.env
COPY build/ /usr/src/izdock/build/
RUN /usr/src/izdock/build/compile.sh

#### runtime stage
FROM ${IMAGE_FROM}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL maintainer="Ugo Viti <ugo.viti@initzero.it>"

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_NAME="nfs-ganesha"
ENV APP_DESCRIPTION="NFS-Ganesha Userspace NFS File Server"

## versions (from versions.env, passed by CI and tools/build.sh)
ARG APP_VER
ARG NTIRPC_VER
ENV APP_VER="${APP_VER}"
ENV NFS_GANESHA_VERSION="${APP_VER}"
ENV NTIRPC_VERSION="${NTIRPC_VER}"

# NFS daemon configuration
ENV EXPORT_PATH="/exports"

## install: OS packages and layout (build/install.sh)
# OS_UPDATE_STAMP: changes every week in CI, so the cached OS upgrade layer is rebuilt
ARG OS_UPDATE_STAMP=""
COPY build/install.sh /usr/src/izdock/build/install.sh
RUN /usr/src/izdock/build/install.sh

COPY --from=build /out/ /
COPY versions.env /usr/src/izdock/versions.env

# verify that all libraries are resolved
RUN ldconfig && \
  ! ldd /usr/bin/ganesha.nfsd /usr/lib/ganesha/*.so | grep "not found" && \
  /usr/bin/ganesha.nfsd -v

# APP volumes
VOLUME ["${EXPORT_PATH}"]

# APP ports (nfs, rpcbind, mountd, nlm, prometheus metrics)
EXPOSE 2049 111 111/udp 20048 32803 9587

# container pre-entrypoint variables
ENV ENTRYPOINT_TINI="true"
ENV UMASK="0002"

# add files to container
COPY Dockerfile filesystem README.md /

# CI args
ARG APP_VER_BUILD
ARG APP_BUILD_COMMIT
ARG APP_BUILD_DATE

# CI envs
ENV APP_VER_BUILD="${APP_VER_BUILD}"
ENV APP_BUILD_COMMIT="${APP_BUILD_COMMIT}"
ENV APP_BUILD_DATE="${APP_BUILD_DATE}"

# entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/ganesha.nfsd", "-F", "-L", "/dev/stdout", "-f", "/etc/ganesha/ganesha.conf"]
