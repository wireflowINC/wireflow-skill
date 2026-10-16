// Writes an import candidate. Deliberately does not authenticate or call an API.
import { mkdir, readFile, writeFile } from "node:fs/promises";
const font = async (p) =>
  `data:font/woff2;base64,${(await readFile(p)).toString("base64")}`;
const props = {
  sansFont: await font(
    "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
  ),
  serifFont: await font(
    "node_modules/@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2",
  ),
};
const source = await readFile("Launch.tsx", "utf8");
const schemaSource = `import {z} from 'zod';\nexport const Schema=z.object({productName:z.string().min(1).max(8).default('form.').describe('$port:text Product name'),tagline:z.string().max(60).default('Your ideas. In motion.').describe('$port:text Closing tagline'),sansFont:z.string().default(${JSON.stringify(props.sansFont)}),serifFont:z.string().default(${JSON.stringify(props.serifFont)})});\n`;
if (
  Buffer.byteLength(source) > 256000 ||
  Buffer.byteLength(schemaSource) > 256000
)
  throw new Error("Block exceeds the inspected API source limit");
await mkdir("out", { recursive: true });
await writeFile(
  "out/wireflow-block.json",
  JSON.stringify(
    {
      name: "open_flow_launch_preview",
      displayName: "Open Flow — launch concept",
      description:
        "18-second motion concept. Production rendering has not yet been verified.",
      source,
      schemaSource,
    },
    null,
    2,
  ) + "\n",
);
await writeFile("out/preview-props.json", JSON.stringify(props) + "\n");
console.log(
  "Prepared out/wireflow-block.json. No API calls, charges, or production changes.",
);
