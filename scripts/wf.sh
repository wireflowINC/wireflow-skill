#!/usr/bin/env bash
# Wireflow API helper — single dispatcher for common operations.
#
# Usage:
#   wf.sh templates                      # list remotion templates
#   wf.sh template <id>                  # fetch one template spec
#   wf.sh nodes                          # node catalog (every type + its ports)
#   wf.sh blocks [--use <tag>]           # motion-graphics block library (filter by purpose: endcard, captions, intro…)
#   wf.sh block <blockId>                # one block: full prop schema + defaults + tags
#   wf.sh generate "<prompt>"            # AI-generate a workflow from a prompt
#   wf.sh check <workflow.json>          # GATE: graph-lint (caps+cycle+handles); repo OR server-side
#   wf.sh create <workflow.json>         # create (gated on check; auto-layout)
#   wf.sh update <workflowId> <wf.json>  # replace (gated on check; auto-layout)
#   wf.sh patch-node <flowId> <nodeId> <json>  # patch ONE node's config/params/label/position (no full round-trip)
#   wf.sh layout <workflow.json> [out]   # re-space nodes (no overlap), no API call
#   wf.sh organize <workflowId>          # refactor live graph: DRY constants + module groups + swimlanes (--dump-plan / --plan p.json)
#   wf.sh run <workflowId> <inputs.json> # run a workflow with inputs (re-runs ALL nodes)
#   wf.sh run-node <workflowId> <nodeId> # re-run ONE node (fresh config), reuse cached upstream
#   wf.sh run-force <workflowId>         # full re-roll: clear ALL cached output first (--no-cache)
#   wf.sh poll <executionId>             # poll execution status once
#   wf.sh wait <executionId>             # BLOCK until done; per-node status + errors (rate-aware)
#   wf.sh list                           # list workflows
#   wf.sh get <workflowId>               # fetch one workflow
#   wf.sh duplicate <flowId> [name]      # server-side clone → prints new id + url
#   wf.sh publish <workflowId>           # make the public page live (VIEW; re-sanitizes nodes)
#   wf.sh unpublish <workflowId>         # back to PRIVATE
#   wf.sh delete <workflowId>            # delete a workflow (clean up test/double-created flows)
#   wf.sh inputs <workflowId>            # show valid input keys for /run
#   wf.sh upload <file|url>              # host a local file/remote url → prints CDN url
#   wf.sh media                          # list assets you've uploaded via the API
#   wf.sh preview <sceneGraph.json>      # cheap dry-run: sampled still frames + diagnostics (no paid render)
#   wf.sh download <url> [out]           # pull a render output (bypasses CDN 403)
#   wf.sh credits                        # show remaining credits
#
# Global flags (before the verb):
#   --key <key>        # supply the API key inline for one call
#
# Env:
#   WIREFLOW_API_KEY   (required). Precedence: WIREFLOW_API_KEY env var >
#                      --key flag > a .env in the cwd. A key read from ./.env
#                      prints a one-line stderr notice so identity swaps show.
#   WIREFLOW_BASE_URL  (optional, default https://www.wireflow.ai/api/v1)

set -euo pipefail

# Global flags parsed BEFORE the verb — e.g. `wf.sh --key wf_live_... duplicate <id>`.
KEY_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY_FLAG="${2:?--key needs a value}"; shift 2 ;;
    --key=*) KEY_FLAG="${1#--key=}"; shift ;;
    *) break ;;
  esac
done

# Key precedence: explicit WIREFLOW_API_KEY env var > --key flag > cwd .env.
# The env var and --key are trusted silently. A cwd .env is the footgun: run
# from a repo that ships its own .env and it would silently swap identities, so
# we only fall back to .env when neither the env var nor --key is given, AND we
# print one stderr notice naming the file so the swap is visible.
if [ -n "${WIREFLOW_API_KEY:-}" ]; then
  : # trust the environment as-is
elif [ -n "$KEY_FLAG" ]; then
  export WIREFLOW_API_KEY="$KEY_FLAG"
elif [ -f ".env" ]; then
  # Only pull WIREFLOW_ prefixed lines so we don't blow away other env.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      WIREFLOW_API_KEY=*|WIREFLOW_BASE_URL=*)
        # Strip a trailing CR (CRLF .env would yield "Bearer key\r" → silent
        # 401s), then surrounding quotes if present
        value="${line#*=}"
        value="${value%$'\r'}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "${line%%=*}=$value"
        ;;
    esac
  done < .env
  if [ -n "${WIREFLOW_API_KEY:-}" ]; then
    printf '→ using WIREFLOW_API_KEY from ./.env\n' >&2
  fi
fi

# ── Never consume the CALLER's stdin ────────────────────────────────────────
# wf.sh is frequently called from inside a `while read -r line; do wf.sh …; done`
# loop. Several sub-invocations (curl, and the python/tsx helpers) inherit the
# script's stdin; if any of them reads it, they drain the loop's input and the
# loop terminates after ONE iteration (the dogfood footgun). No wf.sh verb reads
# stdin (inputs come from file-path or inline-JSON args, and the .env read above
# already uses an explicit `< .env`), so we detach stdin for everything that
# follows. Equivalent to putting `< /dev/null` on every curl/python/node call,
# but impossible to forget on a new one.
exec </dev/null

BASE="${WIREFLOW_BASE_URL:-https://www.wireflow.ai/api/v1}"

if [ -z "${WIREFLOW_API_KEY:-}" ]; then
  cat >&2 <<EOF
error: WIREFLOW_API_KEY is not set.

Precedence: WIREFLOW_API_KEY env var > --key flag > a .env in the cwd.
Options:
  1. Create one at https://www.wireflow.ai/settings?tab=api-keys&section=api-keys
  2. Add it to your shell profile (~/.zshrc or ~/.bashrc):
       export WIREFLOW_API_KEY="wf_live_..."
  3. Pass it inline for one call:
       wf.sh --key wf_live_... <verb> ...
  4. Or put it in a .env file in the directory you run wf.sh from (a
     one-line notice tells you when a key is read from ./.env):
       WIREFLOW_API_KEY=wf_live_...

