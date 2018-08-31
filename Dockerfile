ARG image_from="debian:9.5-slim"
FROM ${image_from}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

ENV APP_NAME    "nfs-ganesha"

ARG NFS_GANESHA_VERSION_MIN="2.6"
ARG NFS_GANESHA_VERSION="2.6.3"
ARG TINI_VERSION="0.18.0"

# NFS daemon configuration
ENV EXPORT_PATH "/data"

# Debian: install needed software
RUN set -xe \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
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
  # install nfs-ganesha
  # 2.6.x path
  && echo "deb https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MIN}/${NFS_GANESHA_VERSION}/Debian/stretch/amd64/apt stretch main" > /etc/apt/sources.list.d/nfs-ganesha.list \
  # 2.5.x path
#  && echo "deb https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MIN}/${NFS_GANESHA_VERSION}/Debian/stretch/apt stretch main" > /etc/apt/sources.list.d/nfs-ganesha.list \
  && curl -s "https://download.nfs-ganesha.org/${NFS_GANESHA_VERSION_MIN}/rsa.pub" | apt-key add - \
#  && apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/nfs-ganesha.list \
  && apt-get update \
  && apt-get install -y \
    nfs-ganesha \
    nfs-ganesha-vfs \
  # install tini
  && wget -q https://github.com/krallin/tini/releases/download/v$TINI_VERSION/tini_$TINI_VERSION-amd64.deb \
  && dpkg -i tini_$TINI_VERSION-amd64.deb \
  && rm -f tini_$TINI_VERSION-amd64.deb \
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
#RUN set -xe \
#	&& apt-get update \
#	&& apt-get install -y --no-install-recommends -V \
#    git \
#    curl \
#    build-essential \
#    libglu1-mesa-dev \
#    libc6-dev \
#    g++ \
#    libboost-dev \
#    doxygen \
#    libjemalloc-dev \
#    libkrb5-dev \
#    libcap-dev \
#    gcc \
#    make \
  # download official nfs-ganesha sources from github
#  && mkdir -p /usr/src/ \
#  && git clone --branch v${NFS_GANESHA_VERSION} --single-branch --depth 1 git://github.com/nfs-ganesha/nfs-ganesha.git /usr/src/nfs-ganesha \
#  && cd /usr/src/nfs-ganesha \
#  && git submodule update --init \
#  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/nfs-ganesha/archive/V${NFS_GANESHA_VERSION}.tar.gz | tar xz -C /usr/src/ \
#  && cd /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION} \
#  && mkdir build && cd build \
#  && cmake -DCMAKE_BUILD_TYPE=Release -Wno-dev ../src/
#  && git clone -o ${NFS_GANESHA_VERSION} --depth 1 git://github.com/nfs-ganesha/nfs-ganesha.git /usr/src/nfs-ganesha \
#  && git checkout V${NFS_GANESHA_VERSION} \
#  && curl -fSL --connect-timeout 30 https://github.com/nfs-ganesha/nfs-ganesha/archive/V${NFS_GANESHA_VERSION}.tar.gz | tar xz -C /usr/src/ \
#  && cd /usr/src/nfs-ganesha-${NFS_GANESHA_VERSION}/build \
#  && rm -r /var/lib/apt/lists/*

# APP volumes
VOLUME ["${EXPORT_PATH}"]

# APP ports
EXPOSE 111 111/udp 662 2049 38465-38467

# add files to container
ADD Dockerfile filesystem /

# entrypoint
ENTRYPOINT ["tini", "-g", "--"]
CMD ["/entrypoint.sh"]

ENV APP_VER "2.6.3-12"
