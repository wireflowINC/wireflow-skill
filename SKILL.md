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
argument-hint: "[templates | blocks | nodes | check <json> | run <id> | generate \"<prompt>\"]"
license: MIT
allowed-tools: Read, Bash, Write, WebFetch
metadata:
  category: creative-automation
  version: "0.7.1"
---

# Wireflow Skill

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
5. **Run** — `bash scripts/wf.sh run <id> '{"inputs": {"<nodeId>": "..."}}'`
6. **Poll** — `bash scripts/wf.sh poll <executionId>` until `status:
   COMPLETED`
7. **Return** — hand the user the workflow URL (so they can inspect/remix
   in the visual editor) and the final output URL (image, MP4, MP3)

## Blocks (reusable motion-graphics scenes)

Blocks are pre-built, parameterized Remotion scene components (kinetic-text
intros, stat counters, animated charts, app showcases, lower-thirds, …) — the
motion-graphics building blocks that take output past a plain image slideshow.

- **Discover:** `bash scripts/wf.sh blocks` → `{ blocks: [{ blockId,
  displayName, description, props, ports, previewUrl }] }`. `props` is the JSON
  Schema of configurable fields; `ports` are wireable inputs; `previewUrl` is a
  rendered preview (may be null).
- **Use:** drop a Block into a `video:remotion` node's scene graph as a scene:
  `{ "type": "block", "blockId": "<id>", "props": { … } }`. Fill `props` per the
  Block's schema. Wire upstream nodes (image/video/audio/text) into the Block's
  `ports` via edges when it has them.
- Prefer a Block over hand-built text/image scenes when one matches the intent —
  it looks far more "produced". See `references/blocks.md`.

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

- It's automatic on `create`. Opt out with `WF_SKIP_LAYOUT=1`.
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
- `references/compositor.md` — the `compv3` compositor node (image + text/scrim
  layers) and the LLM→split→nano_banana→compositor "meme/carousel factory" pattern
- `examples/text-to-image.json` — simplest case (Text Input → FAL image gen)
- `examples/text-to-video.json` — text prompt → image → Kling video
- `examples/remotion-compose.json` — full pipeline ending in a Remotion
  rendered MP4

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
