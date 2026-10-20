#!/usr/bin/env bash
set -euo pipefail

hermes_home="${HERMES_HOME:-$HOME/.hermes}"

probe="$hermes_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "hermes: $probe is not writable" >&2
  exit 1
fi

exit 0
