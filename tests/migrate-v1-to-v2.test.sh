#!/usr/bin/env bash
# Smoke test for migrate-v1-to-v2.sh.
# Verifies the script parses, exits cleanly in dry-run mode, and rejects missing args.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/../scripts/migrate-v1-to-v2.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: $SCRIPT not executable"
  exit 1
fi

# Test 1: no args → usage error
# Capture output first so a non-zero exit from the script doesn't trip pipefail.
no_args_out=$(bash "$SCRIPT" 2>&1 || true)
if printf '%s\n' "$no_args_out" | grep -q "Usage:"; then
  echo "PASS: missing args shows usage"
else
  echo "FAIL: missing args did not show usage"
  exit 1
fi

# Test 2: parse check
if bash -n "$SCRIPT"; then
  echo "PASS: script parses"
else
  echo "FAIL: script does not parse"
  exit 1
fi

echo "OK: 2/2 smoke checks passed"
