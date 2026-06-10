import React from "react";
import { AbsoluteFill, Series, Audio, staticFile, useCurrentFrame, useVideoConfig, interpolate, spring } from "remotion";
import { loadFont as loadPixel } from "@remotion/google-fonts/PressStart2P";
import { loadFont as loadBody } from "@remotion/google-fonts/PixelifySans";
import { SLIDES, type Slide } from "./slides";

const { fontFamily: PIXEL } = loadPixel();
const { fontFamily: BODY } = loadBody();

const C = { bg: "#0b0d0e", panel: "#15191b", ink: "#e9eef0", dim: "#8b969b", green: "#4ee08a", line: "#e9eef0" };

export const FPS = 30;
export const totalFrames = SLIDES.reduce((a, s) => a + Math.round(s.seconds * FPS), 0);

const fadeUp = (frame: number, fps: number, delay: number) => {
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 }, durationInFrames: 18 });
  return { opacity: interpolate(s, [0, 1], [0, 1]), transform: `translateY(${interpolate(s, [0, 1], [16, 0])}px)` };
};

const SlideView: React.FC<{ slide: Slide }> = ({ slide }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ background: C.bg, fontFamily: BODY, padding: "9vh 9vw", justifyContent: "center" }}>
      <Audio src={staticFile(slide.audio)} />
      {/* subtle scanlines */}
      <AbsoluteFill style={{ background: "repeating-linear-gradient(0deg, rgba(255,255,255,0.025) 0 2px, transparent 2px 4px)", pointerEvents: "none" }} />

      {slide.kicker && (
        <div style={{ ...fadeUp(frame, fps, 0), fontFamily: PIXEL, fontSize: 20, color: C.green, letterSpacing: 2, textTransform: "uppercase", marginBottom: 30 }}>
          {slide.kicker}
        </div>
      )}

      <div style={{ ...fadeUp(frame, fps, 6), fontFamily: PIXEL, fontSize: slide.accentTitle ? 110 : 52, color: C.ink, lineHeight: 1.35, marginBottom: 38, textShadow: "5px 5px 0 #000" }}>
        {slide.title}
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 20, maxWidth: 1280 }}>
        {slide.bullets.map((b, i) => (
          <div key={i} style={{ ...fadeUp(frame, fps, 18 + i * 7), display: "flex", alignItems: "flex-start", gap: 18 }}>
            <div style={{ width: 18, height: 18, background: C.green, marginTop: 8, flexShrink: 0 }} />
            <div style={{ fontSize: 34, color: C.ink, opacity: 0.92, lineHeight: 1.45 }}>{b}</div>
          </div>
        ))}
      </div>

      {/* burned-in caption / subtitle */}
      <div style={{ position: "absolute", left: "9vw", right: "9vw", bottom: "7vh", opacity: interpolate(frame, [4, 16], [0, 1], { extrapolateRight: "clamp" }) }}>
        <div style={{ background: C.panel, boxShadow: `0 0 0 3px ${C.ink}`, padding: "16px 22px", fontSize: 24, color: C.ink, lineHeight: 1.5 }}>
          {slide.caption}
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const HajarPitch: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <Series>
        {SLIDES.map((slide, i) => (
          <Series.Sequence key={i} durationInFrames={Math.round(slide.seconds * FPS)}>
            <SlideView slide={slide} />
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};
