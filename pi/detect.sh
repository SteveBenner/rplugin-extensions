#!/usr/bin/env bash
set -euo pipefail

if [ -n "${PI_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.pi" ]; then
  exit 0
fi

exit 1
