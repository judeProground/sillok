#!/usr/bin/env bash
# Verify scripts/lib/project.sh exposes the expected function names.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
LIB="$REPO_ROOT/scripts/lib/project.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

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

echo "test: sillok_project_id does not hardcode organization(login:"
if awk '/^sillok_project_id\(\)/,/^}/' "$REPO_ROOT/scripts/lib/project.sh" \
  | grep -q "organization(login:"; then
  fail "sillok_project_id still uses organization(login:) — should be owner-agnostic"
fi
pass "sillok_project_id is owner-agnostic"

echo "test: sillok_project_field_id does not hardcode organization(login:"
if awk '/^sillok_project_field_id\(\)/,/^}/' "$REPO_ROOT/scripts/lib/project.sh" \
  | grep -q "organization(login:"; then
  fail "sillok_project_field_id still uses organization(login:)"
fi
pass "sillok_project_field_id is owner-agnostic"

echo "test: sillok_project_option_id does not hardcode organization(login:"
if awk '/^sillok_project_option_id\(\)/,/^}/' "$REPO_ROOT/scripts/lib/project.sh" \
  | grep -q "organization(login:"; then
  fail "sillok_project_option_id still uses organization(login:)"
fi
pass "sillok_project_option_id is owner-agnostic"

echo
echo "All project-lib.sh tests passed."
