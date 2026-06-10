# Compositor node (`compv3`) — image + text-layer overlay

Layers text/graphics over a background image — the way to produce **static
"meme" image ads** and **carousel slides** (Cal-AI-style: photo → dark scrim →
bold headline). Renders server-side to a PNG. Pairs with `generate:nano_banana_*`
(or `input:image`) for the background.

## Node shape

```json
{
  "id": "comp1",
  "type": "basedNode",
  "data": {
    "nodeType": "compv3",
    "category": "process",
    "label": "Compositor 1",
    "config": {},
    "inputs": [
      { "id": "background", "type": "IMAGE", "label": "Background", "required": false },
      { "id": "layer_1",    "type": "IMAGE", "label": "Layer 1",   "required": false },
      { "id": "layers",     "type": "TEXT",  "label": "Layers (JSON)", "required": false }
    ],
    "outputs": [ { "id": "image", "type": "IMAGE", "label": "Output" } ],
    "data": {
      "stage": { "width": 1856, "height": 2304 },
      "layers": { "background": {…}, "scrim": {…}, "headline": {…} },
      "layerOrder": ["background", "scrim", "headline"]
    }
  }
}
```

- **`data.data`** is the editor/canvas state: `stage` (canvas px), `layers` (per-layer
  geometry), `layerOrder` (z-order, bottom→top). For programmatic use you can leave a
  minimal `layers`/`layerOrder` and drive content through the **`layers` input port**.
- **Ports (target handles):** `in-background` (the base image), `in-layer_1` (an optional
  overlay image, e.g. a phone mockup), `in-layers` (the **TEXT** JSON below).
- **Output (source handle):** `out-image`.

## The `layers` JSON (fed into `in-layers`)

A JSON **object** keyed by layer name. Each key is a layer; `layerOrder` (in
`data.data`) decides z-order. The renderer switches on exactly four kinds —
`text`, `rectangle` (gradient/solid fill), `image`, `draw` (freehand). `type:
"gradient"` is a **legacy alias of `rectangle`** and still renders (back-compat),
so existing scrim JSON keeps working — but author new fills as `rectangle`.

> **Verified against the renderer 2026-06-09** (`execute-compositor.ts`). Props
> not listed below are read NOWHERE and fail silently — don't set them expecting
> an effect. See "Image layers — styling + fit" and "Still NOT supported" below.

### `gradient` / `rectangle` (scrim, color blocks, highlight bars)
```json
"scrim": {
  "type": "gradient", "angle": 0, "x": 0, "y": 0,
  "width": 1856, "height": 2304, "opacity": 100,
  "stops": [
    { "color": "rgba(0,0,0,0)",    "offset": 0 },
    { "color": "rgba(0,0,0,0.45)", "offset": 0.55 },
    { "color": "rgba(0,0,0,0.85)", "offset": 1 }
  ]
}
```

A `rectangle` is the SAME fill path — use it for solid color blocks,
**highlight bars behind a word**, and (with `cornerRadius`) **pills / badges /
score chips**. Give it explicit `width`/`height` (missing → warns + fills the
whole stage):
```json
"score_chip": {
  "type": "rectangle", "x": 80, "y": 120, "width": 240, "height": 110,
  "opacity": 100, "cornerRadius": 28,
  "fill": { "kind": "solid", "color": "#e11d48" }
}
```
`fill` is `{kind:'solid',color}` | `{kind:'linear',angle,stops}` |
`{kind:'radial',cx,cy,r,stops}`; a bare `fill:"#hex"` string also works (solid).
`cornerRadius` (alias `borderRadius`) rounds the corners — 0/omit = sharp.

### `text` (the headline / hook / CTA)
```json
"headline": {
  "type": "text",
  "text": "YOUR 3PM CRASH STARTS AT 8AM",
  "fill": "#ffffff",
  "fontFamily": "Anton", "fontWeight": "400", "fontSize": 170,
  "x": 90, "y": 1560, "width": 1680, "lineHeight": 1, "letterSpacing": 1,
  "autoFit": true, "autoFitMaxHeight": 600, "autoFitMinFontSize": 90,
  "shadowBlur": 18, "shadowColor": "rgba(0,0,0,0.55)",
  "shadowOffsetX": 0, "shadowOffsetY": 3
}
```
- `autoFit` shrinks `fontSize` to fit `width`/`autoFitMaxHeight` (down to
  `autoFitMinFontSize`) — so you can hardcode a big `fontSize` and let long hooks
  shrink. Stack multiple text layers (e.g. `headline` + `cta`) by adding more keys and
  listing them in `layerOrder`.
