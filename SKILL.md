---
name: wireflow
description: >
  Build and run Wireflow AI workflows via REST API — text→image, text→video,
  audio, and multi-step creative pipelines using FAL models, LLMs, and Remotion
  video compositions. No Wireflow codebase access required; authenticates with
  a scoped API key.
when_to_use: >
  Use when the user says "wireflow", asks to "build a workflow", "run a
  workflow", "generate a video with a remotion template", or wants to automate
  content creation via Wireflow. Do NOT use for direct edits to the Wireflow
  codebase itself, or generic AI image/video requests that don't mention
  Wireflow or its concepts (templates, compose nodes, workflows).
user-invokable: true
argument-hint: "[templates | blocks | nodes | upload <file> | check <json> | run <id> | generate \"<prompt>\"]"
license: MIT
allowed-tools: Read, Bash, Write, WebFetch
metadata:
  category: creative-automation
  version: "0.9.0"
---

# Wireflow Skill

> **⚠️ You are DOGFOODING the user's own product.** Michael owns Wireflow (his
> #1 product, repo at `~/Documents/projects/wireflow`). Using this skill is
> deliberate dogfooding. When the skill or API hits a limitation, bug, or rough
> edge mid-task, that is **valuable product signal** — the most important output
> of the session, not a nuisance. ALWAYS: (1) capture the exact bug/UX gap,
> (2) surface it explicitly as a Wireflow product issue, (3) offer to fix it in
> the wireflow repo. NEVER silently work around a Wireflow flaw, and NEVER call
> it "cosmetic" / "no fix needed" / "leave it" — that is the wrong instinct and
> defeats the purpose of dogfooding.

