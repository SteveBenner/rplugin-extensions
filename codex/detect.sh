#!/usr/bin/env bash
set -euo pipefail

if [ -n "${CODEX_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.codex" ]; then
  exit 0
fi

exit 1
