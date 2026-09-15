import { readFile, writeFile, mkdir } from "node:fs/promises";
const font = async (p) =>
  "data:font/woff2;base64," + (await readFile(p)).toString("base64");
const sansFont = await font(
  "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
);
const serifFont = await font(
  "node_modules/@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2",
);
const source = await readFile("WireflowFilm.tsx", "utf8");
const schemaSource = `import {z} from 'zod';\nexport const Schema=z.object({sansFont:z.string().default(${JSON.stringify(sansFont)}),serifFont:z.string().default(${JSON.stringify(serifFont)}),assetBase:z.string().url().default('https://cdn.wireflow.ai/landing/hero-pitch/'),headline:z.string().max(45).default('One take. Every version.').describe('$port:text Closing headline'),cta:z.string().max(30).default('wireflow.ai').describe('$port:text Call to action')});\n`;
if (
  Buffer.byteLength(source) > 256000 ||
  Buffer.byteLength(schemaSource) > 256000
)
  throw Error("Block exceeds inspected source limits");
await mkdir("out", { recursive: true });
await writeFile(
  "out/wireflow-film-block.json",
  JSON.stringify(
    {
      name: "open_flow_wireflow_launch",
      displayName: "Open Flow — Wireflow launch film",
      description:
        "18-second white editorial launch film using Wireflow demo clips. Local render verified; cloud import remains unverified.",
      source: source.replace("export const filmBeats", "export const beats"),
      schemaSource,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  "Prepared out/wireflow-film-block.json; no API calls or credit spend.",
);
