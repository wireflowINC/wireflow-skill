import React, { useEffect, useState } from "react";
import {
  AbsoluteFill,
  Sequence,
  OffthreadVideo,
  delayRender,
  continueRender,
  cancelRender,
  useCurrentFrame,
} from "remotion";

export type FilmProps = {
  sansFont: string;
  serifFont: string;
  assetBase?: string;
  headline?: string;
  cta?: string;
};
export const filmBeats = [
  { label: "The brief", from: 0, to: 90 },
  { label: "Your creator", from: 90, to: 180 },
  { label: "Your product", from: 180, to: 270 },
  { label: "Your words", from: 270, to: 345 },
  { label: "Every version", from: 345, to: 450 },
  { label: "Wireflow", from: 450, to: 540 },
];
const white = "#fcfcfa",
  ink = "#202122",
  accent = "#5040f2",
  mint = "#cbf5df",
  grey = "#f1f1ef";
const sans = "Flow Sans, Arial, sans-serif",
  serif = "Flow Serif, Georgia, serif";
const clamp = (x: number) => Math.max(0, Math.min(1, x));
const ease = (x: number) => 1 - Math.pow(1 - clamp(x), 4);
const pop = (f: number, s = 0, d = 23) => ease((f - s) / d);
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
const files = [
  "base-1080.mp4",
  "creator-1080.mp4",
  "outfit-1080.mp4",
  "product-1080.mp4",
  "ad-roster-take-gym-720.mp4",
  "ad-matcha-720.mp4",
  "ad-roster-take-car-720.mp4",
  "ad-earbuds-720.mp4",
];
function Word({
  children,
  f,
  start = 0,
  size = 126,
  italic = false,
  color = ink,
}: {
  children: React.ReactNode;
  f: number;
  start?: number;
  size?: number;
  italic?: boolean;
  color?: string;
}) {
  return (
    <div style={{ overflow: "hidden", paddingBottom: 25, marginBottom: -25 }}>
      <div
        style={{
          fontFamily: italic ? serif : sans,
          fontStyle: italic ? "italic" : "normal",
          fontSize: size,
          fontWeight: italic ? 400 : 550,
          letterSpacing: italic ? "-0.025em" : "-.065em",
          lineHeight: 1.03,
          color,
          transform: `translateY(${110 * (1 - pop(f, start))}%)`,
          opacity: clamp((f - start) / 7),
        }}
      >
        {children}
      </div>
    </div>
  );
}
function Pill({
  children,
  active = false,
  style = {},
}: {
  children: React.ReactNode;
  active?: boolean;
  style?: React.CSSProperties;
}) {
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 14,
        borderRadius: 60,
        padding: "15px 30px",
        background: active ? accent : grey,
        color: active ? "white" : ink,
        fontSize: 24,
        fontWeight: 500,
        letterSpacing: "-.025em",
        whiteSpace: "nowrap",
        ...style,
      }}
    >
      {children}
    </div>
  );
}
function Arrow({ size = 30 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 30 30" fill="none">
      <path
        d="M5 15H25M17 7L25 15L17 23"
        stroke="currentColor"
        strokeWidth="2.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
function Clip({
  src,
  start = 0,
  style = {},
}: {
  src: string;
  start?: number;
  style?: React.CSSProperties;
}) {
  return (
    <OffthreadVideo
      src={src}
      startFrom={start}
      muted
      style={{
        width: "100%",
        height: "100%",
        objectFit: "cover",
        objectPosition: "58% center",
        ...style,
      }}
    />
  );
}
function Card({
  src,
  x,
  y,
  w,
  h,
  rotate = 0,
  scale = 1,
  opacity = 1,
  start = 0,
  selected = false,
  children,
}: {
  src: string;
  x: number;
  y: number;
  w: number;
  h: number;
  rotate?: number;
  scale?: number;
  opacity?: number;
  start?: number;
  selected?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: h,
        transform: `rotate(${rotate}deg) scale(${scale})`,
        opacity,
        borderRadius: 32,
        overflow: "hidden",
        background: "#e6e3df",
        boxShadow: selected
          ? "0 0 0 7px " + accent + ",0 22px 55px #24212d18"
          : "0 22px 55px #24212d12",
      }}
    >
      <Clip src={src} start={start} />
      {children}
    </div>
  );
}
function Signature({ light = false }: { light?: boolean }) {
  return (
    <div
      style={{
        position: "absolute",
        left: 90,
        top: 58,
        display: "flex",
        alignItems: "center",
        gap: 19,
        color: light ? "white" : ink,
      }}
    >
      <span style={{ fontSize: 38, fontWeight: 700, letterSpacing: "-.065em" }}>
        Wireflow
      </span>
      <div
        style={{
          height: 23,
          width: 1,
          background: light ? "#ffffff50" : "#22222225",
        }}
      />
      <span style={{ fontSize: 22, letterSpacing: "-.02em" }}>Open Flow</span>
    </div>
  );
}
function Brief() {
  const f = useCurrentFrame();
  const p = pop(f, 0, 30);
  const typed = "Make a launch film for my brand.";
  return (
    <AbsoluteFill style={{ background: white }}>
      <Signature />
      <div style={{ position: "absolute", left: 128, top: 252 }}>
        <Word f={f} size={126}>
          Start with
        </Word>
        <Word f={f} start={5} size={151} italic>
          one idea.
        </Word>
        <div
          style={{
            marginTop: 55,
            fontSize: 29,
            opacity: pop(f, 15),
            color: "#777",
          }}
        >
          Your brand. Your story. Your direction.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 975,
          top: 210,
          width: 790,
          height: 650,
          borderRadius: 42,
          background: "#f1f1ef",
          transform: `translateY(${80 * (1 - p)}px) rotate(${3 * (1 - p)}deg)`,
          opacity: p,
          padding: 42,
        }}
      >
        <div
          style={{
            fontSize: 32,
            fontWeight: 550,
            letterSpacing: "-.04em",
            marginBottom: 36,
          }}
        >
          What are we making?
        </div>
        <div
          style={{
            height: 343,
            borderRadius: 25,
            background: "white",
            padding: 36,
            boxShadow: "0 15px 28px #00000006",
          }}
        >
          <div
            style={{
              fontSize: 37,
              lineHeight: 1.3,
              letterSpacing: "-.045em",
              minHeight: 128,
            }}
          >
            {typed.slice(0, Math.max(0, Math.floor((f - 10) * 1.15)))}
            <span
              style={{ opacity: f < 50 && f % 20 < 12 ? 1 : 0, color: accent }}
            >
              |
            </span>
          </div>
          <div style={{ display: "flex", gap: 12, marginTop: 47 }}>
            <Pill style={{ fontSize: 21 }}>wireflow.ai</Pill>
            <Pill style={{ fontSize: 21 }}>Brand kit ✓</Pill>
            <div
              style={{
                marginLeft: "auto",
                width: 57,
                height: 57,
                borderRadius: "50%",
                background: accent,
                color: "white",
                display: "grid",
                placeItems: "center",
                transform: `scale(${1 + 0.1 * Math.sin(clamp((f - 60) / 12) * Math.PI)})`,
              }}
            >
              <Arrow />
            </div>
          </div>
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 13,
            marginTop: 34,
            opacity: pop(f, 54),
            fontSize: 24,
            color: "#626267",
          }}
        >
          <span
            style={{
              width: 11,
              height: 11,
              borderRadius: "50%",
              background: accent,
            }}
          />
          A little direction. A lot of possibility.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 52,
          left: 130,
          fontSize: 19,
          color: "#919191",
        }}
      >
        01 / THE BRIEF
      </div>
    </AbsoluteFill>
  );
}
function Creator({ base }: { base: string }) {
  const f = useCurrentFrame();
  const pick = f < 38 ? 0 : 1;
  return (
    <AbsoluteFill style={{ background: white }}>
      <div style={{ position: "absolute", left: 135, top: 218 }}>
        <Word f={f} size={124}>
          Choose your
        </Word>
        <Word f={f} start={4} size={156} italic>
          creator.
        </Word>
        <div
          style={{
            fontSize: 28,
            color: "#777",
            marginTop: 45,
            opacity: pop(f, 12),
          }}
        >
          A new face. The same take.
        </div>
      </div>
      {[0, 1, 4].map((i, k) => (
        <Card
          key={i}
          src={base + files[i]}
          x={150 + k * 230}
          y={665 - Math.sin((k * Math.PI) / 2) * 24}
          w={200}
          h={267}
          rotate={[-9, -1, 8][k] * pop(f, 8 + k * 3)}
          scale={lerp(0.65, 1, pop(f, 8 + k * 3))}
          opacity={pop(f, 8 + k * 3)}
          selected={k === pick}
        />
      ))}
      <Card
        key={pick}
        src={base + files[pick]}
        x={1110 + 90 * (1 - pop(f))}
        y={85}
        w={630}
        h={910}
        rotate={2 * (1 - pop(f))}
        opacity={pop(f)}
        start={20}
      >
        <div
          style={{
            position: "absolute",
            bottom: 35,
            left: 0,
            right: 0,
            textAlign: "center",
          }}
        >
          <Pill active>
            {pick === 0 ? "Original take" : "New creator"}
            <span style={{ fontSize: 22 }}>✓</span>
          </Pill>
        </div>
      </Card>
    </AbsoluteFill>
  );
}
function Variations({ base }: { base: string }) {
  const f = useCurrentFrame();
  const idx = f < 28 ? 0 : f < 55 ? 2 : 3;
  const title =
    idx === 0 ? "Original" : idx === 2 ? "New outfit" : "Your product";
  return (
    <AbsoluteFill style={{ background: white }}>
      <div style={{ position: "absolute", left: 135, top: 218 }}>
        <Word f={f} size={126}>
          Make it
        </Word>
        <Word f={f} start={5} size={158} italic>
          your own.
        </Word>
      </div>
      {[0, 1, 2, 3].map((i, k) => (
        <Card
          key={i}
          src={base + files[i]}
          x={116 + k * 192}
          y={645 + [55, 9, 0, 40][k]}
          w={185}
          h={260}
          rotate={[-13, -5, 4, 13][k] * pop(f, 4 + k * 3)}
          scale={lerp(0.65, 1, pop(f, 4 + k * 3))}
          opacity={pop(f, 4 + k * 3)}
          selected={idx === i}
        />
      ))}
      <Pill
        active
        style={{ position: "absolute", top: 937, left: 355, minWidth: 245 }}
      >
        {title}
      </Pill>
      <Card
        key={idx}
        src={base + files[idx]}
        x={1110}
        y={85}
        w={630}
        h={910}
        start={15}
        scale={1 + 0.03 * (1 - pop(f, idx === 2 ? 28 : idx === 3 ? 55 : 0, 13))}
      />
    </AbsoluteFill>
  );
}
function Captions({ base }: { base: string }) {
  const f = useCurrentFrame();
  const words = ["Your", "words.", "In", "motion."];
  const active = Math.min(3, Math.floor(Math.max(0, f - 15) / 12));
  return (
    <AbsoluteFill style={{ background: white }}>
      <div style={{ position: "absolute", left: 135, top: 250 }}>
        <Word f={f} size={126}>
          Give every
        </Word>
        <Word f={f} start={5} size={153} italic>
          word a beat.
        </Word>
      </div>
      <div
        style={{
          position: "absolute",
          left: 140,
          top: 720,
          width: 725,
          borderRadius: 25,
          padding: 26,
          boxShadow: "0 15px 50px #1917250c",
          background: "white",
          border: "1px solid #eeeeeb",
          opacity: pop(f, 8),
          transform: `translateY(${35 * (1 - pop(f, 8))}px)`,
        }}
      >
        <div style={{ fontSize: 21, marginBottom: 24 }}>Caption style</div>
        <div style={{ display: "flex", gap: 14 }}>
          <Pill>Clean</Pill>
          <Pill>Editorial</Pill>
          <Pill active>Kinetic</Pill>
        </div>
      </div>
      <Card src={base + files[0]} x={1110} y={85} w={630} h={910} start={70}>
        <div
          style={{
            position: "absolute",
            left: 38,
            right: 38,
            bottom: 195,
            textAlign: "center",
            fontSize: 56,
            fontWeight: 750,
            lineHeight: 1.2,
            letterSpacing: "-.045em",
            color: "white",
            textShadow: "0 2px 15px #0007",
          }}
        >
          {words.map((w, i) => (
            <React.Fragment key={w}>
              {i === 2 ? <br /> : null}
              <span
                style={{
                  display: "inline-block",
                  margin: "0 4px",
                  padding: "2px 8px",
                  borderRadius: 10,
                  background: i === active ? accent : "transparent",
                  transform: `scale(${i === active ? 1.07 : 1})`,
                }}
              >
                {w}
              </span>
            </React.Fragment>
          ))}
        </div>
      </Card>
    </AbsoluteFill>
  );
}
function Montage({ base, headline }: { base: string; headline: string }) {
  const f = useCurrentFrame();
  const p = pop(f, 0, 35);
  const settle = pop(f, 42, 30);
  const list = [6, 4, 0, 5, 7];
  return (
    <AbsoluteFill style={{ background: white }}>
      {list.map((i, k) => {
        const centre = k - 2;
        return (
          <Card
            key={i}
            src={base + files[i]}
            x={lerp(320 + centre * 450, 140 + k * 341, p) - 50 * (1 - settle)}
            y={
              lerp(130, 210 + Math.abs(centre) * 20, settle) +
              35 * Math.sin(k + f * 0.025)
            }
            w={lerp(390, 308, settle)}
            h={lerp(770, 610, settle)}
            rotate={lerp(centre * -3, centre * 2.5, settle)}
            scale={lerp(0.8, 1, pop(f, k * 3, 28))}
            opacity={pop(f, k * 3)}
            start={15}
          />
        );
      })}
      <div
        style={{
          position: "absolute",
          bottom: 80,
          width: "100%",
          textAlign: "center",
          opacity: pop(f, 26),
        }}
      >
        <Pill
          style={{
            fontSize: 33,
            background: ink,
            color: "white",
            padding: "20px 53px",
          }}
        >
          {headline}
          <span style={{ marginLeft: 10 }}>
            <Arrow />
          </span>
        </Pill>
      </div>
    </AbsoluteFill>
  );
}
function End({ cta }: { cta: string }) {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        background: accent,
        color: "white",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          transform: `translateY(${lerp(60, 0, pop(f))}px) scale(${lerp(0.92, 1, pop(f, 0, 35))})`,
          opacity: pop(f),
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontSize: 219,
            fontWeight: 700,
            letterSpacing: "-.075em",
            lineHeight: 1,
          }}
        >
          Wireflow<span style={{ color: mint }}>.</span>
        </div>
        <div
          style={{
            fontSize: 40,
            marginTop: 43,
            fontWeight: 450,
            letterSpacing: "-.035em",
          }}
        >
          Your ideas. Every version.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 118,
          display: "flex",
          alignItems: "center",
          gap: 30,
          opacity: pop(f, 25),
          transform: `translateY(${25 * (1 - pop(f, 25))}px)`,
        }}
      >
        <span style={{ fontSize: 28 }}>Made with Open Flow</span>
        <span style={{ opacity: 0.45 }}> / </span>
        <Pill
          style={{
            background: "white",
            color: accent,
            fontSize: 29,
            padding: "19px 35px",
          }}
        >
          {cta}
          <Arrow />
        </Pill>
      </div>
    </AbsoluteFill>
  );
}
export default function WireflowFilm({
  sansFont,
  serifFont,
  assetBase = "https://cdn.wireflow.ai/landing/hero-pitch/",
  headline = "One take. Every version.",
  cta = "wireflow.ai",
}: FilmProps) {
  const [h] = useState(() => delayRender("Loading film typography"));
  useEffect(() => {
    let live = true;
    Promise.all([
      new FontFace("Flow Sans", `url(${sansFont})`, {
        weight: "100 900",
      }).load(),
      new FontFace("Flow Serif", `url(${serifFont})`, {
        style: "italic",
      }).load(),
    ])
      .then((fs) => {
        fs.forEach((x) => document.fonts.add(x));
        if (live) continueRender(h);
      })
      .catch((e) => cancelRender(e));
    return () => {
      live = false;
    };
  }, [sansFont, serifFont, h]);
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      data-frame={f}
      style={{ background: white, color: ink, fontFamily: sans }}
    >
      <Sequence from={0} durationInFrames={90}>
        <Brief />
      </Sequence>
      <Sequence from={90} durationInFrames={90}>
        <Creator base={assetBase} />
      </Sequence>
      <Sequence from={180} durationInFrames={90}>
        <Variations base={assetBase} />
      </Sequence>
      <Sequence from={270} durationInFrames={75}>
        <Captions base={assetBase} />
      </Sequence>
      <Sequence from={345} durationInFrames={105}>
        <Montage base={assetBase} headline={headline} />
      </Sequence>
      <Sequence from={450} durationInFrames={90}>
        <End cta={cta} />
      </Sequence>
    </AbsoluteFill>
  );
}
