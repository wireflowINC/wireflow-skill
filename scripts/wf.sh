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
#   WIREFLOW_API_KEY   (required)
#   WIREFLOW_BASE_URL  (optional, default https://wireflow.ai/api/v1)

set -euo pipefail

BASE="${WIREFLOW_BASE_URL:-https://wireflow.ai/api/v1}"

if [ -z "${WIREFLOW_API_KEY:-}" ]; then
  echo "error: WIREFLOW_API_KEY is not set. Create one at https://wireflow.ai/settings/api-keys" >&2
  exit 2
fi

AUTH=(-H "Authorization: Bearer $WIREFLOW_API_KEY")
CT=(-H "Content-Type: application/json")

cmd="${1:-}"
shift || true

case "$cmd" in
  templates)
    curl -sS "${AUTH[@]}" "$BASE/remotion/templates"
    ;;

  template)
    id="${1:?usage: wf.sh template <id>}"
    curl -sS "${AUTH[@]}" "$BASE/remotion/templates/$id"
    ;;

  generate)
    prompt="${1:?usage: wf.sh generate \"<prompt>\"}"
    curl -sS -N "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/generate/stream" \
      -d "$(jq -nc --arg p "$prompt" '{prompt:$p}')"
    ;;

  create)
    file="${1:?usage: wf.sh create <workflow.json>}"
    curl -sS "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows" \
      --data-binary "@$file"
    ;;

  run)
    id="${1:?usage: wf.sh run <workflowId> <inputs.json>}"
    inputs="${2:?usage: wf.sh run <workflowId> <inputs.json>}"
    curl -sS "${AUTH[@]}" "${CT[@]}" \
      -X POST "$BASE/workflows/$id/run" \
      --data-binary "@$inputs"
    ;;

  poll)
    exec_id="${1:?usage: wf.sh poll <executionId>}"
    curl -sS "${AUTH[@]}" "$BASE/workflows/executions/$exec_id/poll"
    ;;

  list)
    curl -sS "${AUTH[@]}" "$BASE/workflows"
    ;;

  get)
    id="${1:?usage: wf.sh get <workflowId>}"
    curl -sS "${AUTH[@]}" "$BASE/workflows/$id"
    ;;

  inputs)
    id="${1:?usage: wf.sh inputs <workflowId>}"
    curl -sS "${AUTH[@]}" "$BASE/workflows/$id/run"
    ;;

  credits)
    curl -sS "${AUTH[@]}" "$BASE/developer/usage"
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
