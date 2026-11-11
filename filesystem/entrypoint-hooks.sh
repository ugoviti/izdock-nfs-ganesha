#!/bin/sh
set -e

# environment variables
: ${EXPORT_PATH:="/exports"}
: ${PSEUDO_PATH:="/exports"}
: ${EXPORT_ID:=1}
# 4 = solo NFSv4 (minor version in NFSV4_MINOR_VERSIONS); "3, 4" per abilitare anche NFSv3
: ${PROTOCOLS:=4}
# NFSv4 funziona solo su TCP; da ganesha 14 NFS non ascolta piu' su UDP
: ${TRANSPORTS:="TCP"}
: ${NFSV4_MINOR_VERSIONS:="0, 1, 2"}
: ${SEC_TYPE:="sys"}
: ${SQUASH_MODE:="No_Root_Squash"}
: ${GRACELESS:=false}
: ${GRACE_PERIOD:=90}
: ${LEASE_LIFETIME:=60}
# fs = stato dei client in /var/lib/nfs/ganesha (persiste solo se e' un volume); none = nessuna recovery
: ${RECOVERY_BACKEND:="fs"}
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

# NLM (lock NFSv3) e rquota servono solo con NFSv3
case "${PROTOCOLS}" in
  *3*) : ${ENABLE_NLM:=true} ;;
  *)   : ${ENABLE_NLM:=false} ;;
esac
: ${ENABLE_RQUOTA:=false}
# rpc.statd (stato dei lock NFSv3) su porte fisse, come le espone il Service:
# con una porta casuale il recupero dei lock dietro un ClusterIP non funziona
: ${STATD_PORT:=662}
: ${STATD_OUTGOING_PORT:=2020}

# traduzione nomi <-> uid/gid (idmapping). Con AUTH_SYS e Only_Numeric_Owners i client
# usano gli id numerici: false evita le ricerche nsswitch per ogni owner
# ("ls -l" di 20000 file: 0.45s invece di 0.58s, owner identici). true con sec=krb5
: ${IDMAPPING_ACTIVE:=false}

# jemalloc: un thread in background restituisce al sistema la memoria liberata anche
# quando il server e' fermo (di default lo fa solo durante nuove allocazioni)
: ${MALLOC_CONF:="background_thread:true"}
export MALLOC_CONF

# PR_SET_IO_FLUSHER evita il deadlock con client NFS sullo stesso nodo sotto pressione di memoria.
# Richiede CAP_SYS_RESOURCE: con false ganesha non parte se manca (meglio di perdere la protezione in silenzio)
: ${ALLOW_SET_IO_FLUSHER_FAIL:=false}

# metriche prometheus su http://<pod>:9587/metrics
: ${ENABLE_METRICS:=true}
: ${MONITORING_PORT:=9587}

# prestazioni (verificate nel codice V15.11, vedi README)
: ${READDIR_RES_SIZE:=1048576}          # byte massimi di una risposta READDIR NFSv4. Default upstream 32 KiB:
                                        # walk di 50000 file 2.3s invece di 1.4s; 1 MiB = quanto chiede il client (come la 3.4)
: ${ENABLE_DYNAMIC_METRICS:=false}      # metriche per client/export: un mutex e allocazioni per ogni READ/WRITE/LOOKUP;
                                        # le metriche del server (rpcs_*, threads, compound) restano
: ${RPC_IOQ_THRDMIN:=2}                 # thread di servizio inattivi tenuti pronti
: ${RPC_IOQ_THRDMAX:=200}               # thread di servizio massimi (= richieste in esecuzione insieme)
: ${ATTR_EXPIRATION_TIME:=60}           # secondi di validita' degli attributi in cache (-1 = finche' ganesha non li cambia)
: ${TRUST_READDIR_NEGATIVE_CACHE:=false} # LOOKUP di file inesistenti risolte dalla cache delle directory

