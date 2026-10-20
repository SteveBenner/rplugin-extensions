#!/usr/bin/env bash
set -euo pipefail

bin_home="${RSTACK_BIN_HOME:-$HOME/.local/bin}"

probe="$bin_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "rstack: $probe is not writable" >&2
  exit 1
fi

exit 0
