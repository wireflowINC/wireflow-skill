import { spawnSync } from "node:child_process";
import "./score.mjs";
function ff(args) {
  const p = spawnSync("ffmpeg", ["-v", "error", "-y", ...args], {
    stdio: "inherit",
  });
  if (p.error) throw p.error;
  if (p.status !== 0) throw Error("FFmpeg failed: " + p.status);
}
ff([
  "-i",
  "out/wireflow-film-silent.mp4",
  "-i",
  "out/original-score.wav",
  "-map",
  "0:v:0",
  "-map",
  "1:a:0",
  "-c:v",
  "copy",
  "-af",
  "loudnorm=I=-16:TP=-1.5:LRA=9",
  "-c:a",
  "aac",
  "-b:a",
  "160k",
  "-ar",
  "48000",
  "-t",
  "18",
  "-movflags",
  "+faststart",
  "out/Wireflow-Launch-1080p.mp4",
]);
ff([
  "-i",
  "out/Wireflow-Launch-1080p.mp4",
  "-vf",
  "scale=1280:720",
  "-c:v",
  "libx264",
  "-profile:v",
  "main",
  "-level:v",
  "3.1",
  "-preset",
  "fast",
  "-crf",
  "25",
  "-pix_fmt",
  "yuv420p",
  "-c:a",
  "aac",
  "-b:a",
  "96k",
  "-ac",
  "2",
  "-ar",
  "44100",
  "-movflags",
  "+faststart",
  "out/Wireflow-Launch-Phone.mp4",
]);
console.log("out/Wireflow-Launch-1080p.mp4");
console.log("out/Wireflow-Launch-Phone.mp4");
