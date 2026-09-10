#!/usr/bin/env bash
# Runs every <fork> test suite.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for suite in encode refresh; do
    echo "=== ${suite}_test.sh ==="
    "$SCRIPT_DIR/${suite}_test.sh"
done
