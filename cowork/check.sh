#!/usr/bin/env bash
set -euo pipefail

root="${PACKAGE_ROOT:-}"
if [ -z "$root" ] || [ ! -d "$root/bin" ]; then
  exit 0
fi

manifest="$(ls "$root"/*.rplugin.yml 2>/dev/null | head -n 1 || true)"
if [ -z "$manifest" ]; then
  exit 0
fi

level="$(ruby -ryaml -rdate -e '
doc = YAML.safe_load(File.read(ARGV[0]), permitted_classes: [Date, Time, Symbol], aliases: true) || {}
compat = doc["compatibility"] || {}
harnesses = compat["harnesses"] || {}
value = harnesses["cowork"]
value = value["status"] || value["level"] if value.is_a?(Hash)
puts value.to_s
' "$manifest")"

case "$level" in
  supported|skills-only)
    echo "cowork: $root/bin exists but Cowork refuses a plugin with a top-level bin/ directory; compatibility.harnesses.cowork is $level" >&2
    exit 1
    ;;
esac

exit 0
