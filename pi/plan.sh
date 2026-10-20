#!/usr/bin/env bash
set -euo pipefail

pi_home="${PI_HOME:-$HOME/.pi}"

if [ -n "${PLUGIN_SKILLS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$pi_home/.agents/skills/$(basename "$line")"
    fi
  done <<< "$PLUGIN_SKILLS"
else
  skills_source="skills/$PLUGIN_ID"
  if [ -e "$PACKAGE_ROOT/$skills_source" ]; then
    echo "$skills_source|$pi_home/.agents/skills/$PLUGIN_ID"
  fi
fi
