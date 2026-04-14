# Workflow JSON Schema

A Wireflow workflow is a directed graph of nodes connected by edges.
Nodes produce outputs on typed output ports; edges wire an output port
on one node to an input port on another.

## Top-level shape

```json
{
  "name": "Product spin video",
  "description": "Optional",
  "nodes": [ /* Node[] */ ],
  "edges": [ /* Edge[] */ ],
  "tags": ["api-generated"],
  "isActive": true
}
```

## Node

```json
{
  "id": "unique-id-string",
  "type": "basedNode",
  "position": { "x": 100, "y": 100 },
  "data": {
    "label": "Human label",
    "nodeType": "input:text",
    "category": "input",
    "config": { "prompt": "a cow in a field" },
    "inputs": [],
    "outputs": []
  }
}
```

Key fields in `data`:

- **`nodeType`** — identifies which behavior runs. Prefix tells you the
  family: `input:*`, `generate:*`, `llm:*`, `compose:*`, `utility:*`,
  `logic:*`, `process:*`.
- **`category`** — groups nodes in the visual editor. Execution also
  branches on category: `input`, `generate`, `llm`, `compose`, `utility`,
  `process`, `logic`.
- **`config`** — the node's static configuration (prompts, model params,
  URLs). **This is where UI edits land.** When resolving inputs for a
  downstream node, Wireflow reads `config[key]` first for input-category
  nodes — so setting `config.prompt = "a cow"` on a Text Input node is
  the correct way to bake in a default prompt.
- **`inputs` / `outputs`** — typed port definitions for the visual
  editor. Usually empty on generated workflows; Wireflow infers them
  from the nodeType at runtime.

## Edge

```json
{
  "id": "unique-edge-id",
  "source": "source-node-id",
  "target": "target-node-id",
  "sourceHandle": "out-prompt",
  "targetHandle": "in-prompt"
}
```

**Handle naming convention:**

- `out-<key>` — source output port (e.g. `out-prompt`, `out-image`,
  `out-video`, `out-text`, `out-audio`)
- `in-<key>` — target input port (e.g. `in-prompt`, `in-image`)

The `<key>` must match the port name on both sides. `out-prompt →
in-prompt` is the most common pattern (Text Input → FAL generate node).

## Common node types

### `input:text` — text input node

```json
{
  "id": "text-input-1",
  "type": "basedNode",
  "position": { "x": 100, "y": 100 },
  "data": {
    "label": "Prompt",
    "nodeType": "input:text",
    "category": "input",
    "config": { "prompt": "a futuristic city at sunset" }
  }
}
```

Outputs: `out-prompt`, `out-text` (same value, two handle aliases).

### `input:image` — image upload input

```json
{
  "data": {
    "nodeType": "input:image",
    "category": "input",
    "inputType": "image",
    "config": {
      "image": "https://cdn.wireflow.ai/uploads/...png",
      "imageUrl": "https://cdn.wireflow.ai/uploads/...png"
    }
  }
}
```

Outputs: `out-image`, `out-media`, `out-url`.

### `generate:<model>` — FAL / Replicate / etc. generator

Examples: `generate:nano_banana_2`, `generate:kling_1_6_pro`,
`generate:imagen_3`, `generate:flux_pro_v1_1_ultra`,
`generate:veo_2`.

```json
{
  "data": {
    "nodeType": "generate:nano_banana_2",
    "category": "generate",
    "config": {
      "prompt": "", /* overridden via edge */
      "num_images": 1,
      "aspect_ratio": "9:16"
    }
  }
}
```

Outputs depend on the model: image models emit `out-image`, video models
emit `out-video`.

**Tip:** don't guess model IDs. Call `/workflows/generate/stream` with a
natural-language description — Wireflow's template matcher picks a valid
model for you.

### `llm:openrouter_router` — LLM prompt generator

```json
{
  "data": {
    "nodeType": "llm:openrouter_router",
    "category": "llm",
    "config": {
      "model": "anthropic/claude-sonnet-4-5",
      "systemPrompt": "You turn product names into viral TikTok hooks.",
      "userPrompt": "" /* comes via edge */
    }
  }
}
```

Outputs: `out-text`.

### `compose:remotion` — Remotion video composition

The only way to render a final MP4 via a Wireflow Remotion template.
Always based on a registered template — call
`GET /remotion/templates` to list them.

```json
{
  "data": {
    "label": "Ohnie Reel",
    "nodeType": "compose:remotion",
    "category": "compose",
    "config": {
      "templateId": "ohnie-reel",
      "props": {
        /* merges with the template's defaultProps — override only
           the fields you care about, the rest come from defaults */
        "shots": [ /* ... */ ],
        "audioSrc": "https://cdn.wireflow.ai/.../voiceover.mp3"
      }
    }
  }
}
```

See `references/remotion-templates.md` for full details on mapping
template `inputMappings` to edges.

Outputs: `out-video`, `out-url`.

### `utility:sticky_note` — editor-only note

Not executable. Filtered out during execution.

### `logic:router` — passthrough / conditional routing

Passes values through without modification. Wireflow's edge resolver
traverses through these automatically, so you can use them to keep the
graph tidy without affecting execution.

## Rules that will bite you

1. **Edge handles must match on both sides.** `out-prompt → in-prompt` is
   OK; `out-prompt → in-text` is broken. Handle names come from the
   node's port schema — usually `prompt`, `image`, `video`, `text`,
   `audio`, `media`, `url`.

2. **Input-category nodes: config is source of truth.** If you want a
   text input node to default to "a cow", set
   `data.config.prompt = "a cow"`. Do NOT set `data.output.prompt` —
   that's a stale cache from past executions and will be ignored by the
   current resolver for input nodes.

3. **Don't leave `result` arrays on fresh nodes.** The `/workflows` POST
   endpoint sanitizes most of this, but if you copy a node from an
   existing workflow, strip `result`, `output`, `selectedOutput`, and
   `selectedIndex` before creating.

4. **Unique IDs.** Node and edge IDs must be unique within the workflow.
   Millisecond timestamps + random suffix is a safe pattern:
   `id: \`${Date.now()}${Math.random().toString(36).slice(2, 6)}\``.

5. **Positions matter for the editor, not execution.** Pick reasonable
   `x`/`y` values (100-2000 range) so the user can see the graph when
   they open it in the visual editor.
