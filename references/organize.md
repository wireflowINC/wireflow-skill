# Compose workflows like a codebase

A node graph is a program. A flat 50-node graph reads like a 500-line function:
it runs, but nobody can see its structure, reuse a piece, or change one part
without fear. The same refactors that make code legible make graphs legible.

Map the concepts directly — every primitive here already exists in Wireflow:

| Codebase concept        | Wireflow primitive                        | How                                            |
| ----------------------- | ----------------------------------------- | ---------------------------------------------- |
| Constant / DRY string   | one `input:text` node, fanned out         | wire its `out-prompt` into many consumers      |
| Composed string         | `utility:prompt_concat`                   | join shared fragments → one prompt             |
| Function / module       | `custom_group` node (labelled box)        | `data.childNodeIds` = members; excluded from execution |
| Section comment         | `utility:sticky_note`                     | a README note or a band label                  |
| Imported package        | `blueprint:invoke`                        | call a published Blueprint as one collapsed node |
| Clean formatting        | swimlane auto-layout                      | `wf.sh organize` / `organize.py`               |

## The three moves

### 1. DRY — hoist repeated text into shared constants

If the same string (a style guide, a negative prompt, a brand voice) is pasted
into 2+ node configs, it is a magic-string duplicated across files. Hoist it:

- Create ONE `input:text` node holding the value.
- Wire its output into every consumer's matching input port (`in-prompt`,
  `in-system_prompt`, `in-negative_prompt`, …). One output fans out to many —
  edge resolution handles this natively.
- Build composite prompts from fragments with `utility:prompt_concat`
  (`prompt1` + `prompt2` → `prompt`), so a shared "style" fragment and a
  per-node "task" fragment combine without copy-paste.

A wired value beats an inline one: it's visible on the canvas, editable in one
place, diffable across versions, and reusable. Only hardcode into `config` when
a value is truly fixed and you want it hidden.

### 2. MODULES — wrap related nodes in labelled groups

Group nodes by **responsibility**, the way you'd split a file into functions.
Each module becomes a `custom_group` box with a name and a color. A reader sees
`① Source footage  ② Hero  ③ B-roll  ④ Endcard  ⑤ Final assembly` instead of
node soup. Good module boundaries:

- A **stage** that produces one asset (generate → process → animate a clip).
- A **shared-inputs** module (identity refs, brand kit) used across the graph.
- A **constants** module (the hoisted `input:text` nodes) — like a config file.
- The **sink** (the final `video:remotion` / compositor) as its own module.

A node belongs to exactly one module. Put nodes shared across several modules
(e.g. a negative prompt used by every clip) into a small "Shared" module rather
than picking one arbitrarily.

### 3. LAYOUT — swimlanes, not soup

`organize` lays the graph out as **swimlanes**: X = dataflow column (left→right,
so edges still read in flow order), Y = module band (each module owns a disjoint
horizontal stripe, so boxes never overlap). This is the architecture-diagram
look: legible at a glance, every module a clean lane.

## Using `wf.sh organize`

```bash
wf.sh organize <id>                  # heuristic plan → apply (PUT)
wf.sh organize <id> --dump-plan      # print the proposed plan, change nothing
wf.sh organize <id> --plan plan.json # apply a hand-authored (semantic) plan
wf.sh organize <id> --save out.json  # also write the organized graph locally
```

It is **non-destructive**: it only adds `custom_group` boxes + hoisted
`input:text` constants and repositions nodes. No node, edge, config, or output
is deleted. Re-running is idempotent (it strips its own prior `group-org-*`
boxes first).

### Hybrid flow (recommended for real graphs)

The built-in heuristic clusters by connected-component + fan-in and names
modules by dominant node family — fine as a floor, but it can't name a module
"Hero — face + voice". So:

1. `wf.sh organize <id> --dump-plan > plan.json`
2. Edit `plan.json`: merge/split `modules`, rename them, pick boundaries that
   match the *intent* of the graph. Add `constants` for text you want hoisted.
3. `wf.sh organize <id> --plan plan.json`

You (the model) are the semantic half: you can see that seven generate→animate
chains are all "b-roll poses" and that two of them are really "detail shots".
The mechanics (boxes, wiring, swimlane layout) are deterministic.

### Exact spacing with measured node sizes

By default `organize` *estimates* node heights — but a node with a media preview
or a cached result panel is far taller than any estimate (e.g. an `input:image`
with stacked uploads can be 1000px+), so estimated swimlanes collide. For exact,
overlap-free spacing, pass real measured sizes:

```bash
wf.sh organize <id> --plan plan.json --dims dims.json
```

Get `dims.json` from a logged-in editor tab (zoom all the way out so every node
renders, then in the console):

```js
copy(JSON.stringify(Object.fromEntries(
  [...document.querySelectorAll('.react-flow__node')]
    .filter(n => !n.className.includes('custom_group'))
    .map(n => [n.getAttribute('data-id'), {width:n.offsetWidth, height:n.offsetHeight}]))))
```

Same `--dims=dims.json` flag works on `layout.py` directly, and on `--check` to
validate overlaps against real sizes (the only check that matters).

### Plan shape

```json
{
  "modules": [
    { "name": "① Hero — face + voice", "color": "#2D6B4F",
      "nodes": ["hero_gen", "hero_i2v", "hero_prompt", "clone_vo", "vo_whisper"] }
  ],
  "constants": [
    { "name": "Brand voice", "text": "calm, knowing, slightly menacing …",
      "targets": [ { "node": "llm_a", "field": "system_prompt" },
                   { "node": "llm_b", "field": "system_prompt" } ] }
  ]
}
```

`color` is a hex (canvas palette: `#2D6B4F #2D4F6B #6B2D6B #6B5A2D #2D6B6B
#6B2D2D`). A constant is only wired when the target node actually exposes a
matching input port, so the edge always resolves; the inline literal is cleared
only once the wire exists.

## When to organize

- **Author it organized from the start.** When you hand-author a workflow, emit
  `custom_group` modules and shared `input:text` constants directly — don't ship
  soup and rely on a cleanup pass.
- **Run `organize` on anything inherited or grown.** Graphs accrete nodes; a
  periodic `organize` is `gofmt` for the canvas.
- Skip it for tiny graphs (< ~8 nodes) — a single lane is already legible.
