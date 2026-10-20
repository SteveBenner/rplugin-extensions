#!/usr/bin/env bash
set -euo pipefail

if [ -n "${RPLUGIN_ANTIGRAVITY_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.gemini" ] || command -v agy >/dev/null 2>&1; then
  exit 0
fi

exit 1
