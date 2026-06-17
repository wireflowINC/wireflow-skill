# Captions — author, correct, and fully restyle (no code)

Captions live on the `video:remotion` node's SceneGraph as **`captionTrack`**.
Everything below is set in JSON via `wf.sh update` / `wf.sh run-node` — you never
touch component code to restyle. `preset` = defaults; any field you set overrides
it on top.

## Get captions on the video

Either **wire** a transcript into the node's `captions` port (a Whisper /
Speech-to-Text node) — the render mirrors it into `captionTrack` automatically —
or **author** `captionTrack.raw` directly:

```jsonc
"captionTrack": {
  "raw": [ { "word": "download", "start": 0.0, "end": 0.3 }, … ]  // Whisper word_timestamps (seconds)
}
```

## Edit the text (fix a brand name, change a word)

- **Fix a mis-transcription durably** (survives the port re-filling the track):
  ```jsonc
  "captionTrack": { "raw": "{{captions}}", "replace": [ { "from": "Risley", "to": "Rizzly" } ] }
  ```
  Whole-word, case-insensitive (`"matchCase": true` to force case). Keep the port wired.
- **Edit any word / timing directly**: edit the `raw` array — change `word`,
  `start`, `end`, split or remove entries. Set `"editedByUser": true` so a wired
  port never overwrites your manual edits.

## Style — every knob, all overridable

```jsonc
"captionTrack": {
  "raw": "{{captions}}",
  "style": "tiktok-kinetic",      // base preset: tiktok-kinetic | minimal | subtitle
  "position": "bottom",           // top | center | bottom  (or topPercent for precise %)
  "topPercent": 78,               // exact vertical %, wins over position

  "activeColor": "#FF2E88",       // highlighted (current) word
  "inactiveColor": "#FFFFFF",     // other words in the line
  "strokeWidth": 2,               // px outline — applied to the ACTIVE word too
  "strokeColor": "rgba(0,0,0,0.8)", // outline color — what makes text readable on ANY bg
  "shadow": "0 2px 8px rgba(0,0,0,0.85)",  // CSS text-shadow string
  "glow": "auto",                 // "auto" (derive from activeColor) | a CSS shadow string | "none"

  "fontFamily": "space-grotesk",  // system | inter | roboto | space-grotesk, OR any CSS font-family
  "fontWeight": 800,              // 400–900
  "fontSizePx": 64,               // absolute px (or use fontScale for relative)
  "fontScale": 1,                 // multiplier on the preset size (ignored if fontSizePx set)
  "letterSpacing": -0.5,          // px (negative tightens)
  "textTransform": "uppercase",   // none | uppercase | lowercase | capitalize
  "chunkSize": 3,                 // words shown on screen at once

  "offsetFrames": 0               // nudge sync (+ delays, − advances)
}
```

### Legibility (the #1 caption problem)
Text washing out on a bright background (a screen recording) is a **stroke**
problem, not a color problem — no fill color reads on both light and dark. Set
**`strokeWidth` + `strokeColor`** (a dark outline); it's applied to the active
word too, so the highlight stays readable everywhere. `paintOrder` keeps the fill
color on top of the stroke.

### Notes
- Unset fields fall back to the chosen `style` preset — start from a preset, override what you need.
- A non-hex `activeColor` with `glow:"auto"` falls back to the preset glow (a non-hex
  color can't take an alpha suffix); set `glow` explicitly to a CSS string if you
  want a custom glow with a named/rgb color.
- **Always `wf.sh preview` and look at the sampled frames before a paid/Meta render** —
  confirm contrast and the brand spelling.