Build and run [Wireflow](https://wireflow.ai) AI workflows from natural
language. Wireflow is a visual AI platform where workflows are node graphs
that chain together image/video/audio generators (FAL, Replicate, OpenAI,
Anthropic, ElevenLabs) and render final output — including professional
video via Remotion compositions.

This skill lets any Claude instance (anywhere — local, cloud, any project)
compose and execute Wireflow workflows on the user's behalf using an API
key. No Wireflow codebase access required.

## Setup (one-time)

1. Create a Wireflow API key at <https://www.wireflow.ai/settings?tab=api-keys&section=api-keys>
   with these scopes:
   - `workflows:read` — list workflows and templates
   - `workflows:write` — create/update workflows
   - `workflows:execute` — run workflows

2. Export it in your shell:
   ```bash
   export WIREFLOW_API_KEY="wf_live_..."
   ```

3. (Optional) Set a custom base URL for self-hosted or staging:
   ```bash
   export WIREFLOW_BASE_URL="https://www.wireflow.ai/api/v1"   # default
   ```

## Core loop

When the user asks you to build or run a Wireflow workflow:

1. **Discover** — fetch available Remotion templates via
   `bash scripts/wf.sh templates`, and reusable motion-graphics scenes
   (Blocks) via `bash scripts/wf.sh blocks`, so you know which compose
   templates and Blocks exist (see *Blocks* below + `references/blocks.md`)
2. **Try the AI generator first** — Wireflow has a built-in workflow
   generator at `POST /workflows/generate/stream` that matches user prompts
   against existing templates. Use `bash scripts/wf.sh generate "<prompt>"`.
   If it returns a clean match, you're done — just run it.
3. **Compose manually** — if the generator doesn't fit, hand-author a
   workflow JSON (nodes + edges). See `references/workflow-schema.md` and
   `examples/` for shape.
4. **Create** — `bash scripts/wf.sh create workflow.json` → returns `id`.
   Positions are auto-laid-out first so nodes never overlap (see *Clean
   layout* below) — don't hand-pick `x`/`y`.
5. **Edit** — to modify an existing workflow (add nodes, change layers,
   rewire), fetch it (`wf.sh get <id>`), edit the JSON, and send it back with
   `bash scripts/wf.sh update <id> workflow.json`. NEVER raw-PUT an edited
   graph: `update` re-runs graph-lint AND auto-layout, so the canvas the
   user opens is clean — edited graphs are the main source of overlapping
   nodes.
6. **Run** — `bash scripts/wf.sh run <id> '{"inputs": {"<nodeId>": "..."}}'`
7. **Poll / wait** — `bash scripts/wf.sh wait <executionId>` BLOCKS until
   `COMPLETED`/`FAILED`, printing **per-node status each tick** and the failing
   node's error (so you can tell "rendering" from "dead"). It's rate-aware
   (6s ticks, backs off on 429). Use `wf.sh poll` for a single snapshot.
8. **Return** — hand the user the workflow URL (so they can inspect/remix
   in the visual editor) and the final output URL (image, MP4, MP3)

> **Observability — poll the EXECUTION, not the workflow.** Per-node run state
> lives on the **execution** (the `executionId` that `run`/`run-node` returns),
> NOT on `GET /workflows/{id}` — that returns the saved graph, whose
> `output/status/error` are null until a run writes them, so polling it to ask
> "is it rendering or dead?" always looks dead. The flow is: `run`/`run-node` →
> grab the `executionId` → `wf.sh wait <executionId>`.
>
> Every poll response carries `nodeStates: [{ nodeId, label, status, error,
> outputUrl, progress, requestId }]` — per-node `PENDING | RUNNING | COMPLETED |
> FAILED` with the error string on a failure (a FAL moderation rejection shows
> here as `FAILED` + the provider message, not a silent hang), plus `progress`
> and the FAL `requestId` for support/debug. `outputUrl` is the **normalized**
> media URL across every output shape — a node's raw `output` is inconsistent
> (`output.url` on some models, `output.images[0].url` on others, string vs
> object), so prefer `nodeStates[].outputUrl`. A `429` means you hit the rate
> limit (~10/min) — slow down; `wf.sh wait` already paces itself.

## Using your own assets (upload)

To put a **real** asset into a workflow — the user's product screenshot, a
logo, a reference/before image — host it first, then wire the returned URL into
an `input:image` / `input:video` / `compv3` node. External hosts are blocked by
the executor; the upload endpoint returns a `cdn.wireflow.ai` URL that's already
on the allowlist, so it works with zero extra steps.

```bash
url=$(bash scripts/wf.sh upload /tmp/screenshot.png)   # local file → CDN url
url=$(bash scripts/wf.sh upload https://example.com/logo.png)  # rehost a remote url
# then drop $url into an input:image node's value and run the workflow
```

- Accepts a local file path **or** a remote URL (it rehosts it). Images, video,
  and audio up to 25MB.
- Prints **only** the public URL on success (so `$(...)` capture works); on
  error it prints the raw JSON to stderr and exits non-zero.
- `bash scripts/wf.sh media` lists what you've uploaded (upload once, reuse the
  URL across runs).
- Needs the `workflows:write` scope (same key that creates workflows).

This is the missing primitive for "show the actual product" ad/brand workflows —
capture → `wf.sh upload` → build the factory around the URL → run.

**Multi-reference image compositing** (e.g. place a product screenshot ONTO a
phone in a second reference) — the multi-ref image models (`generate:nano_banana_pro`,
seedream, …) fold `image1..imageN` into one request. Only `image1` is a static
port, but wiring a 2nd ref headless just works: target `in-image2` (and
`in-image3`, …) — create/update materializes the port from the wired edge, the
same way scene `{{token}}` ports auto-derive. `wf.sh nodes` shows the cap via
`expandedImageInputs`.

