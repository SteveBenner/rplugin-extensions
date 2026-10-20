#!/usr/bin/env bash
set -euo pipefail

if [ -n "${RSTACK_BIN_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.rstack" ]; then
  exit 0
fi

exit 1
