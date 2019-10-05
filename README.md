# Description
NFS-Ganesha is a user-mode file server for NFS (v3, 4.0, 4.1, 4.1 pNFS, 4.2)

# Supported tags
-	`2.8.X-BUILD`, `2.8.X`, `2.8`, `2`, `latest`

Where **X** is the patch version number, and **BUILD** is the build number (look into project [Tags](/repository/docker/izdock/nfs-ganesha/tags/) page to discover the latest versions)

# Dockerfile
- https://github.com/ugoviti/izdock/blob/master/nfs-ganesha/Dockerfile

# Features
- Small image footprint based on [Debian 9 (stretch) Slim](https://hub.docker.com/_/debian/)
- NFS Ganesha binaries are taken from upstream official repository
- Using [tini](https://github.com/krallin/tini) as init process
- Many customizable variables to use

# What is nfs-ganesha?
Nfs-ganesha is a user-mode file server for NFS (v3, 4.0, 4.1, 4.1 pNFS, 4.2) and for 9P from the Plan9 operating system. It can support all these protocols concurrently.
This is an Open Source project with an active community of both company sponsored and independent developers.

# How to use this image.

This image only contains nfs-ganesha from [official home page](https://github.com/nfs-ganesha/nfs-ganesha)
and from [official download repository](https://download.nfs-ganesha.org/)

# Environment variables
You can change the default behaviour using the following variables (with default values):

: ${EXPORT_PATH:="/exports"}
: ${PSEUDO_PATH:="/exports"}
: ${EXPORT_ID:=1}
: ${PROTOCOLS:=4}
: ${TRANSPORTS:="UDP, TCP"}
: ${SEC_TYPE:="sys"}
: ${SQUASH_MODE:="No_Root_Squash"}
: ${GRACELESS:=false}
: ${GRACE_PERIOD:=90}
: ${ACCESS_TYPE:="RW"}
: ${CLIENT_LIST:="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"}
: ${DISABLE_ACL:=false}
: ${ANON_USER:="nobody"}
: ${ANON_GROUP:="nogroup"}
: ${GANESHA_CONFIG:="/etc/ganesha/ganesha.conf"}
: ${GANESHA_LOGFILE:="/dev/stdout"}
: ${LOG_LEVEL:="INFO"}
: ${LOG_COMPONENT:="ALL=INFO;"}

### Create a `Dockerfile` in your project

```dockerfile
FROM izdock/nfs-ganesha
# your commands here
```

Then, run the commands to build and run the Docker image:

```console
$ docker build -t nfs-ganesha .
$ docker run -dit --name nfs-ganesha -p 2049:2049 -p 111:111 nfs-ganesha
```

### Without a `Dockerfile`

If you don't want to include a `Dockerfile` in your project, it is sufficient to do the following:

```$ docker run -dit --name my-nfs -p 2049:2049 -p 111:111 -v "/tmp/testvolme":/data izdock/nfs-ganesha```

### Configuration

To customize the configuration of nfs-ganesha, just change the default variables:

```docker run -dit --name my-nfs -p 2049:2049 -p 111:111 -v "/tmp/testvolme":/data -e CLIENT_LIST="192.168.1.1, 192.168.1.23" -e LOG_LEVEL=DEBUG izdock/nfs-ganesha```

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
