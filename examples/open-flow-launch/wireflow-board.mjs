// Recreate the Open Flow launch film as an editable Wireflow board and, with
// --render, an MP4 rendered by the platform. Reproduces board
// cmu2j0rp1000hle046wpj79xs (2026-09-15) from this directory alone.
//
//   WIREFLOW_API_KEY=wf_live_... node wireflow-board.mjs [--render]
//
// Needs an API key with workflows:read, workflows:write and (for --render)
// workflows:execute. The account pays no generation credits: every node on
// the board is an Import, a Text input or the Video Editor. --render spends
// one Remotion Lambda render (about 90 s, cents) on Wireflow's side.
//
// Steps, each one API call: upload the score, create the board, compile the
// Block, write the scene graph, arrange the board, then optionally run it and
// poll the execution until the film node reports its MP4.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const KEY = process.env.WIREFLOW_API_KEY;
if (!KEY) throw Error("Set WIREFLOW_API_KEY (workflows:read + workflows:write, + workflows:execute for --render)");
const BASE = (process.env.WIREFLOW_BASE_URL || "https://www.wireflow.ai/api/v1").replace(/\/$/, "");
const RENDER = process.argv.includes("--render");
const auth = { Authorization: `Bearer ${KEY}` };

async function api(method, route, body, init = {}) {
  const res = await fetch(`${BASE}${route}`, {
    method,
    headers: { ...auth, ...(body && !(body instanceof FormData) ? { "Content-Type": "application/json" } : {}), ...init.headers },
    body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw Error(`${method} ${route} → HTTP ${res.status}, non-JSON body: ${text.slice(0, 200)}`);
  }
  if (!res.ok) throw Error(`${method} ${route} → HTTP ${res.status}: ${JSON.stringify(json).slice(0, 400)}`);
  return json.data ?? json;
}

// 1. The score, generated locally by score.mjs (deterministic, no samples).
await import("./score.mjs");
const wav = await readFile(path.join(root, "out/original-score.wav"));
const form = new FormData();
form.append("file", new Blob([wav], { type: "audio/wav" }), "original-score.wav");
const scoreUrl = (await api("POST", "/media/upload", form)).url;
console.log("score", scoreUrl);

// 2. The board: one Import node per clip, one for the score, two Text nodes,
//    and the Video Editor with every port it will be wired to DECLARED.
const { CLIP_PORTS, block } = await import("./prepare-film-block.mjs");
const dims = (url) => (/-1080\.mp4$/.test(url) ? "1920x1080" : "720x1280");
const importNode = (id, label, url, inputType, mediaType, extra = {}) => ({
  id,
  type: "basedNode",
  position: { x: 0, y: 0 },
  data: {
    label,
    nodeType: "input:image",
    category: "input",
    inputType,
    config: { image: url, imageUrl: url, mediaType, ...extra },
  },
});
const textNode = (id, label, prompt) => ({
  id,
  type: "basedNode",
  position: { x: 0, y: 0 },
  data: { label, nodeType: "input:text", category: "input", config: { prompt } },
});
const nodes = [
  ...CLIP_PORTS.map((c) => importNode(c.id, c.label, c.url, "video", "VIDEO", { mediaDimensions: dims(c.url) })),
  importNode("score", "Original score", scoreUrl, "audio", "AUDIO"),
  textNode("headline", "Headline", "One take. Every version."),
  textNode("cta", "CTA", "wireflow.ai"),
  {
    id: "film",
    type: "basedNode",
    position: { x: 0, y: 0 },
    data: {
      label: "Open Flow launch film",
      nodeType: "video:remotion",
      category: "video",
      config: {},
      inputs: [
        ...CLIP_PORTS.map((c) => ({ id: c.id, type: "VIDEO", label: c.label, required: false })),
        { id: "audio", type: "AUDIO", label: "Audio", required: false },
        { id: "headline", type: "TEXT", label: "Headline", required: false },
        { id: "cta", type: "TEXT", label: "CTA", required: false },
      ],
      outputs: [
        { id: "video", type: "VIDEO", label: "Video" },
        { id: "thumbnail", type: "IMAGE", label: "Thumbnail" },
      ],
    },
  },
];
const edge = (source, sourceHandle, targetHandle) => ({ id: `e-${source}`, source, target: "film", sourceHandle, targetHandle });
const edges = [
  ...CLIP_PORTS.map((c) => edge(c.id, "out-media", `in-${c.id}`)),
  edge("score", "out-media", "in-audio"),
  edge("headline", "out-prompt", "in-headline"),
  edge("cta", "out-prompt", "in-cta"),
];
const boardBody = {
  name: "Open Flow launch film",
  description:
    "18s Wireflow launch film as a custom Block. Eight swappable clips, the original score, headline and CTA as text nodes. Source: wireflow-skill examples/open-flow-launch.",
  tags: ["open-flow", "launch-film"],
  isActive: true,
  nodes,
  edges,
};
const board = await api("POST", "/workflows", boardBody);
console.log("board", board.id);

// 3. The Block, compiled by Wireflow's bundler and scoped to this board.
// The bundler dedupes identical source across boards; stamp the board id so
// this board gets its own Block (deleting the board deletes it).
const compiled = await api("POST", "/blocks", {
  ...block,
  source: `// Wireflow board ${board.id}\n${block.source}`,
  workflowId: board.id,
});
if (!compiled.renderable) throw Error(`Block ${compiled.blockId} compiled without a Lambda bundle`);
console.log("block", compiled.blockId, compiled.warnings?.length ? compiled.warnings : "");

// 4. The scene graph: one block scene, every prop a {{port}} token.
const props = Object.fromEntries([...CLIP_PORTS.map((c) => c.id), "headline", "cta"].map((id) => [id, `{{${id}}}`]));
const film = nodes.find((n) => n.id === "film");
film.data.config = {
  mode: "sceneGraph",
  props: {
    sceneGraph: {
      fps: 30,
      width: 1920,
      height: 1080,
      scenes: [
        {
          type: "block",
          blockId: compiled.blockId,
          bundledUrl: compiled.bundledUrl,
          durationInFrames: 540,
          props,
          blockInputMappings: compiled.ports,
        },
      ],
    },
    blockInputMappings: compiled.ports,
  },
};
await api("PUT", `/workflows/${board.id}`, { ...boardBody, nodes, edges, baseUpdatedAt: board.updatedAt });

// 5. Arrange from measured card sizes (positions only).
const layout = await api("POST", `/workflows/${board.id}/layout`, {});
console.log("layout moved", layout.moved);
const site = BASE.replace(/\/api\/v1$/, "");
console.log(`open ${site}/flow/${board.id}`);

if (!RENDER) {
  console.log("Add --render to run the board and get the platform MP4.");
  process.exit(0);
}

// 6. Run it. Only the film node does work; the imports and text nodes are free.
const started = Date.now();
const run = await api("POST", `/workflows/${board.id}/run`, {});
console.log("execution", run.executionId);
for (;;) {
  await new Promise((r) => setTimeout(r, 6000));
  const poll = await api("GET", `/workflows/executions/${run.executionId}/poll`);
  const filmState = (poll.nodeStates || []).find((n) => n.nodeId === "film");
  if (poll.status === "FAILED" || filmState?.status === "FAILED")
    throw Error(`Render failed: ${filmState?.error || poll.error || "unknown"}`);
  if (poll.status === "COMPLETED" && filmState?.outputUrl) {
    console.log(`rendered in ${Math.round((Date.now() - started) / 1000)}s`);
    console.log("mp4", filmState.outputUrl);
    break;
  }
  process.stdout.write(".");
}