EOF
  exit 2
fi

# -L so 301/308 redirects (wireflow.ai → www.wireflow.ai) don't swallow
# API responses. Vercel preserves the method + body on 308 for POST.
CURL_FLAGS=(-sS -L)
AUTH=(-H "Authorization: Bearer $WIREFLOW_API_KEY")
CT=(-H "Content-Type: application/json")

# --- ARG_MAX guard for request bodies -----------------------------------
# A workflow graph carrying result history runs to megabytes, and
# `--data-binary "$body"` ships the whole thing as ONE argv entry. Past
# ARG_MAX the exec dies with "Argument list too long" — the request is never
# made, and on a verb whose next step is a poll that reads as "nothing
# happened" rather than as a failure. Every potentially-large body is written
# to a temp file and travels as `--data-binary @file` instead, which curl
# streams.
#
# ONE exit trap owns cleanup. `rm -f` right after the call is not enough:
# `set -e` is on, so any non-zero between mktemp and the rm skips it, and a
# Ctrl-C during a slow upload skips it too.
#
# 🔴 A DIRECTORY, not a registry array. The obvious version keeps an array of
# paths and appends in `wf_tmpfile`, but the call site is
# `f=$(wf_tmpfile)` — a COMMAND SUBSTITUTION, i.e. a subshell — so the append
# dies with the subshell and the trap always sees an empty list. Measured: the
# body files survived the run. One directory sidesteps the whole problem,
# because the trap needs no per-file bookkeeping.
WF_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/wf-body.XXXXXX")
wf_cleanup_tmpfiles() { rm -rf "$WF_TMPDIR"; return 0; }
trap wf_cleanup_tmpfiles EXIT INT TERM

# wf_tmpfile — a temp path inside the auto-cleaned dir. Echoes the path.
wf_tmpfile() { mktemp "$WF_TMPDIR/body.XXXXXX"; }

# wf_body_file <json> — spill a body string to a temp file. Echoes the path,
# so the call site reads `--data-binary "@$(wf_body_file "$body")"`.
wf_body_file() {
  local f
  f=$(wf_tmpfile)
  printf '%s' "$1" >"$f"
  printf '%s' "$f"
}

# Status-aware curl for WRITES. Retries on 429 (rate limit) with backoff, then
# prints the response BODY followed by a final line carrying the HTTP status
# code — callers MUST check that code and fail loud on non-2xx. This exists
# because plain `curl` + `printf "$resp"` silently swallows a 429/4xx body and
# exits 0, so a write that never landed reads as success and a render proceeds
# on stale/wrong cached data (the dogfooding footgun). Server sends
# X-RateLimit-Reset (epoch), not Retry-After, so we use simple linear backoff.
#   echoes: <body>\n<http_code>   (caller: code=$(tail -n1); body=$(sed '$d'))
wf_curl() {
  local tries=0 max="${WF_MAX_RETRIES:-4}" resp code
  while :; do
    resp=$(curl "${CURL_FLAGS[@]}" -w $'\n%{http_code}' "$@")
    code=$(printf '%s' "$resp" | tail -n1)
    if [ "$code" = "429" ] && [ "$tries" -lt "$max" ]; then
      local backoff=$(( (tries + 1) * 15 ))
      echo "⏳ rate-limited (429) — backing off ${backoff}s (retry $((tries + 1))/$max)" >&2
      sleep "$backoff"
      tries=$((tries + 1))
      continue
    fi
    printf '%s' "$resp"
    return 0
  done
}

