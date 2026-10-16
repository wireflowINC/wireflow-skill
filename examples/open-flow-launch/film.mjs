#!/usr/bin/env node
// Open Flow: make an 18 second launch film from up to 8 clips and a headline,
// rendered in the cloud by Wireflow. One command, no npm install (Node 20+).
//
//   export WIREFLOW_API_KEY=wf_live_...
//   node film.mjs --brand "Acme" --headline "Ship your launch today." \
//     --cta "acme.com" --clips ./my-clips
//
// What it does, one API call per step: uploads your clips, creates an
// editable board in your Wireflow account (one Import node per clip, the
// score, three Text nodes and a Video Editor node holding the film), checks
// the cost estimate is 0 credits, runs the film node, waits, prints the MP4.
//
// Key scopes: workflows:read, workflows:write, workflows:execute,
// executions:read.
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const root = path.dirname(fileURLToPath(import.meta.url));
const SITE = "https://www.wireflow.ai";
const UTM = "utm_source=github&utm_medium=cli&utm_campaign=open-flow";
const KEYS_URL = `${SITE}/settings?tab=api-keys&section=api-keys&${UTM}`;
const OFFER_URL = `${SITE}/startups?${UTM}`;
const DEMO_SCORE =
  "https://cdn.wireflow.ai/uploads/api/22491/ddc3d4ed-bfed-4ae9-84f2-739dee3b27e5.wav";
const VIDEO_TYPES = {
  ".mp4": "video/mp4",
  ".mov": "video/quicktime",
  ".m4v": "video/x-m4v",
  ".webm": "video/webm",
};
const AUDIO_TYPES = { ".mp3": "audio/mpeg", ".wav": "audio/wav", ".m4a": "audio/mp4" };
const LIMITS = { headline: 45, cta: 30, brand: 24 };

const HELP = `Open Flow: an 18 second launch film from your clips, rendered by Wireflow.

  node film.mjs [options]          (or: npm run film -- [options])

  --clips <dir|list>   Folder of video clips, or a comma list of files/URLs.
                       Up to 8 are used in name order; fewer are repeated.
                       Leave it out to use the demo clips.
  --headline <text>    Closing line, up to ${LIMITS.headline} characters.
  --brand <text>       Name on the end card, up to ${LIMITS.brand} characters.
  --cta <text>         Button on the end card, e.g. your site, up to ${LIMITS.cta}.
  --music <file|url>   Your own soundtrack (mp3, wav, m4a). Default: the Open Flow score.
  --name <text>        Board name in your Wireflow account.
  --no-render          Build the board but do not render it.
  -h, --help           Show this help.

Needs WIREFLOW_API_KEY. Get a free key: ${KEYS_URL}`;

