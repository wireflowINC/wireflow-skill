# Using Remotion Templates

A `video:remotion` node renders a final MP4 using one of Wireflow's
registered React-based video templates. (The node type was formerly
`compose:remotion`; the API still accepts that name and rewrites it to
`video:remotion` on save, but author new graphs with `video:remotion`.)
The user CANNOT add new templates
via the API — those are code-level compositions that live in the
wireflow repo and ship through a CI deploy pipeline. The skill can only
**configure** existing templates.

## Discovery

```bash
# List all templates the current API key can access
bash scripts/wf.sh templates

# Fetch one template's full spec
bash scripts/wf.sh template ohnie-reel
```

The single-template response includes:

- `id`, `label`, `description`, `category`
- `compositionId` — used internally by Remotion, echo it in the node config
- `fps`, `width`, `height`, `durationInFrames` — visual metadata
- `defaultProps` — the shape the composition expects. Start with these and
  override only what you need
- `inputMappings` — which `propPath`s can be wired from upstream nodes
  (via edges) and which should stay in static `config.props`

## Shape of a compose node

```json
{
  "id": "remotion-render-1",
  "type": "basedNode",
  "position": { "x": 800, "y": 200 },
  "data": {
    "label": "Render Ohnie Reel",
    "nodeType": "video:remotion",
    "category": "compose",
    "config": {
      "templateId": "ohnie-reel",
      "props": {
        /* override only what you want; rest comes from defaultProps */
        "shots": [ /* ... */ ],
        "audioSrc": "https://cdn.wireflow.ai/.../voice.mp3"
      }
    }
  }
}
```

## Mapping inputMappings → edges

Each `inputMapping` tells you which prop is wireable from upstream:

```json
{
  "propPath": "shots.0.generated_video",
  "portId": "shot_1",
  "portLabel": "Shot 1 — ai_cinematic",
  "portType": "VIDEO",
  "required": false
}
```

- `propPath` — dotted path into the composition's props object. The
  Wireflow execute pipeline writes resolved values into this path.
- `portId` — the handle name used on the node's input side. The edge
  `targetHandle` should be `in-<portId>`, e.g. `in-shot_1`.
- `portType` — what kind of upstream output you can wire in (`IMAGE`,
  `VIDEO`, `AUDIO`, `TEXT`, `JSON`).

Example edge wiring a FAL video generator into a template's shot slot:

```json
{
  "id": "edge-1",
  "source": "kling-gen-1",
  "target": "remotion-render-1",
  "sourceHandle": "out-video",
  "targetHandle": "in-shot_1"
}
```

## Static config vs wired ports

Not every `propPath` is in `inputMappings` — some stay static. For the
`ohnie-reel` template, for instance:

- **Wireable** (in inputMappings): `shots.N.generated_video`, `audioSrc`,
  `wordTimestamps`, `brandOverlay.agentLogo`, `brandOverlay.agentName`.
  Wire these via edges from upstream nodes.
- **Static** (edit in `config.props`): the `shots` scaffold (shot count,
  durations, start times, camera_movement), `statsBar.items`, `priceReveal
  .finalPrice`, `brandOverlay.brokerage`.

When composing a workflow, set the static fields in `config.props` and
leave the wirable fields for edges to populate at execution time.

## Common pattern: text prompt → Kling video → Ohnie Reel shot

```
input:text (prompt)
     │ out-prompt
     ▼
video:kling_video_v2_6_pro_text_to_video (video gen)
     │ out-video
     ▼
video:remotion (templateId: ohnie-reel, shot_1 port)
     │ out-video
     ▼
(final MP4)
```

See `examples/remotion-compose.json` for a working instance.

## Defaults matter — start from them

Always fetch `defaultProps` from the template endpoint and use them as
your base. Only override fields you need to change. This keeps your
workflow JSON small, avoids breaking the composition with missing
required props, and makes updates forward-compatible when the Wireflow
team ships new template fields.
