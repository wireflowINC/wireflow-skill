import { access, chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import { brotliDecompressSync } from "node:zlib";
import { spawnSync } from "node:child_process";
import path from "node:path";

export async function resolveBrowser(root) {
  if (process.env.REMOTION_BROWSER_EXECUTABLE)
    return process.env.REMOTION_BROWSER_EXECUTABLE;
  if (process.platform !== "linux" || process.arch !== "x64") {
    throw new Error(
      "Set REMOTION_BROWSER_EXECUTABLE to a compatible local Chromium executable on this platform.",
    );
  }
  // Workspace-local extraction: preserve the caller's ownership in containers.
  const dest = path.join(root, "out", "browser");
  const executable = path.join(dest, "chromium");
  try {
    await access(path.join(dest, "ready"));
    return executable;
  } catch {}
  await mkdir(dest, { recursive: true });
  const bin = path.join(root, "node_modules", "@sparticuz", "chromium", "bin");
  await writeFile(
    executable,
    brotliDecompressSync(await readFile(path.join(bin, "chromium.br"))),
  );
  await chmod(executable, 0o700);
  const unpack = spawnSync("tar", ["-xf", "-", "-C", dest, "--no-same-owner"], {
    input: brotliDecompressSync(
      await readFile(path.join(bin, "swiftshader.tar.br")),
    ),
  });
  if (unpack.status !== 0)
    throw new Error(`Browser support extraction failed: ${unpack.stderr}`);
  await writeFile(path.join(dest, "ready"), "143.0.4\n");
  return executable;
}
