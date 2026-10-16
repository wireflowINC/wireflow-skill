import { spawnSync } from "node:child_process";
import "./score.mjs";
const args = [
  "-y",
  "-i",
  "out/open-flow-launch-silent.mp4",
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
  "192k",
  "-ar",
  "48000",
  "-t",
  "18",
  "-movflags",
  "+faststart",
  "out/open-flow-launch.mp4",
];
const result = spawnSync("ffmpeg", args, { stdio: "inherit" });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status || 1);
