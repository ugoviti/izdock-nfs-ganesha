#!/bin/bash
# Lint shell scripts (shellcheck) and the Dockerfile (hadolint).
#
#   tools/lint.sh        same pinned versions locally, in the pre-commit hook and in CI (.gitea/workflows/lint.yml)
#
# The pinned releases (versions and sha256 below) are downloaded and verified once into
# ~/.cache/izdock-lint (Linux x86_64); elsewhere shellcheck/hadolint from PATH are used.
# Exit code: 0 clean, 1 findings, 2 setup error.
set -Eeuo pipefail

SHELLCHECK_VER=0.11.0
SHELLCHECK_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
HADOLINT_VER=2.14.0
HADOLINT_SHA256=6bf226944684f56c84dd014e8b979d27425c0148f61b3bd99bcc6f39e9dc5a47

root=$(cd "$(dirname "$0")/.." && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/izdock-lint"
cd "$root"

# tool NAME VER SHA256 URL: path of the pinned binary (downloaded and verified once)
tool() {
  local name=$1 ver=$2 sha=$3 url=$4 dir="$cache/$1-$2" f
  if [ -x "$dir/$name" ]; then echo "$dir/$name"; return; fi
  if [ "$(uname -s)-$(uname -m)" != Linux-x86_64 ]; then
    command -v "$name" || { echo "lint: $name not found" >&2; return 2; }
    return
  fi
  mkdir -p "$dir"; f="$dir/download"
  echo "lint: downloading $name $ver" >&2
  curl -fsSL --proto '=https' -o "$f" "$url" || { echo "lint: download failed: $url" >&2; return 2; }
  echo "$sha  $f" | sha256sum -c --quiet - >&2 || { rm -f "$f"; echo "lint: $name sha256 mismatch" >&2; return 2; }
  case "$url" in
    *.tar.xz) tar -xJf "$f" -C "$dir" --strip-components 1 "shellcheck-v$ver/shellcheck"; rm -f "$f" ;;
    *) mv "$f" "$dir/$name"; chmod 755 "$dir/$name" ;;
  esac
  echo "$dir/$name"
}

shellcheck=$(tool shellcheck "$SHELLCHECK_VER" "$SHELLCHECK_SHA256" \
  "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VER/shellcheck-v$SHELLCHECK_VER.linux.x86_64.tar.xz") || exit 2
hadolint=$(tool hadolint "$HADOLINT_VER" "$HADOLINT_SHA256" \
  "https://github.com/hadolint/hadolint/releases/download/v$HADOLINT_VER/hadolint-linux-x86_64") || exit 2

# filesystem/entrypoint.sh (the shared izdock entrypoint) is not linted yet: legacy findings
# (CMD="$@" string assignments); filesystem/entrypoint-hooks.sh is
mapfile -t sh_files < <({
  find build tools .gitea/actions .gitea/scripts -type f -name '*.sh'
  echo filesystem/entrypoint-hooks.sh
  find .githooks -type f
} | sort -u)

rc=0
echo "shellcheck $SHELLCHECK_VER: ${#sh_files[@]} file(s)"
"$shellcheck" --severity=warning --external-sources --source-path=SCRIPTDIR --source-path="$root" --format=gcc "${sh_files[@]}" || rc=1
echo "hadolint $HADOLINT_VER: Dockerfile"
"$hadolint" --config .hadolint.yaml Dockerfile || rc=1
[ "$rc" -eq 0 ] && echo "lint: clean"
exit "$rc"
