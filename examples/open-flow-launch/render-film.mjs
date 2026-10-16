import { bundle } from "@remotion/bundler";

import { readFile, mkdir, writeFile, chmod } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveBrowser } from "./browser.mjs";
const root = path.dirname(fileURLToPath(import.meta.url));
process.chdir(root);
await mkdir("out", { recursive: true });
const font = async (p) =>
  "data:font/woff2;base64," + (await readFile(p)).toString("base64");
const inputProps = {
  assetBase: "/public/wireflow/",
  sansFont: await font(
    "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
  ),
  serifFont: await font(
    "node_modules/@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2",
  ),
};
// Some containers cannot enumerate interfaces. Keep the renderer explicitly on loopback.
try {
  os.networkInterfaces();
} catch (e) {
  if (e.code !== "ERR_SYSTEM_ERROR") throw e;
  const runtime = path.join(
    root,
    "node_modules/@remotion/renderer/dist/esm/index.mjs",
  );
  const original = await readFile(runtime, "utf8");
  const needle = "const networkInterfaces = os8.networkInterfaces();";
  const fixed = original.replace(
    needle,
    "let networkInterfaces; try {networkInterfaces = os8.networkInterfaces();} catch { return {host:'127.0.0.1',hostsToTry:['127.0.0.1']}; }",
  );
  if (fixed !== original) await writeFile(runtime, fixed);
}
const { selectComposition, renderStill, renderMedia } = await import(
  "@remotion/renderer"
);
const serveUrl = await bundle({
  entryPoint: path.join(root, "FilmRoot.tsx"),
  outDir: path.join(root, "out/film-bundle"),
  publicDir: path.join(root, "public"),
});
let browserExecutable = await resolveBrowser(root);
const options = {
  serveUrl,
  inputProps,
  browserExecutable,
  chromiumOptions: { gl: "swangle" },
  timeoutInMilliseconds: 40000,
};
const composition = await selectComposition({ ...options, id: "WireflowFilm" });
if (process.argv.includes("--stills")) {
  for (const frame of [55, 130, 215, 310, 405, 495]) {
    await renderStill({
      ...options,
      composition,
      frame,
      output: path.join(root, `out/film-${frame}.png`),
      scale: 0.5,
    });
    console.log("Frame", frame);
  }
} else {
  await renderMedia({
    ...options,
    composition,
    codec: "h264",
    crf: 20,
    pixelFormat: "yuv420p",
    concurrency: 2,
    outputLocation: path.join(root, "out/wireflow-film-silent.mp4"),
    onProgress: (p) => {
      if (p.renderedFrames % 60 === 0) console.log("Frames", p.renderedFrames);
    },
  });
  console.log("out/wireflow-film-silent.mp4");
}
