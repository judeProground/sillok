#!/usr/bin/env bash
# parse-project-url.sh — extract owner + number from a GitHub Project v2 URL.
# Accepts both org (/orgs/<o>/projects/<n>) and user (/users/<o>/projects/<n>)
# forms, tolerating trailing path segments (e.g. /views/1).
#
# On match: prints two lines, `owner=<o>` then `number=<n>`.
# On no match: prints nothing and exits 0 (caller treats empty output as "skip").
#
# usage: parse-project-url.sh <url>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <url>" >&2
  exit 1
fi

url="$1"

if [[ "$url" =~ ^https?://github\.com/(orgs|users)/([^/]+)/projects/([0-9]+) ]]; then
  echo "owner=${BASH_REMATCH[2]}"
  echo "number=${BASH_REMATCH[3]}"
fi
