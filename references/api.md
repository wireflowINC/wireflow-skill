# Wireflow API Reference

Base URL: `https://wireflow.ai/api/v1` (override with `$WIREFLOW_BASE_URL`)

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
{ "data": { "id": "cmnxw...", "name": "My Workflow", ... } }
```

Empty workflows (0 nodes, 0 edges) are rejected as likely frontend bugs.

### `GET /workflows` — list user workflows

**Scope:** `workflows:read`

**Query params:** `teamId`, `mediaId`, `isActive`

### `GET /workflows/:id` — fetch one

**Scope:** `workflows:read`

### `PUT /workflows/:id` — replace

**Scope:** `workflows:write`

### `DELETE /workflows/:id`

**Scope:** `workflows:write`

## Execution

### `POST /workflows/:id/run` — run with inputs

Higher-level wrapper around `/execute`. Takes friendly `inputs` keyed by
the node ID of input-category nodes.

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
paths the `compose:remotion` node should expose as input ports.

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
  https://wireflow.ai/api/v1/developer/usage
```
