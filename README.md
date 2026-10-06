# Wireflow Skill for Claude

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Build and run [Wireflow](https://wireflow.ai) AI workflows by talking to
Claude. Install it once, then in any project on any machine, ask Claude
to create image, video, and audio pipelines on your Wireflow account.

Full docs, install guide, and examples: **<https://wireflow.ai/skill>**

## What this is

A Claude Code skill: a small bundle of instructions, reference docs, and
helper scripts that teach any Claude instance how to use the Wireflow
REST API on your behalf. No Wireflow codebase access required.

This repo is also a Claude plugin. The plugin ships the same skill plus
Wireflow's hosted MCP server, so Claude can call Wireflow tools directly
once you sign in.

## Install as a Claude plugin

From your shell:

```bash
claude plugin marketplace add wireflowINC/wireflow-skill
claude plugin install wireflow@wireflow
```

Or inside a Claude Code session:

```text
/plugin marketplace add wireflowINC/wireflow-skill
/plugin install wireflow@wireflow
```

In a session, `/plugin install` opens the plugin's page; choose Install
there, then run `/reload-plugins` or start a new session.

What you get:

- **The `wireflow` skill**, as `/wireflow:wireflow`. Claude also loads it
  on its own when you mention Wireflow or ask it to build or run a
  workflow.
- **The Wireflow MCP server** at `https://www.wireflow.ai/api/mcp`, shown
  in `/mcp` as `plugin:wireflow:wireflow`. Its tools let Claude find your
  workflows and templates, run them, and check results and credits.

Auth:

- **MCP tools use OAuth.** Nothing to paste. Run `/mcp`, pick
  `plugin:wireflow:wireflow`, and approve access in the browser window
  that opens. Claude Code stores and refreshes the token.
- **The skill's REST scripts use an API key** in `WIREFLOW_API_KEY`. See
  [Setup](#setup).

To get a newer version later, run
`claude plugin update wireflow@wireflow`.

## Install the skill only (git clone)

```bash
git clone https://github.com/wireflowINC/wireflow-skill ~/.claude/skills/wireflow
```

Claude Code automatically picks up any skill in `~/.claude/skills/`. New
Claude sessions will see the `wireflow` skill in their available-skills
list and auto-trigger on keywords like "wireflow", "build a workflow",
"run a workflow", or "remotion template".

Recent Claude Code versions also load this folder as a plugin
(`wireflow@skills-dir`) because it contains `.claude-plugin/plugin.json`.
The skill keeps its `/wireflow` name and you get the MCP server too.
Pick one install method, not both.

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

- `SKILL.md`: skill manifest + core loop + trigger words
- `references/api.md`: full REST API reference with curl examples
- `references/workflow-schema.md`: node + edge JSON shape, common
  patterns, rules that bite
- `references/remotion-templates.md`: how to construct `compose:remotion`
  nodes from template specs
- `scripts/wf.sh`: single dispatcher for common API operations
  (templates, create, run, poll, list, duplicate, patch-node, credits).
  `patch-node <id> <nodeId> '{"config":{"prompt":"new text"}}'` changes one
  node's config/label/position without round-tripping the whole graph. Its
  `check` gate
  (and the gate inside `create`/`update`/`organize`) graph-lints the workflow
  even without the repo, via the server's `/workflows/lint` endpoint, so the
  "no codebase access required" promise holds.
- `examples/`: working workflow JSONs (text→image, text→video,
  image + audio → Remotion render)
- `.claude-plugin/plugin.json`: the plugin manifest
- `.claude-plugin/marketplace.json`: the one-plugin marketplace that
  `claude plugin marketplace add` reads
- `.mcp.json`: the remote Wireflow MCP server the plugin connects to

## What it sends and where

The plugin only sends your data to Wireflow.

- The MCP server is Wireflow's hosted endpoint,
  `https://www.wireflow.ai/api/mcp`. You approve access on Wireflow's
  consent screen and can revoke it from your Wireflow settings.
- `scripts/wf.sh` calls the Wireflow REST API at
  `https://www.wireflow.ai/api/v1` with your `WIREFLOW_API_KEY`. Its
  `upload` verb sends the file or URL you give it to Wireflow, which hosts
  it on `cdn.wireflow.ai`. Its `download` verb saves a result file to
  disk: Wireflow result URLs go through Wireflow's download proxy, and any
  other URL you pass is fetched straight from its host.
- The Python helpers in `scripts/` only rearrange workflow JSON on your
  machine. They make no network calls.

Runs spend credits from your Wireflow account, the same as in the web app.

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

MIT. See [LICENSE](./LICENSE).
