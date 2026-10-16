import React, { createRef } from "react";
import { createRoot } from "react-dom/client";
import { Player, PlayerRef } from "@remotion/player";
import OpenFlowLaunch from "./Launch";

const ref = createRef<PlayerRef>();
const props = (window as any).previewProps;
createRoot(document.getElementById("root")!).render(
  <Player
    ref={ref}
    component={OpenFlowLaunch}
    inputProps={props}
    compositionWidth={1920}
    compositionHeight={1080}
    durationInFrames={540}
    fps={30}
    controls={false}
    autoPlay={false}
    style={{ width: 1920, height: 1080 }}
  />,
);
(window as any).seekFrame = (frame: number) => ref.current!.seekTo(frame);
(window as any).playerReady = () => Boolean(ref.current);
