#!/usr/bin/env bash
# Fills the public plugin repo (illbytes/hermsy-hermes) from this one.
#
#   tool/export_plugin.sh ~/Code/hermsy-hermes
#
# The repo's root is the plugin itself (plugin.yaml at the top), which is
# what `hermes plugins install illbytes/hermsy-hermes` expects. Tests come
# along under tests/. Nothing is committed or pushed: review, then do that
# yourself.
set -euo pipefail

target="${1:?usage: tool/export_plugin.sh <repo folder>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$here/server/hermes-plugin/hermsy"

mkdir -p "$target"
rsync -a --delete \
  --exclude .git --exclude .gitignore --exclude LICENSE --exclude tests \
  --exclude __pycache__ --exclude '*.pyc' \
  "$plugin/" "$target/"
mkdir -p "$target/tests"
cp "$here/server/hermes-plugin/tests/test_hermsy_plugin.py" "$target/tests/"
# Its own rootdir: the repo root is the plugin package, which pytest would
# otherwise import as a test package. Run with `pytest tests`.
printf '[pytest]\n' > "$target/tests/pytest.ini"
version="$(grep '^version:' "$target/plugin.yaml" | awk '{print $2}')"
echo "Exported hermsy $version to $target"
[ -f "$target/LICENSE" ] || echo "No LICENSE yet: add one before publishing."
