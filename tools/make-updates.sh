#!/bin/bash
# Compare versions.env with upstream and propose updates.
#
#   tools/make-updates.sh [--apply] [--versions FILE]
#
# Prints one line per component of versions.env: current, latest, status
# (ok | UPDATE | unavailable), and for every UPDATE the new KEY=value lines with
# the sha256 of the new files. nfs-ganesha stays on its major version (a newer
# major is only shown as a note, change it by hand); ntirpc and prometheus-cpp-lite
# are not looked up on their own: they are the git submodules of the chosen
# nfs-ganesha tag (src/libntirpc) and of that ntirpc tag (src/monitoring/prometheus-cpp-lite).
# The base image is proposed when its tag was rebuilt upstream (same suite, new digest:
# OS security updates); a newer Debian stable is only shown as a note.
# "unavailable" = the upstream lookup failed (eg. GitHub API rate limit).
#
# Pin: a <NAME>_PIN=<version> line in versions.env (for GANESHA_VER or NTIRPC_VER) keeps
# that component on <version>: never moved by an update, proposed (with its sha256)
# when <NAME>_VER differs, also to go back to an older version. Remove the line to unpin.
#
# --apply writes the proposed lines into versions.env (only KEY=value lines
# already present; every value checked, nothing written if one is missing or
# invalid). Then: tools/build.sh, test, commit.
#
# Exit code: 0 all current (or, with --apply, updates applied), 10 updates
# available, 2 incomplete (lookups unavailable), 1 error. GITHUB_API_TOKEN
# (optional, a GitHub token: never the Gitea one) raises the GitHub API rate limit (60 requests/hour without it).
# Requires: curl, jq, sha256sum.

set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
versions="$root/versions.env"
apply=''
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --versions) versions=${2:?--versions FILE}; shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
# shellcheck source=build/lib.sh
. "$root/build/lib.sh"
load_versions "$versions"

updates=0
unavailable=0
proposals=()

row() { printf '%-28s %-24s %-24s %s\n' "$1" "$2" "$3" "$4"; }
report() { # component current latest [note]
  local name=$1 cur=$2 new=$3 note=${4:-}
  if [ "$cur" == "$new" ]; then row "$name" "$cur" "$new" "ok${note:+ ($note)}"
  else row "$name" "$cur" "$new" "UPDATE${note:+ ($note)}"; updates=$((updates + 1)); return 1
  fi
}
propose() { proposals+=("$@"); }
# lookup: like report, but an empty "latest" means the upstream lookup failed
lookup() { # component current latest source [note]
  if [ -z "$3" ]; then row "$1" "$2" "?" "unavailable ($4)"; unavailable=$((unavailable + 1)); return 0; fi
  report "$1" "$2" "$3" "${5:-}"
}
# apply_pin NAME: with <NAME>_PIN set, the pinned version replaces the upstream one
# (new) and the note says so (with the newest upstream version when it differs)
apply_pin() {
  local k="${1%_VER}_PIN" up=$new
  [ -n "${!k:-}" ] || return 0
  new=${!k}
  if [ -n "$up" ] && [ "$up" != "$new" ]; then note="pinned, latest $up${note:+, $note}"
  else note="pinned${note:+, $note}"; fi
}
# every request retries transient failures; curl messages only when it fails for good
fetch() {
  local err rc=0
  err=$(mktemp)
  curl -fsSL --proto '=https' --connect-timeout 30 --speed-limit 1024 --speed-time 60 --retry 3 --retry-delay 2 --retry-connrefused "$@" 2>"$err" || rc=$?
  [ "$rc" -eq 0 ] || tail -n 1 "$err" >&2
  rm -f "$err"
  return "$rc"
}
# sha256 of a download; empty when the download fails (never the sha256 of an empty file)
sha_of() { local t; t=$(mktemp); if fetch -o "$t" "$1"; then sha256sum "$t" | cut -d' ' -f1; fi; rm -f "$t"; }

