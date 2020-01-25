ARG IMAGE_FROM="debian:buster-slim"
FROM ${IMAGE_FROM}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP_NAME        "nfs-ganesha"
ENV APP_DESCRIPTION "NFS-Ganesha is an NFSv3, v4, v4.1 fileserver that runs in user mode on most UNIX/Linux systems"

# https://github.com/nfs-ganesha/nfs-ganesha/releases
# default version vars
ARG TAG_VER_MAJOR=3
ARG TAG_VER_MINOR=2
#ARG TAG_VER_PATCH=0
#ARG TAG_VER=${TAG_VER_MAJOR}.${TAG_VER_MINOR}.${TAG_VER_PATCH}
ARG TAG_VER=${TAG_VER_MAJOR}.${TAG_VER_MINOR}

# nfs ganesha version vars
ENV NFS_GANESHA_VERSION_MAJOR=${TAG_VER_MAJOR}
ENV NFS_GANESHA_VERSION_MINOR=${TAG_VER_MINOR}
#ENV NFS_GANESHA_VERSION_PATCH=${TAG_VER_PATCH}

ENV NFS_GANESHA_VERSION        ${TAG_VER}
# https://github.com/nfs-ganesha/ntirpc/releases
# for ganesha 3.0.x
ENV NTIRPC_VERSION             ${TAG_VER_MAJOR}.${TAG_VER_MINOR}

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
  # install nfs-ganesha
  # 2.6.x path
#  && echo "deb https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MAJOR}.${NFS_GANESHA_VERSION_MINOR}/${NFS_GANESHA_VERSION}/Debian/stretch/amd64/apt stretch main" > /etc/apt/sources.list.d/nfs-ganesha.list \
#  \
#  # 2.5.x path
#  #&& echo "deb https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MAJOR}.${NFS_GANESHA_VERSION_MINOR}/${NFS_GANESHA_VERSION}/Debian/stretch/apt stretch main" > /etc/apt/sources.list.d/nfs-ganesha.list \
#  \
#  && curl -s "https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MAJOR}.${NFS_GANESHA_VERSION_MINOR}/rsa.pub" | apt-key add - \
#  && apt-get update \
#  && apt-get install -y \
#    nfs-ganesha \
#    nfs-ganesha-vfs \
  # mkdir default export directory
  && mkdir -p ${EXPORT_PATH} \
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
  " \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends -V $buildDeps \
  # download official nfs-ganesha sources from github
  && mkdir -p /usr/src/ \
## test download release
  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/nfs-ganesha/archive/V${NFS_GANESHA_VERSION}.tar.gz | tar xz -C /usr/src/ \
  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/ntirpc/archive/v${NTIRPC_VERSION}.tar.gz | tar xz --strip-components=1 -C /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION}/src/libntirpc/ \
  && cd /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION} \
  && mkdir -p build && cd build \
  # -DALLOCATOR=(jemalloc|tcmalloc|libc) # il default jemalloc genera Segmentation Faults?
  && cmake -DCMAKE_BUILD_TYPE=Release -Wno-dev -DUSE_9P=OFF -DUSE_FSAL_CEPH=OFF -DUSE_FSAL_GLUSTER=OFF -DUSE_FSAL_LUSTRE=OFF -DUSE_FSAL_XFS=OFF -DUSE_FSAL_RGW=OFF -DRADOS_URLS=OFF -DUSE_RADOS_RECOV=OFF -D_MSPAC_SUPPORT=OFF -DUSE_GSS=ON -DUSE_FSAL_LUSTRE=OFF -DALLOCATOR=libc ../src/ \
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

# add files to container
ADD Dockerfile filesystem VERSION README.md /

# entrypoint
ENTRYPOINT ["tini", "-g", "--"]
CMD ["/entrypoint.sh"]