- Text props the renderer honors: `text`, `fontFamily`, `fontWeight`,
  `fontStyle`, `fontSize`, `fill`, `align`, `width`, `lineHeight`, `autoFit*`,
  `stroke`+`strokeWidth`, `shadowColor`/`shadowBlur`/`shadowOffsetX/Y`, `textBg`
  (below), and `highlightWord`/`highlightFill` (below). `letterSpacing` is
  **read but NOT applied** — don't rely on it.

### Highlight one word in a headline — `highlightWord`

The meme-ad move: recolor a single word in the brand color. Set `highlightWord`
(the literal substring) + `highlightFill` (its color); optional `highlightBg`
draws a block behind it. First match per line, any alignment:
```json
"hook": {
  "type": "text", "text": "YOUR 3PM CRASH STARTS AT 8AM",
  "fill": "#ffffff", "fontFamily": "Anton", "fontSize": 150, "x": 90, "y": 1500,
  "highlightWord": "3PM", "highlightFill": "#ffd400"
}
```
Renders in the final **PNG** (the API/factory output). Note: the in-editor live
preview + node thumbnail still show it single-color for now (a fast-follow) — the
rendered MP4/PNG is correct, so for API authoring this Just Works.

### Rounded chips / score badges / pills — use `text.textBg`

The renderer draws an optional **solid rounded rect behind a text layer**
(`textBg`). That IS your "32/100" score chip, "FOUNDING OFFER" tag, or pill —
no separate shape layer needed (a standalone `rectangle` can't round corners):
```json
"score_chip": {
  "type": "text", "text": "32/100", "fill": "#ffffff",
  "fontFamily": "Anton", "fontSize": 90, "x": 90, "y": 120,
  "textBg": { "color": "#e11d48", "radius": 28, "padding": 24, "opacity": 1 }
}
```
`textBg`: `color`, `radius` (corner px), `padding`, `opacity` (0–1).

### Fonts (verified)

Any **Google Font** is fetched + registered on-demand server-side by family
name — not just Anton. So `"fontFamily": "Inter"` (always bundled),
`"Geist"`, `"Bebas Neue"`, etc. all work; pick a clean sans (Inter) for
sublines/source lines and a condensed display face for headlines. **Anton** is
the alias the legacy `Impact`/`Arial Black` names map to. System faces (Arial,
Helvetica, Georgia, Times New Roman) render without a fetch. If a fetch fails it
falls back to Inter — so an unknown/misspelled family silently becomes Inter.
`x/y` are top-left px on the stage; `fill` is hex.

### Image layers — styling + fit (verified)

An `image` layer (e.g. `layer_1`) honors `x`, `y`, `scaleX`, `scaleY`,
`rotation`, `opacity`, plus:
- **`fit`**: `"cover"` | `"contain"` | `"stretch"` — object-fit against the
  stage. The **background** layer auto-covers when its image ≠ the stage size
  (so a non-stage-ratio bg no longer tiles top-left); set `fit` explicitly on any
  image layer to override.
- **`cornerRadius`** (alias `borderRadius`) — rounded corners (the
  floating-screenshot look).
- **`shadowColor` / `shadowBlur` / `shadowOffsetX` / `shadowOffsetY`** — drop
  shadow. Bake the alpha into an `rgba()` `shadowColor`.
- **`imageBorderColor` / `imageBorderWidth`** — a stroke around the image
  (dedicated names, NOT `stroke`).

```json
"screenshot": {
  "url": "...", "x": 240, "y": 600, "scaleX": 0.5, "scaleY": 0.5,
  "cornerRadius": 48, "imageBorderColor": "#ffffff", "imageBorderWidth": 6,
  "shadowColor": "rgba(0,0,0,0.45)", "shadowBlur": 60, "shadowOffsetY": 24
}
```
All render in the final **PNG** and the node thumbnail. (The interactive
editor-modal preview of these image props is a fast-follow; the output is
correct.)

### Background sizing — still prefer stage-aspect for quality

`fit:"cover"` crops to fill, so a wrong-aspect background loses pixels. For the
sharpest result still generate the bg at the stage aspect. The compositor stage
is **1856×2304 (4:5)** — `generate:openai_gpt_image_2` can't do 4:5 (maxes at
2:3), but `generate:nano_banana_pro` / `nano_banana_2` / `nano_banana` all expose
`aspect_ratio: "4:5"`. Use a nano_banana model for compositor backgrounds.