> **Edit-model gotcha (model behavior, not a Wireflow bug):** asking an image
> *edit* model (nano_banana_pro, etc.) to **reposition/move** a subject often
> **duplicates** it (you get two of the person) — the model adds rather than
> relocates. Workarounds: phrase it as a removal+placement ("the frame contains
> exactly ONE person, standing at the right; empty on the left"), or mask/inpaint
> the original location, or composite deterministically (the planned
> video-composite/mask node is the real fix for object-move hooks). For a true
> on-screen MOVE, gen the scene with the subject already where you want it.

## Verify before you pay (dry-run preview)

Before running a workflow that ends in a `video:remotion` SceneGraph render
(which costs real credits), dry-run the graph to LOOK at it first:

```bash
bash scripts/wf.sh preview sceneGraph.json
```

It validates the graph and renders ~3 sampled **still frames** on Lambda
(cents, not FAL credits — no full video render), returning:

- `frames[]` — CDN URLs of the sampled stills. Fetch them and actually look
  (caption contrast, off-screen titles, a Block showing a gray placeholder).
- `diagnostics` — **the structured feedback channel: read this first.** A blank
  scene, an empty caption/audio port, a placeholder block, duration drift — each
  is a `{ code, severity, message, target, hint }` you branch on and fix. See
  "Reading diagnostics" below.
- `issues[]` / `warnings[]` — legacy string versions of the same (kept for
  back-compat; prefer `diagnostics`).
- `durationFrames` / `durationSeconds` / `sceneCount` — so you can confirm the
  timeline matches your audio/voiceover length before rendering.

## Reading diagnostics (self-correct instead of guessing)

Every create/update/preview/run response carries a **`diagnostics`** envelope —
one machine-readable feedback channel so you know what failed, *where*, and *how
to fix it*, instead of inferring from prose or getting silence while a scene
quietly drops.

```jsonc
"diagnostics": { "version": 1, "counts": { "error": 0, "warning": 1, "info": 1 },
  "diagnostics": [
    { "code": "media.port_resolved_empty", "severity": "warning",
      "message": "Scene 3 (image) has no src — a wired media port resolved to empty.",
      "target": { "nodeId": "reel", "sceneIndex": 3 },
      "hint": "Confirm the upstream node emits a url and the edge targets the right handle." }
  ] }
```

The loop: call → read `diagnostics` → if `counts.error > 0` it didn't work →
**branch on `code`** (never the message), locate via `target`, apply `hint` →
re-submit until only `severity:"info"` remains. `error` = must fix; `warning` =
a former *silent* failure, surfaced (empty captions, dropped scene, clamped
overlay); `info` = an automatic repair, no action. Full code table +
self-correction protocol in `references/diagnostics.md`.

Iterate on the JSON until the stills look right, *then* run the full workflow.
The full render also returns a `warnings` array in its node output (same
placeholder/duration-drift signals), so check it after a real run too.

Accepts a raw `{ fps, width, height, scenes }` graph or a `{ sceneGraph: {...} }`
wrapper. Block scenes resolve their bundle automatically — but only Blocks where
`renderable` is true (from `wf.sh blocks`) actually render; others show the gray
placeholder in the preview.

## Authoring ad videos headlessly (SceneGraph)

A `video:remotion` node can carry a **SceneGraph** you author directly in JSON —
the supported path for building UGC/ad videos over the API with no editor.
`{ fps, width, height, scenes: [...] }`, plus these composited layers:

**Scene timing — `durationInFrames` is honored in wall-clock.** The sum of your
scene `durationInFrames` ÷ `fps` is the video's runtime; match it to your VO
length. (If a wired source clip's fps differs, the renderer keeps wall-clock
constant so audio/captions stay synced — and any residual drift is reported in
the run's `warnings[]`.)

> **Speed: prefer the explicit `playbackRate`.** A video scene has
> `playbackRate` — `1` = native, `2` = 2× faster, `0.5` = half speed. That's the
> clean, predictable lever. (Separately, `durationInFrames` *also* time-
> compresses: a scene plays its source to fill exactly `durationInFrames`, so a
> shorter window speeds the clip up — useful, but `playbackRate` is the explicit
> control.) Use `startFrom` (seconds) to start partway into the source instead.

**🔴 Get clips INTO scenes by WIRING, not by baking URLs.** A scene `src` can be
a literal URL **or** a `{{token}}`. Always prefer the token when an upstream node
produces the clip (an AI generator, an upload, a process node) — that keeps the
canvas fully connected so the user can inspect/remix it, which is the whole point
of building inside Wireflow. **One `video:remotion` node takes UNLIMITED media
ports** — it does not cap at one. Each distinct `{{token}}` is its own port, and
**create/update auto-derives the port from the sceneGraph** (same as the editor)
— you do NOT need to declare it in `data.inputs`:

1. Reference a token per scene src: `{ "type": "video", "src": "{{hook}}" }`,
   `{ "type": "video", "src": "{{proof}}" }`, `{ "type": "video", "src": "{{broll}}" }`.
2. Wire one media node into each — the edge `targetHandle` is `in-<token>`:
   ```jsonc
   { "source": "kling-hook",  "target": "reel", "targetHandle": "in-hook"  },
   { "source": "kling-proof", "target": "reel", "targetHandle": "in-proof" },
   { "source": "kling-broll", "target": "reel", "targetHandle": "in-broll" }
   ```

That's it — on create/update the server scans the sceneGraph and materializes a
typed port per token (a `video` scene → VIDEO, `image` → IMAGE, an
`audioTrackConfig` key → AUDIO, etc.), so graph-lint accepts the `in-<token>`
edges and at render each port resolves its `{{token}}` to that node's output URL.
N tokens = N clips composed in ONE node, zero literal URLs, zero orphaned
generators. If you instead paste a generator's URL straight into `src`, its node
is left unwired and shows a stale thumbnail — that is a bug you created, not "by
design." (Template-mode Compose nodes expose fixed `shot_2`, `shot_3`… ports —
`wf.sh template <id>` lists them. `wf.sh nodes` shows `video:remotion` as
`dynamicPorts: true`.)

**Motion on image OR video scenes — `kenBurns`.** Add a slow eased zoom/pan to
any image or video scene: `"kenBurns": "zoom-in" | "zoom-out" | "pan-left" |
"pan-right"`, with `"kenBurnsAmount": 1.08` for a subtle 8% push (default 1.15).
On video it composes on top of `scale`. A gentle `zoom-in` makes static b-roll
feel alive.

**Direct the whole video from a paragraph — `sceneGraph.director`.** Instead of
hand-setting kenBurns/transitions/SFX timing per scene, author a compact
**director** JSON (shots + beats) and the render compiles it onto the
primitives: camera→kenBurns, `transitionIn`→transition, `sfx:"audio_2"`→audio
timing, `emphasis`→a caption word punch, beats timed by `scene:i.start±n` /
`caption:<word>` / `frame:` / `time:`. An LLM writes the director from a line
like *"slow push-in on the hook, hit the notification with a ding, punch
'first', reveal the endcard with a chime."* Full schema + mapping + worked
example: `references/director.md`.

**Voiceover / music / SFX — author `audioTrack` (or `audioTracks`) directly:**
```jsonc
"audioTrack": { "src": "<mp3 url>", "attachTo": "comp", "volume": 1 }
// attachTo: "comp" = whole video; a scene index = that scene only.
// audioTracks: [ ... ] mixes several (VO + music bed + sound effects).
// startFrame = WHEN it begins on the timeline (a delay) — plays from the
//   source's start at that frame. For attachTo:"comp", startFrame is an
//   ABSOLUTE comp frame, so { attachTo:"comp", startFrame: 460 } drops an SFX
//   at frame 460. For a scene index, it's frames after that scene starts.
// trimStart = skip N frames INTO the source file (in-point) — separate from
//   startFrame. Use it to drop the first seconds of a music bed.
```

**Sound effects** (a notification pop, whoosh, UI click) — the
`audio:elevenlabs_sound_effects` node (ElevenLabs SFX v2, the best SFX library)
turns a text description into a sound. Wire a prompt into its `text` port, run it
(`wf.sh run-node`), then drop its `audio` output URL into an `audioTracks` entry
attached to the scene where the effect lands — e.g. a notification sound when a
banner pops in:
```jsonc
"audioTracks": [
  { "src": "<VO mp3>", "attachTo": "comp" },
  { "src": "<sfx mp3 from the SFX node>", "attachTo": 1, "volume": 0.7, "startFrame": 8 }
]
```
Author the node with `nodeType: "audio:elevenlabs_sound_effects"`, set
`config.text` (or wire it), e.g. `"soft UI notification pop, short, clean"`.

**Music bed** (a continuous melodic backing track under the VO) — the
`audio:elevenlabs_music` node. The SFX node above only makes one-shot effects;
it CAN'T produce structured music (it comes out spiky/erratic). Use this for the
bed. Wire a prompt into its `prompt` port, set `config.duration_seconds`
(10–60s) and `config.force_instrumental` (default `true` — no vocals under a
voiceover), run it, then pipe its `audio` output into a reel `audio_N` port at
**low volume** (`{ "attachTo": "comp", "startFrame": 0, "volume": 0.18 }`) so it
runs the whole video under the VO:
```jsonc
// audio:elevenlabs_music — config
{ "prompt": "minimal melodic-trap, confident, emotional, no vocals",
  "duration_seconds": 19, "force_instrumental": true }
```
Costs **$0.80 per bed** (flat — FAL bills $0.80/min rounded up, the node is
capped at 60s). ⚠️ You can't ear-check audio — a human must LISTEN and approve
the bed before it ships.

**Pipe MULTIPLE audio tracks (no literal URLs).** The `video:remotion` node has
numbered audio ports — `audio`, `audio_2`, `audio_3`, … (a new one appears each
time you wire an audio source). Each wired port becomes one mixed `audioTracks[]`
entry automatically. A port only carries a URL, so put each track's timing/mix
in **`sceneGraph.audioTrackConfig`**, keyed by port id:
```jsonc
// In the video:remotion node's sceneGraph:
"audioTrackConfig": {
  "audio":   { "attachTo": "comp" },                          // VO across the video
  "audio_2": { "attachTo": 1, "volume": 0.7, "startFrame": 8 },// SFX on scene 1
  "audio_3": { "attachTo": 2, "volume": 0.7 }                 // SFX on scene 2
}
// then wire 3 audio nodes → the reel's audio / audio_2 / audio_3 ports.
```
Run with `wf.sh run-node <wf> <reelNodeId>` — the render mixes all three on
their beats, with **zero literal audio URLs** in the sceneGraph. (Per-track
fields: attachTo, startFrame, trimStart, volume, keepSceneAudio — same as a
hand-authored audioTracks entry.)

For **foley on a video clip** (make silent Kling b-roll sound real — footsteps,
ambience, impacts synced to the motion), use `audio:mmaudio_v2`: wire the clip
into `video_url` + describe the sound in `prompt`; its `video` output is the same
clip with the soundtrack muxed in — wire that into the reel's scene `src`.

**Karaoke captions — author `captionTrack` directly:**
```jsonc
"captionTrack": {
  "raw": [ { "word": "hook", "start": 0.0, "end": 0.32 }, ... ],  // raw Whisper word_timestamps (seconds)
  "style": "tiktok-kinetic",          // | "minimal" | "subtitle"
  "position": "center",               // | "top" | "bottom"
  "activeColor": "#39FF14", "inactiveColor": "#ffffff",
  "fontFamily": "space-grotesk"       // | "system" | "inter" | "roboto"
}
```
`raw` accepts raw Whisper `word_timestamps` (`[{word,start,end}]` in seconds) —
the renderer normalizes them to frames at the comp fps. (The schema comment
says the generator shouldn't author these; that's about the *editor* flow where
input ports fill them. Direct authoring **is** the supported headless path.)

> **🔴 Hand-authoring a `raw` array while the `captions` port stays wired? Set
> `"editedByUser": true`.** A wired captions port is the source of truth and
> **rebuilds `raw` from the Whisper transcript every render** — so an unflagged
> hand-authored array (e.g. you merged the split `"Social"`/`"Shield."` tokens
> into one `"SocialShield."` word, or dropped the first N words to let the hook
> headline own the open) gets **discarded**. `editedByUser: true` pins your
> array and the Whisper node stays wired/connected (no need to cut the edge);
> `replace` corrections still apply on top. If you forget, the run's
> `diagnostics` returns `captions.port_overrides_authored` telling you exactly
> this. (For a simple brand-name fix, prefer `replace` below — no flag needed.)

**Fix a mis-transcribed brand/term — `captionTrack.replace` (keep the port wired):**
```jsonc
"captionTrack": {
  "raw": "{{captions}}",                              // still piped from Whisper
  "replace": [ { "from": "Risley", "to": "Rizzly" } ] // applied AFTER transcription
}
```
Whisper mishears brand names (e.g. "Rizzly" → "Risley"). `replace` corrects them
**after** the captions port fills the track, so the fix survives — whole-word,
case-insensitive by default (`"matchCase": true` to force exact case). This is
the durable fix; don't cut the captions port. **Before a Meta/paid-ad render,
preview and confirm the brand spelling.** (A human edit in the editor sets
`editedByUser: true`, which also stops the port from overwriting it.)

A **multi-token `from`** MERGES a brand Whisper split across two caption words
into one: `{ "from": "Social Shield", "to": "SocialShield" }` collapses the
`"Social"` + `"Shield."` words into a single `"SocialShield."` word (timing
spans the run, trailing punctuation tolerated). Single-token rules still replace
in place; the two compose.

**Restyle captions fully — no code.** `captionTrack` exposes every style knob
(override on top of the `style` preset): `strokeWidth`/`strokeColor` (the dark
outline that keeps text readable on ANY background — the real legibility fix),
`activeColor`/`inactiveColor`, `glow`, `shadow`, `fontFamily` (any CSS font),
`fontWeight`, `fontSizePx`/`fontScale`, `letterSpacing`, `textTransform`,
`chunkSize`, `position`/`topPercent`. Full field reference + examples:
`references/captions.md`.

**Two ways to feed audio + captions** — author them inline (above), OR **wire
the ports**: connect a TTS node into the `video:remotion` node's `audio` port
and a Whisper node into its `captions` port. The render path now mirrors a wired
`audio`/`captions` port onto `audioTrack`/`captionTrack` automatically (it used
to silently no-op headlessly). Author-provided tracks always win; the token form
`"captionTrack": { "raw": "{{captions}}", "style": … }` + a wired port also works.

**Fixed video/audio/image assets — pipe them through the ONE Import node.**
For a screen recording, b-roll, a pre-made clip, or a reference still (anything
not AI-generated), upload it (`wf.sh upload clip.mp4`) then add an **`input:image`
node — this IS the universal "Import" node** (label "Import", handles image **and**
video **and** audio). Set `data.inputType` to `"video"` / `"audio"` / `"image"`,
put the URL in `config.image` + `config.imageUrl` (any media), add
`config.mediaType` (`"VIDEO"`/`"AUDIO"`/`"IMAGE"`), and wire **its `media`
output** downstream (`sourceHandle: "out-media"`). The asset flows like any other
node output instead of being a hardcoded `src`.

> 🔴 **Do NOT use `input:video` or `input:audio`.** They're the legacy
> "fixed-asset" nodes — they render **blank with a ⚙️ fallback icon** on the
> canvas and are now hidden from the palette/catalog. The Import node
> (`input:image`) is the single correct media-input node for every media type;
> it's the only one that draws a preview. `wf.sh create`/`update` will emit a
> `deprecated-import-node` warning (with the exact replacement) if a graph still
> uses the legacy pair.

**Graphics over video — top-level `overlays` (free-floating image layer):**
```jsonc
"overlays": [
  { "type": "image", "src": "<png url>",
    "attachTo": "comp",          // or a scene index
    "startFrame": 0, "durationInFrames": 45,
    "x": 540, "y": 120, "width": 320, "anchor": "top", "zIndex": 20 }
]
```
Pin a notification banner, App Store badge, ★ sticker, or logo by pixel for a
frame window (zIndex 20 sits above captions, which are at 10). Scene-level
`overlays[]` remain text-only; this top-level layer is for graphics.

**Gradient backgrounds — a `gradient` scene (CTAs/endcards):**
```jsonc
{ "type": "gradient", "durationInFrames": 60,
  "stops": [ { "color": "#ff0040" }, { "color": "#7000ff", "position": 100 } ],
  "angle": 135 }   // 0=bottom→top, 90=left→right, default 180
```

Dry-run with `wf.sh preview` to see stills + a `warnings[]` summary before
rendering. `wf.sh run` accepts a file path **or** inline JSON.

## Blocks (reusable motion-graphics scenes)

Blocks are pre-built, parameterized Remotion scene components (kinetic-text
intros, stat counters, animated charts, app showcases, lower-thirds, …) — the
motion-graphics building blocks that take output past a plain image slideshow.

- **Discover by purpose:** `bash scripts/wf.sh blocks --use endcard` filters by
  `tags` (purpose labels like `endcard`, `cta`, `captions`, `intro`, `chart`,
  `stat`). Plain `wf.sh blocks` lists all → `{ blocks: [{ blockId, displayName,
  description, tags, props, ports, previewUrl, renderable }] }`. Use only
  `renderable: true` blocks (others render a gray placeholder but still bill).
- **Inspect one:** `bash scripts/wf.sh block <blockId>` dumps that block's full
  prop JSON-schema + defaults + `$port:*` wireable inputs — read it before you
  set props.
- **Use:** drop a Block into a `video:remotion` node's scene graph as a scene:
  `{ "type": "block", "blockId": "<id>", "props": { … } }`. Fill `props` per the
  Block's schema. Wire upstream nodes (image/video/audio/text) into the Block's
  `ports` via edges when it has them.
- Prefer a Block over hand-built text/image scenes when one matches the intent —
  it looks far more "produced". See `references/blocks.md`.

**Blocks for ads** — the high-leverage ones (confirm with `--use`, IDs are
per-deploy so look them up by tag, not by hardcoding):

| Need | `--use` tag | What it is |
|------|-------------|------------|
| End card / CTA | `endcard`, `cta` | App Store / download card with icon, rating, badge |
| Karaoke captions | `captions` | TikTok-style word-by-word caption layer |
| Title / hook open | `intro`, `title` | Kinetic typography intro |
| Stat / number flex | `stat`, `kpi` | Animated counter / KPI callout |
| Data | `chart` | Animated bar charts (incl. 3D) |

## Clean layout (automatic)

Programmatically-authored workflows have no rendered DOM, so hand-picked
`x`/`y` coordinates overlap badly — a node holding a long system prompt, or
an image node with a result panel, is far taller than an "average" node, so
fixed row/column spacing collides.

`wf.sh create` fixes this automatically by running `scripts/layout.py`
first: it estimates each node's rendered size from its content (port count,
inline text length, node family) and runs a layered left-to-right DAG layout
(column = longest path from an input; nodes stacked by real estimated
height; sticky notes parked above their section). No browser, no codebase
access — pure computation, so it works for every workflow.