# limiti della cache metadati (MDCACHE). Entries_HWMark e' una soglia "morbida":
# le entry referenziate (file aperti, chunk di directory) possono superarla.
: ${MDCACHE_ENTRIES_HWMARK:=100000}
: ${MDCACHE_ENTRIES_RELEASE_SIZE:=100}
: ${MDCACHE_CHUNKS_HWMARK:=1000}
: ${MDCACHE_CHUNKS_LWMARK:=500}
: ${MDCACHE_DIR_CHUNK:=128}
: ${MDCACHE_LRU_RUN_INTERVAL:=90}

# nfs config requirements
: ${IDMAP_DOMAIN:="$(hostname -d)"}
[ -z "${IDMAP_DOMAIN}" ] && IDMAP_DOMAIN="$(hostname)"

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
    # rpc.statd serve solo ai lock NFSv3 (NLM)
    if [ "${ENABLE_NLM}" = "true" ]; then
        rpc.statd -L -p "${STATD_PORT}" -o "${STATD_OUTGOING_PORT}" || return 0
    fi

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

# livelli di default dei componenti di log. Da ganesha 6 un componente scritto due volte
# e' un errore fatale: quelli presenti in LOG_COMPONENT sostituiscono il default.
# Se LOG_COMPONENT contiene ALL i default non vengono scritti (ALL vale per tutti).
LOG_COMPONENT_DEFAULTS="MEMLEAKS=FATAL; FSAL=FATAL; NFSPROTO=FATAL; NFS_V4=FATAL; EXPORT=FATAL;
  FILEHANDLE=FATAL; DISPATCH=FATAL; MDCACHE=FATAL; MDCACHE_LRU=FATAL; HASHTABLE=FATAL;
  HASHTABLE_CACHE=FATAL; DUPREQ=FATAL; INIT=DEBUG; MAIN=DEBUG; IDMAPPER=FATAL; NFS_READDIR=FATAL;
  NFS_V4_LOCK=FATAL; CONFIG=FATAL; CLIENTID=FATAL; SESSIONS=FATAL; PNFS=FATAL; RW_LOCK=FATAL;
  NLM=FATAL; XPRT=FATAL; NFS_CB=FATAL; THREAD=FATAL; NFS_V4_ACL=FATAL; STATE=FATAL; FSAL_UP=FATAL;
  DBUS=FATAL;"

log_components() {
    # nomi richiesti in LOG_COMPONENT, in maiuscolo (es. "ALL=INFO;CLIENTID=DEBUG;" -> " ALL CLIENTID ")
    wanted=" $(echo "${LOG_COMPONENT}" | tr ';' '\n' | sed -n 's/^[[:space:]]*\([A-Za-z_0-9]*\)[[:space:]]*=.*/\1/p' | tr 'a-z' 'A-Z' | tr '\n' ' ') "
    case "$wanted" in
      *" ALL "*) ;;
      *)
        echo "${LOG_COMPONENT_DEFAULTS}" | tr ';' '\n' | while IFS='=' read -r name level; do
            name=$(echo "$name" | tr -d '[:space:]')
            [ -z "$name" ] && continue
            case "$wanted" in *" $name "*) continue ;; esac
            echo "      ${name} = $(echo "$level" | tr -d '[:space:]');"
        done
        ;;
    esac
    echo "${LOG_COMPONENT}" | tr ';' '\n' | while IFS='=' read -r name level; do
        name=$(echo "$name" | tr -d '[:space:]' | tr 'a-z' 'A-Z')
        [ -z "$name" ] && continue
        echo "      ${name} = $(echo "$level" | tr -d '[:space:]');"
    done
}

