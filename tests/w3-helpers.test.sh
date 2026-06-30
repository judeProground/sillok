#!/usr/bin/env bash
# W3 (#43): unit tests for the four extracted helpers — they must run the SAME
# commands in the SAME order as the inline SKILL.md bash they replace.
#
#   sillok_link_and_push (dev-link.sh) — resolve issue node id -> sillok_link_branch
#       -> git push -u, IN THAT ORDER (link-before-push is create-only).
#   sillok_subissue_link (subissue.sh) — two id resolves -> addSubIssue mutation,
#       with the parent/child owner/repo/number threaded into the queries verbatim.
#   sillok_priority_apply (project.sh) — orgMode guard + NON-FATAL fail-soft around
#       sillok_issue_priority_set; user mode is a clean no-op.
#
# Hermetic: gh / git / the wrapped helpers are stubbed per case; no network, no
# real repo mutations. Each case runs in its own bash -c subshell.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

make_project() {  # $1 = dir, $2 = orgMode (true|false)
  local dir="$1"
  mkdir -p "$dir/.claude/sillok"
  git -C "$dir" init -q
  cat > "$dir/.claude/sillok/workflow.config.json" <<EOF
{ "orgMode": $2, "repo": "o/r", "project": { "priorityField": "Priority", "priorities": { "p3": "Medium" } } }
EOF
}

# ===========================================================================
# (1) sillok_link_and_push — order: node-id resolve, link, push.
# ===========================================================================
PROJ1="$TMP/p1"; make_project "$PROJ1" true
ORDER="$TMP/order1"
WT1="$TMP/wt1"; mkdir -p "$WT1"
read -r -d '' CASE1 <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/dev-link.sh"
# Stub the wrapped primitives to record call order + assert arguments.
sillok_issue_node_id() { echo "node:$1:$2" >> "$ORDER"; printf 'I_node'; }
sillok_link_branch()   { echo "link:$1:$2:$3" >> "$ORDER"; }
git() { echo "git:$*" >> "$ORDER"; }
sillok_link_and_push "o/r" "7" "feature/issue-7-x" "deadbeef" "$WT1"
EOS
PROJ="$PROJ1" REPO_ROOT="$REPO_ROOT" ORDER="$ORDER" WT1="$WT1" bash -c "$CASE1" >/dev/null 2>&1 \
  || fail "(1) sillok_link_and_push returned non-zero on happy path"
# Exact ordered trace. With git fully stubbed the only git call inside the helper
# is the push (the SHA was passed in, not computed here).
got=$(cat "$ORDER")
expected="node:o/r:7
link:I_node:feature/issue-7-x:deadbeef
git:push -u origin feature/issue-7-x"
[[ "$got" == "$expected" ]] || fail "(1) wrong call order/args:
--- got ---
$got
--- want ---
$expected"
pass "(1) sillok_link_and_push: node-id -> link -> push, in order, args threaded"

# (1b) push runs in the supplied directory (cd happens before push).
PROJ1B="$TMP/p1b"; make_project "$PROJ1B" true
PUSHDIR="$TMP/pushdir"; mkdir -p "$PUSHDIR"
CWDFILE="$TMP/cwd1b"
read -r -d '' CASE1B <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/dev-link.sh"
sillok_issue_node_id() { printf 'I_node'; }
sillok_link_branch()   { :; }
git() { pwd > "$CWDFILE"; }   # record cwd at the moment git push runs
sillok_link_and_push "o/r" "7" "br" "sha" "$PUSHDIR"
EOS
PROJ="$PROJ1B" REPO_ROOT="$REPO_ROOT" CWDFILE="$CWDFILE" PUSHDIR="$PUSHDIR" bash -c "$CASE1B" >/dev/null 2>&1 \
  || fail "(1b) returned non-zero"
got_cwd=$(cat "$CWDFILE")
# macOS /tmp symlinks to /private/tmp — resolve both ends before comparing.
[[ "$(cd "$got_cwd" && pwd -P)" == "$(cd "$PUSHDIR" && pwd -P)" ]] \
  || fail "(1b) git push did not run inside push_dir (got '$got_cwd', want '$PUSHDIR')"
pass "(1b) sillok_link_and_push: push runs inside the supplied push_dir"

# ===========================================================================
# (2) sillok_subissue_link — two id resolves then the addSubIssue mutation,
#     with parent/child owner/repo/number threaded into the queries verbatim.
# ===========================================================================
PROJ2="$TMP/p2"; make_project "$PROJ2" true
CALLS="$TMP/calls2"
read -r -d '' CASE2 <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/subissue.sh"
gh() {
  local all="$*"
  case "$all" in
    *'mutation'*'addSubIssue'*) echo "MUT:$all" >> "$CALLS"; printf '1\n' ;;
    *'issue(number: 42)'*)      echo "PARENT_Q:$all" >> "$CALLS"; printf 'PID\n' ;;
    *'issue(number: 7)'*)       echo "CHILD_Q:$all" >> "$CALLS"; printf 'CID\n' ;;
    *) echo "UNEXPECTED:$all" >> "$CALLS"; printf '\n' ;;
  esac
}
sillok_subissue_link "powner" "prepo" "42" "cowner" "crepo" "7"
EOS
PROJ="$PROJ2" REPO_ROOT="$REPO_ROOT" CALLS="$CALLS" bash -c "$CASE2" >/dev/null 2>&1 \
  || fail "(2) sillok_subissue_link returned non-zero"
