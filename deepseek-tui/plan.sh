#!/usr/bin/env bash
set -euo pipefail

if [ -n "${DSH_HOME:-}" ]; then
  dsh_home="$DSH_HOME"
elif [ -d "$HOME/.dsh" ]; then
  dsh_home="$HOME/.dsh"
elif [ -d "$HOME/.deepseek" ]; then
  dsh_home="$HOME/.deepseek"
else
  dsh_home="$HOME/.dsh"
fi

if [ -n "${PLUGIN_SKILLS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$dsh_home/.agents/skills/$(basename "$line")"
    fi
  done <<< "$PLUGIN_SKILLS"
else
  skills_source="skills/$PLUGIN_ID"
  if [ -e "$PACKAGE_ROOT/$skills_source" ]; then
    echo "$skills_source|$dsh_home/.agents/skills/$PLUGIN_ID"
  fi
fi
