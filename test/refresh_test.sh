#!/usr/bin/env bash
# Integration assertions for the <fork> refresh cache in H.update_map_lines().
#
# Usage:
#   ./refresh_test.sh
#
# Drives a real map window in a headless nvim and counts encodes, checking both
# that redundant refreshes are skipped and that every input which should
# invalidate the map still does.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_BIN="${NVIM_BIN:-nvim}"

"$NVIM_BIN" --headless -u NONE -l "$SCRIPT_DIR/refresh_test.lua"
