# Open Flow — creative direction for Wireflow

Use this optional guide when the user asks for an Open Flow example, a branded
launch film, or art direction for a Wireflow composition. Existing workflow
commands, authentication, and ordinary skill behavior stay the same.

## Start from the intended output

Agree on the audience, message, duration, aspect ratio, and one action the viewer
should take. Use supplied brand assets and approved takes. Read Wireflow's live
agent guidelines through MCP `get_guidelines` or `GET /api/v1/agent-guidelines`
before creating a production workflow; do not duplicate that operating contract.

A launch film should demonstrate something visible. A paid-ad variation should
change an identifiable variable (hook, creator, framing, or end card). Do not
invent performance results or present an illustrative interface as a recording
of working software. Distinguish a design preview from a verified platform run.

## Direct the sequence

Write a short shot list before composing. Give each shot a purpose and enough
time to read. Choose a single palette, a small type hierarchy, and a recurring
visual device. Contrast a large, quiet hold with short, decisive movements.

Useful starting structure: introduce the idea, show it clearly, reveal meaningful
variations, then finish with a legible end card. Adapt this to the actual brief;
it is not a mandatory template.

Use reveal → settle → hold → exit timing. Stagger related objects so the eye has
an order to follow. Keep small labels secondary to the main message. Avoid using
constant movement to disguise weak content. Check the layout at phone size.

## Use Wireflow's existing machinery

Discover runnable templates and renderable motion blocks first. See
[blocks.md](blocks.md), [video-assembly.md](video-assembly.md), and
[director.md](director.md) for the existing composition controls. Read schemas
from the current catalog; do not guess node handles or invent block IDs.

For a new visual that the catalog cannot express, a self-contained Remotion Block
can be prepared as source plus a Zod `Schema` module for `POST /api/v1/blocks`.
Check the current endpoint contract and account access before submitting it.
Author from the frame number, load fonts deterministically, use supported root
imports, and export labeled `beats` for longer compositions. Keep content that
users should change exposed as props/ports. Shared templates should be forked
for an experiment rather than overwritten.

## Evaluate the result

Preview the entrance, readable hold, and exit of each important beat. Inspect the
finished motion as well as sampled stills: text bounds, timing, subject continuity,
seams, aspect ratio, and audio. Mechanical validation alone does not establish
visual quality. Quote actual estimates for paid execution and respect the user's
authorized budget. Resume an already charged job rather than purchasing it twice.

Hand back the final file and editable Wireflow board when the platform run is
verified. If authentication or rendering access is unavailable, prepare a clearly
labeled local design preview and import candidate, report the access limitation,
and keep the production step explicitly pending. Do not report a local render as
an end-to-end Wireflow result.

## First example

[Open Flow launch concept](../examples/open-flow-launch/README.md) contains the
18-second source, original procedural artwork and score, local rendering commands,
and a payload preparation command. It uses no generated-media API and makes no
advertising-performance claim. The production import is a separate verification
step; local rendering does not prove it works on Wireflow's renderer.
