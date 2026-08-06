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
      { "id": "background", "type": "IMAGE",   "label": "Background", "required": false },
      { "id": "layer_1",    "type": "IMAGE",   "label": "Layer 1",   "required": false },
      { "id": "data",       "type": "UNKNOWN", "label": "Batch data (array)", "required": false }
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

- **🔴 The canvas lives on `node.data.data` — NOT a port.** `data.data` holds
  `stage` (canvas px), `layers` (per-layer geometry, keyed by layer name), and
  `layerOrder` (z-order, bottom→top). There is **no** `layers` port; author the
  whole canvas on `data.data`. A standalone compv3 (canvas on `data.data`, no
  edges) renders on its own — no dummy upstream node needed.
- **Ports (target handles)** — there are exactly three:
  - `in-background` — an image for the **`background`** layer. ⚠️ A layer named
    `background` MUST already exist in `data.data.layers`/`layerOrder`, or the
    image silently won't render (you'll get a `data.warnings` entry now).
  - `in-layer_1` — an image for the **`layer_1`** layer (same named-layer rule).
  - `in-data` — a **BATCH override ARRAY** (renders the template once per item).
    NOT the canvas — feeding a `{stage,layers,layerOrder}` object here renders
    blank (now flagged in `data.warnings`).
- **Output (source handle):** `out-image` (compv3 emits port id `image`).
- **Upstream image nodes** (`input:image`, `generate:*`) emit **`out-media`**
  (port id `media`) — wire `input:image.out-media → compv3.in-background`. (They
  do NOT emit `out-image`.)

## The `layers` JSON (on `data.data.layers`)

A JSON **object** keyed by layer name. Each key is a layer; `layerOrder` (in
`data.data`) decides z-order. The renderer switches on exactly four kinds —
`text`, `rectangle` (gradient/solid fill), `image`, `draw` (freehand). `type:
"gradient"` is a **legacy alias of `rectangle`** and still renders (back-compat),
so existing scrim JSON keeps working — but author new fills as `rectangle`.

> **Verified against the renderer 2026-06-09** (`execute-compositor.ts`). Props
> not listed below are read NOWHERE and fail silently — don't set them expecting
> an effect. See "Image layers — styling + fit" and "Still NOT supported" below.
>
> ⚠️ This hand-written section is a 2026-06 snapshot and predates content-driven
> layout. **`sizing`/`hug`, `fitTo`, `anchor`/`anchorX`/`anchorY`, `type: "stack"`
> flow layout, `itemTemplate` + `variants`, `$runs`, `$gapBefore`, per-corner
> `cornerRadius` tuples and `$port:` refs are all documented in the GENERATED
> "Layout contract" section at the bottom of this file**, which is emitted from
> the validator's own constants and carries a version stamp. When the two
> disagree, the generated one wins.

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

### `draw` (freehand strokes — sketch a motion path) ⭐ agent-drawable

You can **draw on the image headlessly** — no canvas needed. A `draw` layer
bakes a freehand polyline into the output PNG. Verified in `execute-compositor.ts`:

```json
"carPath": {
  "type": "draw", "x": 0, "y": 0,
  "points": [820,300, 640,330, 470,360, 300,380],
  "stroke": "#ff3b30", "strokeWidth": 8, "opacity": 100
}
```

- **`points`** is a FLAT array `[x0,y0, x1,y1, …]` in **stage pixels** (the 1856×2304
  stage, same space as every other layer's x/y). The renderer smooths it with
  quadratic curves and round caps.
- Props the renderer honors: `points`, `stroke` (hex), `strokeWidth`, `opacity`,
  `x`/`y` (offset added to every point).

**Why an agent would draw:** the **Seedance / i2v "follow the path"** technique —
sketch a red arrow from a subject toward where it should move, then feed the
flattened compositor PNG into an i2v node (Seedance/Kling). The model follows the
drawn path. To turn a friendly arrow into `points`, sample the segment yourself:
`from:[x0,y0] → to:[x1,y1]` becomes `points:[x0,y0, …midpoints…, x1,y1]` (a curved
arrow = add the bend points). ⚠️ The stroke IS baked into the image — it can bleed
into the generated video, so keep it thin/short and prefer a color that reads as
direction, not content.

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

> **Logo/watermark IS supported now** — add the wordmark as a normal `image`
> layer in the template and simply DON'T list it in any `data` item. It becomes a
> **global** layer that renders identically on every output (see *Batch / template
> mode* above). That's the reusable brand slot.

## Batch / template mode — ONE node, N images (the `data` port) ⭐

**This is the reusable-brand-layout pattern.** Instead of one `compv3` per output,
build ONE compv3 whose saved layers ARE your brand template (logo, brand bar, fonts,
scrim, layout), and wire a JSON **array** into its `data` port. The node renders the
template **once per item** and emits an **array of N images** on `out-image`.

- Each item lists ONLY the layer keys it overrides. A layer NOT named in any item
  renders **identically every time** — that's a **global** layer (your logo, brand
  bar, background style, fonts). This is the logo/brand slot you've wanted.
- `string` value = shorthand: a **text** layer's `.text`, an **image** layer's `.url`.
- `object` value = merged onto the layer, e.g. `{ "text": "…", "fill": "#FF6B00" }`
  (nested `transform` is deep-merged).
- **Keep editor-preview placeholders in your bound layers** (e.g. `stat: "0%"`,
  `headline: "TEMPLATE"`). A data override **beats** the template's existing value
  at render — you do NOT need to leave bound fields empty. (Both render paths,
  including a layer the template already had a value for.)

```jsonc
// compv3 config.layers  — the template, authored ONCE. logo+scrim+fonts are global.
{
  "logo":     { "type": "image", "url": "https://…/brand-logo.png", "x": 80, "y": 80, "width": 220 },
  "scrim":    { "type": "rectangle", "x": 0, "y": 1400, "width": 1080, "height": 600,
                "fill": {"kind":"linear","angle":0,"stops":[{"color":"#00000000","offset":0},{"color":"#000000CC","offset":1}]} },
  "headline": { "type": "text", "text": "TEMPLATE", "fontFamily": "Inter", "fontWeight": 800,
                "fontSize": 96, "fill": "#ffffff", "x": 80, "y": 1560 },
  "stat":     { "type": "text", "text": "0%", "fontFamily": "Inter", "fontWeight": 900,
                "fontSize": 140, "fill": "#FF6B00", "x": 80, "y": 1720 }
}
```
```jsonc
// wire this array into compv3.in-data  → 3 on-brand ads; logo + fonts identical on all 3
[
  { "headline": "Cut sugar cravings", "stat": "-42%", "bg": "https://…/a.png" },
  { "headline": "Sleep deeper",        "stat": "+1.3h", "bg": "https://…/b.png" },
  { "headline": "Track every meal",    "stat": "10s",   "bg": "https://…/c.png" }
]
```

- **Output:** `out-image` carries the **array** → wire to `output:preview` (renders a
  gallery) or iterate downstream. `output.url` = first image (back-compat),
  `output.count` = N, `output.failedItems` / `output._warnings.dataItems` flag any
  per-item problems (a data key matching no layer is reported, never a silent blank).
