# Blocks — reusable motion-graphics scenes

Blocks are pre-built, parameterized Remotion scene components (kinetic-text
intros, stat counters, animated charts, lower-thirds, app showcases, news
reels, …). They're how you get **motion graphics** instead of a plain
image-and-text slideshow. Prefer a Block whenever one matches the intent.

## Discover

```bash
bash scripts/wf.sh blocks
```

Returns the public catalog (LIBRARY-visibility Blocks):

```json
{
  "count": 58,
  "usage": "Compose a block as a SceneGraph scene: { type:'block', blockId, props }",
  "blocks": [
    {
      "blockId": "cmoagwaoh0001xgajzhkuautn",
      "name": "kpi_callout",
      "displayName": "KPI Callout",
      "description": "Big stat reveal — number counts up from zero with a label.",
      "props": { /* JSON Schema of configurable fields, e.g. value, label, accentColor */ },
      "ports": [ /* wireable inputs derived from $port:* markers, e.g. {portId,type} */ ],
      "previewUrl": "https://cdn.wireflow.ai/....mp4"   // rendered preview, may be null
    }
  ]
}
```

- **`props`** — the JSON Schema of the Block's configurable fields. Fill these
  to parameterize the Block (text, colors, numbers, style enums).
- **`ports`** — wireable input handles (when the Block consumes upstream media:
  an image, a video, an audio track, a JSON array). Wire upstream nodes into
  them with edges, same as any node port.
- **`previewUrl`** — a short rendered preview. Show it to the user (or look at
  it yourself) to pick the right Block. `null` if not yet generated.

## Use a Block

A Block runs as a **scene inside a `video:remotion` node's scene graph**. Add a
scene of `type: "block"`:

```jsonc
{
  "id": "remotion-1",
  "type": "basedNode",
  "data": {
    "label": "Render",
    "nodeType": "video:remotion",
    "category": "video",
    "config": {
      "props": {
        "sceneGraph": {
          "fps": 30, "width": 1080, "height": 1920,
          "scenes": [
            { "type": "block", "blockId": "<id from wf.sh blocks>",
              "durationInFrames": 90,
              "props": { /* fill per the Block's props schema */ } },
            { "type": "image", "src": "{{hero}}", "durationInFrames": 120, "kenBurns": "zoom-in" }
          ]
        }
      }
    }
  }
}
```

- Fill `props` with values matching the Block's `props` JSON Schema.
- If the Block has `ports`, define matching input ports on the `video:remotion`
  node and wire upstream gen nodes into them; reference them in the scene graph
  with `{{portId}}` placeholders where the Block expects them.
- The renderer resolves the Block's bundle from `blockId` automatically — you
  only need `blockId` + `props`.

## Tips

- A Block scene beats a hand-built `text`/`color` scene for intros, outros,
  stat/data reveals, and brand moments — it looks produced.
- Mix Blocks with plain `image`/`video` scenes in the same scene graph.
- No matching Block? Build the workflow with plain scenes, and tell the user a
  custom Block can be authored (admin/agent feature) for that visual.

## Taste — what good motion graphics look like

**Compose from the curated library first.** The hand-authored blocks bake in
tuned spring/stagger/easing — reuse before hand-rolling raw `text` scenes.
`wf.sh nodes` + `wf.sh blocks` are your vocabulary.

**Motion principles**

- Everything is frame-driven: `useCurrentFrame()` + `interpolate`/`spring`. A
  scene should reveal → settle → hold → exit, not just appear.
- Stagger reveals (words, bars, list items) by a few frames each — simultaneous
  reads flat.
- Resolution-independence: scale px by `width/1080` (or use an SVG `viewBox`) so
  a block looks right at any size/aspect, not only 1080×1920.
- Palette discipline: ONE accent across all scenes reads as one piece;
  per-scene colors read as a template.

**Determinism (hard rules — a non-deterministic block renders wrong on Lambda)**

- Drive ALL animation from `useCurrentFrame()`. NO `requestAnimationFrame`, NO
  wall-clock (`Date.now`/`new Date`), NO unseeded `Math.random` at render time —
  precompute any randomness from an index/seed at module scope.
- 3D: `@remotion/three` `ThreeCanvas` only, never r3f `useFrame`. Wrap async
  (fonts, remote images) in `delayRender`/`continueRender`. Use `OffthreadVideo`
  for video. Media renders need a raised `timeoutInMilliseconds` +
  `concurrencyPerLambda: 1` so the GL context doesn't time out.

**The see loop — never trust "JSON-valid == good"**

- After authoring a composition, RENDER it and LOOK: `wf.sh see <sceneGraph.json>`
  samples frames at 20/55/85% of the duration and downloads PNGs. Read them with
  your vision and self-correct. Failures only the eye catches:
  - **Truncated-axis charts read flat.** A weight series 184→170 scaled 0→max is
    all ~95% height — the loss is invisible. Show a 0-based metric (cumulative
    lbs lost 0→14) so bars grow.
  - **Sampling the exit fade looks dimmed.** Blocks fade out in the last ~12
    frames; sample BEFORE that or the still looks washed out.
  - **`paddingTop: %` resolves against WIDTH, not height** — with
    `translateY(-50%)` it can shove a title offscreen. Use `top:% + translateY(-50%)`.

**Cost discipline (baked in)**

- `wf.sh run <id> <inputs> --shadow` proves wiring + output types for $0 before
  any live spend. `wf.sh credits` + the preflight gate run before any live run.