# wf_lint <file> — graph-lint a workflow JSON before create/update/organize/
# check, whether or not the wireflow repo is present. Writes findings to stderr.
#   1. On-repo (scripts/wf-check.ts in cwd): use it verbatim — zero behavior
#      change for repo devs (its own exit code is returned: 0/1/2).
#   2. Off-repo: POST the JSON to $BASE/workflows/lint (via wf_curl, so a 429
#      backs off + retries). ok:false → return 1 (blocks the write); ok:true
#      with warnings → print them, return 0.
#   3. Endpoint unreachable / 404 / any other non-200 (not deployed yet, old
#      server, auth error): print a LOUD warning that the graph is UNVERIFIED,
#      set WF_LINT_UNVERIFIED=1, and return 0. The create/update/organize
#      gates proceed on that (visible skip — interactive write paths where the
#      POST itself surfaces real errors); the standalone `check` verb fails
#      CLOSED on it (exit 2), so `check && create` chains never read "could
#      not verify" as "safe".
# Callers still honor WF_SKIP_CHECK=1 to bypass this entirely.
WF_LINT_UNVERIFIED=0
wf_lint() {
  local file="$1"
  WF_LINT_UNVERIFIED=0
  if [ -f "scripts/wf-check.ts" ]; then
    npx tsx scripts/wf-check.ts "$file" >&2
    return $?
  fi
  local resp code body ok
  resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
    -X POST "$BASE/workflows/lint" --data-binary "@$file") || true
  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  case "$code" in
    200) ;;
    404) echo "⚠ /workflows/lint not deployed on this server (404) — graph is UNVERIFIED." >&2; WF_LINT_UNVERIFIED=1; return 0 ;;
    ''|000) echo "⚠ server-side lint unreachable — graph is UNVERIFIED. WF_SKIP_CHECK=1 to silence." >&2; WF_LINT_UNVERIFIED=1; return 0 ;;
    *) echo "⚠ server-side lint returned HTTP $code — graph is UNVERIFIED." >&2; WF_LINT_UNVERIFIED=1; return 0 ;;
  esac
  # NOTE: jq's `//` treats `false` as empty, so `.data.ok // .ok` would silently
  # drop a genuine ok:false. Extract with has() to preserve the boolean.
  ok=$(printf '%s' "$body" | jq -r '
    if (.data | type) == "object" and (.data | has("ok")) then .data.ok
    elif has("ok") then .ok
    else empty end' 2>/dev/null || true)
  if [ -z "$ok" ]; then
    echo "⚠ server-side lint returned an unrecognized response — graph is UNVERIFIED." >&2
    WF_LINT_UNVERIFIED=1
    return 0
  fi
  # Print violations, then warnings, in a wf-check-like style (rule + msg + fix).
  printf '%s' "$body" | jq -r '
    (.data.violations // .violations // [])[]
    | if type=="string" then "✗ " + .
      else "✗ \(.rule // "error"): \(.message // "")"
        + (if .nodeId then "  [node \(.nodeId)]" else "" end)
        + (if .fix then "\n  ↳ fix: \(.fix)" else "" end)
      end' >&2 2>/dev/null || true
  printf '%s' "$body" | jq -r '
    (.data.warnings // .warnings // [])[]
    | if type=="string" then "⚠ " + .
      else "⚠ \(.rule // "warning"): \(.message // "")"
        + (if .fix then "\n  ↳ fix: \(.fix)" else "" end)
      end' >&2 2>/dev/null || true
  [ "$ok" = "true" ] && return 0
  return 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  templates)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/remotion/templates"
    ;;

  template)
    id="${1:?usage: wf.sh template <id>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/remotion/templates/$id"
    ;;

  blocks)
    # Catalog of reusable motion-graphics Blocks (id, tags, props schema, ports,
    # preview). Compose one as a SceneGraph scene: {type:'block',blockId,props}.
    # Find by purpose:   wf.sh blocks --use endcard   (matches tags/name)
    # Only the safe set:  wf.sh blocks --renderable
    q=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --use) q="${q:+$q&}use=${2:?usage: wf.sh blocks --use <tag>}"; shift 2 ;;
        --renderable) q="${q:+$q&}renderable=1"; shift ;;
        *) shift ;;
      esac
    done
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/blocks${q:+?$q}"
    ;;

  block)
    # One block's full prop JSON-schema + defaults + purpose tags. Use this to
    # learn exactly what props (and $port:* wireable inputs) a block accepts
    # before composing it. e.g.: wf.sh block <blockId> | jq '.blocks[0].props'
    id="${1:?usage: wf.sh block <blockId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/blocks?id=$id"
    ;;

  nodes)
    # The node catalog — every node type + its ports (what you can wire).
    # This is the source of truth `check` validates edge handles against.
    # Each node has `nodeType` (the CANONICAL key you author — e.g.
    #   "audio:whisper") and `label` (the UI display name — e.g. "Speech to
    #   Text"). Author by nodeType; don't invent names like "Whisper".
    # Each input carries `isPort`: true = wireable port (put in data.inputs);
    #   false = sidebar config (put in data.config) — config inputs show `~cfg`.
    # Find a node by its UI name:  wf.sh nodes | jq '.nodes[] | select(.label=="Speech to Text") | .nodeType'
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/nodes"
    ;;

  check)
    # THE GATE — graph-lint a workflow JSON ({nodes,edges}) before create/run:
    # caps + cycle + dangling-edge + the handle-vs-catalog pass (the silent
    # break the catalog exists to kill). Exit 0 = verified clean, 1 =
    # violations, 2 = could NOT verify (server lint unreachable/erroring and no
    # local wf-check.ts) or usage/parse. Standalone check FAILS CLOSED: a
    # `check && create` chain must never read "could not verify" as "safe".
    # (The gates inside create/update/organize instead warn UNVERIFIED and
    # proceed — the write itself surfaces real errors there.)
    file="${1:?usage: wf.sh check <workflow.json>}"
    [ -f "$file" ] || { echo "✗ file not found: $file" >&2; exit 2; }
    if [ -n "${WF_SKIP_CHECK:-}" ]; then
      echo "⚠ WF_SKIP_CHECK=1 — lint skipped" >&2
      exit 0
    fi
    rc=0; wf_lint "$file" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$WF_LINT_UNVERIFIED" -eq 1 ]; then
      echo "✗ check could NOT verify the graph (server-side lint unavailable) — failing closed (exit 2)." >&2
      exit 2
    fi
    exit "$rc"
    ;;

  see)
    # The taste loop — render a SceneGraph at 20/55/85% of its duration and
    # download PNGs so you can LOOK and self-correct. Budget-capped (3 stills).
    # Block scenes need an inline bundledUrl. Run from the repo root.
    file="${1:?usage: wf.sh see <sceneGraph.json>}"
    if [ -f "scripts/wf-see.ts" ]; then
      npx tsx scripts/wf-see.ts "$file"
    else
      echo "wf see needs the wireflow repo (run from the repo root)" >&2
      exit 2
    fi
    ;;

  generate)
    prompt="${1:?usage: wf.sh generate \"<prompt>\"}"
    curl "${CURL_FLAGS[@]}" -N "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/generate/stream" \
      -d "$(jq -nc --arg p "$prompt" '{prompt:$p}')"
    ;;

  create)
    file="${1:?usage: wf.sh create <workflow.json>}"
    # GATE: never POST a graph that fails graph-lint. Uses the repo's
    # wf-check.ts on-repo, else the server /workflows/lint endpoint — so the
    # gate holds even without codebase access. Set WF_SKIP_CHECK=1 to override
    # (e.g. authoring a dynamic-port-heavy graph the static gate can't verify).
    if [ -z "${WF_SKIP_CHECK:-}" ]; then
      if ! wf_lint "$file"; then
        echo "✗ create blocked — fix the errors above (or WF_SKIP_CHECK=1 to override)" >&2
        exit 1
      fi
    fi
    # Auto-layout before create so programmatically-authored nodes don't
    # overlap (they have no rendered DOM to measure). Opt out: WF_SKIP_LAYOUT=1
    send="$file"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -z "${WF_SKIP_LAYOUT:-}" ] && command -v python3 >/dev/null 2>&1 \
       && [ -f "$SCRIPT_DIR/layout.py" ]; then
      tmp="$(mktemp)"
      if python3 "$SCRIPT_DIR/layout.py" "$file" "$tmp" >/dev/null 2>&1; then
        send="$tmp"
      fi
    fi
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows" \
      --data-binary "@$send"
    ;;

  update)
    id="${1:?usage: wf.sh update <workflowId> <workflow.json>}"
    file="${2:?usage: wf.sh update <workflowId> <workflow.json>}"
    # Same gates as create: never PUT a graph that fails graph-lint (repo
    # wf-check.ts or the server /workflows/lint endpoint), and re-layout before
    # sending — edited graphs (added/removed nodes) are the main source of
    # overlapping "vibe-coded" canvases.
    if [ -z "${WF_SKIP_CHECK:-}" ]; then
      if ! wf_lint "$file"; then
        echo "✗ update blocked — fix the errors above (or WF_SKIP_CHECK=1 to override)" >&2
        exit 1
      fi
    fi
    send="$file"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -z "${WF_SKIP_LAYOUT:-}" ] && command -v python3 >/dev/null 2>&1 \
       && [ -f "$SCRIPT_DIR/layout.py" ]; then
      tmp="$(mktemp)"
      if python3 "$SCRIPT_DIR/layout.py" "$file" "$tmp" >/dev/null 2>&1; then
        send="$tmp"
      fi
    fi
    # Optimistic concurrency: base this edit on the workflow's current
    # updatedAt and send it as baseUpdatedAt, so the server REJECTS (409) if
    # another session/agent saved since — instead of silently clobbering it
    # (the parallel-agent data-loss). Skip with WF_SKIP_CONCURRENCY=1.
    if [ -z "${WF_SKIP_CONCURRENCY:-}" ]; then
      base_ts=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id" \
        | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
