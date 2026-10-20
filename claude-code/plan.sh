#!/usr/bin/env bash
set -euo pipefail

claude_home="${RPLUGIN_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-}}"
if [ -z "$claude_home" ]; then
  if [ -n "${RSTACK_HARNESS_HOME:-}" ]; then
    claude_home="$RSTACK_HARNESS_HOME/claude"
  else
    claude_home="$HOME/.claude"
  fi
fi

if [ -n "${PLUGIN_SKILLS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$claude_home/skills/$(basename "$line")"
    fi
  done <<< "$PLUGIN_SKILLS"
else
  skills_source="skills/$PLUGIN_ID"
  if [ -e "$PACKAGE_ROOT/$skills_source" ]; then
    echo "$skills_source|$claude_home/skills/$PLUGIN_ID"
  fi
fi

if [ -n "${PLUGIN_AGENTS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$claude_home/agents/$(basename "$line")"
    fi
  done <<< "$PLUGIN_AGENTS"
else
  agent_source="agents/$PLUGIN_ID.md"
  if [ -e "$PACKAGE_ROOT/$agent_source" ]; then
    echo "$agent_source|$claude_home/agents/$PLUGIN_ID.md"
  fi
fi

if [ -n "${PLUGIN_COMMANDS:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$claude_home/commands/$(basename "$line")"
    fi
  done <<< "$PLUGIN_COMMANDS"
fi

if [ -n "${PLUGIN_RULES:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -e "$PACKAGE_ROOT/$line" ]; then
      echo "$line|$claude_home/rules/rplugin/$PLUGIN_ID/$(basename "$line")"
    fi
  done <<< "$PLUGIN_RULES"
fi
