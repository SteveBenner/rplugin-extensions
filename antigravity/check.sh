#!/usr/bin/env bash
set -euo pipefail

antigravity_home="${RPLUGIN_ANTIGRAVITY_HOME:-$HOME/.gemini}"

probe="$antigravity_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "antigravity: $probe is not writable" >&2
  exit 1
fi

exit 0
