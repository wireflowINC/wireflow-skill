import React, { createContext, useContext, useEffect, useState } from "react";
import {
  AbsoluteFill,
  cancelRender,
  continueRender,
  delayRender,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export type LaunchProps = {
  sansFont: string;
  serifFont: string;
  productName?: string;
  tagline?: string;
};
const Creative = createContext({
  productName: "form.",
  tagline: "Your ideas. In motion.",
});
export const beats = [
  { label: "Make it move", from: 0, to: 90 },
  { label: "One idea", from: 90, to: 210 },
  { label: "Every angle", from: 210, to: 345 },
  { label: "Make it yours", from: 345, to: 450 },
  { label: "Open Flow", from: 450, to: 540 },
];

const C = {
  bg: "#090a0d",
  paper: "#f0eee8",
  muted: "#a5a5af",
  purple: "#a58cfc",
  indigo: "#5040f2",
  teal: "#14b8a6",
};
const clamp = (n: number) => Math.max(0, Math.min(1, n));
const ease = (n: number) => 1 - Math.pow(1 - clamp(n), 4);
const enter = (f: number, start = 0, duration = 24) =>
  ease((f - start) / duration);
const mix = (a: number, b: number, v: number) => a + (b - a) * v;
const sans = "Flow Sans, Arial, sans-serif";
const serif = "Flow Serif, Georgia, serif";

function Mark({
  size = 44,
  color = C.paper,
}: {
  size?: number;
  color?: string;
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none">
      <path
        d="M8 21H34C48 21 48 43 34 43H8M21 8V34C21 48 43 48 43 34V8"
        stroke={color}
        strokeWidth="6"
        strokeLinecap="round"
      />
    </svg>
  );
}

function Label({
  children,
  style = {},
}: {
  children: React.ReactNode;
  style?: React.CSSProperties;
}) {
  return (
    <div
      style={{
        fontFamily: sans,
        fontSize: 18,
        fontWeight: 500,
        letterSpacing: "0.14em",
        textTransform: "uppercase",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function TextReveal({
  children,
  frame,
  start = 0,
  size = 130,
  italic = false,
  color = C.paper,
  style = {},
}: {
  children: React.ReactNode;
  frame: number;
  start?: number;
  size?: number;
  italic?: boolean;
  color?: string;
  style?: React.CSSProperties;
}) {
  const p = enter(frame, start, 26);
  return (
    <div
      style={{
        overflow: "hidden",
        paddingBottom: size * 0.18,
        marginBottom: -size * 0.18,
        ...style,
      }}
    >
      <div
        style={{
          fontFamily: italic ? serif : sans,
          fontStyle: italic ? "italic" : "normal",
          fontWeight: italic ? 400 : 600,
          letterSpacing: italic ? "-.035em" : "-.065em",
          lineHeight: 1.04,
          fontSize: size,
          color,
          transform: `translateY(${(1 - p) * 115}%)`,
          opacity: clamp((frame - start) / 9),
        }}
      >
        {children}
      </div>
    </div>
  );
}

function Bottle({
  id,
  tint = "#b7a5f3",
  angle = 0,
  width = 280,
}: {
  id: string;
  tint?: string;
  angle?: number;
  width?: number;
}) {
  const { productName } = useContext(Creative);
  return (
    <svg
      width={width}
      height={width * 1.92}
      viewBox="0 0 300 576"
      style={{ overflow: "visible", transform: `rotate(${angle}deg)` }}
    >
      <defs>
        <linearGradient id={`${id}-body`}>
          <stop stopColor="#191921" />
          <stop offset=".13" stopColor="#575661" />
          <stop offset=".29" stopColor="#d9d6dc" />
          <stop offset=".43" stopColor="#9c99a7" />
          <stop offset=".63" stopColor="#4b4858" />
          <stop offset=".88" stopColor="#262532" />
          <stop offset="1" stopColor="#14131b" />
        </linearGradient>
        <linearGradient id={`${id}-cap`} x2="0" y2="1">
          <stop stopColor="#62616e" />
          <stop offset=".18" stopColor="#17171e" />
          <stop offset=".82" stopColor="#292832" />
          <stop offset="1" stopColor="#777383" />
        </linearGradient>
        <linearGradient id={`${id}-label`} x2="1" y2=".2">
          <stop stopColor={tint} />
          <stop offset=".5" stopColor={tint} />
          <stop offset="1" stopColor="#545163" />
        </linearGradient>
        <linearGradient id={`${id}-shine`}>
          <stop stopColor="white" stopOpacity="0" />
          <stop offset=".5" stopColor="white" stopOpacity=".5" />
          <stop offset="1" stopColor="white" stopOpacity="0" />
        </linearGradient>
      </defs>
      <ellipse cx="150" cy="549" rx="117" ry="18" fill="#000" opacity=".22" />
      <rect
        x="100"
        y="5"
        width="100"
        height="87"
        rx="18"
        fill={`url(#${id}-cap)`}
      />
      {Array.from({ length: 17 }, (_, i) => (
        <path
          key={i}
          d={`M${105 + i * 5.5} 15V69`}
          stroke="#aaa6b4"
          strokeOpacity=".22"
        />
      ))}
      <path
        d="M96 72C96 91 67 98 60 125C57 136 56 149 56 168V490Q56 540 106 540H194Q244 540 244 490V168C244 149 243 136 240 125C233 98 204 91 204 72Z"
        fill={`url(#${id}-body)`}
        stroke="#d4d0df"
        strokeOpacity=".27"
      />
      <path
        d="M102 91C81 111 75 137 75 164V496"
        stroke="white"
        strokeWidth="4"
        opacity=".27"
      />
      <rect
        x="56"
        y="196"
        width="188"
        height="229"
        fill={`url(#${id}-label)`}
      />
      <path d="M57 196H243M57 425H243" stroke="#ece6ff" strokeOpacity=".25" />
      <g fill="#17141f" fontFamily={sans} textAnchor="middle">
        <text x="150" y="235" fontSize="13" letterSpacing="4">
          STUDIO / 01
        </text>
        <text
          x="148"
          y="307"
          fontSize={productName.length > 5 ? 47 : 65}
          fontWeight="600"
          letterSpacing="-3"
        >
          {productName}
        </text>
        <path d="M89 329H211" stroke="#17141f" opacity=".4" />
        <text x="150" y="357" fontSize="11" letterSpacing="2.5">
          DAILY ESSENTIAL
        </text>
        <text x="150" y="391" fontSize="10" letterSpacing="1.4">
          100 ML / DAILY SERIES
        </text>
      </g>
      <rect
        x="74"
        y="203"
        width="35"
        height="215"
        fill={`url(#${id}-shine)`}
        opacity=".24"
      />
    </svg>
  );
}

function AdCard({
  id,
  frame,
  variant = 0,
  width = 370,
  height = 600,
  compact = false,
}: {
  id: string;
  frame: number;
  variant?: number;
  width?: number;
  height?: number;
  compact?: boolean;
}) {
  const { productName } = useContext(Creative);
  const schemes = [
    {
      bg: "#c0b2eb",
      ink: "#282035",
      top: "Less, but",
      word: "better.",
      tag: "THE DAILY EDIT",
      tint: "#b7a5f3",
    },
    {
      bg: "#174d47",
      ink: "#e6fff2",
      top: "Find your",
      word: "form.",
      tag: "A FRESH PERSPECTIVE",
      tint: "#9bc7b8",
    },
    {
      bg: "#e4ded1",
      ink: "#282822",
      top: "Make room",
      word: "for you.",
      tag: "YOUR NEW ROUTINE",
      tint: "#d4ccb7",
    },
  ];
  const v = schemes[variant % 3],
    s = width / 370;
  return (
    <div
      style={{
        position: "relative",
        width,
        height,
        overflow: "hidden",
        borderRadius: 24 * s,
        background: v.bg,
        color: v.ink,
        border: "1px solid rgba(255,255,255,.22)",
        boxShadow: "0 28px 80px #0005",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage: `radial-gradient(ellipse at ${40 + Math.sin(frame / 40) * 15}% 30%, #ffffff20, transparent 60%)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 25 * s,
          right: 25 * s,
          top: 22 * s,
          display: "flex",
          justifyContent: "space-between",
          fontSize: 11 * s,
          fontWeight: 600,
          letterSpacing: 2 * s,
        }}
      >
        <span>{productName}</span>
        <span>0{variant + 1}</span>
      </div>
      <div
        style={{
          position: "absolute",
          top: compact ? 45 * s : 61 * s,
          left: 28 * s,
          right: 28 * s,
          fontSize: compact ? 44 * s : 51 * s,
          lineHeight: 0.98,
          letterSpacing: -2.3 * s,
          fontWeight: 500,
        }}
      >
        {v.top}
        <div
          style={{
            fontFamily: serif,
            fontStyle: "italic",
            fontSize: compact ? 60 * s : 73 * s,
            letterSpacing: -2 * s,
          }}
        >
          {v.word}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: width * 0.21,
          top: compact ? height * 0.31 : height * 0.34,
          transform: `translateY(${Math.sin(frame / 37 + variant) * 5 * s}px) rotate(${variant === 1 ? -12 : variant === 2 ? 12 : -5}deg)`,
        }}
      >
        <Bottle id={id} width={width * 0.56} tint={v.tint} />
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 22 * s,
          left: 26 * s,
          fontSize: 9 * s,
          letterSpacing: 1.7 * s,
          fontWeight: 600,
        }}
      >
        {v.tag}
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 20 * s,
          right: 23 * s,
          fontSize: 14 * s,
        }}
      >
        ↗
      </div>
    </div>
  );
}

function Opening({ f }: { f: number }) {
  const line = enter(f, 4, 60),
    out = enter(f, 72, 18);
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at 85% 70%, #5040f238, transparent 52%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 82,
          top: 65,
          display: "flex",
          alignItems: "center",
          gap: 15,
          opacity: enter(f, 0, 15),
        }}
      >
        <Mark size={34} />
        <Label>
          Open Flow{" "}
          <span style={{ color: "#777984", marginLeft: 13 }}>by Wireflow</span>
        </Label>
      </div>
      <svg
        width="1920"
        height="1080"
        style={{
          position: "absolute",
          transform: `translateX(${out * 500}px) scale(${1 + out * 0.15})`,
        }}
      >
        <defs>
          <linearGradient id="wire">
            <stop stopColor={C.purple} />
            <stop offset="1" stopColor={C.teal} />
          </linearGradient>
        </defs>
        <path
          d="M990 114C1550 -90 1760 298 1464 400C1210 488 1320 838 1611 702C1880 574 1744 1012 1160 1000"
          fill="none"
          stroke="#8175c714"
          strokeWidth="124"
        />
        <path
          d="M990 114C1550 -90 1760 298 1464 400C1210 488 1320 838 1611 702C1880 574 1744 1012 1160 1000"
          pathLength="1"
          strokeDasharray="1"
          strokeDashoffset={1 - line}
          fill="none"
          stroke="url(#wire)"
          strokeWidth="46"
          strokeLinecap="round"
        />
        <path
          d="M990 114C1550 -90 1760 298 1464 400C1210 488 1320 838 1611 702C1880 574 1744 1012 1160 1000"
          pathLength="1"
          strokeDasharray=".06 .94"
          strokeDashoffset={-f / 100}
          fill="none"
          stroke="#ede8ff"
          strokeWidth="4"
          strokeLinecap="round"
          opacity=".7"
        />
      </svg>
      <div
        style={{
          position: "absolute",
          left: 112,
          top: 280,
          transform: `translateY(${-out * 100}px)`,
          opacity: 1 - out,
        }}
      >
        <TextReveal frame={f} start={5} size={188}>
          Make it
        </TextReveal>
        <TextReveal frame={f} start={13} size={237} italic color={C.purple}>
          move.
        </TextReveal>
        <div
          style={{
            marginTop: 42,
            fontSize: 26,
            color: C.muted,
            opacity: enter(f, 32, 18),
          }}
        >
          An idea is only the beginning.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 60,
          left: 114,
          right: 100,
          display: "flex",
          justifyContent: "space-between",
          color: C.muted,
          opacity: enter(f, 25, 18),
        }}
      >
        <Label style={{ fontSize: 14 }}>
          Creative tools. Open possibilities.
        </Label>
        <Label style={{ fontSize: 14 }}>01 / 05</Label>
      </div>
    </AbsoluteFill>
  );
}

function Idea({ f }: { f: number }) {
  const p = enter(f),
    open = enter(f, 20, 42),
    exit = enter(f, 104, 16);
  return (
    <AbsoluteFill
      style={{ background: C.paper, color: C.bg, overflow: "hidden" }}
    >
      <div style={{ position: "absolute", left: 100, top: 82 }}>
        <Label style={{ color: "#6c6972" }}>01 — Start somewhere</Label>
      </div>
      <div style={{ position: "absolute", left: 108, top: 225 }}>
        <TextReveal frame={f} size={155} color={C.bg}>
          One
        </TextReveal>
        <TextReveal frame={f} start={7} size={205} italic color={C.indigo}>
          idea.
        </TextReveal>
        <div
          style={{
            fontSize: 26,
            lineHeight: 1.5,
            color: "#686570",
            marginTop: 50,
            opacity: enter(f, 30, 20),
          }}
        >
          Your product.
          <br />
          Your point of view.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 108,
          top: 780,
          display: "flex",
          alignItems: "center",
          gap: 15,
          opacity: enter(f, 45, 18),
        }}
      >
        <div
          style={{ width: 9, height: 9, borderRadius: 9, background: C.indigo }}
        />
        <Label style={{ fontSize: 14, letterSpacing: ".09em" }}>
          Original concept · form.
        </Label>
      </div>
      <div
        style={{
          position: "absolute",
          left: 950,
          top: 112,
          transform: `translateY(${(1 - p) * 180 - exit * 70}px) rotate(${mix(11, -5, open)}deg) scale(${mix(0.82, 1, p)})`,
          opacity: 1 - exit * 0.3,
        }}
      >
        <div
          style={{
            position: "absolute",
            width: 505,
            height: 816,
            borderRadius: 30,
            background: "#d5cfe2",
            transform: `translate(${open * 90}px, ${-open * 14}px) rotate(${open * 12}deg)`,
          }}
        />
        <div
          style={{
            position: "absolute",
            width: 505,
            height: 816,
            borderRadius: 30,
            background: "#272b2a",
            transform: `translate(${-open * 55}px, ${open * 5}px) rotate(${-open * 9}deg)`,
          }}
        />
        <AdCard id="idea" frame={f} width={505} height={816} />
      </div>
      <div
        style={{
          position: "absolute",
          right: 95,
          bottom: 65,
          color: "#6c6972",
        }}
      >
        <Label style={{ fontSize: 14 }}>02 / 05</Label>
      </div>
    </AbsoluteFill>
  );
}

function Angles({ f }: { f: number }) {
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at 60% 100%, #14b8a61a, transparent 62%)",
        }}
      />
      <div style={{ position: "absolute", left: 96, top: 64 }}>
        <Label style={{ color: C.muted }}>02 — Explore the possibilities</Label>
      </div>
      <div
        style={{
          position: "absolute",
          left: 90,
          top: 135,
          display: "flex",
          gap: 34,
          alignItems: "baseline",
        }}
      >
        <TextReveal frame={f} size={111}>
          Every
        </TextReveal>
        <TextReveal frame={f} start={5} size={145} italic color={C.purple}>
          angle.
        </TextReveal>
      </div>
      {[0, 1, 2].map((v) => {
        const p = enter(f, v * 7, 32),
          settle = enter(f, 50, 45);
        return (
          <div
            key={v}
            style={{
              position: "absolute",
              left: 350 + v * 437,
              top: 350,
              transform: `translate(${mix((1 - v) * 380, 0, p)}px, ${mix(420, 0, p) + Math.sin(f / 43 + v) * 4}px) rotate(${mix((v - 1) * 13, (v - 1) * 2, settle)}deg)`,
              opacity: p,
            }}
          >
            <AdCard
              id={`angle-${v}`}
              frame={f}
              variant={v}
              width={370}
              height={605}
            />
            <div
              style={{
                marginTop: 23,
                display: "flex",
                alignItems: "center",
                gap: 12,
                color: "#c0bdc8",
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: 7,
                  background: [C.purple, C.teal, "#e4ded1"][v],
                }}
              />
              <Label style={{ fontSize: 13, letterSpacing: ".08em" }}>
                {["A new hook", "A new mood", "A new direction"][v]}
              </Label>
            </div>
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          right: 94,
          top: 99,
          fontSize: 21,
          color: C.muted,
          opacity: enter(f, 25, 20),
        }}
      >
        Same product. Fresh perspectives.
      </div>
    </AbsoluteFill>
  );
}

function Yours({ f }: { f: number }) {
  const zoom = enter(f, 0, 35),
    swipe = enter(f, 80, 25);
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          left: -85,
          top: -220,
          transform: `rotate(-12deg) translateY(${mix(85, -60, f / 105)}px) scale(${mix(0.95, 1, zoom)})`,
          opacity: 0.42,
        }}
      >
        {[0, 1, 2, 3, 4].map((v) => (
          <div
            key={v}
            style={{
              position: "absolute",
              left: v * 448,
              top: v % 2 ? 150 : 0,
            }}
          >
            <AdCard
              id={`wall-${v}`}
              variant={v % 3}
              frame={f}
              width={410}
              height={1080}
            />
          </div>
        ))}
      </div>
      <AbsoluteFill
        style={{
          background:
            "linear-gradient(0deg, #090a0de8, #090a0d55 50%, #090a0d88)",
        }}
      />
      <div style={{ position: "absolute", left: 100, top: 70 }}>
        <Label>03 — The next version is yours</Label>
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 340,
          textAlign: "center",
          transform: `scale(${1 + swipe * 0.09})`,
          opacity: 1 - swipe,
        }}
      >
        <TextReveal frame={f} size={147}>
          Make it
        </TextReveal>
        <TextReveal frame={f} start={8} size={217} italic color="#d0c2ff">
          yours.
        </TextReveal>
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            gap: 17,
            marginTop: 49,
          }}
        >
          {["Rewrite", "Restyle", "Repeat"].map((t, i) => (
            <div
              key={t}
              style={{
                padding: "14px 30px",
                border: "1px solid #ffffff42",
                borderRadius: 60,
                background: i === 1 ? "#ffffff" : "#15151bb0",
                color: i === 1 ? C.bg : C.paper,
                fontSize: 20,
                transform: `translateY(${(1 - enter(f, 25 + i * 6, 20)) * 30}px)`,
                opacity: enter(f, 25 + i * 6, 20),
              }}
            >
              {t}
            </div>
          ))}
        </div>
      </div>
      <div
        style={{ position: "absolute", bottom: 60, left: 100, color: C.muted }}
      >
        <Label style={{ fontSize: 14 }}>
          A starting point you can keep creating with.
        </Label>
      </div>
    </AbsoluteFill>
  );
}

function Closing({ f }: { f: number }) {
  const { tagline } = useContext(Creative);
  const p = enter(f, 0, 32);
  return (
    <AbsoluteFill style={{ background: C.indigo, overflow: "hidden" }}>
      <svg
        width="1920"
        height="1080"
        style={{
          position: "absolute",
          opacity: 0.15,
          transform: `translateX(${mix(200, 0, p)}px)`,
        }}
      >
        <path
          d="M1400 -160V280C1400 650 1930 660 1930 280V-160M1650 400V1110"
          fill="none"
          stroke="#cdbdff"
          strokeWidth="160"
          strokeLinecap="round"
        />
      </svg>
      <div
        style={{
          position: "absolute",
          left: 98,
          top: 67,
          display: "flex",
          alignItems: "center",
          gap: 15,
        }}
      >
        <Mark size={38} />
        <Label>By Wireflow</Label>
      </div>
      <div style={{ position: "absolute", left: 103, top: 253 }}>
        <TextReveal frame={f} start={3} size={172}>
          open
        </TextReveal>
        <TextReveal frame={f} start={11} size={231} italic>
          flow.
        </TextReveal>
      </div>
      <div
        style={{
          position: "absolute",
          left: 117,
          top: 801,
          fontSize: 30,
          letterSpacing: "-.02em",
          opacity: enter(f, 26, 22),
        }}
      >
        {tagline}
      </div>
      <div
        style={{
          position: "absolute",
          left: 118,
          bottom: 60,
          right: 100,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          opacity: enter(f, 34, 20),
        }}
      >
        <Label style={{ fontSize: 15, letterSpacing: ".08em" }}>
          A creative toolkit for Wireflow
        </Label>
        <span style={{ fontSize: 23 }}>
          wireflow.ai <span style={{ marginLeft: 20 }}>↗</span>
        </span>
      </div>
    </AbsoluteFill>
  );
}

export default function OpenFlowLaunch({
  sansFont,
  serifFont,
  productName = "form.",
  tagline = "Your ideas. In motion.",
}: LaunchProps) {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const [fontHandle] = useState(() =>
    delayRender("Loading embedded typefaces"),
  );
  useEffect(() => {
    const first = new FontFace("Flow Sans", `url(${sansFont})`, {
      weight: "100 900",
    });
    const second = new FontFace("Flow Serif", `url(${serifFont})`, {
      style: "italic",
    });
    Promise.all([first.load(), second.load()])
      .then((fonts) => {
        fonts.forEach((font) => document.fonts.add(font));
        continueRender(fontHandle);
      })
      .catch(cancelRender);
  }, [sansFont, serifFont, fontHandle]);
  const scale = Math.min(width / 1920, height / 1080);
  return (
    <Creative.Provider value={{ productName, tagline }}>
      <AbsoluteFill
        data-frame={frame}
        style={{
          background: C.bg,
          overflow: "hidden",
          fontFamily: sans,
          color: C.paper,
        }}
      >
        <style>{`@font-face{font-family:Flow Sans;src:url("${sansFont}") format("woff2");font-weight:100 900;font-display:block}@font-face{font-family:Flow Serif;src:url("${serifFont}") format("woff2");font-style:italic;font-weight:400;font-display:block}*{box-sizing:border-box}`}</style>
        <div
          style={{
            position: "absolute",
            width: 1920,
            height: 1080,
            left: (width - 1920 * scale) / 2,
            top: (height - 1080 * scale) / 2,
            transform: `scale(${scale})`,
            transformOrigin: "top left",
          }}
        >
          {frame < 90 ? (
            <Opening f={frame} />
          ) : frame < 210 ? (
            <Idea f={frame - 90} />
          ) : frame < 345 ? (
            <Angles f={frame - 210} />
          ) : frame < 450 ? (
            <Yours f={frame - 345} />
          ) : (
            <Closing f={frame - 450} />
          )}
          <div
            style={{
              position: "absolute",
              inset: 0,
              pointerEvents: "none",
              boxShadow: "inset 0 0 100px #00000008",
            }}
          />
        </div>
      </AbsoluteFill>
    </Creative.Provider>
  );
}
