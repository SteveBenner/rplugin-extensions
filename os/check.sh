#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  target="${RPLUGIN_SYSTEMD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"

  probe="$target"
  while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
    probe="$(dirname "$probe")"
  done

  if [ ! -w "$probe" ]; then
    echo "os: $probe is not writable" >&2
    exit 1
  fi

  exit 0
fi

if command -v launchctl >/dev/null 2>&1; then
  target="$HOME/Library/LaunchAgents"

  probe="$target"
  while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
    probe="$(dirname "$probe")"
  done

  if [ ! -w "$probe" ]; then
    echo "os: $probe is not writable" >&2
    exit 1
  fi

  exit 0
fi

exit 0
