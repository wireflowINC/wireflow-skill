#!/usr/bin/env bash
# Wireflow API helper — single dispatcher for common operations.
#
# Usage:
#   wf.sh templates                      # list remotion templates
#   wf.sh template <id>                  # fetch one template spec
#   wf.sh nodes                          # node catalog (every type + its ports)
#   wf.sh blocks                         # motion-graphics block library
#   wf.sh generate "<prompt>"            # AI-generate a workflow from a prompt
#   wf.sh check <workflow.json>          # GATE: graph-lint (caps+cycle+handles)
#   wf.sh create <workflow.json>         # create (gated on check; auto-layout)
#   wf.sh layout <workflow.json> [out]   # re-space nodes (no overlap), no API call
#   wf.sh run <workflowId> <inputs.json> # run a workflow with inputs
#   wf.sh poll <executionId>             # poll execution status
#   wf.sh list                           # list workflows
#   wf.sh get <workflowId>               # fetch one workflow
#   wf.sh inputs <workflowId>            # show valid input keys for /run
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
    # Catalog of reusable motion-graphics Blocks (id, props schema, ports,
    # preview). Compose one as a SceneGraph scene: {type:'block',blockId,props}.
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/blocks"
    ;;

  nodes)
    # The node catalog — every node type + its ports (what you can wire).
    # This is the source of truth `check` validates edge handles against.
    # Pipe to jq to filter, e.g.: wf.sh nodes | jq '.nodes[] | select(.category=="Audio")'
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

  layout)
    file="${1:?usage: wf.sh layout <workflow.json> [out.json]}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/layout.py" "$file" "${2:-}"
    ;;

  run)
    id="${1:?usage: wf.sh run <workflowId> <inputs.json>}"
    inputs="${2:?usage: wf.sh run <workflowId> <inputs.json>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$id/run" \
      --data-binary "@$inputs"
    ;;

  poll)
    exec_id="${1:?usage: wf.sh poll <executionId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/executions/$exec_id/poll"
    ;;

  list)
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows"
    ;;

  get)
    id="${1:?usage: wf.sh get <workflowId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id"
    ;;

  inputs)
    id="${1:?usage: wf.sh inputs <workflowId>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "$BASE/workflows/$id/run"
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
    sed -n '2,20p' "$0"
    ;;

  *)
    echo "unknown command: $cmd" >&2
    echo "run 'wf.sh help' for usage" >&2
    exit 2
    ;;
esac
