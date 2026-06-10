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
`data.data`) decides z-order. Two layer types matter:

### `gradient` (scrim — for text legibility over busy photos)
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
- Fonts seen in use: **Anton** (bold condensed headline). `x/y` are top-left px on the
  stage; `fill` is hex; shadows aid legibility.

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
  - `wrap`: `{ "keys": ["s1_prompt", …], "prefix": "<art-style prefix>", "suffix": "<…NO text rendered…>" }`
    — wraps ONLY the listed prompt keys with a shared style so every background is
    visually cohesive and text-free (text comes from the compositor, not the image).
  - Input handle: `in-json`. The LLM's `out-text` → `in-json`.
- So the LLM emits one JSON with `slideN_scene` (background prompt) + `slideN_layers`
  (the scrim+headline object above) per variation. Each compositor gets its background
  from its nano_banana node and its text from the matching `out-sN_layers`.
- Output of each `compv3` → `out-image` → an `action:social_publish`, `output:preview`,
  or just downloaded for the ad manager.

**To add a real product screenshot** (e.g. phone with the app open), wire an
`input:image` into `compv3.in-layer_1` and add a `layer_1` entry (image type) to
`layerOrder` above the background.