- **Absent / non-array `data` → single render** (exact back-compat).
- **Cost:** local @napi-rs/canvas render — **no FAL credits**. Capped at **50 items**,
  4 concurrent.
- **Validate first:** `bash scripts/wf.sh check workflow.json` (graph-lint) checks the
  `in-data` edge and flags a data key that matches no template layer with a
  did-you-mean — so a typo fails free, before a run. Discover the port with
  `bash scripts/wf.sh nodes | …` (compv3 now lists `data:JSON`).
- The `bg` values above are per-item background URLs (e.g. from N `nano_banana` nodes,
  or an image array, or literal URLs). Everything that stays constant lives in the
  template as a global layer.

### Feeding the batch from AI generation — `utility:build_data` ⭐

The `data` port wants **literal** values (text + image URLs), but a real ad
factory **generates** them at runtime (the LLM writes copy, a model makes the
backgrounds). The **`utility:build_data`** node bridges that — it zips an LLM
records array with a generated-images array, by index, into the `data` array:

```
input:text (topic) ─► llm (emits [{headline, stat}, …])  ──► build_data.in-records ─┐
                                                                                     ├─► build_data.out-data ─► compv3.in-data ─► N branded ads
llm prompts ─► generate:nano_banana_pro (N images, an array) ─► build_data.in-images ┘
```

- **`build_data` inputs:** `records` (the LLM's JSON array, e.g.
  `[{"headline":"…","stat":"…"}, …]`) + `images` (an array of generated images).
  **Config `imageKey`** (default `"bg"`) = which layer the image URL lands in.
- It zips by index → `[{headline, stat, bg:<url>}, …]` on `out-data`; wire that
  straight into `compv3.in-data`. Length mismatches are zipped to the longer side
  and reported in `output._warnings.build`.
- **This is the one-Compositor factory.** One brand template + this connector
  replaces the old "one compositor per slide" wiring below. Use it whenever the
  copy and/or backgrounds are generated rather than literal.
- Make the LLM emit a clean **array of objects** whose keys match your bound layer
  keys (`headline`, `stat`, …). `wf.sh nodes` lists `utility:build_data`
  (`records`, `images` → `data`); `wf.sh check` validates the edges.

### Authoring the data inline (no wiring) — the Batch panel

For hand-made variations, the Compositor editor has a **"Batch" toggle** (a
spreadsheet UI): columns = your text/image layers, rows = variations, with live
per-row previews and a "Generate" button. It persists to
`node.data.data.batchData`, which the engine reads as the **fallback** when no
`in-data` edge is wired. So a human can build a batch with zero graph wiring; an
agent should still prefer wiring `in-data` (from `build_data` or a JSON node).

## The factory pattern (older: one compositor per slide)

> Prefer the single **`data`-port** node above for same-layout variations. The N-node
> wiring below is only needed when each output needs a **genuinely different layout**.
> This is how the "LinkedIn Carousel — BasedHealth" / ad-meme factory was wired:

