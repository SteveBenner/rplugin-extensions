#!/usr/bin/env bash
set -euo pipefail

if [ -n "${DSH_HOME:-}" ]; then
  exit 0
fi

if [ -d "$HOME/.dsh" ] || [ -d "$HOME/.deepseek" ]; then
  exit 0
fi

exit 1
