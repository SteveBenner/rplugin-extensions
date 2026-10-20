#!/usr/bin/env bash
set -euo pipefail

if [ -n "${HERMES_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.hermes" ]; then
  exit 0
fi

exit 1