- It's automatic on `create` AND `update`. Opt out with `WF_SKIP_LAYOUT=1`.
- Re-space an existing JSON without creating: `bash scripts/wf.sh layout wf.json out.json`.
- Sanity-check overlaps: `python3 scripts/layout.py --check wf.json`.
- Set positions to anything when authoring — they're recomputed. Just keep
  edges correct; layout reads flow order from them.
- The estimator is heuristic (no browser, works anywhere). For a
  **pixel-perfect** layout, pass real measured sizes. In a logged-in editor
  tab, fit-view, then run in the console:
  `copy(JSON.stringify(Object.fromEntries([...document.querySelectorAll('.react-flow__node')].map(n=>[n.getAttribute('data-id'),{width:n.offsetWidth,height:n.offsetHeight}]))))`
  — save the clipboard to `dims.json`, then
  `python3 scripts/layout.py wf.json out.json --dims=dims.json` (real sizes +
  tighter gaps + vertical centering). This is the reliable fix when the
  estimate is off (e.g. a node with a big cached result panel, or the editor
  caps a long text field shorter than estimated).

## Reference files

Read these on demand when composing workflows:

- `references/workflow-schema.md` — node + edge JSON shape, input ports,
  common patterns
- `references/api.md` — full REST API surface with curl examples
- `references/remotion-templates.md` — how to construct a `video:remotion`
  node from a template spec
