import React from "react";
import { registerRoot, Composition } from "remotion";
import WireflowFilm from "./WireflowFilm";
const Root = () => (
  <Composition
    id="WireflowFilm"
    component={WireflowFilm}
    durationInFrames={540}
    fps={30}
    width={1920}
    height={1080}
    defaultProps={{ sansFont: "", serifFont: "" }}
  />
);
registerRoot(Root);