let args;
try {
  args = parseArgs({
    options: {
      clips: { type: "string" },
      headline: { type: "string", default: "One take. Every version." },
      brand: { type: "string", default: "Wireflow" },
      cta: { type: "string", default: "wireflow.ai" },
      music: { type: "string" },
      name: { type: "string" },
      "no-render": { type: "boolean", default: false },
      "publish-block": { type: "boolean", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
  }).values;
} catch (e) {
  fail(`${e.message}\n\n${HELP}`);
}
if (args.help) {
  console.log(HELP);
  process.exit(0);
}
for (const [k, max] of Object.entries(LIMITS)) {
  args[k] = args[k].trim();
  if (!args[k]) fail(`--${k} can't be empty.`);
  if (args[k].length > max) fail(`--${k} is ${args[k].length} characters; keep it to ${max}.`);
}

const KEY = process.env.WIREFLOW_API_KEY?.trim();
if (!KEY) fail(`Set WIREFLOW_API_KEY first. Get a free key here:\n  ${KEYS_URL}`);
const BASE = (process.env.WIREFLOW_BASE_URL || `${SITE}/api/v1`).replace(/\/$/, "");
const APP = BASE.replace(/\/api\/v1$/, "");
const cwd = process.env.INIT_CWD || process.cwd();

function fail(msg) {
  console.error(`\n${msg}`);
  process.exit(1);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// One API call. Free keys allow 10 requests a minute, so a 429 waits for the
// window to reset and tries again instead of failing the run.
// A connection that never opened is retried too (the request was never sent).
const CONNECT_ERRORS = /UND_ERR_CONNECT_TIMEOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|ENETUNREACH|EHOSTUNREACH/;
async function api(method, route, body) {
  for (let attempt = 0; ; attempt++) {
    const isForm = body instanceof FormData;
    let res;
    try {
      res = await fetch(`${BASE}${route}`, {
        method,
        headers: {
          Authorization: `Bearer ${KEY}`,
          ...(body && !isForm ? { "Content-Type": "application/json" } : {}),
        },
        body: isForm ? body : body ? JSON.stringify(body) : undefined,
      });
    } catch (e) {
      const retryable = method === "GET" || CONNECT_ERRORS.test(`${e.cause?.code} ${e.cause?.message}`);
      if (!retryable || attempt >= 4) throw e;
      await sleep(3000 * (attempt + 1));
      continue;
    }
    if (res.status === 429 && attempt < 6) {
      const wait = Math.min(65, Number(res.headers.get("retry-after")) || 15);
      process.stdout.write(`\n  rate limit, waiting ${wait}s...`);
      await sleep(wait * 1000);
      continue;
    }
    const text = await res.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      throw Error(`${method} ${route}: HTTP ${res.status}: ${text.slice(0, 200)}`);
    }
    if (res.status === 401) fail(`Wireflow did not accept that API key. Make a new one:\n  ${KEYS_URL}`);
    if (res.status === 403 && /scope/i.test(text))
      fail(
        `Your API key is missing a scope. Make a key with workflows:read, workflows:write,\nworkflows:execute and executions:read:\n  ${KEYS_URL}\n\n${text.slice(0, 300)}`,
      );
    if (!res.ok) throw Error(`${method} ${route}: HTTP ${res.status}: ${JSON.stringify(json).slice(0, 400)}`);
    return json.data ?? json;
  }
}

// Host a local file (or rehost a URL) on Wireflow's CDN and return its URL.
async function upload(src, types) {
  if (/^https?:\/\//.test(src)) return (await api("POST", "/media/upload", { url: src })).url;
  const file = path.resolve(cwd, src);
  const type = types[path.extname(file).toLowerCase()];
  if (!type) fail(`${src}: use one of ${Object.keys(types).join(", ")}`);
  const bytes = (await stat(file)).size;
  const data = await readFile(file);
  if (bytes <= 4_000_000) {
    const form = new FormData();
    form.append("file", new Blob([data], { type }), path.basename(file));
    return (await api("POST", "/media/upload", form)).url;
  }
  // Bigger files go straight to the CDN through a signed URL (video up to 100MB).
  const mint = await api("POST", "/media/upload-url", { contentType: type, bytes, filename: path.basename(file) });
  const put = await fetch(mint.uploadUrl, { method: mint.method || "PUT", headers: mint.headers || {}, body: data });
  if (!put.ok) throw Error(`Upload of ${src} failed: HTTP ${put.status} ${(await put.text()).slice(0, 200)}`);
  return (await api("POST", "/media/upload-url/complete", { mediaId: mint.mediaId })).url;
}

async function listClips(spec) {
  const full = path.resolve(cwd, spec);
  const isDir = !/^https?:\/\//.test(spec) && !spec.includes(",") && (await stat(full).catch(() => null))?.isDirectory();
  if (!isDir) return spec.split(",").map((s) => s.trim()).filter(Boolean);
  const names = (await readdir(full))
    .filter((n) => VIDEO_TYPES[path.extname(n).toLowerCase()])
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (!names.length) fail(`No video files (${Object.keys(VIDEO_TYPES).join(", ")}) in ${spec}`);
  return names.map((n) => path.join(full, n));
}

const { CLIP_PORTS, block } = await import("./prepare-film-block.mjs");

// ── 1. Who am I ────────────────────────────────────────────────────────────
const me = await api("GET", "/me");
const creditsBefore = me.credits;
console.log(`Signed in to Wireflow as ${me.email} (${creditsBefore} credits)`);

// ── 2. Clips and music ─────────────────────────────────────────────────────
let clipUrls = CLIP_PORTS.map((c) => c.url);
if (args.clips) {
  const sources = await listClips(args.clips);
  if (sources.length > 8) console.log(`  ${sources.length} clips found, using the first 8`);
  const urls = [];
  for (const [i, s] of sources.slice(0, 8).entries()) {
    process.stdout.write(`  uploading clip ${i + 1}/${Math.min(8, sources.length)} ${path.basename(s)}...`);
    urls.push(await upload(s, VIDEO_TYPES));
    console.log(" done");
  }
  clipUrls = CLIP_PORTS.map((_, i) => urls[i % urls.length]);
}
const scoreUrl = args.music ? await upload(args.music, AUDIO_TYPES) : DEMO_SCORE;

// ── 3. The film Block ──────────────────────────────────────────────────────
// Wireflow hosts one compiled copy of WireflowFilm.tsx (hosted-block.json).
// Compiling custom Block code is open to the Wireflow team only for now, so
// --publish-block is the maintainer path that refreshes that copy.
let hosted = JSON.parse(await readFile(path.join(root, "hosted-block.json"), "utf8").catch(() => "null"));
if (!hosted && !args["publish-block"]) fail("hosted-block.json is missing. Re-clone the repo.");
if (args["publish-block"]) {
  const compiled = await api("POST", "/blocks", {
    ...block,
    source: `// Open Flow launch film. Source: github.com/wireflowINC/wireflow-skill examples/open-flow-launch\n${block.source}`,
  });
  if (!compiled.renderable) fail(`Block ${compiled.blockId} compiled but is not renderable.`);
  hosted = { blockId: compiled.blockId, bundledUrl: compiled.bundledUrl, ports: compiled.ports };
  console.log(`Compiled block ${compiled.blockId}. Save this as hosted-block.json:\n${JSON.stringify(hosted, null, 2)}`);
}

// ── 4. The board ───────────────────────────────────────────────────────────
const importNode = (id, label, url, inputType, mediaType) => ({
  id,
  type: "basedNode",
  position: { x: 0, y: 0 },
  data: { label, nodeType: "input:image", category: "input", inputType, config: { image: url, imageUrl: url, mediaType } },
});
const textNode = (id, label, prompt) => ({
  id,
  type: "basedNode",
  position: { x: 0, y: 0 },
  data: { label, nodeType: "input:text", category: "input", config: { prompt } },
});
const TEXT_PORTS = [
  ["headline", "Headline", args.headline],
  ["cta", "Call to action", args.cta],
  ["brand", "Brand", args.brand],
];
const props = Object.fromEntries([...CLIP_PORTS.map((c) => c.id), ...TEXT_PORTS.map(([id]) => id)].map((id) => [id, `{{${id}}}`]));
const film = {
  id: "film",
  type: "basedNode",
  position: { x: 0, y: 0 },
  data: {
    label: "Open Flow launch film",
    nodeType: "video:remotion",
    category: "video",
    inputs: [
      ...CLIP_PORTS.map((c) => ({ id: c.id, type: "VIDEO", label: c.label, required: false })),
      { id: "audio", type: "AUDIO", label: "Audio", required: false },
      ...TEXT_PORTS.map(([id, label]) => ({ id, type: "TEXT", label, required: false })),
    ],
    outputs: [
      { id: "video", type: "VIDEO", label: "Video" },
      { id: "thumbnail", type: "IMAGE", label: "Thumbnail" },
    ],
    config: {
      mode: "sceneGraph",
      props: {
        sceneGraph: {
          fps: 30,
          width: 1920,
          height: 1080,
          scenes: [
            {
              type: "block",
              blockId: hosted.blockId,
              bundledUrl: hosted.bundledUrl,
              // Fixed: a long clip must not stretch the 18 second film.
              durationMode: "fixed",
              durationInFrames: 540,
              props,
              blockInputMappings: hosted.ports,
            },
          ],
        },
        blockInputMappings: hosted.ports,
      },
    },
  },
};
const nodes = [
  ...CLIP_PORTS.map((c, i) => importNode(c.id, c.label, clipUrls[i], "video", "VIDEO")),
  importNode("score", "Music", scoreUrl, "audio", "AUDIO"),
  ...TEXT_PORTS.map(([id, label, value]) => textNode(id, label, value)),
  film,
];
const edge = (source, sourceHandle, targetHandle) => ({ id: `e-${source}`, source, target: "film", sourceHandle, targetHandle });
const edges = [
  ...CLIP_PORTS.map((c) => edge(c.id, "out-media", `in-${c.id}`)),
  edge("score", "out-media", "in-audio"),
  ...TEXT_PORTS.map(([id]) => edge(id, "out-prompt", `in-${id}`)),
];
const board = await api("POST", "/workflows", {
  name: args.name || `${args.brand} launch film`,
  description: "18 second launch film made with Open Flow (github.com/wireflowINC/wireflow-skill). Swap a clip or a line, then run the film node.",
  tags: ["open-flow", "launch-film"],
  isActive: true,
  nodes,
  edges,
});
await api("POST", `/workflows/${board.id}/layout`, {});
const boardUrl = `${APP}/flow/${board.id}`;
console.log(`Board ready: ${boardUrl}`);

if (args["no-render"]) {
  console.log("Skipped the render (--no-render). Open the board and press Run on the film node.");
  process.exit(0);
}

// ── 5. Check the price, then render ────────────────────────────────────────
const estimate = await api("POST", `/workflows/${board.id}/estimate`, {});
const cost = estimate.estimatedCredits ?? estimate.totalCredits ?? 0;
if (cost > 0) fail(`This board would cost ${cost} credits, expected 0. Nothing was run. Open it here: ${boardUrl}`);
console.log("Cost estimate: 0 credits. Rendering (about 2 to 4 minutes)...");

const saved = await api("GET", `/workflows/${board.id}`);
const started = Date.now();
const run = await api("POST", `/workflows/${board.id}/execute`, {
  nodes: saved.nodes,
  edges: saved.edges,
  targetNodeId: "film",
});
const executionId = run.executionId || run.id;
if (!executionId) throw Error(`No execution id in the run response: ${JSON.stringify(run).slice(0, 300)}`);

let mp4;
while (!mp4) {
  if (Date.now() - started > 15 * 60_000) fail(`Still rendering after 15 minutes. Check the board: ${boardUrl}`);
  await sleep(8000);
  const poll = await api("GET", `/workflows/executions/${executionId}/poll`);
  const state = (poll.nodeStates || []).find((n) => n.nodeId === "film");
  if (poll.status === "FAILED" || state?.status === "FAILED")
    fail(`The render failed: ${state?.error || poll.error || "no detail"}\nBoard: ${boardUrl}`);
  mp4 = state?.outputUrl || state?.outputUrls?.[0];
  if (!mp4 && (poll.status === "COMPLETED" || state?.status === "COMPLETED"))
    fail(`The run finished without a video. Board: ${boardUrl}`);
  if (!mp4) process.stdout.write(".");
}
const after = await api("GET", "/me");
console.log(`\n\nDone in ${Math.round((Date.now() - started) / 1000)}s. Credits used: ${creditsBefore - after.credits}.`);
console.log(`Your film: ${mp4}`);
console.log(`Edit it:   ${boardUrl}`);
console.log(`\nWant us to make your launch video? Get a free media plan: ${OFFER_URL}`);
