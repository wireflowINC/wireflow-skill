#!/usr/bin/env bash
# Wireflow API helper — single dispatcher for common operations.
#
# Usage:
#   wf.sh templates                      # list remotion templates
#   wf.sh template <id>                  # fetch one template spec
#   wf.sh generate "<prompt>"            # AI-generate a workflow from a prompt
#   wf.sh create <workflow.json>         # create a workflow from a JSON file
#   wf.sh run <workflowId> <inputs.json> # run a workflow with inputs
#   wf.sh poll <executionId>             # poll execution status
#   wf.sh list                           # list workflows
#   wf.sh get <workflowId>               # fetch one workflow
#   wf.sh inputs <workflowId>            # show valid input keys for /run
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

  generate)
    prompt="${1:?usage: wf.sh generate \"<prompt>\"}"
    curl "${CURL_FLAGS[@]}" -N "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/generate/stream" \
      -d "$(jq -nc --arg p "$prompt" '{prompt:$p}')"
    ;;

  create)
    file="${1:?usage: wf.sh create <workflow.json>}"
    curl "${CURL_FLAGS[@]}" "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows" \
      --data-binary "@$file"
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
