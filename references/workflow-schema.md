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

### `type` (top-level) — React Flow renderer routing

Different from `data.nodeType`. React Flow uses the top-level `type`
field to pick which component renders the node. Valid values:

- **`"basedNode"`** — the default for ~everything (all FAL models, LLMs,
  inputs, compose, logic, utility)
- **`"stickyNote"`** — **required** for `utility:sticky_note` nodes. If
  you set `type: "basedNode"` for a sticky note, it renders as a generic
  empty card with just the label. The sticky note component specifically
  reads `data.text` (NOT `data.config.text`) — see pitfalls below.
- **`"custom_group"`** — for group containers

Rule of thumb: if `data.nodeType` starts with `utility:sticky_note`,
use `type: "stickyNote"`. Otherwise use `type: "basedNode"`.

### Key fields in `data`

- **`nodeType`** — identifies which behavior runs. Prefix tells you the
  family: `input:*`, `generate:*`, `llm:*`, `video:*`, `audio:*`,
  `talking:*`, `utility:*`, `logic:*`, `process:*`, `output:*`.
- **`category`** — groups nodes in the visual editor. Execution also
  branches on category: `input`, `generate`, `llm`, `video`, `audio`,
  `talking`, `utility`, `logic`, `process`, `output`.
- **`config`** — the node's static configuration (prompts, model params,
  URLs). **This is where UI edits land.** When resolving inputs for a
  downstream node, Wireflow reads `config[key]` first for input-category
  nodes — so setting `config.prompt = "a cow"` on a Text Input node is
  the correct way to bake in a default prompt.
- **`inputs` / `outputs`** — typed port definitions. **Declare these
  explicitly** on any node whose ports should be visually connectable.
  If you omit `inputs: []`, BasedNode renders zero input handles and
  edges targeting that node won't visually attach. **Include ONLY the
  port inputs (`isPort:true`), not config fields** — see "The node catalog
  is NOT a clone source" below. Same goes for `category`: derive it from
  the nodeType, don't copy the catalog's UI-group value.

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

- `out-<portId>` — source output port (e.g. `out-prompt`, `out-images`,
  `out-video`, `out-text`, `out-audio`)
- `in-<portId>` — target input port (e.g. `in-prompt`, `in-image_url`,
  `in-text`)

The `<portId>` segment corresponds to the `id` field of the port in the
node's `inputs` / `outputs` array, NOT a semantic name. For a FAL Kling
node with `inputs: [{ id: "image_url", type: "IMAGE" }]`, the target
handle is `in-image_url` (not `in-image`).

**Source and target handles do NOT need matching key names.** They only
need matching port types. Example: wiring a Nano Banana image generator
into a Kling i2v video node looks like this:

```json
{
  "source": "n-nano-banana",
  "target": "n-kling",
  "sourceHandle": "out-images",   // Nano Banana's output port id is "images"
  "targetHandle": "in-image_url"  // Kling's input port id is "image_url"
}
```

