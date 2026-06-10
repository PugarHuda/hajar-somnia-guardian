import React from "react";
import { Composition } from "remotion";
import { HajarPitch, FPS, totalFrames } from "./HajarPitch";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="HajarPitch"
      component={HajarPitch}
      durationInFrames={totalFrames}
      fps={FPS}
      width={1920}
      height={1080}
    />
  );
};
