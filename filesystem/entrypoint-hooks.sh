#!/bin/sh
set -e

# entrypoint hooks
hooks_always() {

# environment variables
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
#: ${CLIENT_LIST:="*"}
: ${CLIENT_LIST:="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"}
: ${DISABLE_ACL:=false}
: ${ANON_USER:="nobody"}
: ${ANON_GROUP:="nogroup"}
: ${GANESHA_CONFIG:="/etc/ganesha/ganesha.conf"}
: ${GANESHA_LOGFILE:="/dev/stdout"}
: ${LOG_LEVEL:="INFO"}
: ${LOG_COMPONENT:="ALL=INFO;"}

# nfs config requirements
: ${IDMAP_DOMAIN:="$(hostname -d)"}
[ -z "${IDMAP_DOMAIN}" ] && IDMAP_DOMAIN="$HOSTNAME"

echo "=> Configuring NFS Ganesha Server..."

bootstrap_idmap() {
    echo "--> Bootstrapping idmap config"
    cat<<END > /etc/idmapd.conf
[General]
Domain = ${IDMAP_DOMAIN}

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup

[Translation]
Method = nsswitch
END

}

init_rpc() {
    echo "--> Starting rpc services"
    if [ ! -x /run/rpcbind ] ; then
        # debian
        install -m755 -g root -o root -d /run/rpcbind
        touch /run/rpcbind/rpcbind.xdr /run/rpcbind/portmap.xdr
    fi
    rpcbind || return 0
    rpc.statd -L || return 0

    # not needed with ganesha
    # rpc.gssd || return 0
    # rpc.idmapd || return 0
    sleep 0.5
}

init_dbus() {
    echo "--> Starting dbus"
    if [ ! -x /var/run/dbus ] ; then
        # debian
        install -m755 -g messagebus -o messagebus -d /var/run/dbus
        # redhat
        #install -m755 -g dbus -o dbus -d /var/run/dbus
    fi
    rm -f /var/run/dbus/*
    rm -f /var/run/messagebus.pid
    dbus-uuidgen --ensure
    dbus-daemon --system --fork
    sleep 0.5
}

# pNFS
# Ganesha by default is configured as pNFS DS.
# A full pNFS cluster consists of multiple DS
# and one MDS (Meta Data server). To implement
# this one needs to deploy multiple Ganesha NFS
# and then configure one of them as MDS:
# GLUSTER { PNFS_MDS = ${WITH_PNFS}; }

bootstrap_config() {
    echo "--> Writing configuration"
    cat <<END >${GANESHA_CONFIG}

# https://www.mankier.com/8/ganesha-log-config
# the log levels are: NULL, FATAL, MAJ, CRIT, WARN, EVENT, INFO, DEBUG, MID_DEBUG, M_DBG, FULL_DEBUG, F_DBG
# other examples: http://docs.ceph.com/docs/master/radosgw/nfs/

LOG {
    Default_Log_Level = ${LOG_LEVEL};

    Components {
      #ALL = DEBUG;
      MEMLEAKS = FATAL;
      FSAL = FATAL;
      NFSPROTO = FATAL;
      NFS_V4 = FATAL;
      EXPORT = FATAL;
      FILEHANDLE = FATAL;
      DISPATCH = FATAL;
      CACHE_INODE = FATAL;
      CACHE_INODE_LRU = FATAL;
      HASHTABLE = FATAL;
      HASHTABLE_CACHE = FATAL;
      DUPREQ = FATAL;
      INIT = DEBUG;
      MAIN = DEBUG;
      IDMAPPER = FATAL;
      NFS_READDIR = FATAL;
      NFS_V4_LOCK = FATAL;
      CONFIG = FATAL;
      CLIENTID = FATAL;
      SESSIONS = FATAL;
      PNFS = FATAL;
      RW_LOCK = FATAL;
      NLM = FATAL;
      RPC = FATAL;
      NFS_CB = FATAL;
      THREAD = FATAL;
      NFS_V4_ACL = FATAL;
      STATE = FATAL;
      FSAL_UP = FATAL;
      DBUS = FATAL;
      ${LOG_COMPONENT}
    }

    Format {
      date_format = ISO-8601;
      time_format = ISO-8601;
      EPOCH = FALSE;
      CLIENTIP = TRUE;
      HOSTNAME = TRUE;
      PID = FALSE;
      THREAD_NAME = FALSE;
      FILE_NAME = FALSE;
      LINE_NUM = FALSE;
      FUNCTION_NAME = FALSE;
      COMPONENT = TRUE;
      LEVEL = TRUE;
    }
}

NFSV4 {
    Graceless = ${GRACELESS};
    Grace_Period = ${GRACE_PERIOD};
    Allow_Numeric_Owners = true;
    Only_Numeric_Owners = true;
}

# test 20180831
NFS_Core_Param
{
    MNT_Port = 20048;
    fsid_device = true;
}


EXPORT {
    # Export Id (mandatory, each EXPORT must have a unique Export_Id)
    Export_Id = ${EXPORT_ID};

    # Exported path (mandatory)
    Path = "${EXPORT_PATH}";

    # Pseudo Path (required for NFS v4)
    Pseudo = "${PSEUDO_PATH}";

    # Access control options
    Access_type = NONE;
    Squash = ${SQUASH_MODE};

    # NFS protocol options
    Transports = ${TRANSPORTS};
    Protocols = ${PROTOCOLS};
    SecType = ${SEC_TYPE};
    Disable_ACL = ${DISABLE_ACL};
    # changed to false, otherwise normal users can't access directories where gid=0
    Manage_Gids = false;

    #to test disable getattr cache
    #Attr_Expiration_Time = 0;

    Anonymous_uid = $(id -u $ANON_USER);
    Anonymous_gid = $(awk -F: '/^'$ANON_GROUP':/ { print $3 }' /etc/group);

    CLIENT {
        Clients = ${CLIENT_LIST};
        Access_Type = ${ACCESS_TYPE};
    }

    # Exporting FSAL
    FSAL {
        name = VFS;
    }
}

END
}

if [ ! -f ${EXPORT_PATH} ]; then
    mkdir -p "${EXPORT_PATH}"
fi

echo "Initializing Ganesha NFS server"
echo "=================================="
echo "export path: ${EXPORT_PATH}"
echo "=================================="

bootstrap_config
bootstrap_idmap
init_rpc
init_dbus

echo "Generated NFS-Ganesha config:"
cat ${GANESHA_CONFIG}

echo "--> Starting NFS Ganesha"
exec /usr/bin/ganesha.nfsd -F -L ${GANESHA_LOGFILE} -f ${GANESHA_CONFIG}
}

hooks_always
