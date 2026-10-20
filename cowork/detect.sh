#!/usr/bin/env bash
set -euo pipefail

if command -v claude >/dev/null 2>&1; then
  exit 0
fi

exit 1