### Image-gen `image_size`: pass a `{width,height}` DICT, not a string

`generate:openai_gpt_image_2` (and other `IMAGE_SIZE` models) want
`image_size` as either a **preset string** (`"square_hd"`, `"portrait_4_3"`, …)
or a **`{"width":N,"height":N}` object** (arbitrary positive dims accepted, e.g.
`{"width":1856,"height":2304}`). A bare `"1024x1536"` STRING is rejected by the
provider at runtime — `wf check` now catches it pre-flight with a fix.

### Still NOT supported

- **Per-word styling beyond a single highlight** (multiple differently-styled
  spans). Use `highlightWord` for one word; stack separate text layers for more.
- **Logo/watermark slot.** No built-in brand layer — add the wordmark as a
  normal `image` layer (burns a `layer_*` port) positioned by hand.

## The factory pattern (mass-produce variations in one workflow)

This is how the "LinkedIn Carousel — BasedHealth" / ad-meme factory is wired:

```
input:text (topic) ─────┐
                        ├─► llm:openrouter_router ─► utility:json_multi_extract ─┬─► generate:nano_banana_pro (sN) ─► compv3.in-background
input:text (sysprompt) ─┘   (emits JSON: per-slide   (paths: map JSON→ports;     │
                            scene prompt + layers)     wrap: prepend/append art   └─► compv3.in-layers   (the sN_layers JSON)
                                                       style to scene prompts)
```

- **`utility:json_multi_extract`** config:
  - `paths`: a JSON string mapping **output handle → JSON path** in the LLM output,
    e.g. `{"s1_prompt":"slide1_scene","s1_layers":"slide1_layers","caption":"caption", …}`.
    Produces handles `out-s1_prompt … out-sN_prompt`, `out-s1_layers … out-sN_layers`, `out-caption`.
  - ⚠️ **Partial-miss (verified):** if a path isn't found in the LLM JSON (LLM
    renamed a key, emitted fewer slides than `paths` expects), that handle emits
    an **empty string and the node still reports success** (partial extraction is
    intentional) — the downstream compositor renders blank. The node now attaches
    `output._warnings.missingPaths` listing the missed path keys (and shows an
    amber "N missing fields" badge in the UI), incl. `*`-fanout paths with holes.
    So: keep the LLM's key names EXACTLY matching `paths`, pin the slide count,
    and after a run check `output._warnings` / that every `out-sN_*` handle is
    non-empty before trusting the comps. The extractor strips ```` ```json ````
    fences and a `{text:"…"}` wrapper, so prose-wrapped JSON is handled; renamed
    or missing keys are not.
  - `wrap`: `{ "keys": ["s1_prompt", …], "prefix": "<art-style prefix>", "suffix": "<…NO text rendered…>" }`
    — wraps ONLY the listed prompt keys with a shared style so every background is
    visually cohesive and text-free (text comes from the compositor, not the image).
  - Input handle: `in-json`. The LLM's `out-text` → `in-json`.
- So the LLM emits one JSON with `slideN_scene` (background prompt) + `slideN_layers`
  (the scrim+headline object above) per variation. Each compositor gets its background
  from its nano_banana node and its text from the matching `out-sN_layers`.
- Output of each `compv3` → `out-image` → an `action:social_publish`, `output:preview`,
  or just downloaded for the ad manager.
- **Pulling the finals:** a factory run yields N `out-image` URLs across N comp
  nodes — there's no zip/"download all" endpoint, so read each comp's `out-image`
  from the poll result and pull it with `bash scripts/wf.sh download <url> sN.png`
  (routes through the allowlisted proxy — a direct curl to `cdn.wireflow.ai`
  **403s** on the edge WAF's user-agent block).

**To add a real product screenshot** (e.g. phone with the app open), wire an
`input:image` into `compv3.in-layer_1` and add a `layer_1` entry (image type) to
`layerOrder` above the background.
