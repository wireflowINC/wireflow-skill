# Wireflow Skill for Claude

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Build and run [Wireflow](https://wireflow.ai) AI workflows by talking to
Claude. Install this skill once, then in any project on any machine, ask
Claude to create image, video, and audio pipelines using your Wireflow
API key.

Full docs, install guide, and examples: **<https://wireflow.ai/skill>**

## What this is

A Claude Code skill — a small bundle of instructions, reference docs, and
helper scripts that teach any Claude instance how to use the Wireflow
REST API on your behalf. No Wireflow codebase access required.

## Install

```bash
git clone https://github.com/wireflowINC/wireflow-skill ~/.claude/skills/wireflow
```

Claude Code automatically picks up any skill in `~/.claude/skills/`. New
Claude sessions will see the `wireflow` skill in their available-skills
list and auto-trigger on keywords like "wireflow", "build a workflow",
"run a workflow", or "remotion template".

## Setup

1. Create a scoped API key at <https://www.wireflow.ai/settings?tab=api-keys&section=api-keys>
   with the scopes you need: `workflows:read`, `workflows:write`,
   `workflows:execute`.
2. Add the key to your shell profile:
   ```bash
   export WIREFLOW_API_KEY="wf_live_..."
   ```
3. Restart your terminal (or `source` the profile).

Key precedence is `WIREFLOW_API_KEY` env var > `--key <key>` flag > a `.env` in
the current directory. A key read from `./.env` prints a one-line notice so a
repo's own `.env` can't silently swap identities. For a one-off call:
`bash scripts/wf.sh --key wf_live_... <verb> ...`.

## Use

Open Claude in any directory and ask:

> Build me a Wireflow workflow that takes a product name, has Claude write
> a viral TikTok hook, then generates a 9:16 product photo with Nano Banana.

> Run my Wireflow workflow `<id>` with the prompt "a cow in a neon field"
> and download the result.

> Use the foodscan Remotion template to make a TikTok about a Caesar
> salad being 850 calories.

## What's in the bundle

- `SKILL.md` — skill manifest + core loop + trigger words
- `references/api.md` — full REST API reference with curl examples
- `references/workflow-schema.md` — node + edge JSON shape, common
  patterns, rules that bite
- `references/remotion-templates.md` — how to construct `compose:remotion`
  nodes from template specs
- `scripts/wf.sh` — single dispatcher for common API operations
  (templates, create, run, poll, list, duplicate, credits). Its `check` gate
  (and the gate inside `create`/`update`/`organize`) graph-lints the workflow
  even without the repo, via the server's `/workflows/lint` endpoint — so the
  "no codebase access required" promise holds.
- `examples/` — working workflow JSONs: text→image, text→video,
  image + audio → Remotion render

## What the skill can NOT do

- **Ship new Remotion compositions.** Those are React code in the
  Wireflow repo and require a Lambda bundle redeploy. The skill only
  *configures* existing compositions via their input ports and props.
  If you need a genuinely new visual type, ask the Wireflow team to
  author it.
- **Replace the visual editor.** Complex workflows are still easier to
  prototype in the visual editor first, then call via the skill once
  they're working.
- **Bypass credit costs.** Every run deducts credits from your Wireflow
  balance. The skill checks your balance before kicking off expensive
  video jobs (Kling, Veo, long Remotion renders).

## License

MIT — see [LICENSE](./LICENSE).
