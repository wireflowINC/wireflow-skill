# Video assembly: which node, which scene type, how to verify

This exists because an agent once spent an hour and several paid renders
concluding side-by-side video was impossible. It was not. Read this before
building anything that combines clips.

## Which node

| Need | Use |
|------|-----|
| Two or more videos on screen AT THE SAME TIME (side-by-side, PiP, overlay) | `video:remotion` with a `split` or `composite` scene (below), OR `process:video_composite` |
| Sequential scenes, text, captions, audio, branded templates | `video:remotion` (Compose Video / Video Editor) |
| One composited SHOT from N layered clips, as a standalone graph step | `process:video_composite` (per-layer x/y/scale/rotation/opacity/blendMode + startFrame/trimIn/trimOut/playbackRate in `config.layers`) |
| Layering images/text/data into an IMAGE | `compv3` (Compositor). Outputs an image, never video |

Rule of thumb: if the whole video lives in one `video:remotion` node it is
easier to iterate (re-renders are free of AI-generation cost and the labels,
captions, and audio all live in one place). Reach for `process:video_composite`
when you need the composited shot as an intermediate artifact for further
processing.

## Simultaneous video inside a sceneGraph

These are scene types in the same `scenes[]` array as everything else.

50/50 split (two videos side by side; `horizontal` = left/right, the
`top`/`bottom` keys mean left/right in that layout):

```json
{ "type": "split", "layout": "horizontal", "durationInFrames": 150,
  "top":    { "type": "video", "src": "{{clipA}}" },
  "bottom": { "type": "video", "src": "{{clipB}}" } }
```

Free placement (PiP, overlap, custom sizes) with `composite`:

```json
{ "type": "composite", "durationInFrames": 150, "layers": [
  { "src": "{{background}}", "kind": "video", "x": 0,   "y": 0, "scale": 1 },
  { "src": "{{pip}}",        "kind": "video", "x": 700, "y": 60, "scale": 0.3 } ] }
```

There is also `triptych` (2-3 full-width bands that wipe in staggered).

## Mistakes that look like missing features (they are not)

- `layers` only works on `type:"composite"` scenes. Putting `layers` on a
  `type:"video"` scene makes the validator see a video scene with no `src`
  and drop it.
- Top-level `overlays` are image/text ONLY. A video overlay is silently
  stripped. Use a `composite` scene instead.
- `x`/`y` on a plain `video` scene is ignored (scenes are fullscreen; only
  `scale` applies). Use `composite`.
- `split` uses `top`/`bottom` keys even in horizontal layout. `left`/`right`
  keys are not recognized.

## Verify your work for ~$0 before any paid render

`POST /api/v1/render/remotion/preview` with `{ "sceneGraph": {...} }` renders
a few sampled STILL frames (Lambda stills cost cents and no credits) and
returns CDN URLs plus every validation issue:

```json
{ "frames": [{ "frame": 60, "url": "https://cdn..." }],
  "issues": ["scene[2].src: video scene has no src — dropped"],
  "renderable": true, "durationFrames": 300, "fps": 25 }
```

LOOK at the frames. Fix every `issues` entry. Only then run the workflow.
Never conclude "the platform cannot do X" from a failed render without
checking `issues` and this document first.

## Timeline tracks (LIVE)

`video:remotion` sceneGraphs now accept a top-level `tracks` array: a real
timeline, like a conventional editor. Scenes play sequentially as the base
layer; track clips sit at ABSOLUTE frame positions composited above them.
Use tracks for overlapping clips, B-roll over a base video, PiP, or anything
needing precise absolute timing. Track array order is z-order (first =
bottom). All timing is FRAMES (seconds x fps).

```json
{ "fps": 30, "width": 1080, "height": 1920,
  "scenes": [ { "type": "video", "src": "{{base}}", "durationInFrames": 300 } ],
  "tracks": [
    { "clips": [ { "src": "{{broll}}", "startFrame": 90, "durationInFrames": 120, "muted": true } ] },
    { "clips": [ { "src": "{{reaction}}", "startFrame": 0, "durationInFrames": 300,
                   "width": 360, "x": 320, "y": 700 } ] } ] }
```

Clip fields: `startFrame` (required), `durationInFrames` (required),
`trimInFrames`/`trimOutFrames`, `playbackRate`, `muted`/`volume`,
`x`/`y`/`width`/`height`/`scale`/`rotation`/`opacity`/`fit`, `kind:
"video"|"image"|"text"` (text clips take `text`, `fontSize`, `color`,
`background`, `fontWeight`).

⚠️ **Coordinates are offsets from the CANVAS CENTER, not top-left.**
`x: 0, y: 0` means centered; positive x moves right, positive y moves down.
A 1080x1920 comp's bottom-right quadrant starts around `x: 270, y: 480` for
a small clip, NOT `x: 540, y: 960`. Same convention as `composite` scene
layers. Verify placement with the preview endpoint above; the full clip
shape is in the scene-graph schema doc the API serves.

Comp duration = max(scenes sum, latest clip end), or an explicit top-level
`explicitDurationInFrames`. Audio rule: when a comp-wide audioTrack replaces
scene audio, track video clips are muted too unless a clip explicitly sets
`muted: false` AND a `volume`.
