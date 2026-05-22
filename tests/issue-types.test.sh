#!/usr/bin/env bash
# Verify scripts/lib/issue-types.sh exposes the expected function names.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/issue-types.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

# Source in subshell and check function existence
result=$(bash -c "source '$LIB' && declare -F sillok_issue_type_id sillok_issue_type_set" 2>&1)

if echo "$result" | grep -q "sillok_issue_type_id" && echo "$result" | grep -q "sillok_issue_type_set"; then
  echo "OK: required functions exist"
else
  echo "FAIL: missing functions"
  echo "$result"
  exit 1
fi
