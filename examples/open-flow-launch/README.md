# Open Flow launch film

An 18 second launch film built from 8 clips, a headline, a brand name and a
call to action. Wireflow renders it in the cloud. You get an MP4 and an
editable board.

## Run it

Node 20 or newer, no `npm install`:

```bash
export WIREFLOW_API_KEY="wf_live_..."   # free key: see below
node film.mjs --brand "Acme" --headline "Launch day. Every version." --cta "acme.com" --clips ./my-clips
```

From the repo root the same thing is `npm run film -- <options>`. Run
`node film.mjs --help` for every option. With no options you get the demo film.

The key comes from the
[Wireflow API keys page](https://www.wireflow.ai/settings?tab=api-keys&section=api-keys&utm_source=github&utm_medium=readme&utm_campaign=open-flow).
It needs `workflows:read`, `workflows:write`, `workflows:execute` and
`executions:read`. Read access is ticked for you, so tick the other two.

What you see:

```
Signed in to Wireflow as you@example.com (60 credits)
  uploading clip 1/4 1.mp4... done
  ...
Board ready: https://www.wireflow.ai/flow/<id>
Cost estimate: 0 credits. Rendering (about 2 to 4 minutes)...
.............

Done in 117s. Credits used: 0.
Your film: https://cdn.wireflow.ai/videos/remotion/<you>/<render>.mp4
Edit it:   https://www.wireflow.ai/flow/<id>
```

## What each clip does

| Time | Scene | Clips on screen |
| --- | --- | --- |
| 0 to 3 s | The brief: "Start with one idea." Your CTA shows in the prompt card. | none |
| 3 to 6 s | "Choose your creator." | 1, 2, 5 |
| 6 to 9 s | "Make it your own." | 1, 2, 3, 4 |
| 9 to 11.5 s | "Give every word a beat." Kinetic captions. | 1 |
| 11.5 to 15 s | Five moving cards with your headline. | 1, 5, 6, 7, 8 |
| 15 to 18 s | End card: your brand name and CTA button. | none |

Clips sit in tall rounded cards and are cropped to fill them, so phone video
works best. Each card shows a few seconds, so 3 to 15 second clips are plenty.
A longer clip is fine: the film stays 18 seconds. Give fewer than 8 clips and
they repeat in order. Files: mp4, mov, m4v or webm, up to 100MB each. You can
also pass links: `--clips https://example.com/a.mp4,https://example.com/b.mp4`.

## What `film.mjs` does

Each step is one call to the Wireflow API with your key:

1. `GET /me` to check the key and show your balance.
2. Uploads each clip to Wireflow's CDN (`POST /media/upload`, or a signed
   upload for files over 4MB).
3. `POST /workflows` creates the board: 8 Import nodes (clips), 1 Import node
   (music), 3 Text nodes (headline, CTA, brand) and a Video Editor node
   holding the film as one Block scene. Every clip and line is a port on that
   node, wired from its input node.
4. `POST /workflows/{id}/layout` lays the board out.
5. `POST /workflows/{id}/estimate` checks the run costs 0 credits. If it
   ever doesn't, the script stops before running anything.
6. `POST /workflows/{id}/execute` runs the film node, then it polls until the
   MP4 is ready (8 seconds between checks, 15 minute limit).

Free keys can make 10 API calls a minute. When the script hits that, it
waits and keeps going.

## The Block

`WireflowFilm.tsx` is a normal Remotion composition.
`prepare-film-block.mjs` turns it into a Wireflow Block: the 8 clips become
`$port:video` ports, headline, CTA and brand become `$port:text` ports, and
the two fonts in `fonts/` get embedded so the film looks the same in the
editor and in the cloud. `node prepare-film-block.mjs` writes the result to
`out/wireflow-film-block.json` so you can read it (no network calls).

Wireflow hosts one built copy of that Block. Its id is in
`hosted-block.json`, and every board `film.mjs` makes points at it. Uploading
new Block code to Wireflow is open to the Wireflow team only for now, so if
you change the TSX, render it on your own machine (below). Maintainers
refresh the hosted copy with `node film.mjs --publish-block --no-render`
and commit the new `hosted-block.json`.

## Render on your own machine

Needs FFmpeg and a Chromium browser. On Linux x64 the pinned
`@sparticuz/chromium` package is used; anywhere else set
`REMOTION_BROWSER_EXECUTABLE` (on a Mac, `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`).

```bash
npm ci
npm run film:stills    # 6 PNG frames in out/
npm run film:render    # out/Wireflow-Launch-1080p.mp4 and a smaller phone cut
```

`film-assets.mjs` downloads the 8 demo clips listed in `film-assets.json` into
`public/wireflow/` (ignored by git). `score.mjs` writes the original score,
made from code with no samples. Local renders make no Wireflow API calls and
use no credits.

## Rights

The composition code and the score are MIT, like the rest of the repo. Inter
and Instrument Serif are under the SIL Open Font License (see
`fonts/OFL-*.txt`). The demo clips are Wireflow marketing footage and are not
relicensed here; use your own clips for your own film.

## Want us to make it for you?

[Get a free media plan](https://www.wireflow.ai/startups?utm_source=github&utm_medium=readme&utm_campaign=open-flow)
and we'll make your launch video.
