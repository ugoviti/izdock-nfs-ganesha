## quick build and test
# docker build --pull --rm --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=fffffff --build-arg APP_BUILD_DATE=$(date +%s) -t nfs-ganesha .
# docker run --rm --name nfs-ganesha --cap-add SYS_RESOURCE --cap-add DAC_READ_SEARCH -v /tmp/data:/data -e EXPORT_PATH=/data nfs-ganesha

ARG IMAGE_FROM="debian:trixie-slim"

## packages version vars

# https://github.com/nfs-ganesha/nfs-ganesha/releases
# dalla V8.0 upstream usa un modello "rolling": ogni tag Vx.y non-prerelease e' una release stabile
ARG APP_VER=15.11

# https://github.com/nfs-ganesha/ntirpc/tags
# versione del submodule src/libntirpc nel tag di ganesha (V15.11 -> v15.11, V6.5 -> v6.3, V3.4 -> v3.4)
ARG NTIRPC_VERSION=15.11

# submodule src/monitoring/prometheus-cpp-lite di ntirpc v15.11 (non incluso negli archivi github)
ARG PROMETHEUS_CPP_LITE_COMMIT=48d09c45ee6deb90e02579b03037740e1c01fd27

# allocatore: jemalloc (default upstream) | libc | tcmalloc
ARG ALLOCATOR=jemalloc

# ACL NFSv4 su FSAL VFS: OFF come nella 3.4 di produzione. Con ON il server dichiara il supporto ACL
# e "ls -l" fa una GETACL per ogni file (20000 file: 3.2s invece di 0.3s), anche con Disable_ACL=true
ARG ENABLE_ACL=OFF

#### build stage
FROM ${IMAGE_FROM} AS build

ARG APP_VER
ARG NTIRPC_VERSION
ARG PROMETHEUS_CPP_LITE_COMMIT
ARG ALLOCATOR
ARG ENABLE_ACL

RUN set -eux && \
  apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    cmake \
    pkg-config \
    bison \
    flex \
    libfl-dev \
    libcap-dev \
    libnfsidmap-dev \
    libdbus-1-dev \
    libblkid-dev \
    uuid-dev \
    liburcu-dev \
    libacl1-dev \
    libjemalloc-dev \
    libssl-dev \
    libboost-dev \
  && rm -rf /var/lib/apt/lists/*

# download official nfs-ganesha, ntirpc and prometheus-cpp-lite sources from github
RUN set -eux && \
  SRC=/usr/src/nfs-ganesha-${APP_VER} && \
  mkdir -p /usr/src && \
  curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/nfs-ganesha/archive/V${APP_VER}.tar.gz | tar xz -C /usr/src/ && \
  curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/ntirpc/archive/v${NTIRPC_VERSION}.tar.gz | tar xz --strip-components=1 -C ${SRC}/src/libntirpc/ && \
  mkdir -p ${SRC}/src/libntirpc/src/monitoring/prometheus-cpp-lite && \
  curl -fSL --connect-timeout 30 https://github.com/biaks/prometheus-cpp-lite/archive/${PROMETHEUS_CPP_LITE_COMMIT}.tar.gz | tar xz --strip-components=1 -C ${SRC}/src/libntirpc/src/monitoring/prometheus-cpp-lite/

# compile nfs-ganesha: solo FSAL VFS, niente kerberos, 9P (rimosso upstream), ceph/gluster/rgw
RUN set -eux && \
  cd /usr/src/nfs-ganesha-${APP_VER} && \
  mkdir -p build && cd build && \
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
    # metriche di processo (procps) non disponibili: ganesha cerca libprocps, assente in trixie
    -DALLOCATOR=${ALLOCATOR} \
    -DENABLE_VFS_POSIX_ACL=${ENABLE_ACL} \
    -DENABLE_RFC_ACL=${ENABLE_ACL} \
    ../src/ && \
  make -j"$(nproc)" && \
  make install DESTDIR=/out && \
  install -D -m644 ../src/scripts/ganeshactl/org.ganesha.nfsd.conf /out/etc/dbus-1/system.d/org.ganesha.nfsd.conf && \
  rm -rf /out/usr/include /out/usr/share/doc /out/usr/lib/systemd /out/etc/sysconfig /out/etc/logrotate.d

#### runtime stage
FROM ${IMAGE_FROM}

LABEL maintainer="Ugo Viti <ugo.viti@initzero.it>"

ARG APP_VER
ARG NTIRPC_VERSION
ARG ALLOCATOR

ENV APP_NAME        "nfs-ganesha"
ENV APP_DESCRIPTION "NFS-Ganesha Userspace NFS File Server"

## set internal variables using defined args
ENV APP_VER             ${APP_VER}
ENV NFS_GANESHA_VERSION ${APP_VER}
ENV NTIRPC_VERSION      ${NTIRPC_VERSION}

# NFS daemon configuration
ENV EXPORT_PATH "/exports"

# debian: install runtime software
RUN set -eux && \
  apt-get update && apt-get upgrade -y && \
  apt-get install -y --no-install-recommends \
    tini \
    netbase \
    procps \
    psmisc \
    rsync \
    e2fsprogs \
    acl \
    nfs-common \
    rpcbind \
    dbus \
    libjemalloc2 \
    liburcu8t64 \
    libnfsidmap1 \
    libcap2 \
    libblkid1 \
    libuuid1 \
    libacl1 \
    libdbus-1-3 \
    libssl3t64 \
  && \
  # mkdir default export directory
  mkdir -p ${EXPORT_PATH} && \
  # fix missing directories
  mkdir -p /var/run/ganesha /var/lib/nfs/ganesha && \
  # fix missing /etc/mtab
  rm -f /etc/mtab && \
  ln -s /proc/mounts /etc/mtab && \
  # cleanup system
  rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=build /out/ /

# verify that all libraries are resolved
RUN set -eux && \
  ldconfig && \
  ! ldd /usr/bin/ganesha.nfsd /usr/lib/ganesha/*.so | grep "not found" && \
  /usr/bin/ganesha.nfsd -v

# APP volumes
VOLUME ["${EXPORT_PATH}"]

# APP ports (nfs, rpcbind, mountd, nlm, prometheus metrics)
EXPOSE 2049 111 111/udp 20048 32803 9587

# container pre-entrypoint variables
ENV ENTRYPOINT_TINI "true"
ENV UMASK           0002

# add files to container
ADD Dockerfile filesystem README.md /

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