```
input:text (topic) ─────┐
                        ├─► llm:openrouter_router ─► utility:json_multi_extract ─┬─► generate:nano_banana_pro (sN) ─► compv3.in-background
input:text (sysprompt) ─┘   (emits JSON: per-slide   (paths: map JSON→ports;     │
                            scene prompt + layers)     wrap: prepend/append art   └─► sN_layers JSON → written onto each compv3's data.data (NOT a port)
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
- **Pulling the finals:** with the **`data`-port** node, one comp emits all N URLs
  in `output.image[]` (read `output.image[i].url` from the poll result). The older
  N-node factory yields N `out-image` URLs across N comp nodes. Either way there's no
  zip/"download all" endpoint — pull each with `bash scripts/wf.sh download <url> sN.png`
  (routes through the allowlisted proxy — a direct curl to `cdn.wireflow.ai` **403s**
  on the edge WAF's user-agent block).

**To add a real product screenshot** (e.g. phone with the app open), wire an
`input:image` into `compv3.in-layer_1` and add a `layer_1` entry (image type) to
`layerOrder` above the background. A bare image-**URL string** feeding an image
port now works directly (it used to crash on the layer merge — fixed).

## Editing layers on an EXISTING compositor (programmatic layer management)

The template layers live ON the node at `node.data.data`:

```jsonc
{
  "stage":      { "width": 1080, "height": 1350 },   // canvas px
  "layers":     {                                     // keyed by layer id
    "background": { "url": "https://…", "fit": "cover" },
    "scrim":      { "type": "rectangle", "x": 0, "y": 0, "width": 1080, "height": 1350,
                    "opacity": 60, "fill": { "kind": "linear", "angle": 0, "stops": [
                      { "color": "rgba(0,0,0,0.85)", "offset": 0 },
                      { "color": "rgba(0,0,0,0)",    "offset": 1 } ] } },
    "headline":   { "type": "text", "text": "HEADLINE", "x": 64, "y": 96,
                    "fontSize": 96, "fontFamily": "DM Sans", "fontWeight": "bold",
                    "fill": "#FFFFFF", "width": 952 },
    "logo":       { "url": "data:image/png;base64,…", "x": 64, "y": 1180 }
  },
  "layerOrder": ["background", "scrim", "headline", "logo"]   // bottom → top
}
```

To add/change/remove layers on a workflow that already exists:

1. `bash scripts/wf.sh get <workflowId>` → save the JSON.
2. Edit the compositor node's `data.data.layers` + `data.data.layerOrder`
   (add a text layer, tweak a scrim, reorder — same shapes as the `layers`
   port JSON documented above; `layerOrder` is bottom-up, last = topmost).
3. `bash scripts/wf.sh update <workflowId> wf.json` — graph-lint + auto-layout
   run automatically.

Notes that save you a redo:

- **Don't touch `data.output`** — it's the cached render; the engine
  re-renders when inputs/layers actually changed (hash-gated).
- Layer `opacity` is **0–100**, gradient stop alpha lives in the rgba color,
  stop `offset` is 0–1.
- A `background` image layer with no explicit `fit` cover-fits the stage
  automatically when its size differs from the stage.
- Batch rows override layer content per-output by key (`headline` row cell →
  `headline` layer text). Keys with no matching layer are ignored.
- The user's editor previews the FIRST wired data row on the canvas, so a
  template with placeholder content still LOOKS live once data is wired.

<!-- generated:BEGIN section=compositor-layout source=src/lib/workflow/workflow-schema.ts -->
<!-- generated:STAMP date=2026-08-06 sha=268376098db8 hash=85ef50edbc0d -->

> **Generated 2026-08-06 from `src/lib/workflow/workflow-schema.ts` @ `268376098db8`.**
> Do not hand-edit between the markers; edit the constant in the Wireflow
> repo and regenerate. Prose outside the markers is hand-written and safe.

## Layout contract — the full text the validator enforces

Everything below is the `COMPOSITOR_LAYOUT_CONTRACT` constant, verbatim. It is
the same string served on `GET /api/v1/workflows/{id}/schema` (per compv3 node,
under `compositor[].layout`) and the same one the zod `.describe()`s and the
runtime refusals quote. If this section and a refusal message disagree, the
refusal is right and this file is stale — check the version stamp above.

Machine-readable companions on that same endpoint: `compositor[].layoutSchema`
(JSON Schema for the opt-in layout fields) and `compositor[].stackSchema`
(JSON Schema for a `type: "stack"` layer). Fetch those rather than transcribing
field names out of the prose.

Layers are absolute x/y/width/height by default. Three OPT-IN fields make geometry follow content; a layer that declares none of them renders exactly as before. (1) SIZING, text layers only: `sizing: { width: "fixed"|"hug", height: "fixed"|"hug" }`. "hug" fits the BOX to the text; `autoFit` is the OPPOSITE (it shrinks the TEXT to fit a fixed box), so declaring `autoFit` together with `sizing.height: "hug"` is refused. `maxWidth` forces wrapping and `minWidth` is a floor; both apply with or without `sizing`. OPTICAL CENTRING, text layers: `verticalAlign: "optical"`. A text box is `lines x fontSize x lineHeight`, and ALL of the leading — `(lineHeight - 1) x fontSize` — accumulates BELOW the final baseline instead of being split around the block, so a hugged layer inside a `fitTo` container with SYMMETRIC padding renders its glyphs about `0.2 x fontSize` HIGH (measured on a real composite: 23px above the first line's caps against 39px below the last baseline, at fontSize 40 / lineHeight 1.3). `optical` switches the layer to HALF-LEADING metrics — exactly what CSS does inside a line box: half the leading above the first line, half below the last, BOTH halves then trimmed off the measured box, so the box is the text block's em span (`lines x fontSize x lineHeight - (lineHeight - 1) x fontSize`) so equal padding stops depending on lineHeight. USE IT FOR EVERY CONTAINER-AROUND-TEXT LAYOUT (bubbles, badges, pills, buttons); the `textBg` pill is trimmed the same way, so it stays centred on the glyphs too. The alternative is per-fontSize asymmetric padding, which is exactly the hand-tuning these fields exist to delete. It is OPT-IN, not the default, only because templates already exist whose asymmetric padding compensates for the old skew and flipping the default would double-correct them — making it the default is a stated follow-up. `lineHeight: 1` has no leading, so "optical" is an exact identity there; the legacy `top`/`middle`/`bottom` values of this same field (block alignment inside a fixed height) are untouched and `"center"` is accepted as an alias for `"middle"`; and it is REFUSED on a layer that does not render as text, naming the layer and listing the valid values. WHAT IT DOES NOT DO, so you do not measure the leftover and re-file it: "optical" removes the LINE-HEIGHT-dependent skew ENTIRELY (12px at fontSize 40 / lineHeight 1.3, 72px at 120 / 1.6), and nothing else. A residual remains, because half-leading is an EM-BOX construction and a line of glyphs does not fill its em box symmetrically. It depends on the FONT and — this is the part that surprises people — on the TEXT ITSELF. A line with NO DESCENDERS (ALL-CAPS badges and buttons, "no time like now") ends at the BASELINE instead of a descender bottom, so its ink block sits high in the em box and it reads at the NEGATIVE EDGE of the range: measured at fontSize 40, a descender-less line is 6-8px MORE negative than a mixed-glyph one on the same face. MEASURED ENVELOPE on real bakes at fontSize 40, across three faces and both content classes: -13px to +1px (mixed-glyph lines -5 to +1; descender-less lines -13 to -4), where a NEGATIVE number means the glyphs sit that far above centre. It scales with fontSize (about -0.35x to +0.04x of it), plus a pixel or two of RASTERISATION QUANTISATION that matters most below about 30px, where one whole ink row is already 4% of the em. It is INVARIANT to lineHeight, and that invariance IS the guarantee: equal padding gives you a gap difference that no longer changes when you change lineHeight or the leading, NOT one that is pixel-zero. HOW THAT IS KNOWN, both legs, because neither carries it alone: (1) MEASURED identical at lineHeight 1.0 and 1.3 across every face x size x content combination, INCLUDING sizes whose fontSize x lineHeight product is FRACTIONAL (25 and 33 at lineHeight 1.3) — a matrix of whole-number products only would have made the rounding a no-op, so "no drift" there would have been consistent with a rounding fault too and proved nothing; and (2) STRUCTURALLY, the baked PNG applies no vertical paint shift at all (it draws from ty=0 with textBaseline "top") and a single optical line measures EXACTLY fontSize, so on the surface that ships there is no rounded quantity for a half-pixel to hide in. Zeroing it would mean trimming to the font's own ascent/descent (CSS text-box-trim) instead of the em box, which would stop `lineHeight: 1` being an identity, so it is deliberately out of scope. If you need an ALL-CAPS badge optically centred to the pixel, nudge its container's padding by the measured amount for that face and size; nothing about that changes when the text length or lineHeight does. (2) FIT-TO-CONTENT, rectangle/image layers: `fitTo: "<layerName>"` plus `padding`, which is CSS order [top, right, bottom, left] or one number for all four. The layer resolves to the target layer's MEASURED box grown by the padding, so a chat bubble stops being correct for exactly one text length. (3) ANCHORING, any layer: `anchor: { to: "<layerName>"|"$stage", edge: "top"|"bottom"|"left"|"right", gap, align: "start"|"center"|"end" }` positions against the target's RESOLVED box, so a stack stays correct when an upstream layer changes height. `align` operates on the axis PERPENDICULAR to `edge` — the CROSS axis, exactly like flexbox `align-items` — so `edge: "bottom"` + `align: "end"` is bottom AND right-aligned. CROSS-AXIS INSET: `anchor.alignOffset` (a number, default 0) shifts the layer along that SAME cross axis, on top of `align`. THREE RULES: (1) `align: "start"` insets INWARD from the near edge — position = start + alignOffset; (2) `align: "end"` insets INWARD from the far edge — position = end - alignOffset; (3) `align: "center"` applies it as a SIGNED offset from the centre, where POSITIVE shifts toward "end". START AND END ARE BOTH INWARD ON PURPOSE: pinning a corner never needs a negative number, and only `center` — which has no inward direction — spends the sign on full freedom. NEGATIVES ARE LEGAL on every align (they push OUTWARD past the reference edge, which is a real if unusual choice), the value must be finite and within ±16384, and `alignOffset: 0` resolves byte-identical to a scene authored before the field existed. The rule is IDENTICAL for a layer target and for `$stage` — only the MAIN axis inverts between them. So "sit 76px up from the bottom and 68px in from the right" is `anchor: { to: "$stage", edge: "bottom", align: "end", gap: 76, alignOffset: 68 }`. Without it that corner was inexpressible and the workaround was an invisible 1px guide rectangle to absorb the anchor. PER-AXIS ANCHORS: `anchorX` and `anchorY` SPLIT `anchor` PER AXIS, like CSS position properties: each takes the SAME `{ to, edge, gap }` shape and the SAME semantics as `anchor` (a LAYER target is OUTSIDE-adjacent, `"$stage"` is INSIDE-pinned), but governs ONE axis and leaves the other free. `anchorY` takes a VERTICAL edge ("top"/"bottom"); `anchorX` takes a HORIZONTAL edge ("left"/"right"); the wrong axis is REFUSED, naming the field. They may point at DIFFERENT targets, and that is the entire point: `anchorY: { to: "msg1", edge: "top", gap: 8 }` + `anchorX: { to: "$stage", edge: "left", gap: 24 }` is "directly above msg1, at the card's left edge" — a layout a whole `anchor` cannot express, because `anchor` couples both axes to one target. `align`/`alignOffset` are NOT accepted on a per-axis anchor and are REFUSED rather than ignored: they act on the CROSS axis of a whole `anchor`, and here the cross axis is either free or governed by the other per-axis anchor. Declaring `anchor` together with `anchorX` or `anchorY` on the same layer is REFUSED as a contradiction — use either the whole form or the per-axis form. THE LAYOUT THIS UNLOCKS, and the reason it exists: a chat thread. WRONG (fixed slots) — give each bubble a hardcoded y, and the gap between two bubbles becomes a function of how long the previous message was: 26px after a one-liner, 75px after a message that wrapped to three lines. Content-dependent spacing is the single clearest tell that a screenshot is fake. RIGHT (chained per-axis) — `msg1: { anchorY: { to: "$stage", edge: "bottom", gap: 40 }, anchorX: { to: "$stage", edge: "left", gap: 24 } }`, then `msg2: { anchorY: { to: "msg1", edge: "top", gap: 8 }, anchorX: { to: "$stage", edge: "left", gap: 24 } }`, then msg3 chained off msg2 the same way. Every inter-bubble gap is EXACTLY 8px no matter how any message wraps, because each bubble is measured from the RESOLVED box of the one before it while its left edge stays welded to the card. ANCHORED-PAIR COLLISIONS: when layer B anchors to layer A — whole or per-axis — with a NON-NEGATIVE `gap`, the layout has DECLARED they sit apart, so if their resolved boxes then intersect by more than 0.5px on BOTH axes the render output carries `{ code: "layout-collision", layer, target, box, targetBox, overlap: { x, y } }` plus a human sentence, and the render still completes.

🔴 THE PRECISE PROPERTY, because "never gives false positives" would be the wrong claim: IT NEVER FIRES ON AUTHORED BLEED. A NEGATIVE `gap` is legal and is the ONLY way to place a layer INSIDE a LAYER target (only `$stage` is inside-pinned), so `anchor: { to: "hero", edge: "top", gap: -60 }` is exactly how you lay a scrim over a hero — that overlap is DECLARED, and it is never reported. Nor does a plain absolutely-positioned overlay warn, because it declares no anchor between the overlapping pair. It is also NOT transitive: a chain msg1 -> msg2 -> msg3 is checked link by link.

⚠️ SO DO NOT TREAT THIS AS AN AUTHORING CHECK. With authored bleed excluded, the outside-adjacent formulas guarantee `gap` clearance measured from the same box the check recomputes, which means a non-negative gap CANNOT produce an intersection: this warning is a LAYOUT-ENGINE TRIPWIRE, and seeing one means our resolver regressed, not that your scene is wrong. Report it rather than editing the scene. In particular it CANNOT catch the mistake it is most often assumed to catch — fixed x/y slots that end up overlapping once content grows — because those declare no anchor at all; the fix for that is to CHAIN the layers with per-axis anchors so the spacing is derived. DECLARED NON-OVERLAP — THE AUTHORING CHECK, and the one to reach for: ASSERT that this layer stays clear of the named layers: `mustNotOverlap: ["msg1", "msg2"]`. After layout resolves, any named layer whose box intersects this one by more than 0.5px on BOTH axes is reported as `layout-collision` on the render output (same envelope as the other warnings: `{ code, layer, target, box, targetBox, overlap }`), and the render still completes. IT IS FALSE-POSITIVE-FREE BY CONSTRUCTION, not by heuristic: you DECLARED the separation, so nothing is inferred and there is no intent to guess wrong about. A deliberate overlay simply never declares the pair.

🔴 USE IT ON FIXED-SLOT LAYOUTS, which is the one failure the anchor-based check structurally cannot see: hardcoded x/y with no anchors declares no relationship, so nothing can be verified against it. A layer that hugs its text will walk into its neighbour as the text grows, and this is what catches it. SYMMETRIC BY DECLARATION ONLY: A naming B does not make B name A, but the PAIR is reported ONCE (keyed on the sorted pair), so a mutual declaration does not double-report. Unknown layer names are REFUSED (`unknown-reference`, naming the valid layers) exactly like `fitTo`/`anchor.to` — a typo'd assertion that silently checks nothing is the worst possible outcome. Listing the layer itself is refused, duplicates are ignored, and "$stage" is refused (every visible layer overlaps the canvas; for leaving it, see `layout-overflow`).

🔴 THREE LAYERS OF DEFENCE AGAINST THE SAME DEFECT, so pick the right one rather than assuming the others cover you. (1) `mustNotOverlap` is the AUTHORING ASSERTION: you declare the separation you are relying on and every violation is reported — it is the ONLY one that catches a fixed-slot layout, because such a scene declares no anchors for anything to be checked against. (2) The anchored-pair `layout-collision` above is an ENGINE INVARIANT: it cannot fire on a layout the resolver can produce, so it only ever means our arithmetic regressed. (3) CHAINING the layers with per-axis anchors (`anchorY: { to: "msg1", edge: "top", gap: 8 }`) makes the whole class IMPOSSIBLE BY CONSTRUCTION, because the spacing is derived from the resolved box instead of measured once — that is the real fix, and the other two are the safety net for layouts that have not been converted yet.

🔴 THE SEMANTICS INVERT BETWEEN THE TWO ANCHOR TARGETS, and this is the one thing to get right: anchoring to a LAYER places this layer OUTSIDE-adjacent to that layer's edge (`edge: "bottom"` means "sit BELOW it"), while anchoring to the reserved target `"$stage"` (the canvas itself) pins this layer INSIDE the canvas against that edge (`edge: "bottom", gap: 60` means this layer's OWN BOTTOM edge sits 60px above the stage bottom). A `$stage`-pinned layer therefore GROWS AWAY from the edge it is pinned to: a bottom-anchored hug-sized caption grows UPWARD as it goes from one line to six, and its bottom edge does not move — which is how a chat bubble stops walking off the canvas as the text gets longer. Same per edge: `edge: "right"` pins the right edge and grows leftward. `$stage` is an `anchor.to` target ONLY: `fitTo: "$stage"` is REFUSED (fitTo grows a container around another layer's measured box; to cover the canvas, just set x/y/width/height), and a layer literally named `$stage` in the layers map is REFUSED rather than silently shadowing the reserved target. fitTo and anchor.to reference layers BY NAME (the keys of the layers map, the same names listed in `layers` above). An unknown name, a circular reference, or the autoFit/hug contradiction FAILS the render with a message naming the offending layer, and nothing is silently repaired. Rotation is ignored by layout (an anchor uses the target's unrotated box).

🔴 ANCHOR THE LAYER THAT HAS THE CONTENT; CONTAINERS `fitTo` IT. Layers resolve INDEPENDENTLY, so anchoring a `fitTo` container does NOT drag its target along. `bubble: { fitTo: "message", anchor: { to: "$stage", edge: "bottom" } }` gives you a bubble sized to the message, parked at the bottom, and EMPTY, with the message still where it was declared. The correct form is the mirror image: put the `anchor` on `message` and let `bubble` merely `fitTo` it, so the bubble follows the text. A container that ends up not overlapping its own target is reported as `layout-detached-container` (a warning, not a refusal). OVERFLOW IS A WARNING, NOT A REFUSAL: any layer whose RESOLVED box leaves the stage is reported on the render output as `warnings` (one human sentence each) plus `layoutWarnings` (structured: `{ code: "layout-overflow", layer, box, stage, edges }`), and the render still completes, because bleed is a legitimate choice. An unattended batch should assert `layoutWarnings.length === 0`; in batch mode each entry also carries its `item` index. BATCH LEGIBILITY: one mis-authored layer on a 30-item batch produces 30 near-identical entries, so a batch output ALSO carries `layoutWarningsSummary` — one entry per distinct (code, layer, target) triple — the TARGET is part of the key, so one layer colliding with two different anchor targets is two entries rather than one that under-reports — shaped `{ code, layer, items: [<indices>], count, sample: <one representative structured warning> }` — and its human `warnings` lines are the summary sentences (one per distinct triple, so EVERY distinct problem is named) plus at most the first 3 per-item lines and a "… and K more" tail.

⚠️ THOSE 3 SAMPLE LINES ARE THE FIRST 3 IN ITEM ORDER, NOT ONE PER CODE, so when several layers are wrong they can all belong to the loudest one — the summary sentences above them are what guarantee coverage, and `layoutWarnings` is where you go for any specific item.

🔴 KEEP ASSERTING ON `layoutWarnings`, NOT on the summary: `layoutWarnings` is the per-item channel and its shape is frozen, the summary is a roll-up for reading. `layoutWarningsSummary` is ABSENT (not an empty array) when there is nothing to summarize, and it never appears on a single (non-batch) render, which is unchanged.

⚠️ TWO CARVE-OUTS ON THAT ADVICE, so you do not over-trust it. (a) TEXT layers are measured for the overflow check even without `sizing`, but an IMAGE layer that declares no width/height is UNMEASURABLE at layout time (natural size is not known without fetching), so it can only ever report a `top`/`left` overflow — give image layers explicit width/height if you need them checked. (b) The `template_api` execution poll strips node output to an allowlist, so neither `layoutWarnings` NOR `layoutWarningsSummary` is visible to template_api callers; both are present on the normal execution poll and on the executions GET. ALL FOUR SURFACES RESOLVE: the visual compositor editor resolves layout on its canvas, and so do the baked PNG, the node thumbnail and the HTML export, through the same shared resolver.

⚠️ AUTHORING IS NARROWER THAN RESOLVING, so do not infer one from the other: the editor's Layout panel authors `sizing`/`fitTo`/`anchor` only. `anchorX`/`anchorY` are JSON/API-authored today — the panel RESOLVES and PAINTS them correctly and shows a notice naming them, but has no controls for them, and it disables the whole-`anchor` picker on such a layer so the contradiction cannot be created by hand. What the editor shows is what renders. The resolved x/y/width/height is DERIVED and is never written back into the layer, so `sizing`/`fitTo`/`anchor` stay the source of truth; an axis layout owns is not draggable or resizable in the editor. Ownership is PER AXIS: a layer carrying only `anchorY` cannot be dragged vertically (the drag pins to the resolved y) but moves freely on X, and a nudge key on the owned axis is inert.(4) STACKS — FLOW LAYOUT, the fourth capability and the one that makes a SEQUENCE of variable-height elements expressible at all. A `type: "stack"` layer is FLOW LAYOUT — CSS block flow / SwiftUI VStack / Figma Auto Layout. Its children are laid out one after another along `direction` ("vertical" | "horizontal") with a CONSTANT `gap` between them, each keeping its own content-driven size, so a chat thread has the same spacing whether a bubble is one line or four. That is the whole reason it exists: `anchor` couples BOTH axes to ONE target, so a sequence of variable-height elements had to be hand-positioned into fixed slots, and the gaps then varied with the content. TWO BINDING MODES, and a stack is exactly one of them (declaring both is refused): (A) `children: ["msg1","msg2","msg3"]` names layers that already exist at the TOP LEVEL of the layers map, flowed in list order. (B) `items` + a TEMPLATE is the DATA-DRIVEN REPEATER: `items` is an array, or a reference like "$data.messages" into the data context (the current batch row in batch mode); the template is instantiated once per item under the layer names `<stack>/<index>/<layerName>`. The template is EITHER `itemTemplate` (one base, refined by `variants` — the recommended form) OR `itemTemplates` (one whole template per `item.type`, for structurally different items).

🔴 ITEMS BIND EXACTLY LIKE A BATCH `data` ROW — an item's keys name LAYERS INSIDE ITS TEMPLATE and a string value sets a text layer's `text` or an image layer's `url`. There is no `bind` field anywhere in the compositor. `type` is consumed as the template discriminator and never binds to a layer, and so is `variants.key`. The ONE place `{{tokens}}` exist is INSIDE a mode-B template, where `{{index}}`, `{{count}}` and the item's own fields substitute into any string — see the SCOPE TOKENS rules. Nowhere else in the compositor.

🔴 A STACK WITH A `fill` IS A FRAME: it paints that fill BEHIND its own children, inset by its `padding`. That is how a chat bubble is drawn, and it REPLACES `fitTo`, which is REFUSED on a stack child (it sets position AND size from its target while the stack also sets position, so it was a dead field). A stack with no `fill` paints nothing at all and is pure layout. PER-CHILD FIELDS, on the CHILD layer: `alignSelf: "start"|"center"|"end"` is its CROSS-axis alignment (flexbox `align-self`) and `sizing.<crossAxis>: "fill"` stretches it across the stack's content box.

🔴 IT IS `alignSelf`, NOT `align`. `align` is already a text layer's TEXT alignment on every compositor surface, so reusing it would give `align: "center"` two meanings on one layer. This is the ONE place the stack vocabulary leaves flexbox's shortest spelling, and it uses flexbox's own longer one. "fill" is the THIRD sizing mode (`fixed` | `hug` | `fill`) and it is STACK-ONLY: on the stack's FLOW axis, or on a layer that is not a stack child, it is REFUSED. If EVERY child fills and the stack declares no cross size, that is refused too — the box they stretch to would be zero. THE STACK'S OWN SIZE: it HUGS its content per axis by default (children + gaps + padding on the flow axis, the widest child on the cross axis) and takes a declared `width`/`height` instead when one is given. It positions itself with the ordinary `x`/`y` or `anchor`, including `anchor.to: "$stage"`. CLIPPING: `overflow: "clip"` needs a FIXED size on the flow axis (declaring it on a hugging stack is REFUSED, because a hug box is exactly as big as its content and nothing could ever fall outside it). The flow then runs FROM THE STACK'S ANCHORED EDGE: a vertical stack anchored `edge: "bottom"` (or a horizontal one anchored `edge: "right"`) lays out from the FAR end, so the LAST item sits against that edge and the FIRST items are the ones that fall out. That is the 30-message thread: pin the stack to the bottom of the stage, give it a fixed height, and the newest message is always visible.

🔴 CLIPPING REPORTS AS `layoutInfo`, NOT `layoutWarnings`, and the separation is deliberate: clipping is the FEATURE WORKING, so putting it in the warning array would fire on every correct render of that thread and train callers to ignore the channel. Shape: `{ code: "layout-clipped", stack, clip: {x,y,width,height}, clipped: [<ids never painted>], partial: [<ids painted partially>] }`, plus one human line on `warnings`. Children under a clip are EXCLUDED from the overflow check for the same reason, so `layoutWarnings.length === 0` still means what it always meant. REFUSALS (never repairs, always naming layers): a `children` entry that is not a layer; a layer claimed by two stacks; a `children` entry that is itself a top-level stack; a child that also declares its own `anchor`, `anchorX`, `anchorY` or `fitTo` — the stack owns its children's positions, and this is refused IDENTICALLY IN BOTH BINDING MODES; `items` without `itemTemplates`; an `item.type` that is not a template key (the valid ones are listed); `items` resolving to a non-array; a real layer whose name collides with the `<stack>/<index>/<layer>` namespace; a NEGATIVE `gap` (overlap inside a flow has no reading — use `anchor` with a negative gap for that); `rotation` on a stack (layout works in unrotated stage space, so it is a dead field); a child with no measurable size (an image with no declared width/height, exactly as `fitTo` refuses); nesting deeper than TWO levels. An `items` reference that resolves to NOTHING is an EMPTY stack, not an error — one batch row missing a field must not fail the run. WARNINGS, NOT REFUSALS: an item that omits a field EVERY OTHER item of its type sets is reported as `missing-bound-field` on the render `warnings`, because those layers ship the TEMPLATE PLACEHOLDER — the fake-screenshot tell this feature exists to kill. A template layer that NO item ever binds is a static label and is not reported. Under `variants` the VARIANT VALUE is the item's type, so a `number` divider binding `pre`/`post` is never compared against a `him` bubble binding `txt`. SINGLETON RULE: a variant holding exactly ONE item has no sibling to compare against, so it is expected to bind the layers its own `variants.map` entry styles instead — minus any layer no item anywhere binds, which is still a static label. INVISIBLE CHILDREN take NO FLOW SPACE: `visible: false` closes the gap (as in Figma) rather than leaving a hole the size of a hidden layer. VARIANTS — ONE TEMPLATE, PER-VALUE PATCHES, and the reason `itemTemplates` is now the narrow case rather than the default. `itemTemplate` (SINGULAR) + `variants` is the RECOMMENDED mode-B form, and it SUBSUMES `itemTemplates` (plural) for everything except structurally different items. ONE base template, plus PATCHES that deep-merge over it per item: `variants: { key: "from", map: { "him": { "bubble": { "fill": "#5B4AF0" }, "$align": "end" }, "her": { "bubble": { "fill": "#25282E" }, "$align": "start" } } }`. PATCHES DEEP-MERGE LIKE A SHALLOW THEME OVERRIDE: objects merge key by key, and scalars AND ARRAYS REPLACE wholesale (a `cornerRadius` 4-tuple or a `points` list is one value, not a list to merge element-wise). A patch's TOP LEVEL accepts EXACTLY THREE `$`-prefixed directives, and any other `$` key is REFUSED: `$align` sets that INSTANCE's `alignSelf` (its cross-axis alignment in the stack), `$gapBefore` adds main-axis space before that instance, and `$runs` (in a `map` entry only) declares positional patches inside a run of THAT value. Every other key names a layer, and one naming a layer the base template does not have is REFUSED, listing the valid layers — a patch REFINES the base and cannot introduce a layer. `variants.key` names the ITEM FIELD that picks the patch, it is REQUIRED, and (like `type`) it is consumed as a discriminator and never binds onto a layer. An item whose key value has NO `map` entry renders the UNPATCHED base and ALWAYS warns `missing-variant` naming the value — an unmapped enum value is a typo or a data change, never a deliberate "no styling". RUN SELECTORS — `variants.runs: { firstOfRun, midOfRun, lastOfRun, onlyOfRun }` — patch by POSITION inside a RUN, which is a MAXIMAL STREAK OF CONSECUTIVE ITEMS whose `key` value is equal. Think CSS sibling selectors, with the streak in place of the parent. ORDER, LEAST SPECIFIC FIRST: BASE -> `map` PATCH -> SHARED `runs` -> THAT MAP ENTRY'S OWN `$runs`. Each later step wins on a field both set. `onlyOfRun` (a streak of one) applies INSTEAD of `firstOfRun`+`lastOfRun`, exactly like CSS `:only-child`, and does NOT fall back to them.

🔴 RUNS ARE PARTITIONED OVER WHAT SURVIVES `hideIfEmpty`, NOT OVER THE RAW ARRAY. A run expresses VISUAL ADJACENCY, and an item collapsed to nothing paints nothing and takes no flow space, so it does NOT split its neighbours: [him, her(empty), him] is ONE run of two `him` bubbles, with the grouped corners and the `$gapBefore` rhythm both reflecting that.

⚠️ SURVIVAL IS DECIDED BEFORE THE RUN PATCHES APPLY, and that ordering is forced rather than chosen: a run position is derived FROM which items survive, so survival cannot depend on a run patch. A run patch that sets a bound text can therefore neither resurrect nor collapse an instance. A hidden item receives NO run patch at all, because a patch on it would be a statement about pixels that do not exist. RUN PARTITIONING COMPARES KEY VALUES AS STRINGS: two items whose key value is an OBJECT are `[object Object]` to each other and land in the SAME run, and a missing/null key value runs with other missing ones (one streak, not N streaks of one). Use scalar enum values.

🔴 RUN SELECTORS DRIVE SPACING AS WELL AS STYLE, via `$gapBefore` — a patch top-level key (sibling of `$align`) adding EXTRA main-axis space BEFORE that instance, ADDITIVE to the stack's own `gap`, and IGNORED on the first item that flows (nothing to be spaced from). Real DM spacing — 8px inside a same-sender run, 24px on a sender switch — is exactly `gap: 8` plus `runs: { "firstOfRun": { "$gapBefore": 16 }, "onlyOfRun": { "$gapBefore": 16 } }`.

⚠️ DECLARE BOTH, and this is the one thing people get wrong: a lone message is a run of ONE, so it is `onlyOfRun` and `firstOfRun` never fires on it — a thread that alternates every message would otherwise get no switch gap at all. It SUPERSEDES the invisible-spacer-item workaround, which put layout knowledge into the data (and into an LLM prompt).

🔴 A MAP ENTRY MAY CARRY ITS OWN `$runs`, AND THE GROUPED-DM CASE IS WHY. Inside a streak of same-sender bubbles the corner FACING THE NEIGHBOUR goes tight — and since a run never spans two key values, that is a DIFFERENT corner per sender, which one shared `runs` map cannot say. `cornerRadius` is [topLeft, topRight, bottomRight, bottomLeft]. RIGHT-ALIGNED sender (the flat side is the RIGHT): firstOfRun [46,46,8,46] (bottom-right tight, facing the bubble below), midOfRun [46,8,8,46] (both right corners), lastOfRun [46,8,46,46] (top-right, facing the bubble above), onlyOfRun [46,46,46,46]. LEFT-ALIGNED sender mirrors it on the LEFT: firstOfRun [46,46,46,8], midOfRun [8,46,46,8], lastOfRun [8,46,46,46], onlyOfRun [46,46,46,46]. Keep the shared `runs` for rules that are genuinely position-only. USE `itemTemplates` (plural) ONLY when items are STRUCTURALLY different layers (a date divider is not a bubble with another fill). Declaring BOTH forms, or `variants` together with `itemTemplates`, is REFUSED. WRONG (two whole templates for a styling delta): `itemTemplates: { "him": { "bubble": {...20 fields...}, "text": {...8 fields...} }, "her": { "bubble": {...the same 20 fields, one of them different...}, "text": {...the same 8 fields...} } }` — every layer, font and padding is duplicated, the copies drift, and BOTH still render so nothing ever tells you they drifted. RIGHT (one base + patches): `itemTemplate: { "bubble": {...20 fields...}, "text": {...8 fields...} }` plus `variants: { "key": "from", "map": { "him": { "bubble": { "fill": "#5B4AF0", "cornerRadius": [46,46,46,46] }, "$align": "end", "$runs": { "firstOfRun": { "bubble": { "cornerRadius": [46,46,8,46] } }, "midOfRun": { "bubble": { "cornerRadius": [46,8,8,46] } }, "lastOfRun": { "bubble": { "cornerRadius": [46,8,46,46] } } } }, "her": { "bubble": { "fill": "#25282E", "cornerRadius": [46,46,46,46] }, "$align": "start", "$runs": { "firstOfRun": { "bubble": { "cornerRadius": [46,46,46,8] } }, "midOfRun": { "bubble": { "cornerRadius": [8,46,46,8] } }, "lastOfRun": { "bubble": { "cornerRadius": [8,46,46,46] } } } } } }`. One shape, and the difference between senders is the four lines that ARE the difference. AND THE SAME MECHANISM DRIVES SPACING: `gap: 8` on the stack plus `variants: { "runs": { "firstOfRun": { "$gapBefore": 16 } } }` is 8px inside a same-sender run and 24px on a sender switch — the real DM rhythm, in two numbers, with no invisible spacer items in the data.

✅ THE 4-TUPLE `cornerRadius` FORM IS LIVE (per-corner radius shipped in #958), so the example above renders exactly as written: `[topLeft, topRight, bottomRight, bottomLeft]`, CSS `border-radius` order, on all four surfaces. A SCALAR still applies to all four corners, and any other shape is REFUSED naming the layer rather than silently rendering square. The patch mechanism is value-agnostic — it merges whatever you write, and the radius value is then validated by the one shared normalizer. SCOPE TOKENS, inside a mode-B template only: any string may contain `{{index}}` (0-based) and `{{count}}` (the number of items), plus the ITEM'S OWN FIELDS by name (`{{name}}`, dotted paths like `{{author.name}}`), so `"#{{index}} of {{count}}"` needs no extra data field.

🔴 A DATA FIELD WINS OVER THE META-TOKEN OF THE SAME NAME: an item carrying `index` renders ITS value, because the author's data beats our magic. A token that resolves to nothing (or to an object/array, which has no text form) is left LITERAL on the canvas and reported as `unknown-scope-token` — substituting "" would hide the mistake inside a paid render. `{{first}}` / `{{last}}` are deliberately NOT tokens: a boolean has no useful text form and its real use is conditional STYLING, which `variants.runs` already does without inventing a conditional syntax. `hideIfEmpty: true` on a TEXT layer (anywhere in the scene, stack or not) treats that layer as `visible: false` when its RESOLVED text is empty or whitespace — so it paints nothing, its `textBg` paints nothing, and inside a stack it takes NO FLOW SPACE (the gap closes, as `visible: false` already does).

🔴 THIS IS THE CURE FOR THE BLOB. Without it an empty text layer collapses to a ZERO-SIZED BOX but the FRAME around it still paints its `padding`, so a missing field renders as a small coloured lozenge nobody authored. WITH it, a frame whose children ALL end up hidden this way is hidden too, so the bubble disappears with its text. Without the flag, behaviour is unchanged byte for byte — an empty text layer still collapses and its frame still paints. It is REFUSED on a non-text layer, naming the field: for an image with no url, or an empty frame, set `visible` directly. NESTING is capped at TWO levels and only inside an ITEM TEMPLATE (either form: `itemTemplate` or `itemTemplates`), because the canonical shape needs both: COLUMN -> ROW -> BUBBLE, where the row puts an avatar beside a bubble and the bubble is a FILLED stack whose padding insets its text. Wrapping, `space-between` and grid are deliberately absent.

🔴 TWO DIFFERENT THINGS ARE SPELLED `fill`, ON DIFFERENT KEYS, AND THEY ARE DELIBERATELY DISTINCT: `fill` on a STACK is BACKGROUND PAINT (it makes the stack a frame and takes a colour or gradient, alongside `stroke` and `cornerRadius`), while `sizing.width: "fill"` on a CHILD is CROSS-AXIS STRETCH (an enum value on a different key, which paints nothing). One is a paint property on the container, the other is a sizing mode on a child; nothing that accepts one accepts the other.

🔴 A STACK PAINTS NOTHING ITSELF UNLESS IT DECLARES A `fill`. With one it is a FRAME: it paints that fill behind its own children, inset by its `padding` — which is how a chat bubble is drawn, and what REPLACES `fitTo` on a stack child. Without a fill it is removed from the paint order entirely. Either way its children take its z-slot in flow order. The editor canvas resolves and paints stacks READ-ONLY: interactive stack editing (drag to reorder, drag the gap) is stated PHASE 2, and stacks are authored as JSON today. PER-CORNER RADII: `cornerRadius` on a rectangle or image layer takes either ONE number (all four corners) or a 4-TUPLE `[topLeft, topRight, bottomRight, bottomLeft]` in CSS border-radius order. THE LAYOUT THIS UNLOCKS: message grouping in a chat mock. Back-to-back bubbles from the same sender flatten ONLY the corner facing their neighbour — `cornerRadius: [46, 46, 8, 46]` is a pill everywhere except the bottom-right, which is where the next bubble from the same sender sits. A single scalar radius cannot express it, and uniform pills on every bubble is the clearest tell that a chat screenshot is fake. Radii that overlap are clamped exactly like CSS (Backgrounds and Borders Level 3 §5.5 "Overlapping curves"): for each side let f = sideLength / (sum of its two radii), and if the smallest f across the four sides is below 1, EVERY radius is scaled by that same factor — so the shape stays proportional instead of one corner being lopped. Each radius is then additionally capped at half the shorter side so the compositor editor, the baked PNG and the HTML export draw an identical outline. ANY OTHER SHAPE IS REFUSED, NOT REPAIRED: a bare string, a 2-tuple, a 5-tuple, a negative number or a NaN fails the render with an error naming the layer, the value received and the accepted forms. It is never silently treated as zero — which is exactly what used to happen, rendering four sharp corners with no diagnostic anywhere. WIREABLE ASSETS — `"$port:<name>"`. Any string in a layer, at any depth (top-level layer, `itemTemplate`, `itemTemplates`, a `variants` patch), may be exactly `"$port:<name>"`. Saving the workflow MINTS a real IMAGE input port called `<name>` on the node; at render time the wired input's URL is substituted for the reference.

🔴 WRONG: `itemTemplates: { "beat": { "art": { "url": "https://cdn.example.com/meme.png" } } }` — a baked CDN string. It renders, and everything else about it is broken: the asset is INVISIBLE on the canvas (nothing is wired, so the node card shows no source and the owner asks "where are the memes?"), it is UNSWAPPABLE in the editor, and it is UNAUDITABLE — nothing can say which run used which image. RIGHT: `itemTemplates: { "beat": { "art": { "url": "$port:meme_cooked" } } }` plus an Import node (or any image-producing node) wired into the `meme_cooked` input. Same picture, and now the canvas tells the truth. This is the ONLY way a port can reach a layer INSIDE a template: an item binds from its own ROW DATA, which is per-item by construction, so a shared asset had nowhere else to live. PORT NAMES match /^[a-z0-9_]+$/ (they become real handle ids, `in-<name>`); anything else is REFUSED at save, naming the layer and the offending name. A name that already belongs to an input port this feature did not mint (`background`, `layer_1`, …) is REFUSED rather than re-owned. LIFECYCLE IS SYMMETRIC: the port is minted when the first reference appears and REMOVED when the last one goes away, and repeated saves are a fixed point. BATCH: a `$port:` reference resolves ONCE PER RUN — it is the port's value, not a per-item value. Items vary by row data; ports supply the assets shared across items. For a different image per item, bind it from the row exactly as before. IT WORKS IN A JSON `layers` INPUT TOO — the same syntax, the same channel, the same refusal — so a programmatically-built layer map can reference ports exactly like a saved scene.

🔴 UNRESOLVABLE IS A REFUSAL, NOT A BLANK, and the message tells you WHICH of the two it is. NOT WIRED: the port exists on the node and nothing feeds it — wire an image node. NOT MINTED: no `$port:`-minted port of that name, which means either the workflow has not been saved since you added the reference, or the name collides with a port this feature did not create and the save refused to re-own it — rename it and save. The render FAILS naming the port and every layer that references it, and uploads nothing, because a silently blank asset is the exact defect this syntax replaced. `POST /api/v1/workflows/{id}/dryrun` catches both statically, for $0, BEFORE any paid upstream node runs. In the EDITOR the same layer paints a dashed placeholder chip naming the port — on every instance of a stack, not on the container — so the fix is visible instead of inferable. Only a whole-string match counts: a URL that merely contains "$port:" is a URL.

### Numeric bounds referenced above

- `anchor.alignOffset` must be finite and within ±16384.

<!-- generated:END section=compositor-layout -->

<!-- generated:BEGIN section=compositor-port-refs source=src/components/workflows/compositor/compositor-validation.ts -->
<!-- generated:STAMP date=2026-08-06 sha=268376098db8 hash=dd7ff04474d2 -->

> **Generated 2026-08-06 from `src/components/workflows/compositor/compositor-validation.ts` @ `268376098db8`.**
> Do not hand-edit between the markers; edit the constant in the Wireflow
> repo and regenerate. Prose outside the markers is hand-written and safe.

## Wireable assets — `$port:<name>`

This is the tail of the layout contract above, repeated under its own heading on
purpose: `$port:` is what an agent greps for when an asset inside an
`itemTemplate` needs to come from a wired node instead of a baked CDN string,
and until now it appeared only in `blocks.md`.

WIREABLE ASSETS — `"$port:<name>"`. Any string in a layer, at any depth (top-level layer, `itemTemplate`, `itemTemplates`, a `variants` patch), may be exactly `"$port:<name>"`. Saving the workflow MINTS a real IMAGE input port called `<name>` on the node; at render time the wired input's URL is substituted for the reference.

🔴 WRONG: `itemTemplates: { "beat": { "art": { "url": "https://cdn.example.com/meme.png" } } }` — a baked CDN string. It renders, and everything else about it is broken: the asset is INVISIBLE on the canvas (nothing is wired, so the node card shows no source and the owner asks "where are the memes?"), it is UNSWAPPABLE in the editor, and it is UNAUDITABLE — nothing can say which run used which image. RIGHT: `itemTemplates: { "beat": { "art": { "url": "$port:meme_cooked" } } }` plus an Import node (or any image-producing node) wired into the `meme_cooked` input. Same picture, and now the canvas tells the truth. This is the ONLY way a port can reach a layer INSIDE a template: an item binds from its own ROW DATA, which is per-item by construction, so a shared asset had nowhere else to live. PORT NAMES match /^[a-z0-9_]+$/ (they become real handle ids, `in-<name>`); anything else is REFUSED at save, naming the layer and the offending name. A name that already belongs to an input port this feature did not mint (`background`, `layer_1`, …) is REFUSED rather than re-owned. LIFECYCLE IS SYMMETRIC: the port is minted when the first reference appears and REMOVED when the last one goes away, and repeated saves are a fixed point. BATCH: a `$port:` reference resolves ONCE PER RUN — it is the port's value, not a per-item value. Items vary by row data; ports supply the assets shared across items. For a different image per item, bind it from the row exactly as before. IT WORKS IN A JSON `layers` INPUT TOO — the same syntax, the same channel, the same refusal — so a programmatically-built layer map can reference ports exactly like a saved scene.

🔴 UNRESOLVABLE IS A REFUSAL, NOT A BLANK, and the message tells you WHICH of the two it is. NOT WIRED: the port exists on the node and nothing feeds it — wire an image node. NOT MINTED: no `$port:`-minted port of that name, which means either the workflow has not been saved since you added the reference, or the name collides with a port this feature did not create and the save refused to re-own it — rename it and save. The render FAILS naming the port and every layer that references it, and uploads nothing, because a silently blank asset is the exact defect this syntax replaced. `POST /api/v1/workflows/{id}/dryrun` catches both statically, for $0, BEFORE any paid upstream node runs. In the EDITOR the same layer paints a dashed placeholder chip naming the port — on every instance of a stack, not on the container — so the fix is visible instead of inferable. Only a whole-string match counts: a URL that merely contains "$port:" is a URL.

<!-- generated:END section=compositor-port-refs -->