print(((d.get("data") or d) or {}).get("updatedAt") or "")' 2>/dev/null)
      if [ -n "$base_ts" ]; then
        merged="$(mktemp)"
        BASE_TS="$base_ts" python3 -c 'import json,os,sys
d=json.load(open(sys.argv[1])); d["baseUpdatedAt"]=os.environ["BASE_TS"]
json.dump(d, open(sys.argv[2],"w"))' "$send" "$merged" && send="$merged"
      fi
    fi
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X PUT "$BASE/workflows/$id" --data-binary "@$send")
    code=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    printf '%s\n' "$body"
    if [ "$code" = "409" ]; then
      echo "✗ CONFLICT (409): the workflow changed since you loaded it — another session/agent saved. Your write was NOT applied (no clobber). Re-fetch with 'wf.sh get $id', reapply your edit, and update again." >&2
      exit 2
    fi
    # Fail loud on ANY non-2xx (incl. a persistent 429 after retries) — a
    # swallowed write that reads as success is the worst footgun for a render.
    case "$code" in
      2*) ;;
      *) echo "✗ update FAILED (HTTP $code): write did NOT land — fix the error above before running anything downstream." >&2; exit 1 ;;
    esac
    ;;

  patch-node)
    # Patch ONE node without round-tripping the whole graph.
    # PATCH /workflows/:id/nodes/:nodeId — body is raw JSON with any of
    # { config, params, label, position } (at least one required). Merge
    # semantics: shallow per-field merge for config/params (a key set to null
    # DELETES it); label/position replace. The server rejects structural fields
    # (output/result/nodeType/isExecuting → 400 invalid_field), refreshes
    # derived output for input:* nodes, and mirrors config→params, so a one-key
    # prompt patch just works. No graph-lint gate: a single-node config patch
    # can't break topology.
    #   wf.sh patch-node <flowId> <nodeId> '{"config":{"prompt":"new text"}}'
    #
    # Optimistic concurrency: mirrors `update` — GET the workflow's current
    # updatedAt and inject it as baseUpdatedAt so a racing save is REJECTED
    # (409), not clobbered. Skipped if the caller already put baseUpdatedAt in
    # the body, or WF_SKIP_CONCURRENCY=1. (The server ALSO compare-and-swaps on
    # every write, so a concurrent write still 409s regardless.)
    id="${1:?usage: wf.sh patch-node <flowId> <nodeId> <json-body>}"
    node_id="${2:?usage: wf.sh patch-node <flowId> <nodeId> <json-body>}"
    json="${3:-}"
    # Validate the body is present + valid JSON BEFORE any network call
    # (missing/bad local input → usage, exit 2).
    if [ -z "$json" ] || ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
      echo "✗ patch-node: missing or invalid JSON body: ${json:-<empty>}" >&2
      echo "usage: wf.sh patch-node <flowId> <nodeId> '{\"config\":{\"prompt\":\"...\"}}'" >&2
      exit 2
    fi
    body="$json"
    has_base=$(printf '%s' "$json" | jq -r 'has("baseUpdatedAt")' 2>/dev/null || echo false)
    if [ -z "${WF_SKIP_CONCURRENCY:-}" ] && [ "$has_base" != "true" ]; then
      base_ts=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id" \
        | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
