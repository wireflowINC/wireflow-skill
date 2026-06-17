# Diagnostics — how Wireflow tells you what's wrong

Every authoring/validation/render surface returns a **`diagnostics`** envelope: a
single, machine-readable feedback channel you read to know exactly what failed,
*where*, and *how to fix it* — instead of inferring from prose or, worse, getting
silence while a scene quietly drops.

Read `diagnostics` on every response. It is the difference between guessing and
self-correcting.

## The envelope

```jsonc
"diagnostics": {
  "version": 1,
  "counts": { "error": 0, "warning": 2, "info": 1 },
  "diagnostics": [
    {
      "code": "media.port_resolved_empty",      // STABLE — branch on this, never the message
      "severity": "warning",                     // error | warning | info
      "message": "Scene 3 (image) has no src — a wired media port resolved to empty. It renders blank.",
      "target": { "nodeId": "reel", "sceneIndex": 3, "path": "scenes[3].src" },
      "hint": "The source node output carries no usable url. For an uploaded asset, ensure the node emits a url.",
      "docs": "https://www.wireflow.ai/docs/diagnostics#media.port_resolved_empty"
    }
  ]
}
```

## Severity contract

| severity | meaning | what to do |
|----------|---------|------------|
| `error` | will not render / the write was **rejected** | MUST fix before it works |
| `warning` | it rendered, but almost certainly **not what you intended** (a former *silent drop* — empty caption port, dropped scene, clamped overlay) | read it; usually you want to fix it |
| `info` | an automatic repair was applied (port hydration, fps default, deprecated-type migration) | no action needed |

## Where it appears

- **`POST`/`PUT /workflows`** → response carries `diagnostics` (and a 422 with
  `diagnostics` when a strict write is rejected). Tells you what normalization
  changed and what graph-lint rejected.
- **`POST /render/remotion/preview`** (`wf.sh preview`) → `diagnostics` catch the
  blank-scene / placeholder-block / empty-token problems **before you pay** for a
  render.
- **Run / execute** (the remotion node output) → `diagnostics` on the finished
  render: empty audio/caption tracks, dropped scenes, duration drift, clamped
  overlays.

## The self-correction loop

1. Make the call (create / preview / run).
2. Read `diagnostics.diagnostics`. If `counts.error > 0`, it didn't work — fix
   those first.
3. For each diagnostic, **branch on `code`**, use `target` to locate it, apply
   `hint`. (Fetch `docs` if you need more.)
4. Re-submit. Repeat until only `info` remains.

Always `wf.sh preview` before a paid run and clear the `warning`/`error`
diagnostics there first.

## Codes you'll hit building ads

| code | severity | fix |
|------|----------|-----|
| `media.port_resolved_empty` | warning | A scene/overlay `src` resolved blank. Confirm the upstream node emits a URL and the edge targets the right handle. Uploaded `input:image/video/audio` now expose `url`. |
| `scene.dropped_no_src` | warning | Image/video scene had no `src` → removed. Same cause as above, at validation time. |
| `captions.empty` | warning | No captions. Wire the `captions` port to a Whisper node (auto-mirrored into `captionTrack`), or author `captionTrack.raw`. |
| `audio.empty` | warning | No audio. Wire the `audio` port (auto-mirrored into `audioTrack`) or author `audioTrack.src`. |
| `media.placeholder_block` | warning | Block has no deployed bundle → gray placeholder, still billed. Use a `renderable` block (`wf.sh blocks --renderable`). |
| `overlay.clamped` | warning | An overlay ran past the comp/scene bound. Shrink its `startFrame`/`durationInFrames`. |
| `timing.duration_drift` | warning | Rendered runtime ≠ authored wall-clock; audio/captions may desync. Match `sum(durationInFrames)/fps` to your VO length. |
| `node.ports_hydrated` | info | We filled the node's canonical ports from the registry. No action. |
| `node.category_set` | info | We resolved the execution category. No action. |
| `graph.*` | error/warning | A graph-lint rule (`graph.dangling-edge`, `graph.cycle`, …). The `hint` is the concrete fix. |

The envelope `version` lets you pin the shape; new codes can appear without
breaking you, so treat an unknown `code` as its `severity` + `hint`.
