# Open Flow — Wireflow launch film

The latest example recreates the supplied VEED reference's editorial motion language
for Wireflow: white canvas, oversized sans/italic type, rounded creator cards,
a fan of alternatives, kinetic captions, a moving gallery, and an indigo end card.
It uses Wireflow's own existing landing-page demo footage. It includes **no VEED
footage, music, logos, or source code**.

## Reproduce the Wireflow film

```bash
cd examples/open-flow-launch
npm ci
npm run film:stills
npm run film:render
```

Requires Node 20+, FFmpeg and a compatible Chromium (see platform requirements below).
`film:assets` downloads the eight explicitly listed public videos in
`film-assets.json` into ignored `public/wireflow/`. If the CDN blocks a scripted
download, save those exact URLs from your browser into that folder and rerun.
Downloads and renders make no generation API calls and spend no Wireflow credits.
Missing clips fail the render; no placeholder is substituted.

| Time | Beat |
| --- | --- |
| 0–3 s | Brand brief and prompt |
| 3–6 s | Original creator becomes a new creator |
| 6–9 s | Original, outfit and product variations |
| 9–11.5 s | Frame-driven kinetic captions |
| 11.5–15 s | Five moving creative cards |
| 15–18 s | Wireflow / Open Flow end card |

`WireflowFilm.tsx` is the editable composition. `FilmRoot.tsx` registers it;
`render-film.mjs` uses Remotion's native renderer and `OffthreadVideo` for reliable
video frames. The local renderer falls back to a loopback-only server when its
container cannot enumerate network interfaces. Typography is embedded at render time.
The original score is shared with the first concept below.

Outputs:

- `out/Wireflow-Launch-1080p.mp4`: 1920×1080 master, 30 fps, H.264/AAC, 18 seconds.
- `out/Wireflow-Launch-Phone.mp4`: 1280×720, H.264 Main 3.1/AAC, optimized for download
  and progressive playback using fast-start MP4 metadata.

The prompt card is a motion-design illustration, not a screen recording of an
agent completing the workflow. Existing footage was reused for this local render;
this does **not** demonstrate fresh generation from a website and brand kit.
A successful live Wireflow run remains a separate acceptance requirement.

```bash
npm run film:prepare:block
```

This writes `out/wireflow-film-block.json`, a self-contained Block import candidate
with text props, font data and public media references. Import validation, cloud
media access, font/audio parity and the finished editable board are unverified.
The Block is silent; attach `out/original-score.wav` separately in the board.
See the production verification steps below. Do not present this local render as
an authenticated platform run or as a fresh generation benchmark.

The repository's MIT license covers the new composition code and score. The linked
Wireflow marketing clips retain their existing rights and are not relicensed here.
For another brand, substitute approved footage. Dependency and font licenses remain
in force.

---

## Earlier procedural product concept

An 18-second launch-film concept: **Make it move → One idea → Every angle →
Make it yours → Open Flow.** Dark backgrounds, Wireflow's indigo/teal palette,
editorial type, a procedural product illustration, and an original electronic score.

This is a **local design preview**, not a verified end-to-end Wireflow run. `form.`
is an original illustrative brand, not a client or a performance case study.
No VEED footage, renderer, code, or recipes are included.

## Reproduce the preview

Requirements: Node 20+, FFmpeg on `PATH`, and a supported Chromium browser.
Linux x64 uses the browser bundled with the pinned npm dependency. On another
platform, set `REMOTION_BROWSER_EXECUTABLE` to an existing compatible executable.

```bash
cd examples/open-flow-launch
npm ci
npm run stills
npm run render
```

The finished file is `out/open-flow-launch.mp4`: 1920×1080, 30 fps, 18 seconds,
H.264/AAC. The local renderer seeks a Remotion Player to each exact frame and
encodes screenshots with FFmpeg. Source and frame timing live in `Launch.tsx`;
the score is `score.mjs`.
Dependencies, extracted browser files, and outputs stay inside this example and
are ignored by git. Installing the existing Wireflow skill does not install them.

## Prepare for Wireflow

```bash
npm run prepare:block
```

This writes `out/wireflow-block.json`, containing source and a Zod module with
embedded font defaults, for the inspected `POST /api/v1/blocks` contract. It
**does not make a network request, create a block, or spend credits**.

With an authenticated Wireflow session, the remaining verification is:

1. Read current guidelines and schemas. Create a new draft board and use the
   API's real `video:remotion` node shape.
2. Submit the block candidate with `workflows:write` access, scoped to the new
   board using `workflowId`. Inspect the returned errors/warnings and require
   `renderable: true`; only use the returned `blockId`.
3. Add a block scene lasting 540 frames in a 1920×1080, 30 fps scene graph.
   Import the original score onto an audio node and wire it to the composition;
   the Block itself is silent. Use the catalog's current audio handles.
4. Preview representative frames. Compare typography, timing, and layout with
   the local preview. Read the cost estimate and obtain any needed spend
   authorization before a full run.
5. Inspect the finished video, then return its output URL and editable board.

The source contains no filesystem reads, `staticFile`, wall-clock animation, or
relative imports. Fonts load before a frame is accepted. The `beats` export
provides editor chapters. Cloud font handling, block bundling, board editability,
audio wiring, cost, and full rendering remain **unverified** until that run.

## Compatibility

This example is opt-in. The repository name, root `name: wireflow` skill, existing
installation command, scripts, API behavior, and current examples are retained.
There is no rename, automatic migration, production deployment, or new MCP server.

## Credits and licenses

New example source, vector artwork, and procedural score follow the repository's
MIT license. Inter and Instrument Serif come from pinned Fontsource packages and
retain their SIL Open Font Licenses (see the packages' `LICENSE` files). Remotion
and Chromium retain their own dependency licenses. Existing Wireflow colors were
read from its landing-page design system. No outside media is required.
