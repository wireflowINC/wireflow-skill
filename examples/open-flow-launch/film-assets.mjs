import { mkdir, readFile, writeFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(
  await readFile(path.join(root, "film-assets.json"), "utf8"),
);
await mkdir(path.join(root, "public/wireflow"), { recursive: true });
for (const asset of manifest.assets) {
  const out = path.join(root, "public/wireflow", asset.file);
  try {
    if ((await stat(out)).size > 1000) {
      console.log("Using", asset.file);
      continue;
    }
  } catch {}
  const response = await fetch(asset.url);
  if (!response.ok)
    throw Error(
      `Download failed (${response.status}) for ${asset.file}. Open its URL from film-assets.json in a browser, save the video into public/wireflow, then rerun. No placeholder will be substituted.`,
    );
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 1000 || !bytes.subarray(4, 8).equals(Buffer.from("ftyp")))
    throw Error(`Invalid MP4 for ${asset.file}`);
  await writeFile(out, bytes);
  console.log("Saved", asset.file);
}