- `references/blocks.md` — discover + compose motion-graphics Blocks
  (`wf.sh blocks`, the `{type:'block',...}` scene shape)
- `references/diagnostics.md` — the `diagnostics` feedback protocol: codes,
  severity, and the read→fix→retry self-correction loop
- `references/captions.md` — author / correct / fully restyle captions from the
  `captionTrack` schema (text, timing, stroke, glow, font, color — no code)
- `references/director.md` — the **director** layer: a paragraph of direction →
  shots + beats JSON → compiled onto the scene graph (camera, SFX timing,
  caption punches, overlay timing). The highest-level way to author a video.
- `references/compositor.md` — the `compv3` compositor node (image + text/scrim
  layers) and the LLM→split→nano_banana→compositor "meme/carousel factory" pattern
- `examples/text-to-image.json` — simplest case (Text Input → FAL image gen)
- `examples/text-to-video.json` — text prompt → image → Kling video
- `examples/remotion-compose.json` — full pipeline ending in a Remotion
  rendered MP4
- `examples/ad-ugc.json` — **the canonical UGC ad**: prompt → nano-banana →
  Kling i2v → `video:remotion` reel, with ElevenLabs VO + Whisper karaoke
  captions wired into the `audio`/`captions` ports and an endcard block. Copy
  this to author a full ad; swap the endcard via `wf.sh blocks --use endcard`.

