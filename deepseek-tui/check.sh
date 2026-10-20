#!/usr/bin/env bash
set -euo pipefail

if [ -n "${DSH_HOME:-}" ]; then
  dsh_home="$DSH_HOME"
elif [ -d "$HOME/.dsh" ]; then
  dsh_home="$HOME/.dsh"
elif [ -d "$HOME/.deepseek" ]; then
  dsh_home="$HOME/.deepseek"
else
  dsh_home="$HOME/.dsh"
fi

probe="$dsh_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "deepseek-tui: $probe is not writable" >&2
  exit 1
fi

exit 0
