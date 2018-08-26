#!/bin/sh
# initzero docker entrypoint generic script
# written by Ugo Viti <ugo.viti@initzero.it>
# 20180814

#set -x

app_pre_hooks() {
: ${APP_RELINK:=0}
: ${APP_NAME:=CHANGEME}
: ${APP_VER:=0}
echo "=> Starting container: $APP_NAME:$APP_VER"

# verify if exist custom directory overrides
if [ $APP_RELINK = 1 ]; then
[ ! -z "${APP_CONF}" ] && relink_dir "${APP_CONF_DEFAULT}" "${APP_CONF}"
[ ! -z "${APP_DATA}" ] && relink_dir "${APP_DATA_DEFAULT}" "${APP_DATA}"
[ ! -z "${APP_LOGS}" ] && relink_dir "${APP_LOGS_DEFAULT}" "${APP_LOGS}"
[ ! -z "${APP_TEMP}" ] && relink_dir "${APP_TEMP_DEFAULT}" "${APP_TEMP}"
[ ! -z "${APP_WORK}" ] && relink_dir "${APP_WORK_DEFAULT}" "${APP_WORK}"
[ ! -z "${APP_SHARED}" ] && relink_dir "${APP_SHARED_DEFAULT}" "${APP_SHARED}"
else
  echo "Skipping APP directories relinking"
fi
}

app_post_hooks() {
/entrypoint-hooks.sh
}

# if required move configurations and webapps dirs to custom directory
relink_dir() {
	local dir_default="$1"
	local dir_custom="$2"

	# make destination dir if not exist
	[ ! -e "$dir_default" ] && mkdir -p "$dir_default"
	[ ! -e "$(dirname "$dir_custom")" ] && mkdir -p "$(dirname "$dir_custom")"

	echo "$APP directory container override detected! default: $dir_default custom: $dir_custom"
	if [ ! -e "$dir_custom" ]; then
		echo -e -n "=> moving the $dir_default directory to $dir_custom ..."
		mv "$dir_default" "$dir_custom"
	else
		echo -e -n "=> directory $dir_custom already exist... "
		mv "$dir_default" "$dir_default"-dist
	fi
	echo "linking $dir_custom into $dir_default"
	ln -s "$dir_custom" "$dir_default"
}

# exec app hooks
app_pre_hooks
app_post_hooks
echo "========================================================================"
# exec entrypoint arguments
[ ! -z "${APP_USERNAME}" ] && set -x && exec su -m ${APP_USERNAME} -s /bin/bash -c "$@" || exec "$@"