## Triggering this skill

Use when the user asks to:

- "Build me a Wireflow workflow that…"
- "Run my Wireflow workflow…"
- "Generate a [video/image/audio] via Wireflow"
- "Make a TikTok / reel / short using a Wireflow Remotion template"
- "Automate [creative pipeline] on Wireflow"

Do **not** trigger for:

- Editing the Wireflow codebase itself (that's direct repo work in the
  wireflow project)
- Unrelated AI image/video requests that don't mention Wireflow or its
  concepts (templates, compose nodes, workflows)

## What you can't do via this skill

- **Ship new Remotion compositions.** Compositions are React code that
  lives in the Wireflow repo and requires a Lambda bundle redeploy. The
  skill only *configures* existing compositions via `defaultProps` and
  input ports. If the user needs a genuinely new visual type, tell them
  to ask the Wireflow team to author it (or vibe-code it themselves in
  the wireflow repo — an auto-deploy GitHub Action ships it ~2 min after
  merge).
- **List all FAL models.** The registry is ~200+ models and lives in the
  repo. If the user needs a specific model, call
  `POST /workflows/generate/stream` with a prompt describing what they
  want — Wireflow's generator picks the right model automatically.
- **Edit the prompt of a running execution.** Workflow executions
  snapshot their inputs at start time. To re-run with a different prompt,
  call `/workflows/<id>/run` again with new inputs.

## Cost & credit awareness

Every run costs credits against the user's Wireflow account. Common costs
per run (approximate):

- Simple text→image: ~5-20 credits
- Text→video (Kling 1.6): ~300-600 credits
- Full Remotion compose with 5 shots + audio: ~1000-2000 credits

Before running expensive workflows (Kling, Veo, long Remotion renders),
confirm with the user. Use `bash scripts/wf.sh credits` to check their
balance first if the run is large.
