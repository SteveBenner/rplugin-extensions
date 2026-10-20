#!/usr/bin/env bash
set -euo pipefail

hermes_home="${HERMES_HOME:-$HOME/.hermes}"

if [ -n "${PLUGIN_SKILLS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$hermes_home/skills/$(basename "$line")"
    fi
  done <<< "$PLUGIN_SKILLS"
else
  skills_source="skills/$PLUGIN_ID"
  if [ -e "$PACKAGE_ROOT/$skills_source" ]; then
    echo "$skills_source|$hermes_home/skills/$PLUGIN_ID"
  fi
fi