gh_api() { fetch ${GITHUB_API_TOKEN:+-H "Authorization: Bearer $GITHUB_API_TOKEN"} -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"; }
# gh_submodule REPO PATH REF: commit sha of the git submodule PATH at REF
gh_submodule() { local j; j=$(gh_api "repos/$1/contents/$2?ref=$3") || return 1; jq -r 'select(.type == "submodule") | .sha // empty' <<< "$j"; }

row COMPONENT CURRENT LATEST STATUS

# --- base image: digest of debian:<suite>-slim; a newer Debian stable is only a note
# (the current stable is the suite tagged "latest" in the official images library file;
# the stable-slim and <suite>-slim digests differ even with the same content)
hub=https://hub.docker.com/v2/repositories/library/debian/tags
digest=$(fetch "$hub/$DEBIAN_SUITE-slim" | jq -r '.digest // empty' || true)
stable=$(fetch https://raw.githubusercontent.com/docker-library/official-images/master/library/debian |
         sed -n 's/^Tags: \([a-z][a-z]*\),.*[ ,]latest\(,.*\)*$/\1/p' | head -1 || true)
note=''
if [ -n "$stable" ] && [ "$stable" != "$DEBIAN_SUITE" ]; then
  note="debian stable is now $stable: change DEBIAN_SUITE by hand"
elif [ -n "$digest" ] && [ "$digest" != "$DEBIAN_DIGEST" ]; then
  note="tag $DEBIAN_SUITE-slim rebuilt upstream"
fi
if [ -z "$digest" ]; then
  lookup DEBIAN_DIGEST "${DEBIAN_DIGEST:7:12}" "" "Docker Hub"
else
  report DEBIAN_DIGEST "${DEBIAN_DIGEST:7:12}" "${digest:7:12}" "$DEBIAN_SUITE-slim${note:+, $note}" ||
    propose "DEBIAN_DIGEST=$digest"
fi

# --- nfs-ganesha: newest non-prerelease release Vx.y[.z] on the current major
new='' note='' top=''
if j=$(gh_api "repos/nfs-ganesha/nfs-ganesha/releases?per_page=100"); then
  all=$(jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name' <<< "$j" |
        sed -n 's/^V\([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)*\)$/\1/p' | sort -V || true)
  new=$(grep -E "^${GANESHA_VER%%.*}\." <<< "$all" | tail -1 || true)
  top=$(tail -1 <<< "$all")
  if [ -n "$top" ] && [ "${top%%.*}" != "${GANESHA_VER%%.*}" ]; then note="major $top available"; fi
fi
apply_pin GANESHA_VER
ganesha=$GANESHA_VER
if ! lookup GANESHA_VER "$GANESHA_VER" "$new" "GitHub API" "$note"; then
  ganesha=$new
  propose "GANESHA_VER=$new" "GANESHA_SHA256=$(sha_of "$(ganesha_url "$new")")"
fi

# --- ntirpc: the tag whose commit is the src/libntirpc submodule of the nfs-ganesha tag
new='' note=''
if sub=$(gh_submodule nfs-ganesha/nfs-ganesha src/libntirpc "V$ganesha") && [ -n "$sub" ] &&
   j=$(gh_api "repos/nfs-ganesha/ntirpc/tags?per_page=100"); then
  new=$(jq -r --arg s "$sub" '.[] | select(.commit.sha == $s) | .name' <<< "$j" | sed -n 's/^v//p' | sort -V | tail -1 || true)
  [ -n "$new" ] || echo "ntirpc: no tag for commit $sub (submodule of V$ganesha)" >&2
fi
note="submodule of nfs-ganesha V$ganesha"
apply_pin NTIRPC_VER
ntirpc=$NTIRPC_VER
if ! lookup NTIRPC_VER "$NTIRPC_VER" "$new" "GitHub API" "$note"; then
  ntirpc=$new
  propose "NTIRPC_VER=$new" "NTIRPC_SHA256=$(sha_of "$(ntirpc_url "$new")")"
fi

# --- prometheus-cpp-lite: the src/monitoring/prometheus-cpp-lite submodule of the ntirpc tag
new=$(gh_submodule nfs-ganesha/ntirpc src/monitoring/prometheus-cpp-lite "v$ntirpc" || true)
if [ -z "$new" ]; then
  lookup PROMETHEUS_CPP_LITE_COMMIT "${PROMETHEUS_CPP_LITE_COMMIT::12}" "" "GitHub API"
else
  report PROMETHEUS_CPP_LITE_COMMIT "${PROMETHEUS_CPP_LITE_COMMIT::12}" "${new::12}" "submodule of ntirpc v$ntirpc" ||
    propose "PROMETHEUS_CPP_LITE_COMMIT=$new" "PROMETHEUS_CPP_LITE_SHA256=$(sha_of "$(prometheus_url "$new")")"
fi

echo
[ "$unavailable" -eq 0 ] || echo "$unavailable lookup(s) unavailable: the report is incomplete" >&2
if [ "$updates" -eq 0 ]; then
  [ "$unavailable" -eq 0 ] || exit 2
  echo "all components are current"
  exit 0
fi
echo "$updates update(s) available, proposed versions.env lines:"
printf '  %s\n' "${proposals[@]}"
[ -n "$apply" ] || exit 10

# --- --apply: replace the KEY=value lines, all or nothing
for line in "${proposals[@]}"; do
  k=${line%%=*} v=${line#*=}
  [[ "$k" =~ ^[A-Z0-9_]+$ ]] || { echo "apply: invalid line '$line'" >&2; exit 1; }
  grep -q "^$k=" "$versions" || { echo "apply: $k is not in $versions" >&2; exit 1; }
  [ -n "$v" ] || { echo "apply: $k has no value (upstream lookup failed): nothing written" >&2; exit 1; }
  case "$k" in
    *_SHA256) [[ "$v" =~ ^[0-9a-f]{64}$ ]] || { echo "apply: $k is not a sha256 ('$v'): nothing written" >&2; exit 1; } ;;
    *_DIGEST) [[ "$v" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "apply: $k is not a digest ('$v'): nothing written" >&2; exit 1; } ;;
    *_COMMIT) [[ "$v" =~ ^[0-9a-f]{40}$ ]] || { echo "apply: $k is not a commit sha ('$v'): nothing written" >&2; exit 1; } ;;
  esac
done
out=$(mktemp "$versions.XXXXXX")
awk 'NR == FNR { i = index($0, "="); val[substr($0, 1, i - 1)] = substr($0, i + 1); next }
     !/^#/ && (i = index($0, "=")) > 1 && ((k = substr($0, 1, i - 1)) in val) { print k "=" val[k]; next }
     { print }' <(printf '%s\n' "${proposals[@]}") "$versions" > "$out"
chmod --reference="$versions" "$out"
mv -f "$out" "$versions"
echo
echo "applied ${#proposals[@]} line(s) to $versions"
echo "next: tools/build.sh, test, then commit (git diff to review)"
[ "$unavailable" -eq 0 ] || exit 2
exit 0
