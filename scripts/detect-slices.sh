#!/usr/bin/env bash
# detect-slices.sh — scan a project for vertical-slice directories and emit
# candidate domain names.
#
# Looks at the following layout families (each existence-checked):
#   * Feature-Sliced Design: src/{entities,features,widgets,pages,slices,modules}/<name>/
#   * App-router style: app/<name>/
#   * Native modules: modules/<name>/
#   * Monorepo packages: packages/<name>/
#   * Monorepo apps: apps/<name>/
#   * Go: internal/<name>/, cmd/<name>/, pkg/<name>/
#   * Rust workspace: crates/<name>/
#   * Microservices: services/<name>/
#   * Generic src/ fallback: src/<name>/ (only when no FSD subdirs exist under src/)
#
# A name's rank = the number of distinct layout families it appears in.
# Generic infrastructure names (components, utils, types, etc.) are filtered.
# Output is tab-separated <name>\t<rank>, sorted by rank desc then name asc,
# hard-capped at 100 lines. Empty output is a legitimate result.
#
# usage: detect-slices.sh <project-root>
# bash 3.2 compatible (no mapfile, no negative array indexing).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <project-root>" >&2
  exit 1
fi

ROOT="$1"
if [[ ! -d "$ROOT" ]]; then
  echo "[detect-slices] project root does not exist: $ROOT" >&2
  exit 1
fi

# Layout families: each entry is "<existence-path>:<scan-path>". For FSD entries
# the existence-path and scan-path coincide.
FAMILIES=(
  # FSD (frontend)
  "$ROOT/src/entities"
  "$ROOT/src/features"
  "$ROOT/src/widgets"
  "$ROOT/src/pages"
  "$ROOT/src/slices"
  "$ROOT/src/modules"
  # App-router / native
  "$ROOT/app"
  "$ROOT/modules"
  # Monorepo
  "$ROOT/packages"
  "$ROOT/apps"
  # Go
  "$ROOT/internal"
  "$ROOT/cmd"
  "$ROOT/pkg"
  # Rust workspace
  "$ROOT/crates"
  # Microservices
  "$ROOT/services"
)

# Generic src/ fallback: scan src/ as flat when no FSD subdirs exist.
has_fsd=false
for fsd_dir in entities features widgets pages slices modules; do
  if [[ -d "$ROOT/src/$fsd_dir" ]]; then
    has_fsd=true
    break
  fi
done
if [[ "$has_fsd" == "false" && -d "$ROOT/src" ]]; then
  FAMILIES+=("$ROOT/src")
fi

# Generic names that are never domain slices. Kept as a single regex-ready string
# for grep -wxF matching. Add new names as they show up in real-world projects.
GENERIC_NAMES='__mocks__
__tests__
node_modules
.next
.turbo
.git
.nuxt
.svelte-kit
dist
build
.cache
out
coverage
index
types
hooks
components
common
shared
core
lib
utils
helpers
internal
constants
config
configs
mocks
mock
test
tests
styles
theme
themes
public
assets
models
services
api
apis
db
dbs
database
providers
contexts
store
stores
reducers
hocs
layouts
layout
fonts
icons
images
locales
i18n
vendor'

is_generic() {
  printf '%s\n' "$GENERIC_NAMES" | grep -qxF "$1"
}

# Skip rules: starts with _ or ., contains route-group/route-param brackets, > 40 chars.
should_skip() {
  local name="$1"
  case "$name" in
    _*|.*) return 0 ;;
    *\(*|*\)*|*\[*|*\]*) return 0 ;;
  esac
  if [[ ${#name} -gt 40 ]]; then
    return 0
  fi
  if is_generic "$name"; then
    return 0
  fi
  return 1
}

# Normalize: lowercase, replace _ with -, strip surrounding hyphens.
normalize() {
  local n="$1"
  n=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  # strip leading/trailing hyphens
  n="${n#-}"
  n="${n%-}"
  printf '%s' "$n"
}

# Tally file: each scanned name gets one line "<family-id>\t<normalized-name>".
TALLY=$(mktemp)
trap 'rm -f "$TALLY"' EXIT

family_id=0
for fam in "${FAMILIES[@]}"; do
  family_id=$((family_id + 1))
  if [[ ! -d "$fam" ]]; then
    continue
  fi
  # First-level directories only.
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    base=$(basename "$path")
    if should_skip "$base"; then
      continue
    fi
    norm=$(normalize "$base")
    [[ -z "$norm" ]] && continue
    if should_skip "$norm"; then
      continue
    fi
    printf '%d\t%s\n' "$family_id" "$norm" >> "$TALLY"
  done < <(find "$fam" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
done

if [[ ! -s "$TALLY" ]]; then
  exit 0
fi

# Reduce: for each (family_id, name), count = 1; sum families per name. Then
# rank = number of distinct families a name appeared in.
sort -u "$TALLY" \
  | awk -F'\t' '{ count[$2]++ } END { for (n in count) printf "%s\t%d\n", n, count[n] }' \
  | sort -t$'\t' -k2,2nr -k1,1 \
  | head -n 100