print(((d.get("data") or d) or {}).get("updatedAt") or "")' 2>/dev/null)
      if [ -n "$base_ts" ]; then
        body=$(printf '%s' "$json" | jq -c --arg t "$base_ts" '. + {baseUpdatedAt:$t}')
      fi
    fi
    # Via temp file: a node patch is small for a prompt tweak, but a compv3
    # `data` patch carries the whole layer document and blows ARG_MAX.
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X PATCH "$BASE/workflows/$id/nodes/$node_id" \
      --data-binary "@$(wf_body_file "$body")")
    code=$(printf '%s' "$resp" | tail -n1)
    payload=$(printf '%s' "$resp" | sed '$d')
    case "$code" in
      2*)
        # A 2xx without a parseable node is NOT success (same hardening as
        # duplicate) — print the raw body and fail loud.
        patched=$(printf '%s' "$payload" | jq -r '.data.node.id // empty' 2>/dev/null || true)
        if [ -z "$patched" ]; then
          echo "✗ patch-node returned HTTP $code but no node in the response:" >&2
          printf '%s\n' "$payload" >&2
          exit 1
        fi
        label=$(printf '%s' "$payload" | jq -r '.data.node.data.label // .data.node.label // empty' 2>/dev/null || true)
        new_ts=$(printf '%s' "$payload" | jq -r '.data.updatedAt // empty' 2>/dev/null || true)
        printf 'patched node: %s\n' "$patched"
        [ -n "$label" ] && printf 'label:        %s\n' "$label"
        [ -n "$new_ts" ] && printf 'updatedAt:    %s\n' "$new_ts"
        # explicit success: the [ -n ] && printf guards above leak exit 1 under
        # set -e when a field is absent (the PR #2 footgun) — never let an
        # empty label/updatedAt turn a landed patch into a failed exit code.
        exit 0
        ;;
      409)
        # Concurrent write raced yours (or your baseUpdatedAt was stale). The
        # patch did NOT land — re-GET and retry so you don't clobber their save.
        current=$(printf '%s' "$payload" | jq -r '.currentUpdatedAt // empty' 2>/dev/null || true)
        yours=$(printf '%s' "$payload" | jq -r '.yourBaseUpdatedAt // empty' 2>/dev/null || true)
        echo "✗ CONFLICT (409): the workflow changed since you loaded it — another session/agent saved. Your patch was NOT applied (no clobber)." >&2
        [ -n "$current" ] && echo "  current updatedAt:  $current" >&2
        [ -n "$yours" ]   && echo "  your baseUpdatedAt: $yours" >&2
        echo "  Re-fetch with 'wf.sh get $id', reapply your edit, and patch-node again." >&2
        exit 1
        ;;
      ''|000)
        echo "✗ patch-node failed — could not reach $BASE (connection error)" >&2
        exit 1 ;;
      *)
        # 400 invalid_field / 404 / 403 / 413 — print the server's message verbatim.
        echo "✗ patch-node failed (HTTP $code)" >&2
        printf '%s\n' "$payload" >&2
        exit 1 ;;
    esac
    ;;

  layout)
    file="${1:?usage: wf.sh layout <workflow.json> [out.json]}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/layout.py" "$file" "${2:-}"
    ;;

  organize)
    # Refactor a live graph "like a codebase": hoist text reused by 2+ nodes
    # into shared input:text constants, wrap related nodes into labelled
    # custom_group modules, and re-space everything as swimlanes (X = dataflow,
    # Y = module band). Non-destructive: only adds groups/constants + moves nodes.
    #
    #   wf.sh organize <id>                  # heuristic plan -> apply (PUT)
    #   wf.sh organize <id> --dump-plan      # print the proposed plan, no changes
    #   wf.sh organize <id> --plan plan.json # apply a hand-authored (semantic) plan
    #   wf.sh organize <id> --save out.json  # also write the organized graph locally
    #
    # Hybrid workflow: `--dump-plan` to get the heuristic's modules, hand-edit the
    # names/boundaries, then re-apply with `--plan`. See references/organize.md.
    id="${1:?usage: wf.sh organize <workflowId> [--dump-plan] [--plan p.json] [--save out.json]}"
    shift
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    plan_arg=(); dims_arg=(); dump=0; save=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --plan) plan_arg=(--plan "$2"); shift 2;;
        --dims) dims_arg=("--dims=$2"); shift 2;;   # real node sizes (dims.json) → exact spacing
        --dump-plan) dump=1; shift;;
        --save) save="$2"; shift 2;;
        *) shift;;
      esac
    done
    full="$(mktemp)"; graph="$(mktemp)"; out="$(mktemp)"; put="$(mktemp)"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id" \
      | jq '(.workflow // .data // .)' > "$full"
    jq '{nodes, edges}' "$full" > "$graph"
    if ! jq -e '.nodes | type == "array"' "$graph" >/dev/null 2>&1; then
      echo "✗ organize — could not read nodes/edges from GET $id" >&2
      exit 1
    fi
    if [ "$dump" = 1 ]; then
      # ${arr[@]+...} guard: empty arrays are safe under `set -u` on bash 3.2
      python3 "$SCRIPT_DIR/organize.py" "$graph" ${plan_arg[@]+"${plan_arg[@]}"} --dump-plan
      exit 0
    fi
    if ! python3 "$SCRIPT_DIR/organize.py" "$graph" "$out" \
         ${plan_arg[@]+"${plan_arg[@]}"} ${dims_arg[@]+"${dims_arg[@]}"} >&2; then
      echo "✗ organize — organize.py failed" >&2
      exit 1
    fi
    [ -n "$save" ] && cp "$out" "$save" && echo "saved organized graph -> $save" >&2
    # Build the PUT body from WRITABLE fields only. Round-tripping the full
    # GET object 400s: the API rejects non-writable fields (linkPermission
    # since 2026-07 — "use POST /visibility"), and server-derived state
    # (userId/mediaId/timestamps) doesn't belong in a PUT either.
    jq --slurpfile o "$out" '{name, description, tags, isActive, nodes: $o[0].nodes, edges: $o[0].edges} | with_entries(select(.value != null))' "$full" > "$put"
    # Same gate as create/update: repo wf-check.ts on-repo, else server-side
    # /workflows/lint — so organize's apply step is gated without the repo too.
    if [ -z "${WF_SKIP_CHECK:-}" ]; then
      if ! wf_lint "$put"; then
        echo "✗ organize blocked — graph-lint failed (WF_SKIP_CHECK=1 to override)" >&2
        exit 1
      fi
    fi
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X PUT "$BASE/workflows/$id" --data-binary "@$put"
    ;;

  run)
    # <inputs> may be a FILE PATH or an inline JSON string, e.g.
    #   wf.sh run <id> inputs.json
    #   wf.sh run <id> '{"inputs":{"node_1":"hello"}}'
    id="${1:?usage: wf.sh run <workflowId> <inputs.json | '{json}'>}"
    inputs="${2:?usage: wf.sh run <workflowId> <inputs.json | '{json}'>}"
    if [ -f "$inputs" ]; then
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/workflows/$id/run" --data-binary "@$inputs"
    else
      # Inline JSON still goes via a temp file — an inputs blob can carry a
      # base64 payload or a long caption array and blow ARG_MAX as argv.
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/workflows/$id/run" \
        --data-binary "@$(wf_body_file "$inputs")"
    fi
    ;;

  run-node)
    # Re-run ONE node and reuse cached upstream outputs — no full-graph re-roll.
    # `wf.sh run` re-executes EVERY node (re-rolling AI gens, so the media
    # changes each time). run-node hits /execute with targetNodeId: only that
    # node + any upstream deps WITHOUT a cached result run; everything else is
    # passed for data. Use this to re-render the remotion node after a caption/
    # graph edit WITHOUT re-generating the (good, expensive) Kling/image gens.
    # The TARGET always recomputes from its CURRENT config — editing a node's
    # config (e.g. a TTS node's text) and run-node'ing it now returns fresh
    # output, never the previous cached render.
    # Returns an executionId — poll it with `wf.sh poll <executionId>`.
    wf_id="${1:?usage: wf.sh run-node <workflowId> <nodeId>}"
    node_id="${2:?usage: wf.sh run-node <workflowId> <nodeId>}"
    # Body via temp file: a graph with result history exceeds ARG_MAX as argv.
    rn_body=$(wf_tmpfile)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$wf_id" \
      | NODE_ID="$node_id" python3 -c '
