// Local preview renderer: the same Remotion component, sought frame by frame.
// Explicit loopback binding avoids enumerating network interfaces in containers.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { build } from "esbuild";
import { chromium } from "playwright-core";
import { resolveBrowser } from "./browser.mjs";
const root = path.dirname(fileURLToPath(import.meta.url));
process.chdir(root);
await mkdir("out", { recursive: true });
const data = async (p) =>
  `data:font/woff2;base64,${(await readFile(p)).toString("base64")}`;
const inputProps = {
  sansFont: await data(
    "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
  ),
  serifFont: await data(
    "node_modules/@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2",
  ),
};
await build({
  entryPoints: ["player.tsx"],
  bundle: true,
  outfile: "out/player.js",
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "warning",
});
const js = await readFile("out/player.js");
const html = `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#090a0d;overflow:hidden}*{box-sizing:border-box}</style></head><body><div id="root"></div><script>window.previewProps=${JSON.stringify(inputProps)}</script><script src="/player.js"></script></body></html>`;
const server = createServer((req, res) => {
  res.setHeader(
    "Content-Type",
    req.url === "/player.js" ? "text/javascript" : "text/html",
  );
  res.end(req.url === "/player.js" ? js : html);
});
await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolve);
});
let browser;
try {
  browser = await chromium.launch({
    executablePath: await resolveBrowser(root),
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-partial-raster",
      "--disable-zero-copy",
    ],
  });
  const page = await browser.newPage({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
  });
  const errors = [];
  page.on("pageerror", (e) => {
    errors.push(e.message);
    console.error(e.message);
  });
  page.on("console", (message) => {
    if (message.type() === "error") console.error(message.text());
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.waitForFunction(() => window.playerReady?.(), null, {
    timeout: 10000,
  });
  await page.waitForFunction(
    () =>
      document.fonts.check('600 30px "Flow Sans"') &&
      document.fonts.check('italic 30px "Flow Serif"'),
  );
  const capture = async (frame) => {
    await page.evaluate((f) => window.seekFrame(f), frame);
    await page.waitForFunction(
      (f) =>
        document.querySelector("[data-frame]")?.getAttribute("data-frame") ===
        String(f),
      frame,
    );
    await page.evaluate(
      () =>
        new Promise((resolve) =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        ),
    );
    if (errors.length) throw new Error(errors.join("\n"));
    return await page.screenshot({ type: "png", fullPage: true });
  };
  if (process.argv.includes("--stills")) {
    for (const frame of [45, 135, 190, 250, 300, 385, 500]) {
      await writeFile(`out/frame-${frame}.png`, await capture(frame));
      console.log(`Frame ${frame}`);
    }
  } else {
    const ff = spawn(
      "ffmpeg",
      [
        "-y",
        "-f",
        "image2pipe",
        "-vcodec",
        "png",
        "-framerate",
        "30",
        "-i",
        "-",
        "-c:v",
        "libx264",
        "-preset",
        "fast",
        "-crf",
        "18",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "out/open-flow-launch-silent.mp4",
      ],
      { stdio: ["pipe", "ignore", "pipe"] },
    );
    let log = "";
    ff.stderr.on("data", (b) => (log += b.toString()));
    ff.stdin.on("error", () => {});
    const completion = new Promise((resolve, reject) => {
      ff.on("error", reject);
      ff.on("close", (code) =>
        code === 0 ? resolve() : reject(new Error(log.slice(-3000))),
      );
    });
    try {
      for (let frame = 0; frame < 540; frame++) {
        const buf = await capture(frame);
        if (!ff.stdin.write(buf)) await once(ff.stdin, "drain");
        if (frame % 60 === 0) console.log(`Rendered ${frame}/540`);
      }
      ff.stdin.end();
      await completion;
    } catch (e) {
      ff.kill();
      await completion.catch(() => {});
      throw e;
    }
    console.log("out/open-flow-launch-silent.mp4");
  }
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
