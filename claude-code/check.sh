#!/usr/bin/env bash
set -euo pipefail

claude_home="${RPLUGIN_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-}}"
if [ -z "$claude_home" ]; then
  if [ -n "${RSTACK_HARNESS_HOME:-}" ]; then
    claude_home="$RSTACK_HARNESS_HOME/claude"
  else
    claude_home="$HOME/.claude"
  fi
fi

probe="$claude_home"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
  probe="$(dirname "$probe")"
done

if [ ! -w "$probe" ]; then
  echo "claude-code: $probe is not writable" >&2
  exit 1
fi

exit 0
