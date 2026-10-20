#!/usr/bin/env bash
set -euo pipefail

codex_home="${CODEX_HOME:-$HOME/.codex}"

probe="$codex_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "codex: $probe is not writable" >&2
  exit 1
fi

exit 0
