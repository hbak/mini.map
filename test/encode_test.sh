#!/usr/bin/env bash
# Differential + performance assertions for the <fork> map encoder rewrite.
#
# Usage:
#   ./encode_test.sh
#
# Pins MiniMap.encode_strings() to the byte-for-byte output of the upstream
# algorithm it replaced (inlined as the reference inside encode_test.lua), and
# asserts the rewrite is actually fast.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_BIN="${NVIM_BIN:-nvim}"

"$NVIM_BIN" --headless -u NONE -l "$SCRIPT_DIR/encode_test.lua"
