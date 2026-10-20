#!/usr/bin/env bash
set -euo pipefail

pi_home="${PI_HOME:-$HOME/.pi}"

probe="$pi_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "pi: $probe is not writable" >&2
  exit 1
fi

exit 0
