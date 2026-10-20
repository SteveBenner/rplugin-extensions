#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  exit 0
fi

if command -v launchctl >/dev/null 2>&1; then
  exit 0
fi

if command -v crontab >/dev/null 2>&1; then
  exit 0
fi

exit 1
