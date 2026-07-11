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

## Coming: timeline tracks

A `tracks` model (clips at absolute frame positions on stacked tracks, with
x/y/scale, trim, and playbackRate, like a conventional editor timeline) is
landing in `video:remotion`. When available it appears in this document and
in the scene-graph schema doc served by the API.