import json, sys, os
wf = json.load(sys.stdin)
json.dump({
    "nodes": wf.get("nodes", []),
    "edges": wf.get("edges", []),
    "targetNodeId": os.environ["NODE_ID"],
}, open(sys.argv[1], "w"))' "$rn_body"
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$wf_id/execute" --data-binary "@$rn_body")
    code=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    printf '%s\n' "$body"
    # Fail loud on non-2xx (incl. a 429 swallowed before this fix → a render
    # proceeding on the wrong cached voice). A run that didn't start must NOT
    # read as success.
    case "$code" in
      2*) ;;
      *) echo "✗ run-node FAILED (HTTP $code): execution did NOT start — nothing to poll." >&2; exit 1 ;;
    esac
    # Even on 2xx, confirm an execution actually came back (executionRuns[].id),
    # so a malformed/empty success body fails loud instead of leaving poll blind.
    printf '%s' "$body" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.stderr.write("✗ run-node: non-JSON response — execution may not have started.\n"); sys.exit(1)
runs = d.get("executionRuns") or []
if not (runs and runs[0].get("id")) and not d.get("executionId"):
    sys.stderr.write("✗ run-node: success status but no executionId in response — nothing to poll.\n"); sys.exit(1)
# Loud stale-upstream warning: a PAID upstream node is serving a cached result
# whose inputs changed since it last ran, so this targeted run built on old data.
for s in (d.get("staleDependencies") or []):
    sys.stderr.write("⚠️  STALE upstream: paid node %r served a CACHED result; its inputs changed (%s). Re-run it to refresh.\n" % (s.get("nodeId"), ",".join(s.get("changedKeys", []))))
' || exit 1
    ;;

  run-force)
    # Like `run` but clears EVERY node's cached output first (--no-cache): a
    # full re-roll from scratch, ignoring all prior renders/generations. Use
    # when you suspect stale cached state anywhere in the graph.
    wf_id="${1:?usage: wf.sh run-force <workflowId>}"
    # Body goes via a temp file: a graph carrying result history exceeds
    # ARG_MAX, and --data-binary "$var" ships the whole body as one argv.
    rf_body=$(wf_tmpfile)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$wf_id" \
      | python3 -c '
