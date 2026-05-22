#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/dev-link.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

result=$(bash -c "source '$LIB' && declare -F sillok_issue_node_id sillok_link_branch" 2>&1)

if echo "$result" | grep -q "sillok_issue_node_id" && echo "$result" | grep -q "sillok_link_branch"; then
  echo "OK: required functions exist"
else
  echo "FAIL: missing functions"
  echo "$result"
  exit 1
fi
