#!/usr/bin/env bash
set -euo pipefail

for var in RPLUGIN_CLAUDE_HOME CLAUDE_CONFIG_DIR RSTACK_HARNESS_HOME; do
  if [ -n "${!var:-}" ]; then
    exit 0
  fi
done

if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
  exit 0
fi

exit 1
