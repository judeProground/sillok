#!/usr/bin/env bash
# Verify scripts/lib/project.sh exposes the expected function names.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/../scripts/lib/project.sh"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: $LIB does not exist"
  exit 1
fi

expected=(
  sillok_project_id
  sillok_project_item_for_issue
  sillok_project_item_add
  sillok_project_field_id
  sillok_project_option_id
  sillok_project_status_get
  sillok_project_status_set
)

result=$(bash -c "source '$LIB' && declare -F ${expected[*]}" 2>&1)

ok=1
for fn in "${expected[@]}"; do
  if ! echo "$result" | grep -q "$fn"; then
    echo "FAIL: missing function $fn"
    ok=0
  fi
done

if [[ "$ok" == "1" ]]; then
  echo "OK: all required functions exist"
else
  exit 1
fi
