ARG image_from="debian:buster-slim"
FROM ${image_from}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP_NAME        "nfs-ganesha"
ENV APP_DESCRIPTION "NFS-Ganesha is an NFSv3,v4,v4.1 fileserver that runs in user mode on most UNIX/Linux systems"

# default version vars
ARG tag_ver_major=2
ARG tag_ver_minor=8
ARG tag_ver_patch=2
ARG tag_ver=${tag_ver_major}.${tag_ver_minor}.${tag_ver_patch}

# nfs ganesha version vars
ENV NFS_GANESHA_VERSION_MAJOR=${tag_ver_major}
ENV NFS_GANESHA_VERSION_MINOR=${tag_ver_minor}
ENV NFS_GANESHA_VERSION_PATCH=${tag_ver_patch}

ENV NFS_GANESHA_VERSION        ${tag_ver}
ENV NTIRPC_VERSION             1.8.0
# for ganesha 2.6.x
#ENV NTIRPC_VERSION             1.6.3

#ENV TINI_VERSION               0.18.0

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
  # install tini
 #  && wget -q https://github.com/krallin/tini/releases/download/v$TINI_VERSION/tini_$TINI_VERSION-amd64.deb \
#  && dpkg -i tini_$TINI_VERSION-amd64.deb \
#  && rm -f tini_$TINI_VERSION-amd64.deb \
  # mkdir default export directory
  && mkdir -p ${EXPORT_PATH} \
  # cleanup system
  && rm -rf /var/lib/apt/lists/*

# Alpine: install extra software (TEST)
#RUN set -xe \
#  && apk upgrade --update --no-cache \
#  && apk add \
#    tini \
#    bash \
#    e2fsprogs-extra \
#    acl \
#    rsync \
#    nfs-utils \
#    jemalloc \
#    libnsl \
#    krb5 \
#    libcap \
#    libnsl \
#  && rm -rf /var/cache/apk/* /tmp/*

# Alpine: compile nfs-ganesha (TEST)
#RUN set -xe \
#  && apk add --virtual .build-deps \
#    curl \
#    git \
#    build-base \
#    cmake \
#    bison \
#    flex \
#    krb5-dev \
#    libcap-dev \
#    samba-dev \
#    xfsprogs-dev \
#    doxygen \
#    jemalloc-dev \
#    libnsl-dev \

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