import json, sys
wf = json.load(sys.stdin)
json.dump({
    "nodes": wf.get("nodes", []),
    "edges": wf.get("edges", []),
    "force": True,
}, open(sys.argv[1], "w"))' "$rf_body"
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$wf_id/execute" --data-binary "@$rf_body")
    code=$(printf '%s' "$resp" | tail -n1)
    printf '%s\n' "$(printf '%s' "$resp" | sed '$d')"
    case "$code" in
      2*) ;;
      *) echo "✗ run-force FAILED (HTTP $code): execution did NOT start." >&2; exit 1 ;;
    esac
    ;;

  poll)
    exec_id="${1:?usage: wf.sh poll <executionId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/executions/$exec_id/poll"
    ;;

  wait)
    # BLOCK until an execution reaches COMPLETED/FAILED, printing per-node status
    # each tick — so you can tell "rendering" from "dead" instead of polling a
    # null by hand. Reads the poll response's `nodeStates` [{nodeId,label,status,
    # error,outputUrl}]. Polls every 6s (safe under the 10/min API limit) and
    # backs off on a 429. On FAILED it prints the failing node's error (e.g. a
    # FAL moderation rejection); on COMPLETED it prints the output URLs.
    #   WF_WAIT_INTERVAL (default 6s), WF_WAIT_MAX_TICKS (default 200 = ~20 min).
    exec_id="${1:?usage: wf.sh wait <executionId>}"
    interval="${WF_WAIT_INTERVAL:-6}"
    max_ticks="${WF_WAIT_MAX_TICKS:-200}"
    tick=0
    while [ "$tick" -lt "$max_ticks" ]; do
      resp=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" -w $'\n%{http_code}' \
        "$BASE/workflows/executions/$exec_id/poll")
      code=$(printf '%s' "$resp" | tail -n1)
      body=$(printf '%s' "$resp" | sed '$d')
      if [ "$code" = "429" ]; then
        echo "⏳ rate-limited (429) — backing off 30s" >&2
        sleep 30; tick=$((tick + 1)); continue
      fi
      if [ "$code" != "200" ]; then
        echo "✗ poll HTTP $code: $body" >&2; exit 1
      fi
      # Shape-robust status read. The executions/<id>/poll endpoint returns a
      # top-level UPPERCASE `.status` for BOTH full-run and run-node (single-node)
      # executions. But the /run and /execute endpoints wrap their status under
      # `.data.status` in lowercase ("running"/"completed") — so if a caller ever
      # feeds `wait` one of those (or the server shape shifts), read either place
      # and normalize the case, or the loop would never see COMPLETED and hang.
      status=$(printf '%s' "$body" | jq -r \
        '((.status // .data.status) // "UNKNOWN") | ascii_upcase')
      printf '[%s] ' "$status"
      printf '%s\n' "$body" | jq -r \
        '((.nodeStates // .data.nodeStates) // []) | map("\(.label // .nodeId):\(.status)") | join("  ")'
      case "$status" in
        COMPLETED)
          echo "✓ COMPLETED"
          printf '%s' "$body" | jq -r \
            '((.nodeStates // .data.nodeStates) // []) | .[] |
               ((.outputUrls // (if .outputUrl then [.outputUrl] else [] end))) as $u |
               (if ($u | length) > 1
                  then "  → \(.label // .nodeId) (\($u | length) outputs):", ($u[] | "      \(.)")
                elif ($u | length) == 1
                  then "  → \(.label // .nodeId): \($u[0])"
                else empty end),
               (if .text then "  ✎ \(.label // .nodeId): \(.text | gsub("\\s+";" ") | .[0:140])\(if (.text|length) > 140 then "…" else "" end)" else empty end)'
          exit 0 ;;
        FAILED)
          echo "✗ FAILED" >&2
          printf '%s' "$body" | jq -r \
            '((.nodeStates // .data.nodeStates) // []) | map(select(.status=="FAILED")) | .[] | "  ✗ \(.label // .nodeId): \(.error // "no error detail")"' >&2
          printf '%s' "$body" | jq -r '(.error // .data.error) // empty' >&2
          exit 1 ;;
      esac
      sleep "$interval"; tick=$((tick + 1))
    done
    echo "✗ timed out after $((max_ticks * interval))s — last status: $status" >&2
    exit 1
    ;;

  list)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows"
    ;;

  get)
    id="${1:?usage: wf.sh get <workflowId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id"
    ;;

  duplicate)
    # Server-side clone of a workflow → a NEW workflow you own. Optional name
    # overrides the copy's name (default: the server picks one). Prints the new
    # id + url plainly so callers can parse them. Goes through wf_curl so a 429
    # backs off; any non-2xx fails LOUD (exit 1) — a swallowed clone that reads
    # as success is the write footgun this repo guards against.
    id="${1:?usage: wf.sh duplicate <workflowId> [name]}"
    name="${2:-}"
    if [ -n "$name" ]; then
      body="$(jq -nc --arg n "$name" '{name:$n}')"
    else
      body='{}'
    fi
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$id/duplicate" --data-binary "$body") || true
    code=$(printf '%s' "$resp" | tail -n1)
    payload=$(printf '%s' "$resp" | sed '$d')
    case "$code" in
      2*)
        new_id=$(printf '%s' "$payload" | jq -r '.data.id // empty' 2>/dev/null || true)
        url=$(printf '%s' "$payload" | jq -r '.data.url // empty' 2>/dev/null || true)
        # A 2xx without a parseable new id is NOT success — an empty/odd body
        # printed as a blank line + exit 0 would read as a clone that landed.
        if [ -z "$new_id" ]; then
          echo "✗ duplicate returned HTTP $code but no workflow id in the response:" >&2
          printf '%s\n' "$payload" >&2
          exit 1
        fi
        printf 'id:  %s\n' "$new_id"
        if [ -n "$url" ]; then printf 'url: %s\n' "$url"; fi
        ;;
      ''|000)
        echo "✗ duplicate failed — could not reach $BASE (connection error)" >&2
        exit 1 ;;
      *)
        echo "✗ duplicate failed (HTTP $code)" >&2
        printf '%s\n' "$payload" >&2
        exit 1 ;;
    esac
    ;;

  publish|unpublish)
    # Flip a workflow's public visibility via POST :id/visibility (shipped
    # 2026-07-20; needs the endpoint deployed). publish = VIEW (public page at
    # /workflows/<id>), unpublish = PRIVATE. Going public re-sanitizes nodes
    # server-side (secret-shaped config/params values are wiped in place).
    # NOTE: the v1 PUT silently ignored linkPermission historically and now
    # 400s on it — this verb is the correct path.
    id="${1:?usage: wf.sh publish|unpublish <workflowId>}"
    if [ "$cmd" = "publish" ]; then vis="view"; else vis="private"; fi
    resp=$(wf_curl "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$id/visibility" \
      --data-binary "$(jq -nc --arg v "$vis" '{visibility:$v}')") || true
    code=$(printf '%s' "$resp" | tail -n1)
    payload=$(printf '%s' "$resp" | sed '$d')
    case "$code" in
      2*)
        perm=$(printf '%s' "$payload" | jq -r '.linkPermission // .data.linkPermission // empty' 2>/dev/null || true)
        url=$(printf '%s' "$payload" | jq -r '.url // .data.url // empty' 2>/dev/null || true)
        if [ -z "$perm" ]; then
          echo "✗ $cmd returned HTTP $code but no linkPermission in the response:" >&2
          printf '%s\n' "$payload" >&2
          exit 1
        fi
        printf 'linkPermission: %s\n' "$perm"
        if [ -n "$url" ]; then printf 'url: %s\n' "$url"; fi
        ;;
      404)
        echo "✗ $cmd failed (HTTP 404) — workflow not found, not yours, or the /visibility endpoint is not deployed yet" >&2
        exit 1 ;;
      ''|000)
        echo "✗ $cmd failed — could not reach $BASE (connection error)" >&2
        exit 1 ;;
      *)
        echo "✗ $cmd failed (HTTP $code)" >&2
        printf '%s\n' "$payload" >&2
        exit 1 ;;
    esac
    ;;

  delete)
    # Delete a workflow (cleans up double-creates / throwaway test flows so they
    # don't pile up). Scope: workflows:write. Irreversible — deletes only the
    # flow you own.
    id="${1:?usage: wf.sh delete <workflowId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" -X DELETE "$BASE/workflows/$id"
    ;;

  inputs)
    id="${1:?usage: wf.sh inputs <workflowId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id/run"
    ;;

  upload)
    # Host a local file (or rehost a remote url) onto cdn.wireflow.ai and print
    # the public URL — the one primitive that lets an agent get a real asset
    # (product screenshot, logo, reference image) into a workflow. The printed
    # url is already on the executor allowlist, so wire it straight into an
    # input:image / input:video / compv3 node. Scope: workflows:write.
    #   url=$(wf.sh upload /tmp/shot.png)   # -> https://cdn.wireflow.ai/uploads/...
    src="${1:?usage: wf.sh upload <file|url>}"
    case "$src" in
      http://*|https://*)
        resp=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
          -X POST "$BASE/media/upload" \
          -d "$(jq -nc --arg u "$src" '{url:$u}')") ;;
      *)
        [ -f "$src" ] || { echo "file not found: $src" >&2; exit 2; }
        # Derive the MIME from the extension and send it explicitly — curl -F
        # otherwise sends application/octet-stream, which some clients can't
        # recover from. (The server also infers from the extension as a fallback.)
        case "${src##*.}" in
          jpg|jpeg) mime=image/jpeg ;;
          png)      mime=image/png ;;
          gif)      mime=image/gif ;;
          webp)     mime=image/webp ;;
          avif)     mime=image/avif ;;
          mp4)      mime=video/mp4 ;;
          webm)     mime=video/webm ;;
          mov)      mime=video/quicktime ;;
          mp3)      mime=audio/mpeg ;;
          wav)      mime=audio/wav ;;
          m4a)      mime=audio/mp4 ;;
          *)        mime=application/octet-stream ;;
        esac
        resp=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" \
          -X POST "$BASE/media/upload" \
          -F "file=@$src;type=$mime") ;;
    esac
    # Print just the CDN url (the point of the command). On error, dump the
    # raw JSON to stderr and fail so callers see what went wrong.
    if url=$(printf '%s' "$resp" | jq -re '.data.url' 2>/dev/null); then
      printf '%s\n' "$url"
    else
      printf '%s\n' "$resp" >&2
      exit 1
    fi
    ;;

  media)
    # List assets you've uploaded via the API (upload once, reuse the url).
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/media"
    ;;

  preview)
    # Dry-run a SceneGraph: validates it, renders ~3 sampled STILL frames on
    # Lambda (cents, not FAL credits — no full video render), and returns their
    # CDN urls + diagnostics (validation repairs, placeholder blocks, duration).
    # LOOK at the frames and self-correct BEFORE paying for a full render.
    # Repo-free version of `wf.sh see`. Accepts a raw { fps,width,height,scenes }
    # graph or a { sceneGraph: {...} } wrapper.
    # <sceneGraph> may be a file path or an inline JSON string.
    file="${1:?usage: wf.sh preview <sceneGraph.json | '{json}'>}"
    if [ -f "$file" ]; then
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/render/remotion/preview" --data-binary "@$file"
    else
      # A whole sceneGraph inline is exactly the shape that overflows argv.
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/render/remotion/preview" \
        --data-binary "@$(wf_body_file "$file")"
    fi
    ;;

  download)
    # Pull a render/output file. cdn.wireflow.ai 403s plain curl/python (edge
    # WAF user-agent block — infra-level, not fixable in the app), so route
    # through the app's allowlisted download proxy: it fetches server-side (no
    # UA block) and needs no auth. Whitelisted hosts: cdn.wireflow.ai, fal.media,
    # replicate.delivery, storage.googleapis.com, oai blob. For other hosts it
    # falls back to a direct fetch with a browser UA.
    src="${1:?usage: wf.sh download <url> [out.file]}"
    out="${2:-$(basename "${src%%\?*}")}"
    origin="${BASE%/api/v1}"
    case "$src" in
      *cdn.wireflow.ai/*|*cdn.atomu.ai/*|*fal.media/*|*replicate.delivery/*|*storage.googleapis.com/*|*oaidalleapiprodscus.blob.core.windows.net/*)
        curl -fsSL -G "$origin/api/download" --data-urlencode "url=$src" -o "$out" \
          && echo "saved → $out" ;;
      *)
        curl -fsSL -A "Mozilla/5.0" "$src" -o "$out" && echo "saved → $out" ;;
    esac
    ;;

  credits)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/developer/usage"
    ;;

  estimate)
    # wf.sh estimate <workflowId> — predicted credit cost of a run, per node.
    # Quote THIS number to the user, never a rule of thumb; estimateComplete
    # false means the total is a lower bound (see references/api.md).
    id="${1:?usage: wf.sh estimate <workflowId>}"
    curl "${CURL_FLAGS[@]}" -X POST "${AUTH[@]}" -H 'Content-Type: application/json' \
      -d '{}' "$BASE/workflows/$id/estimate"
    ;;

  ""|-h|--help|help)
    sed -n '2,40p' "$0"
    ;;

  *)
    echo "unknown command: $cmd" >&2
    echo "run 'wf.sh help' for usage" >&2
    exit 2
    ;;
esac
