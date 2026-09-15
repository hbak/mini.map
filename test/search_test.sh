#!/usr/bin/env bash
# Differential assertions for the <fork> `builtin_search` integration.
#
# Usage:
#   ./search_test.sh
#
# Pins the integration to the set of lines a real `/` search matches, including
# the large-buffer and expensive-pattern cases where upstream's `searchcount()`
# call silently times out and truncates the result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_BIN="${NVIM_BIN:-nvim}"

"$NVIM_BIN" --headless -u NONE -l "$SCRIPT_DIR/search_test.lua"