trace=$(cat "$CALLS")
# Order: parent id query, child id query, then the mutation.
[[ "$(printf '%s\n' "$trace" | sed -n '1p')" == PARENT_Q:* ]] || fail "(2) first call must resolve parent id: $trace"
[[ "$(printf '%s\n' "$trace" | sed -n '2p')" == CHILD_Q:*  ]] || fail "(2) second call must resolve child id: $trace"
[[ "$(printf '%s\n' "$trace" | sed -n '3p')" == MUT:*      ]] || fail "(2) third call must be the addSubIssue mutation: $trace"
# Parent query carries parent owner/repo; child query carries child owner/repo.
grep -q 'PARENT_Q:.*owner: "powner".*name: "prepo".*issue(number: 42)' "$CALLS" \
  || fail "(2) parent query missing parent owner/repo/number"
grep -q 'CHILD_Q:.*owner: "cowner".*name: "crepo".*issue(number: 7)' "$CALLS" \
  || fail "(2) child query missing child owner/repo/number"
# Mutation wires the two resolved ids into addSubIssue.
grep -q 'MUT:.*addSubIssue(input: { issueId: "PID", subIssueId: "CID" })' "$CALLS" \
  || fail "(2) mutation did not thread resolved PARENT_ID/CHILD_ID"
pass "(2) sillok_subissue_link: parent-id -> child-id -> addSubIssue, args verbatim"

# (2b) UNEXPECTED must never fire — proves only the three intended calls run.
grep -q 'UNEXPECTED' "$CALLS" && fail "(2b) an unexpected gh call fired" || true
[[ "$(grep -c '' "$CALLS")" == "3" ]] || fail "(2b) expected exactly 3 gh calls, got $(grep -c '' "$CALLS")"
pass "(2b) sillok_subissue_link: exactly three gh calls, nothing extra"

# ===========================================================================
# (3) sillok_priority_apply — org mode delegates; failure is NON-FATAL.
# ===========================================================================
# (3a) org mode + success: calls sillok_issue_priority_set, rc 0, no warning.
PROJ3="$TMP/p3"; make_project "$PROJ3" true
ERR3="$TMP/err3a"; MARK3="$TMP/mark3a"
read -r -d '' CASE3A <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/project.sh"
sillok_issue_priority_set() { echo "called:$1:$2" >> "$MARK"; return 0; }
sillok_priority_apply "https://github.com/o/r/issues/7" p3
EOS
set +e
PROJ="$PROJ3" REPO_ROOT="$REPO_ROOT" MARK="$MARK3" bash -c "$CASE3A" 2>"$ERR3"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "(3a) expected rc 0, got $rc (stderr: $(cat "$ERR3"))"
grep -q 'called:https://github.com/o/r/issues/7:p3' "$MARK3" \
  || fail "(3a) sillok_issue_priority_set not called with the url+key"
[[ ! -s "$ERR3" ]] || fail "(3a) expected no warning on success, got: $(cat "$ERR3")"
pass "(3a) priority_apply org+success: delegates, rc 0, silent"

# (3b) org mode + failure: warns to stderr but stays rc 0 (NON-FATAL).
PROJ3B="$TMP/p3b"; make_project "$PROJ3B" true
ERR3B="$TMP/err3b"
read -r -d '' CASE3B <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/project.sh"
sillok_issue_priority_set() { return 1; }
sillok_priority_apply "https://github.com/o/r/issues/7" p3
EOS
set +e
PROJ="$PROJ3B" REPO_ROOT="$REPO_ROOT" bash -c "$CASE3B" 2>"$ERR3B"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "(3b) priority failure must be NON-FATAL (rc 0), got $rc"
grep -q 'priority not set' "$ERR3B" || fail "(3b) expected 'priority not set' warning, got: $(cat "$ERR3B")"
grep -q 'sillok-init' "$ERR3B" || fail "(3b) expected re-init pointer in warning, got: $(cat "$ERR3B")"
pass "(3b) priority_apply org+failure: warns, rc 0 (NON-FATAL)"

# (3c) user mode (orgMode=false): no delegation at all, rc 0, silent.
PROJ3C="$TMP/p3c"; make_project "$PROJ3C" false
ERR3C="$TMP/err3c"; MARK3C="$TMP/mark3c"
read -r -d '' CASE3C <<'EOS' || true
set -euo pipefail
cd "$PROJ"
source "$REPO_ROOT/scripts/lib/project.sh"
sillok_issue_priority_set() { echo called >> "$MARK"; }
sillok_priority_apply "https://github.com/o/r/issues/7" p3
EOS
set +e
PROJ="$PROJ3C" REPO_ROOT="$REPO_ROOT" MARK="$MARK3C" bash -c "$CASE3C" 2>"$ERR3C"
rc=$?
set -e
[[ $rc -eq 0 ]] || fail "(3c) user mode must be rc 0, got $rc"
[[ ! -f "$MARK3C" ]] || fail "(3c) user mode must NOT call sillok_issue_priority_set"
[[ ! -s "$ERR3C" ]] || fail "(3c) user mode must be silent, got: $(cat "$ERR3C")"
pass "(3c) priority_apply user mode: no-op, no delegation, silent"

echo
echo "All W3 helper tests passed."
