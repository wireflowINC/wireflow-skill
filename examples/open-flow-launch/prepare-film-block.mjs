// Turn WireflowFilm.tsx into a Wireflow Block: eight `$port:video` clip ports,
// `$port:text` headline, CTA and brand ports, and the two typefaces (in
// ./fonts, SIL OFL) embedded in the source so the Block renders the same in
// the editor and in the cloud. No npm install, no network, no credits.
//
// `film.mjs` imports `block` and `CLIP_PORTS` from
// here. Run it directly to write out/wireflow-film-block.json for inspection.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(
  await readFile(path.join(root, "film-assets.json"), "utf8"),
);
// Order matches the `files` array the composition indexed; labels become port
// labels on the canvas. Clip 1 is on screen the longest.
export const CLIP_PORTS = [
  ["clip1", "Clip 1: hero take"],
  ["clip2", "Clip 2: second take"],
  ["clip3", "Clip 3: variation"],
  ["clip4", "Clip 4: product shot"],
  ["clip5", "Clip 5: montage"],
  ["clip6", "Clip 6: montage"],
  ["clip7", "Clip 7: montage"],
  ["clip8", "Clip 8: montage"],
].map(([id, label], i) => ({
  id,
  label,
  url: manifest.assets[i].url,
}));

const font = async (p) =>
  "data:font/woff2;base64," +
  (await readFile(path.join(root, p))).toString("base64");
const sansFont = await font("fonts/inter-latin-wght-normal.woff2");
const serifFont = await font("fonts/instrument-serif-latin-400-italic.woff2");

let source = await readFile(path.join(root, "WireflowFilm.tsx"), "utf8");
const replace = (from, to) => {
  if (!source.includes(from)) throw Error(`Transform anchor missing: ${from.slice(0, 60)}`);
  source = source.split(from).join(to);
};

replace(
  `export type FilmProps = {
  sansFont: string;
  serifFont: string;
  assetBase?: string;
  headline?: string;
  cta?: string;
  brand?: string;
};
export const filmBeats = [`,
  `export type FilmProps = {
${CLIP_PORTS.map((c) => `  ${c.id}?: string;`).join("\n")}
  headline?: string;
  cta?: string;
  brand?: string;
};
// Typography embedded so the block renders the same in the editor and in the cloud.
const SANS_FONT = ${JSON.stringify(sansFont)};
const SERIF_FONT = ${JSON.stringify(serifFont)};
const asText = (v: unknown, fallback: string) =>
  typeof v === "string" && v.trim()
    ? v
    : v && typeof v === "object" && typeof (v as { text?: unknown }).text === "string"
      ? String((v as { text: string }).text)
      : fallback;
const isUrl = (v: unknown): v is string =>
  typeof v === "string" && v.startsWith("http");
export const beats = [`,
);
replace(
  `const files = [
  "base-1080.mp4",
  "creator-1080.mp4",
  "outfit-1080.mp4",
  "product-1080.mp4",
  "ad-roster-take-gym-720.mp4",
  "ad-matcha-720.mp4",
  "ad-roster-take-car-720.mp4",
  "ad-earbuds-720.mp4",
];
`,
  "",
);
for (const fn of ["Creator", "Variations", "Captions"])
  replace(`function ${fn}({ base }: { base: string })`, `function ${fn}({ clips }: { clips: string[] })`);
replace(
  "function Montage({ base, headline }: { base: string; headline: string })",
  "function Montage({ clips, headline }: { clips: string[]; headline: string })",
);
for (const k of ["i", "pick", "idx", "0"]) replace(`src={base + files[${k}]}`, `src={clips[${k}]}`);
replace(
  `  return (
    <OffthreadVideo
      src={src}`,
  `  if (!isUrl(src)) return null;
  return (
    <OffthreadVideo
      src={src}`,
);
const rootStart = source.indexOf("export default function WireflowFilm(");
if (rootStart < 0) throw Error("Transform anchor missing: root component");
source =
  source.slice(0, rootStart) +
  `export default function WireflowFilm(props: FilmProps) {
  const clips = [
${CLIP_PORTS.map((c) => `    props.${c.id},`).join("\n")}
  ].map((c) => (isUrl(c) ? c : ""));
  const headline = asText(props.headline, "One take. Every version.");
  const cta = asText(props.cta, "wireflow.ai");
  const brand = asText(props.brand, "Wireflow");
  const [h] = useState(() => delayRender("Loading film typography"));
  useEffect(() => {
    let live = true;
    Promise.all([
      new FontFace("Flow Sans", \`url(\${SANS_FONT})\`, {
        weight: "100 900",
      }).load(),
      new FontFace("Flow Serif", \`url(\${SERIF_FONT})\`, {
        style: "italic",
      }).load(),
    ])
      .then((fs) => {
        fs.forEach((x) => document.fonts.add(x));
        if (live) continueRender(h);
      })
      .catch((e) => cancelRender(e));
    return () => {
      live = false;
    };
  }, [h]);
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      data-frame={f}
      style={{ background: white, color: ink, fontFamily: sans }}
    >
      <Sequence from={0} durationInFrames={90}>
        <Brief cta={cta} />
      </Sequence>
      <Sequence from={90} durationInFrames={90}>
        <Creator clips={clips} />
      </Sequence>
      <Sequence from={180} durationInFrames={90}>
        <Variations clips={clips} />
      </Sequence>
      <Sequence from={270} durationInFrames={75}>
        <Captions clips={clips} />
      </Sequence>
      <Sequence from={345} durationInFrames={105}>
        <Montage clips={clips} headline={headline} />
      </Sequence>
      <Sequence from={450} durationInFrames={90}>
        <End cta={cta} brand={brand} />
      </Sequence>
    </AbsoluteFill>
  );
}
`;
if (/files\[|base \+/.test(source)) throw Error("Transform left an assetBase reference behind");

const schemaSource =
  `import { z } from 'zod';\nexport const Schema = z.object({\n` +
  CLIP_PORTS.map(
    (c) =>
      `  ${c.id}: z.string().default(${JSON.stringify(c.url)}).describe('$port:video ${c.label}'),`,
  ).join("\n") +
  `\n  headline: z.string().max(45).default('One take. Every version.').describe('$port:text Closing headline'),` +
  `\n  cta: z.string().max(30).default('wireflow.ai').describe('$port:text Call to action'),` +
  `\n  brand: z.string().max(24).default('Wireflow').describe('$port:text Brand name on the end card'),\n});\n`;

const bytes = Buffer.byteLength(source) + Buffer.byteLength(schemaSource);
if (bytes > 256000) throw Error(`Block exceeds the 256000 byte bundler cap (${bytes})`);

export const block = {
  name: "open_flow_wireflow_launch",
  displayName: "Open Flow launch film",
  description:
    "18-second launch film: brief, creator swap, outfit and product variations, kinetic captions, moving cards, end card. Eight swappable clips plus headline, CTA and brand ports.",
  source,
  schemaSource,
};
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await mkdir(path.join(root, "out"), { recursive: true });
  await writeFile(
    path.join(root, "out/wireflow-film-block.json"),
    JSON.stringify(block, null, 2) + "\n",
  );
  console.log(`Prepared out/wireflow-film-block.json (${bytes} bytes); no API calls or credit spend.`);
}
