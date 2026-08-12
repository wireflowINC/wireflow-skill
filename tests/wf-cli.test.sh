#!/usr/bin/env bash
# Regression tests for scripts/wf.sh — the dogfood-batch fixes.
#   Bug 1: `wait` must terminate on run-node executions (shape-robust +
#          case-insensitive status parse).
#   Bug 2: wf.sh must NOT consume the caller's stdin (breaks `while read` loops).
#
# Pure bash + jq, no network. Run: bash tests/wf-cli.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$DIR/scripts/wf.sh"
fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# The exact status-normalization jq the `wait` loop uses. Kept in lockstep with
# scripts/wf.sh — if you change it there, change it here.
norm_status() { jq -r '((.status // .data.status) // "UNKNOWN") | ascii_upcase'; }

echo "Bug 1 — wait status parse is shape- + case-robust:"

# Top-level UPPERCASE (the executions/<id>/poll shape for full AND run-node).
s=$(printf '%s' '{"status":"COMPLETED","nodeStates":[]}' | norm_status)
[ "$s" = "COMPLETED" ] && pass "top-level UPPERCASE .status → COMPLETED" \
  || fail "top-level .status not read (got '$s')"

# Nested lowercase (the /run + /execute shape) — must still resolve, not hang.
s=$(printf '%s' '{"data":{"status":"completed"}}' | norm_status)
[ "$s" = "COMPLETED" ] && pass "nested lowercase .data.status → COMPLETED" \
  || fail "nested .data.status not read/upcased (got '$s')"

s=$(printf '%s' '{"data":{"status":"failed"}}' | norm_status)
[ "$s" = "FAILED" ] && pass "nested lowercase .data.status → FAILED" \
  || fail "nested failed not resolved (got '$s')"

# A still-running poll must NOT falsely read terminal.
s=$(printf '%s' '{"status":"RUNNING"}' | norm_status)
[ "$s" = "RUNNING" ] && pass "RUNNING stays RUNNING (loop keeps polling)" \
  || fail "running misread (got '$s')"

# Absent status is UNKNOWN, never a terminal state (loop keeps going, then times
# out — it must never mistake a malformed body for COMPLETED).
s=$(printf '%s' '{}' | norm_status)
[ "$s" = "UNKNOWN" ] && pass "missing status → UNKNOWN (not terminal)" \
  || fail "missing status not UNKNOWN (got '$s')"

# The wait loop's case only exits on COMPLETED / FAILED — confirm both nested
# lowercase shapes upcase into a value that branch matches.
for pair in "completed COMPLETED" "failed FAILED"; do
  raw="${pair%% *}"; want="${pair##* }"
  s=$(printf '%s' "{\"data\":{\"status\":\"$raw\"}}" | norm_status)
  case "$s" in
    "$want") pass "case-branch matches for nested '$raw'";;
    *) fail "nested '$raw' would NOT hit the $want branch (got '$s')";;
  esac
done

echo "Bug 2 — wf.sh does not eat the caller's stdin:"

# Structural: the stdin-detach guard is present.
if grep -q 'exec </dev/null' "$WF"; then
  pass "wf.sh detaches stdin (exec </dev/null guard present)"
else
  fail "stdin guard missing — a wf.sh call in a while-read loop can drain input"
fi

# Behavioral: a 3-line while-read loop calling wf.sh iterates 3 times AND still
# sees every line. If wf.sh consumed stdin, the loop would end after line 1 and
# `seen` would be "a", not "abc".
export WIREFLOW_API_KEY="wf_test_offline_key"
seen=$(printf 'a\nb\nc\n' | while read -r line; do
  bash "$WF" help >/dev/null 2>&1
  printf '%s' "$line"
done)
[ "$seen" = "abc" ] && pass "while-read loop keeps its stdin across 3 wf.sh calls" \
  || fail "loop stdin drained by wf.sh (saw '$seen', expected 'abc')"

iters=$(printf 'a\nb\nc\n' | while read -r line; do
  bash "$WF" help >/dev/null 2>&1; echo x
done | wc -l | tr -d ' ')
[ "$iters" = "3" ] && pass "loop ran exactly 3 iterations" \
  || fail "loop iterated $iters times, expected 3"

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL PASS"
else
  echo "$fails FAILED" >&2
fi
exit "$fails"
