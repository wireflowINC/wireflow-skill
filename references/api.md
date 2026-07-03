# Wireflow API Reference

Base URL: `https://www.wireflow.ai/api/v1` (override with `$WIREFLOW_BASE_URL`)

Auth: `Authorization: Bearer $WIREFLOW_API_KEY`

Content type: `application/json`

## Workflows — CRUD

### `POST /workflows` — create or update

Create a new workflow (omit `id`) or update an existing one (include `id`).

**Scope:** `workflows:write`

**Body:**
```json
{
  "id": "optional-existing-id",
  "name": "My Workflow",
  "description": "Optional",
  "nodes": [ /* Node[] */ ],
  "edges": [ /* Edge[] */ ],
  "tags": ["demo"],
  "isActive": true
}
```

**Response:**
```json
{
  "data": { "id": "cmnxw...", "name": "My Workflow", ... },
  "meta": { "migrations": [ ... ], "warnings": [ ... ] }
}
```

`meta.migrations` lists what the server normalized for you (e.g. a deprecated
`compose:remotion` rewritten to `video:remotion`, a sticky note's `node.type`
set to `stickyNote`, or a `video:remotion` template's input ports materialized).
`meta.warnings` are non-blocking lint notes.

Empty workflows (0 nodes, 0 edges) are rejected as likely frontend bugs.

**Graph validation (fail-closed).** Before saving, the server normalizes the
graph and runs the SAME graph-lint gate as `wf check`. If the graph has errors
(unknown `nodeType`, deprecated alias that can't be auto-migrated, a dangling
edge, an edge to a port that doesn't exist, or a cycle) it returns **HTTP 422**:

```json
{
  "error": { "type": "invalid_request_error", "code": "invalid_graph",
             "message": "Workflow graph failed validation (N errors). ..." },
  "violations": [ { "rule": "bad-target-handle", "message": "...",
                    "fix": "Did you mean \"in-hookImage\"? ...",
                    "nodeId": "...", "edgeId": "..." } ],
  "warnings": [ ... ],
  "migrations": [ ... ]
}
```

Each violation carries a concrete `fix` (often a "did you mean" suggestion).
Run `wf check <workflow.json>` locally first to catch these before POSTing.
Pass `?strict=false` to save a graph despite errors (rare — only for
dynamic-port graphs the static gate can't fully verify).

### `GET /workflows` — list user workflows

**Scope:** `workflows:read`

**Query params:** `teamId`, `mediaId`, `isActive`

### `GET /workflows/:id` — fetch one

**Scope:** `workflows:read`

### `PUT /workflows/:id` — replace

**Scope:** `workflows:write`

### `PATCH /workflows/:id/nodes/:nodeId` (patch ONE node)

**Scope:** `workflows:write`

Update a single node in place without round-tripping the whole graph. At least
one of `config`, `params`, `label`, `position` is required.

**Body:**
```json
{ "config": { "prompt": "new hook text" },
  "params": { "seed": 42 },
  "label": "Hook Writer",
  "position": { "x": 120, "y": 40 },
  "baseUpdatedAt": "2026-07-02T10:00:00.000Z" }
```

**Merge semantics:**
- `config` and `params` merge **shallowly, per key**: keys you send are set,
  keys you omit are left alone, and a key set to `null` **deletes** it.
- `label` and `position` **replace** (no merge).
- The server refreshes derived output for `input:*` nodes and mirrors `config`
  into `params`, so a one-key patch on a prompt just works (no need to also send
  `params` or the node's `output`).

**Forbidden fields:** `output`, `result`, `nodeType`, `isExecuting`, and other
structural keys are rejected with `400 invalid_field` (a single-node patch can't
restructure the graph, so there is no graph-lint gate on this route).

**Optimistic concurrency:** the server **always** compare-and-swaps the write.
If a concurrent write landed after yours started, it returns `409`:
```json
{ "error": { "type": "conflict_error", "code": "stale_write" },
  "currentUpdatedAt": "2026-07-02T10:03:00.000Z",
  "yourBaseUpdatedAt": "2026-07-02T10:00:00.000Z" }
```
Passing `baseUpdatedAt` (the `updatedAt` you saw when you loaded the workflow)
additionally makes the server reject the patch if the workflow changed since
**you** loaded it, not just during the write window. On a `409`, re-`GET` the
workflow, reapply your edit, and patch again. Nothing was clobbered.

**Response:** `200`
```json
{ "data": { "node": { "id": "node_abc", "data": { "label": "Hook Writer" } },
            "updatedAt": "2026-07-02T10:05:00.000Z" } }
```

Other errors: `404` (node or workflow not found), `403` (wrong owner / missing
scope), `413` (body over the 256KB cap).

`bash scripts/wf.sh patch-node <flowId> <nodeId> '<json-body>'` does this for
you: it validates the JSON locally (exit 2 on bad input, no network call),
injects the current `updatedAt` as `baseUpdatedAt` (skip with
`WF_SKIP_CONCURRENCY=1` or by supplying your own), prints the patched node id +
label + new `updatedAt` on success, and fails loud on `409`/`400`/other (exit
1).

### `DELETE /workflows/:id`

**Scope:** `workflows:write`

### `POST /workflows/:id/duplicate` — clone a workflow

**Scope:** `workflows:write`

Server-side clones a workflow (a template or an existing flow) into a NEW one
you own. Body is optional; pass `{ "name": "..." }` to override the copy's name.

**Response:** `201`
```json
{ "data": { "id": "cmnxw...", "name": "My Workflow (copy)",
            "url": "https://www.wireflow.ai/workflows/cmnxw..." } }
```

`bash scripts/wf.sh duplicate <id> [name]` prints the new `id` + `url`; non-2xx
fails loud (exit 1).

### `POST /workflows/lint` — graph-lint without the repo

**Scope:** `workflows:read`

Runs the SAME graph-lint gate as create/update, but as a standalone endpoint so
a caller without the wireflow codebase can validate a graph. Body is
`{ nodes, edges }` or a full workflow object.

**Response:** `200`
```json
{ "data": { "ok": true,
            "violations": [ { "rule": "bad-target-handle", "message": "...",
                              "fix": "Did you mean \"in-hook\"?", "nodeId": "..." } ],
            "warnings": [ ... ] } }
```

`ok:false` means the graph has violations (block the write). `wf.sh check` uses
the repo's `wf-check.ts` on-repo and this endpoint off-repo. If the server
predates this endpoint (404) or errors: standalone `wf.sh check` fails CLOSED
(warns `UNVERIFIED`, exit 2), while the gates inside `create`/`update`/
`organize` warn `UNVERIFIED` and proceed (the write surfaces real errors).

## Execution

### `POST /workflows/:id/run` — run with inputs

Higher-level wrapper around `/execute`. Takes friendly `inputs` keyed by
the node ID of input-category nodes.

> ⚠️ **`/run` re-executes the WHOLE graph** — every node runs fresh, so any
> non-deterministic AI gen (image/Kling/etc.) is **re-rolled** and the media
> changes on each run. To re-render just one node and KEEP the existing
> upstream creatives, use single-node execution (below) — not `/run`.

**Scope:** `workflows:execute`

**Body:**
```json
{
  "inputs": {
    "1776100982446": "a cow standing in a field",
    "1776100968381e1h3": "https://cdn.wireflow.ai/reference.png"
  }
}
```

To discover valid `inputs` keys for a workflow, call:
```
GET /workflows/:id/run
```
which returns the list of input node IDs, labels, types, and defaults.

**Response:** `{ data: { executionId, status: "RUNNING" } }`

### `POST /workflows/:id/execute` — run ONE node, reuse cached upstream

The "re-render just this node" path (the editor's "Run selected"). Pass
`targetNodeId`: only that node **+ any upstream dependency that lacks a cached
result** runs; every other node is passed through for its data (cached output
reused — no re-roll). This is how you re-render a `video:remotion` node after a
caption/graph edit without re-generating the (good, expensive) Kling/image gens.

**Scope:** `workflows:execute`

**Body:** the full saved graph + the target:
```json
{ "nodes": [ ... ], "edges": [ ... ], "targetNodeId": "reel" }
```
The nodes carry their cached `output`/`result` (fetch them with
`GET /workflows/:id`), which is what lets the executor skip the upstream gens.
The workflow must be active. A server-side credit pre-check still runs.

**Response:** `{ executionId, status }` — poll with the same poll endpoint.

**Skill shortcut:** `wf.sh run-node <workflowId> <nodeId>` does the fetch +
reshape + POST for you, then `wf.sh poll <executionId>`.

### `GET /workflows/executions/:id/poll` — poll status

**Scope:** `workflows:read`

**Response when complete:**
```json
{
  "data": {
    "status": "COMPLETED",
    "nodeResults": { "nodeRuns": [...] },
    "finalOutput": { "url": "https://cdn.wireflow.ai/..." }
  }
}
```

Other statuses: `RUNNING`, `FAILED`, `CANCELLED`.

## AI Workflow Generator

### `POST /workflows/generate/stream` — generate from prompt

Wireflow's built-in generator matches a natural-language prompt against
existing template workflows + AI-composes a new one if no template fits.
**Use this first** — it's cheaper than hand-rolling a workflow JSON.

**Scope:** `workflows:write`

**Body:**
```json
{
  "prompt": "Take a product photo and generate a 5-second Kling video of it spinning",
  "images": ["https://cdn.example.com/product.jpg"]
}
```

Response is server-sent events (SSE). Each event is a partial or final
workflow JSON. Final event contains `{ done: true, workflow: { id, ... } }`.

## Remotion Templates

### `GET /remotion/templates` — list templates

**Scope:** `workflows:read`

**Response:**
```json
{
  "data": [
    {
      "id": "imessage-prank",
      "label": "iMessage Prank",
      "description": "...",
      "category": "prank",
      "compositionId": "IMessagePrank",
      "fps": 30,
      "width": 1080,
      "height": 1920,
      "durationInFrames": 900,
      "defaultProps": { ... },
      "inputMappings": [
        { "propPath": "hookImage", "portId": "hookImage", "portLabel": "Hook Image", "portType": "IMAGE", "required": true },
        ...
      ]
    }
  ]
}
```

### `GET /remotion/templates/:id` — fetch one

**Scope:** `workflows:read`

Returns the full template spec. Use `inputMappings` to know which prop
paths the `video:remotion` node should expose as input ports.

## Rate limits & errors

Standard Stripe-style error envelope:
```json
{
  "error": {
    "type": "invalid_request_error" | "authentication_error" | "insufficient_credits_error" | "api_error",
    "message": "Human-readable",
    "code": "missing_fields"
  }
}
```

Rate limits vary by plan (free tier ~60 req/min, paid ~300 req/min).
429 responses include `Retry-After` header.

## Credits

Every run deducts credits based on model pricing. Check the user's
balance:
```bash
curl -H "Authorization: Bearer $WIREFLOW_API_KEY" \
  https://www.wireflow.ai/api/v1/developer/usage
```
