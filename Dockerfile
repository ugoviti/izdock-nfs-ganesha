# docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=fffffff --build-arg APP_BUILD_DATE=$(date +%s) -t nfs-ganesha .
# docker run --rm --name nfs-ganesha -v /tmp/data:/data nfs-ganesha

ARG IMAGE_FROM="debian:buster-slim"
FROM ${IMAGE_FROM}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP_NAME        "nfs-ganesha"
ENV APP_DESCRIPTION "NFS-Ganesha Userspace NFS File Server"

# https://github.com/nfs-ganesha/nfs-ganesha/releases
# default version vars
ARG APP_VER_MAJOR=3
ARG APP_VER_MINOR=3
#ARG APP_VER_PATCH=0

#ARG APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}.${APP_VER_PATCH}
ARG APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}
ENV APP_VER=${APP_VER}

# nfs ganesha version vars
ENV NFS_GANESHA_VERSION_MAJOR=${APP_VER_MAJOR}
ENV NFS_GANESHA_VERSION_MINOR=${APP_VER_MINOR}
#ENV NFS_GANESHA_VERSION_PATCH=${APP_VER_PATCH}

ENV NFS_GANESHA_VERSION        ${APP_VER}
# https://github.com/nfs-ganesha/ntirpc/releases
# for ganesha 3.0.x
ENV NTIRPC_VERSION             ${APP_VER_MAJOR}.${APP_VER_MINOR}

# for ganesha 2.8.x
#ENV NTIRPC_VERSION             1.8.0

# for ganesha 2.6.x
#ENV NTIRPC_VERSION             1.6.3

# NFS daemon configuration
ENV EXPORT_PATH "/exports"

# Debian: install needed software
RUN set -xe \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    tini \
    apt-transport-https \
    ca-certificates \
    netbase \
    wget \
    curl \
    gnupg \
    procps \
    net-tools \
    rsync \
    e2fsprogs \
    acl \
    nfs-common \
    psmisc \
    dbus \
    libjemalloc2 \
    liburcu6 \
    fuse \
    libcrcutil0 \
    libfuse2 \
    libisal2 \
    xfsprogs \
  # mkdir default export directory
  && mkdir -p ${EXPORT_PATH} \
  # fix missing /etc/mtab
  && ln -s /proc/mounts /etc/mtab \
  # cleanup system
  && rm -rf /var/lib/apt/lists/*

# Debian: compile nfs-ganesha (TEST)
RUN set -eux \
	&& buildDeps=" \
    git \
    curl \
    bison \
    flex \
    build-essential \
    libglu1-mesa-dev \
    libc6-dev \
    g++ \
    libboost-dev \
    doxygen \
    libjemalloc-dev \
    libkrb5-dev \
    libcap-dev \
    gcc \
    make \
    cmake \
    libbison-dev \
    pkg-config \
    libfl-dev \
    libnfsidmap-dev \
    libdbus-1-dev \
    libblkid-dev \
    liburcu-dev \
    xfslibs-dev \
    python3-distutils \
  " \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends -V $buildDeps \
  # download official nfs-ganesha sources from github
  && mkdir -p /usr/src/ \
  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/nfs-ganesha/archive/V${NFS_GANESHA_VERSION}.tar.gz | tar xz -C /usr/src/ \
  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/ntirpc/archive/v${NTIRPC_VERSION}.tar.gz | tar xz --strip-components=1 -C /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION}/src/libntirpc/ \
  && cd /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION} \
  && mkdir -p build && cd build \
  # -DALLOCATOR=(jemalloc|tcmalloc|libc) # il default jemalloc genera Segmentation Faults?
  && cmake -DCMAKE_BUILD_TYPE=Release -Wno-dev -DUSE_9P=OFF -DUSE_FSAL_CEPH=OFF -DUSE_FSAL_GLUSTER=OFF -DUSE_FSAL_LUSTRE=OFF -DUSE_FSAL_LIZARDFS=OFF -DUSE_FSAL_XFS=ON -DUSE_FSAL_RGW=OFF -DRADOS_URLS=OFF -DUSE_RADOS_RECOV=OFF -D_MSPAC_SUPPORT=OFF -DUSE_GSS=ON -DUSE_FSAL_LUSTRE=OFF -DALLOCATOR=libc ../src/ \
  && make \
  && make install \
  \
  && cp /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION}/src/scripts/ganeshactl/org.ganesha.nfsd.conf /etc/dbus-1/system.d/ \
  && apt-get purge -y --auto-remove $buildDeps \
  && rm -r /var/lib/apt/lists/* /usr/src/*

# APP volumes
VOLUME ["${EXPORT_PATH}"]

# APP ports
EXPOSE 111 111/udp 2049 20048 38465-38467

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
