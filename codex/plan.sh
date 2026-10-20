#!/usr/bin/env bash
set -euo pipefail

codex_home="${CODEX_HOME:-$HOME/.codex}"

if [ -n "${PLUGIN_AGENTS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="$(basename "$line" .md)"
    if [ "$n" = "$PLUGIN_ID" ]; then
      continue
    fi
    toml_source="codex/agents/$n.toml"
    if [ -e "$PACKAGE_ROOT/$toml_source" ]; then
      echo "$toml_source|$codex_home/agents/$n.toml"
    fi
  done <<< "$PLUGIN_AGENTS"
fi

toml_source="codex/agents/$PLUGIN_ID.toml"
if [ -e "$PACKAGE_ROOT/$toml_source" ]; then
  echo "$toml_source|$codex_home/agents/$PLUGIN_ID.toml"
fi

profile_source="build/codex/$PLUGIN_ID.config.toml"
if [ -e "$PACKAGE_ROOT/$profile_source" ]; then
  echo "$profile_source|$codex_home/$PLUGIN_ID.config.toml"
fi