bootstrap_config() {
    echo "--> Writing configuration"
    cat <<END >${GANESHA_CONFIG}

# https://www.mankier.com/8/ganesha-log-config
# the log levels are: NULL, FATAL, MAJ, CRIT, WARN, EVENT, INFO, DEBUG, MID_DEBUG, M_DBG, FULL_DEBUG, F_DBG
# other examples: http://docs.ceph.com/docs/master/radosgw/nfs/

LOG {
    Default_Log_Level = ${LOG_LEVEL};

    Components {
$(log_components)
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

# test 20180831 (questo sembra far perdere tutti i mount points ai clients dopo che è stato riavviato il server nfs: Could not map fsid=0 to filesystem)
#NFS_Core_Param
#{
#    MNT_Port = 20048;
#    fsid_device = true;
#}

# test 20200810
NFS_Core_Param
{
    Protocols = ${PROTOCOLS};
    MNT_Port = 20048;
    NLM_Port = 32803;
    fsid_device = false;
    Enable_NLM = ${ENABLE_NLM};
    Enable_RQUOTA = ${ENABLE_RQUOTA};
    Allow_Set_Io_Flusher_Fail = ${ALLOW_SET_IO_FLUSHER_FAIL};
    Enable_Metrics = ${ENABLE_METRICS};
    Enable_Dynamic_Metrics = ${ENABLE_DYNAMIC_METRICS};
    Monitoring_Port = ${MONITORING_PORT};
    Readdir_Res_Size = ${READDIR_RES_SIZE};
    RPC_Ioq_ThrdMin = ${RPC_IOQ_THRDMIN};
    RPC_Ioq_ThrdMax = ${RPC_IOQ_THRDMAX};
}

NFSV4 {
    Graceless = ${GRACELESS};
    Grace_Period = ${GRACE_PERIOD};
    Lease_Lifetime = ${LEASE_LIFETIME};
    Minor_Versions = ${NFSV4_MINOR_VERSIONS};
    RecoveryBackend = ${RECOVERY_BACKEND};
    Allow_Numeric_Owners = true;
    Only_Numeric_Owners = true;
}

DIRECTORY_SERVICES {
    Idmapping_Active = ${IDMAPPING_ACTIVE};
}

MDCACHE {
    Entries_HWMark = ${MDCACHE_ENTRIES_HWMARK};
    Entries_Release_Size = ${MDCACHE_ENTRIES_RELEASE_SIZE};
    Chunks_HWMark = ${MDCACHE_CHUNKS_HWMARK};
    Chunks_LWMark = ${MDCACHE_CHUNKS_LWMARK};
    Dir_Chunk = ${MDCACHE_DIR_CHUNK};
    LRU_Run_Interval = ${MDCACHE_LRU_RUN_INTERVAL};
}

EXPORT {
    # Export Id (mandatory, each EXPORT must have a unique Export_Id)
    Export_Id = ${EXPORT_ID};

    # Exported path (mandatory)
    Path = "${EXPORT_PATH}";

    # Pseudo Path (required for NFS v4)
    Pseudo = "${PSEUDO_PATH}";

    # Access control options
    Access_Type = NONE;
    #Access_Type = ${ACCESS_TYPE};
    Squash = ${SQUASH_MODE};

    # NFS protocol options
    Transports = ${TRANSPORTS};
    Protocols = ${PROTOCOLS};
    SecType = ${SEC_TYPE};
    Disable_ACL = ${DISABLE_ACL};

    # changed to false, otherwise normal users can't access directories where gid=0
    Manage_Gids = false;

    # validita' degli attributi in cache e cache negativa delle LOOKUP
    Attr_Expiration_Time = ${ATTR_EXPIRATION_TIME};
    Trust_Readdir_Negative_Cache = ${TRUST_READDIR_NEGATIVE_CACHE};

    Anonymous_uid = $(id -u $ANON_USER);
    Anonymous_gid = $(awk -F: '/^'$ANON_GROUP':/ { print $3 }' /etc/group);

    CLIENT {
      Clients = ${CLIENT_LIST};
      Access_Type = ${ACCESS_TYPE};
      Protocols = ${PROTOCOLS};
    }

    Filesystem_id = 1.1;

    # Exporting FSAL
    FSAL {
      name = VFS;
    }
}
END
}

if [ ! -d "${EXPORT_PATH}" ]; then
    mkdir -p "${EXPORT_PATH}"
fi

mkdir -p /var/lib/nfs/ganesha

# fix not existing /etc/mtab
[ ! -e "/etc/mtab" ] && ln -s /proc/mounts /etc/mtab

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
