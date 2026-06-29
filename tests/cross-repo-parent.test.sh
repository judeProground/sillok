#!/usr/bin/env bash
# Unit test for cross-repo --parent parsing logic.
# Tests the regex used in sillok-start (without actually invoking the command).
set -euo pipefail

# Inline the parsing logic for unit testing
parse_parent() {
  local parent_arg="$1"
  if [[ "$parent_arg" =~ ^https?://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
    echo "URL ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$parent_arg" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
    echo "CROSS ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$parent_arg" =~ ^[0-9]+$ ]]; then
    echo "LOCAL $parent_arg"
  else
    echo "INVALID"
  fi
}

# Test cases
expected_outputs=(
  "42::LOCAL 42"
  "myorg/projects#42::CROSS myorg projects 42"
  "https://github.com/myorg/projects/issues/42::URL myorg projects 42"
  "garbage::INVALID"
)

fails=0
for tc in "${expected_outputs[@]}"; do
  input="${tc%%::*}"
  expected="${tc#*::}"
  actual=$(parse_parent "$input")
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $input → $actual"
  else
    echo "FAIL: $input → expected '$expected' got '$actual'"
    fails=$((fails + 1))
  fi
done

if [[ $fails -gt 0 ]]; then
  exit 1
fi
echo "OK: all 4 cases passed"
