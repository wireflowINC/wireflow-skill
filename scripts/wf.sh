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
#   wf.sh check <workflow.json>          # GATE: graph-lint (caps+cycle+handles)
#   wf.sh create <workflow.json>         # create (gated on check; auto-layout)
#   wf.sh update <workflowId> <wf.json>  # replace (gated on check; auto-layout)
#   wf.sh layout <workflow.json> [out]   # re-space nodes (no overlap), no API call
#   wf.sh run <workflowId> <inputs.json> # run a workflow with inputs (re-runs ALL nodes)
#   wf.sh run-node <workflowId> <nodeId> # re-run ONE node (fresh config), reuse cached upstream
#   wf.sh run-force <workflowId>         # full re-roll: clear ALL cached output first (--no-cache)
#   wf.sh poll <executionId>             # poll execution status once
#   wf.sh wait <executionId>             # BLOCK until done; per-node status + errors (rate-aware)
#   wf.sh list                           # list workflows
#   wf.sh get <workflowId>               # fetch one workflow
#   wf.sh delete <workflowId>            # delete a workflow (clean up test/double-created flows)
#   wf.sh inputs <workflowId>            # show valid input keys for /run
#   wf.sh upload <file|url>              # host a local file/remote url → prints CDN url
#   wf.sh media                          # list assets you've uploaded via the API
#   wf.sh preview <sceneGraph.json>      # cheap dry-run: sampled still frames + diagnostics (no paid render)
#   wf.sh download <url> [out]           # pull a render output (bypasses CDN 403)
#   wf.sh credits                        # show remaining credits
#
# Env:
#   WIREFLOW_API_KEY   (required — or place it in a .env file in cwd)
#   WIREFLOW_BASE_URL  (optional, default https://www.wireflow.ai/api/v1)

set -euo pipefail

# Auto-load WIREFLOW_* vars from a .env file in the current directory if
# the key isn't already set in the environment. Keeps repo-scoped keys
# working without asking users to `source .env` manually every session.
# Only pulls WIREFLOW_ prefixed lines so we don't blow away other env.
if [ -z "${WIREFLOW_API_KEY:-}" ] && [ -f ".env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      WIREFLOW_API_KEY=*|WIREFLOW_BASE_URL=*)
        # Strip surrounding quotes if present
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "${line%%=*}=$value"
        ;;
    esac
  done < .env
fi

BASE="${WIREFLOW_BASE_URL:-https://www.wireflow.ai/api/v1}"

if [ -z "${WIREFLOW_API_KEY:-}" ]; then
  cat >&2 <<EOF
error: WIREFLOW_API_KEY is not set.

Options:
  1. Create one at https://www.wireflow.ai/settings?tab=api-keys&section=api-keys
  2. Add it to your shell profile (~/.zshrc or ~/.bashrc):
       export WIREFLOW_API_KEY="wf_live_..."
  3. Or put it in a .env file in the directory you run wf.sh from:
       WIREFLOW_API_KEY=wf_live_...

EOF
  exit 2
fi

# -L so 301/308 redirects (wireflow.ai → www.wireflow.ai) don't swallow
# API responses. Vercel preserves the method + body on 308 for POST.
CURL_FLAGS=(-sS -L)
AUTH=(-H "Authorization: Bearer $WIREFLOW_API_KEY")
CT=(-H "Content-Type: application/json")

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
    # break the catalog exists to kill). Exit 0 = safe, 1 = errors (with fixes).
    # Uses the ONE graph-lint source in the repo (no drift); run from repo root.
    file="${1:?usage: wf.sh check <workflow.json>}"
    if [ -f "scripts/wf-check.ts" ]; then
      npx tsx scripts/wf-check.ts "$file"
    else
      echo "wf check needs the wireflow repo (run from the repo root)" >&2
      exit 2
    fi
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
    # GATE: never POST a graph that fails graph-lint. Set WF_SKIP_CHECK=1 to
    # override (e.g. authoring a dynamic-port-heavy graph the static gate
    # can't fully verify). Run from the repo root so wf-check.ts is found.
    if [ -z "${WF_SKIP_CHECK:-}" ] && [ -f "scripts/wf-check.ts" ]; then
      if ! npx tsx scripts/wf-check.ts "$file" >&2; then
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
    # Same gates as create: never PUT a graph that fails graph-lint, and
    # re-layout before sending — edited graphs (added/removed nodes) are the
    # main source of overlapping "vibe-coded" canvases.
    if [ -z "${WF_SKIP_CHECK:-}" ] && [ -f "scripts/wf-check.ts" ]; then
      if ! npx tsx scripts/wf-check.ts "$file" >&2; then
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
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X PUT "$BASE/workflows/$id" \
      --data-binary "@$send"
    ;;

  layout)
    file="${1:?usage: wf.sh layout <workflow.json> [out.json]}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/layout.py" "$file" "${2:-}"
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
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/workflows/$id/run" --data-binary "$inputs"
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
    body=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$wf_id" \
      | NODE_ID="$node_id" python3 -c '
import json, sys, os
wf = json.load(sys.stdin)
sys.stdout.write(json.dumps({
    "nodes": wf.get("nodes", []),
    "edges": wf.get("edges", []),
    "targetNodeId": os.environ["NODE_ID"],
}))')
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$wf_id/execute" --data-binary "$body"
    ;;

  run-force)
    # Like `run` but clears EVERY node's cached output first (--no-cache): a
    # full re-roll from scratch, ignoring all prior renders/generations. Use
    # when you suspect stale cached state anywhere in the graph.
    wf_id="${1:?usage: wf.sh run-force <workflowId>}"
    body=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$wf_id" \
      | python3 -c '
import json, sys
wf = json.load(sys.stdin)
sys.stdout.write(json.dumps({
    "nodes": wf.get("nodes", []),
    "edges": wf.get("edges", []),
    "force": True,
}))')
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$wf_id/execute" --data-binary "$body"
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
      status=$(printf '%s' "$body" | jq -r '.status // "UNKNOWN"')
      printf '[%s] ' "$status"
      printf '%s\n' "$body" | jq -r \
        '(.nodeStates // []) | map("\(.label // .nodeId):\(.status)") | join("  ")'
      case "$status" in
        COMPLETED)
          echo "✓ COMPLETED"
          printf '%s' "$body" | jq -r \
            '(.nodeStates // []) | map(select(.outputUrl)) | .[] | "  → \(.label // .nodeId): \(.outputUrl)"'
          exit 0 ;;
        FAILED)
          echo "✗ FAILED" >&2
          printf '%s' "$body" | jq -r \
            '(.nodeStates // []) | map(select(.status=="FAILED")) | .[] | "  ✗ \(.label // .nodeId): \(.error // "no error detail")"' >&2
          printf '%s' "$body" | jq -r '.error // empty' >&2
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
        resp=$(curl "${CURL_FLAGS[@]}" "${AUTH[@]}" \
          -X POST "$BASE/media/upload" \
          -F "file=@$src") ;;
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
      curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
        -X POST "$BASE/render/remotion/preview" --data-binary "$file"
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

  ""|-h|--help|help)
    sed -n '2,25p' "$0"
    ;;

  *)
    echo "unknown command: $cmd" >&2
    echo "run 'wf.sh help' for usage" >&2
    exit 2
    ;;
esac
