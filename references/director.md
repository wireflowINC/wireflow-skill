# Director — direct a video from a paragraph, not keyframes

The **director** is a compact JSON you put on a `video:remotion` node's
SceneGraph (`sceneGraph.director`). An LLM authors it from a paragraph of
direction; a pure server-side step **compiles it onto scene-graph primitives**
at render time (camera moves, transitions, where SFX land, which word punches,
when an overlay appears) and then removes it. You direct **shots** and **beats**
— you never hand-author keyframes, React, or per-frame values.

Composition stays in the scene graph (bespoke banners, kinetic captions, endcard
blocks). The director only *directs*.

## Schema

```jsonc
"director": {
  "shots": [
    { "ref": 0, "camera": "push-in", "intensity": 0.08, "ease": "in-out", "transitionIn": "cut" },
    { "ref": 1, "camera": "static", "pace": "tight" },
    { "ref": 2, "camera": "push-in", "intensity": 0.05 },
    { "ref": 3, "camera": "static" }
  ],
  "beats": [
    { "at": "scene:2.start",   "sfx": "audio_2" },
    { "at": "scene:3.start",   "sfx": "audio_3" },
    { "at": "caption:first",   "emphasis": "punch" },
    { "at": "scene:1.start+12","punch": 0.05 },
    { "at": "scene:2.start+8", "overlay": "notification" }
  ],
  "pacing": "high-energy"
}
```

- **shots[].ref** — the scene index this shot directs.
- **camera** — `static` | `push-in` | `pull-out` | `pan-left` | `pan-right`.
- **intensity** — fraction of the move (`0.08` = an 8% push). Default ~0.15.
- **transitionIn** — `cut` | `fade` | `slide` | `zoom` (the transition INTO the scene).
- **pace** — `tight` is advisory only; it never auto-trims (that would desync VO/captions).
- **beats[].at** — when it fires (see *Beat refs* below).
- **sfx** — a wired audio port id (`audio_2`, `audio_3`, …) to place at this beat.
- **emphasis** — punch the caption word at this beat (any string, e.g. `"punch"`).
- **punch** — a transient SCALE pop on the scene at this beat (a block-slam hitting an audio impact). The number is the scale delta (`0.05` = a 5% pop). Distinct from the slow eased `kenBurns` — this is a snappy one-frame hit.
- **overlay** — re-time the scene-graph overlay whose `name` matches.

## Compile mapping (director → primitive)

| director | scene-graph primitive |
|----------|-----------------------|
| `camera: "push-in"` + `intensity` | `scene.kenBurns = "zoom-in"`, `kenBurnsAmount = 1 + intensity` (eased) |
| `camera: "pull-out" / "pan-*"` | the matching `kenBurns` effect |
| `transitionIn` | `scene.transition` |
| `sfx: "audio_2"` at a beat | `audioTrackConfig["audio_2"] = { attachTo, startFrame }` resolved from `at` (the multi-audio mirror then places it) |
| `emphasis` at a beat | `word.emphasis = true` on the caption word → renders bigger (a punch) |
| `punch: 0.05` at a beat | `scene.punch = { at, amount }` → a transient scale pop on that scene's frame (composes on top of kenBurns) |
| `overlay: "notification"` | sets that overlay's `startFrame` (bespoke overlays stay author-controlled — the director only TIMES them) |

## Beat refs (`at`)

- `scene:<i>.start` / `scene:<i>.end`, optionally `±<frames>` (e.g. `scene:2.start+8`).
- `caption:<word>` — the frame of that word, from the wired `word_timestamps`
  (so *"punch in on 'first'"* just works).
- `frame:<n>` / `time:<sec>`.

A scene-relative SFX beat scene-attaches the track; a `caption:`/`frame:`/`time:`
SFX beat pins it to the comp at the absolute frame.

## Worked example

Direction: *"slow push-in on the hook, hold the proof, hit the notification with
a ding, punch 'first', reveal the endcard with a chime."*

1. Wire: 2 ElevenLabs SFX nodes → the reel's `audio_2` (ding) + `audio_3`
   (chime); a Whisper node → `captions`.
2. Author the director on the sceneGraph:
   ```jsonc
   "director": {
     "shots": [
       { "ref": 0, "camera": "push-in", "intensity": 0.08 },  // hook
       { "ref": 1, "camera": "static" },                       // hold the proof
       { "ref": 3, "camera": "push-in", "intensity": 0.05 }    // endcard reveal
     ],
     "beats": [
       { "at": "scene:2.start", "sfx": "audio_2" },            // notification ding
       { "at": "scene:3.start", "sfx": "audio_3" },            // endcard chime
       { "at": "caption:first", "emphasis": "punch" }          // punch the word
     ]
   }
   ```
3. `wf.sh run-node <wf> <reelNodeId>` — the hook pushes in, "first" punches, the
   ding and chime land on their beats. **No hand-edited scene graph.**

## Notes
- The director runs BEFORE the audio/caption mirror, so its `audioTrackConfig`
  feeds the multi-audio piping and its emphasis flows into the resolved captions.
- Bad shot refs, unresolved beats (e.g. a caption word not in the transcript),
  and `tight` pace hints come back in the run's `diagnostics` (codes
  `director.*`) — read them and fix, nothing fails silently.
- Depends on: kenBurns (image+video), multi-audio piping (`audioTrackConfig`),
  caption emphasis, and the wired `word_timestamps` — all live.
```