Both are IMAGE type, so the edge is valid even though the keys differ.
Same pattern for wiring an LLM's `out-text` into a FAL image generator's
`in-prompt` — both TEXT, perfectly legal.

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
      "model": "anthropic/claude-sonnet-4.5",
      "max_tokens": 400,
      "temperature": 0.85,
      "system_prompt": "You turn product names into viral TikTok hooks."
    },
    "inputs": [
      { "id": "prompt", "type": "TEXT", "label": "Prompt", "required": true },
      { "id": "system_prompt", "type": "TEXT", "label": "System Prompt", "required": false },
      { "id": "frames", "type": "IMAGE", "label": "Frames", "required": false },
      { "id": "image1", "type": "IMAGE", "label": "Image 1", "required": false }
    ],
    "outputs": [{ "id": "text", "type": "TEXT", "label": "Response" }]
  }
}
```

Fields (all snake_case, NOT camelCase):
- `model` — OpenRouter slug (e.g. `anthropic/claude-sonnet-4.5`,
  `openai/gpt-4o`, `google/gemini-2.0-flash-exp`)
- `system_prompt` — not `systemPrompt`
- `max_tokens`, `temperature` — standard
- User prompt comes via the `in-prompt` port (wired from an upstream
  input:text or an upstream node's text output). Do not use `userPrompt`.

**Best practice: extract system prompts as visible `input:text` nodes.**
Instead of baking `system_prompt` into config, create an `input:text`
node holding the prompt and wire its `out-prompt` into the LLM's
`in-system_prompt` port. This makes prompts first-class canvas objects
— visible, editable inline, diffable across versions, and reusable
across multiple LLM nodes. Only hardcode into config when the prompt is
truly fixed and you want to hide it.

Outputs: `out-text`.

### `video:remotion` — Remotion video composition

The only way to render a final MP4 via a Wireflow Remotion template.
Always based on a registered template — call
`GET /remotion/templates` to list them.

```json
{
  "id": "n-remotion",
  "type": "basedNode",
  "data": {
    "label": "Ohnie Reel",
    "nodeType": "video:remotion",
    "category": "video",
    "config": {
      "templateId": "ohnie-reel",
      "props": {
        /* merges with the template's defaultProps — override only
           the fields you care about, the rest come from defaults */
        "shots": [ /* ... */ ],
        "audioSrc": "https://cdn.wireflow.ai/.../voiceover.mp3"
      }
    },
    "inputs": [
      { "id": "hookImage", "type": "IMAGE", "label": "Image", "required": false },
      { "id": "avatarVideo", "type": "VIDEO", "label": "Video", "required": false },
      { "id": "text", "type": "TEXT", "label": "Text", "required": false }
    ],
    "outputs": [
      { "id": "video", "type": "VIDEO", "label": "Video" },
      { "id": "thumbnail", "type": "IMAGE", "label": "Thumbnail" }
    ]
  }
}
```

**The nodeType is `video:remotion`, not `compose:remotion`.** Older docs
may reference `compose:remotion` — it's wrong.

**Use the default input handles.** The canvas library declares exactly
three input ports for every `video:remotion` node:

- `hookImage` (IMAGE) — the hero/cover image fed into the composition
- `avatarVideo` (VIDEO) — the main speaker / character video
- `text` (TEXT) — caption or any text passthrough

Target handles should be `in-hookImage`, `in-avatarVideo`, `in-text`.
**Do not invent custom handle names** like `in-heroImage` or
`in-speakerVideo` — BasedNode only renders the three handles declared
above, so edges with custom targets will have nothing to attach to
visually (and won't resolve inputs correctly).

See `references/remotion-templates.md` for full details on mapping
template `inputMappings` to the `config.props` shape.

Outputs: `out-video`, `out-thumbnail`.

### `utility:sticky_note` — editor-only note

Not executable. Filtered out during execution. Used for canvas README
notes, design annotations, and inline documentation.

```json
{
  "id": "n-sticky",
  "type": "stickyNote",
  "position": { "x": 40, "y": 40 },
  "width": 520,
  "height": 260,
  "style": { "width": 520, "height": 260 },
  "data": {
    "label": "README",
    "nodeType": "utility:sticky_note",
    "category": "utility",
    "text": "Workflow notes...\n\nBullet one\nBullet two",
    "color": "purple",
    "textSize": "small"
  }
}
```

**Three gotchas that silently break sticky notes:**

1. **Top-level `type` must be `"stickyNote"`**, NOT `"basedNode"`. React
   Flow routes nodes to their renderer by this field. If you use
   `basedNode`, the sticky renders as a generic empty card with just
   the label — no text, no styling.

2. **Content lives at `data.text`**, NOT `data.config.text`. The
   StickyNoteNode component reads from `data.text` directly. Writing
   to `data.config.text` silently does nothing.

3. **Size lives in `style.{width,height}`**, not just top-level
   `width`/`height`. The sticky renders via a React Flow `NodeResizer`
   that reads `style`; a size set only on top-level width/height (or
   omitted) collapses to a tiny ~200×100 default and clips the text. Set
   both `style` and the top-level fields (mirror them). `wf.sh create`'s
   layout pass auto-fixes + auto-sizes stickies, so this only bites when
   you skip layout.

Optional styling: `data.color` (one of `yellow`, `pink`, `blue`,
`green`, `purple`) and `data.textSize` (`small`, `medium`, `large`).

### `logic:router` — passthrough / conditional routing

Passes values through without modification. Wireflow's edge resolver
traverses through these automatically, so you can use them to keep the
graph tidy without affecting execution.

## Rules that will bite you

1. **Edges only need type compatibility, not matching handle keys.**
   The resolver looks up the source output port by `sourceHandle` and
   writes it into the target input port by `targetHandle`. The keys do
   not need to match by name. `out-images → in-image_url` is fine (both
   IMAGE). `out-text → in-prompt` is fine (both TEXT). What you CAN'T
   do is wire incompatible types (e.g. `out-text → in-image_url`).

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
   `x`/`y` values and space nodes ~520px apart horizontally, ~400px
   vertically, so the graph is readable when the user opens it.

## Common pitfalls (real bugs we've hit)

These are all bugs that have silently broken generated workflows. Check
your JSON against every item before calling `POST /workflows`.

### Sticky notes render as empty cards
Symptom: sticky note shows just the label "README" in a generic empty
card, no text, no background color.

Cause: one of two wrong fields.

**Fix:**
- Top-level `type` must be `"stickyNote"`, not `"basedNode"`
- Content goes at `data.text` (top level), not `data.config.text`

### video:remotion node has no visible input handles
Symptom: edges targeting the Remotion node don't visually attach. The
node shows no input circles on its left edge.

Cause: `data.inputs` array was omitted, or custom handle names were
invented (`in-heroImage`, `in-speakerVideo`, etc.).

**Fix:** declare the three canonical ports:
```json
"inputs": [
  { "id": "hookImage", "type": "IMAGE" },
  { "id": "avatarVideo", "type": "VIDEO" },
  { "id": "text", "type": "TEXT" }
]
```
Target handles are then `in-hookImage`, `in-avatarVideo`, `in-text`.

### LLM field names are snake_case
`system_prompt`, `max_tokens`, `temperature` — not `systemPrompt`, not
`userPrompt`. The user prompt comes via the `in-prompt` input port, not
a config field.

### LLM node has wrong nodeType
`llm:openrouter_router` is the correct nodeType for OpenRouter-routed
LLM calls. Not `llm:openai` or `llm:anthropic`. Set the specific model
via `config.model` using the OpenRouter slug
(e.g. `anthropic/claude-sonnet-4.5`, `openai/gpt-4o`).

### `compose:remotion` does not exist
The correct nodeType is `video:remotion`. Any code or doc mentioning
`compose:remotion` is out of date.

### ElevenLabs voice field
Accepts either a premade voice name from the enum (`Rachel`, `Charlie`,
`Bella`, etc.) OR a voice_id. Do NOT pass decorated library names like
`"Charlie - Deep, Confident, Energetic"` — FAL will reject them. When
in doubt, pass a voice_id (28-char string from ElevenLabs).

### Kling model_version must match a real variant
For `video:kling_video_2_5_i2v`, valid values are: `3.0-pro`,
`3.0-standard`, `2.6-pro`, `o1`, `2.5-pro`, `2.5-standard`,
`2.1-master`. Default to `2.5-pro` unless you have a reason to pick
otherwise.

### The node catalog (`wf.sh nodes`) is NOT a clone source for `node.data`

`wf.sh nodes` / `GET /api/v1/nodes` is for **discovery** — finding which
nodeTypes and ports exist. Do NOT copy its node objects verbatim into your
`node.data`. Two fields differ from what a persisted node needs, and both fail
SILENTLY (graph-lint + the API accept them; the bug only shows on the canvas):

**1. Catalog `category` is the UI sidebar group, not the execution category.**
The catalog returns things like `"Helpers"`, `"edit"`, `"Editing"`. But
`data.category` must be the EXECUTION category the renderer + engine use. Using
the catalog value makes the node render as a generic icon-only card (e.g. a Text
Input with no editable prompt field). Set it from the **nodeType**:
- prefixed → the prefix: `input:text`→`input`, `generate:*`→`generate`,
  `video:*`→`video`, `utility:/llm:/audio:/edit:/iterator:/process:` → that prefix.
- non-prefixed → special-case: `compv3` (Compositor) → `process`.

**2. Catalog `inputs` is a FLAT list with no `isPort` — don't dump it all.**
A persisted node's `data.inputs` contains ONLY the connectable **port** inputs
(each `isPort: true`). Config-only fields (`aspect_ratio`, `num_images`,
`resolution`, `quality`, `duration`, `generate_audio`, …) live ONLY in
`data.config`. The catalog lists ports AND config fields together with no flag,
so dumping them all exposes every config knob as a connectable port on the
canvas. Canonical port sets (examples):
- `generate:nano_banana_pro` → `[prompt, image1]`
- `video:bytedance_seedance_v1_lite_text_to_video` → `[prompt, image_url,
  end_image_url, reference_image_urls]`
- `compv3` → `[background, layer_1, layers]`

**The reliable fix for both:** copy `data.inputs` / `data.outputs` /
`data.category` from a REAL UI-created node of that nodeType —
`SELECT nodes FROM "Workflow" WHERE nodes::text LIKE '%"<nodeType>"%' ORDER BY
"updatedAt" DESC LIMIT 1` — and put model params in `data.config`, never as
extra `data.inputs` entries.

## Best practices

### Extract system prompts as visible input:text nodes
Instead of burying `system_prompt` inside `config`, create an
`input:text` node on the canvas holding the prompt and wire its
`out-prompt` into the LLM's `in-system_prompt` port. This:

- Makes prompts visible on the canvas
- Lets the user edit them inline without opening a config panel
- Allows one prompt to be reused across multiple LLM nodes
- Makes prompts diffable when you version workflows

Example layout: one column of prompt nodes on the left, LLM nodes in
the middle, outputs on the right.

### One input drives the whole graph (batch-friendly shape)
For CSV/batch use cases, structure workflows so a **single** input node
drives all downstream generation. If you need two different derived
values (e.g. a spoken script AND a visual prompt from the same angle),
use two parallel LLM calls that both read from the same angle input —
don't make the user specify multiple parallel inputs, or you can't
batch from a flat data source.

### Use the default canvas handle names for `video:remotion`
Always `hookImage` / `avatarVideo` / `text`. Never invent custom names.
The canvas library only declares these three ports for every remotion
node, regardless of what the underlying composition's `inputMappings`
look like. Prop resolution happens separately via `config.props`.
