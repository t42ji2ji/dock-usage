import React from "react";
import { AbsoluteFill, Audio, Img, interpolate, Sequence, staticFile, useCurrentFrame, Easing } from "remotion";
import spec from "./tracks.json";

const W = 1920;
const H = 1080;
const FONT = 'system-ui, -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';
const ease = Easing.bezier(0.45, 0, 0.15, 1);

// ---------- Dock 版面 ----------
const D = 128; // 圖示邊長（鏡頭倍率 1 時）
const GAP = 14;
const PAD = 14;
type Slot = { id: string; track?: string; plain?: string; drawn?: Drawn; running?: boolean } | { id: "divider" };
type Drawn = "chat" | "notes" | "music" | "mail" | "photos";
const SLOTS: Slot[] = [
  { id: "finder", track: "finder", plain: "finder", running: true },
  { id: "chat", drawn: "chat", running: true },
  { id: "notes", drawn: "notes" },
  { id: "music", drawn: "music" },
  { id: "chrome", track: "chrome", plain: "chrome", running: true },
  { id: "claude", track: "claude", plain: "claude", running: true },
  { id: "gpt", track: "gpt", plain: "gpt", running: true },
  { id: "photos", drawn: "photos" },
  { id: "mail", drawn: "mail" },
  { id: "divider" },
  { id: "trash", track: "trash", plain: "trash" },
];
const DIV_W = 24;
const widths = SLOTS.map((s) => (s.id === "divider" ? DIV_W : D));
const DOCK_W = widths.reduce((a, b) => a + b, 0) + GAP * (SLOTS.length - 1) + PAD * 2;
const DOCK_H = D + PAD * 2;
const DOCK_X = (W - DOCK_W) / 2;
const DOCK_Y = H - 28 - DOCK_H;
const ICON_Y = DOCK_Y + PAD + D / 2; // 圖示中心 y
const centers: Record<string, number> = {};
{
  let x = DOCK_X + PAD;
  SLOTS.forEach((s, i) => {
    centers[s.id] = x + widths[i] / 2;
    x += widths[i] + GAP;
  });
}

// ---------- 鏡頭 ----------
type Cam = { f: number; s: number; x: number; y: number };
// y 換算：讓圖示落在畫面 ty 的位置
const focusY = (s: number, ty: number) => ICON_Y - (ty - H / 2) / s;
const mid = (a: string, b: string) => (centers[a] + centers[b]) / 2;
// 段落切點對齊配樂小節：BAR(k) = 105 + 69.66k（103 BPM，見 Audio 段）
const CAM: Cam[] = [
  { f: 0, s: 1.25, x: W / 2, y: focusY(1.25, 720) },
  { f: 104, s: 1.25, x: W / 2, y: focusY(1.25, 720) },
  // Claude 特寫
  { f: 132, s: 4.6, x: centers.claude, y: focusY(4.6, 610) },
  { f: 244, s: 4.8, x: centers.claude, y: focusY(4.8, 610) },
  // Claude + ChatGPT 雙圖示
  { f: 268, s: 3.3, x: mid("claude", "gpt"), y: focusY(3.3, 640) },
  { f: 384, s: 3.45, x: mid("claude", "gpt"), y: focusY(3.45, 640) },
  // 紅點：推到最近
  { f: 400, s: 5.0, x: centers.claude, y: focusY(5.0, 640) },
  { f: 452, s: 5.2, x: centers.claude, y: focusY(5.2, 640) },
  // 硬切 Finder
  { f: 453, s: 3.4, x: centers.finder, y: focusY(3.4, 640) },
  { f: 522, s: 3.7, x: centers.finder, y: focusY(3.7, 640) },
  // 硬切垃圾桶
  { f: 523, s: 3.4, x: centers.trash, y: focusY(3.4, 640) },
  { f: 592, s: 3.7, x: centers.trash, y: focusY(3.7, 640) },
  // 硬切 Chrome（卡片在上方）
  { f: 593, s: 2.6, x: centers.chrome, y: focusY(2.6, 800) },
  { f: 620, s: 3.0, x: centers.chrome, y: focusY(3.0, 790) },
  { f: 732, s: 3.0, x: centers.chrome, y: focusY(3.0, 790) },
  // 平移到聊天圖示
  { f: 752, s: 3.0, x: centers.chat, y: focusY(3.0, 760) },
  { f: 830, s: 3.1, x: centers.chat, y: focusY(3.1, 760) },
];
const camAt = (f: number) => {
  let i = 0;
  while (i < CAM.length - 1 && CAM[i + 1].f <= f) i++;
  const a = CAM[i];
  const b = CAM[Math.min(i + 1, CAM.length - 1)];
  if (a === b || f <= a.f) return a;
  const t = ease(Math.min(1, (f - a.f) / (b.f - a.f)));
  return { f, s: a.s + (b.s - a.s) * t, x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
};
const toScreen = (c: Cam, x: number, y: number) => ({ x: W / 2 + (x - c.x) * c.s, y: H / 2 + (y - c.y) * c.s });

// ---------- 圖示 ----------
const trackOf = (name: string) => spec.tracks.find((t) => t.name === name)!;
const trackLen = (name: string) => trackOf(name).segments.reduce((a, s) => a + s.n, 0);
const frameSrc = (name: string, i: number) => staticFile(`gen/${name}/${String(i).padStart(4, "0")}.png`);

// 第一個帶紅點的影格（紅點畫在圖示外，遮罩要另外留一個圓）
const attnFrom = (name: string) => {
  let i = 0;
  for (const seg of trackOf(name).segments) {
    if ((seg as { attn?: number }).attn) return i;
    i += seg.n;
  }
  return Infinity;
};
const TrackIcon: React.FC<{ name: string; plain: string; f: number; size: number }> = ({ name, plain, f, size }) => {
  const t = trackOf(name);
  const local = f - t.start;
  const plainImg = <Img src={staticFile(`gen/plain/${plain}.png`)} style={{ position: "absolute", inset: 0, width: size, height: size }} />;
  if (local < 0) return <div style={{ position: "relative", width: size, height: size }}>{plainImg}</div>;
  const idx = Math.min(local, trackLen(name) - 1);
  const masks = [`url(${staticFile(`gen/mask/${plain}.png`)})`];
  if (idx >= attnFrom(name)) masks.push("radial-gradient(circle at 84% 16%, #000 13.2%, transparent 13.6%)");
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      {plainImg}
      <Img
        src={frameSrc(name, idx)}
        style={{
          position: "absolute",
          inset: 0,
          width: size,
          height: size,
          maskImage: masks.join(", "),
          WebkitMaskImage: masks.join(", "),
          maskSize: "100% 100%",
          WebkitMaskSize: "100% 100%",
        }}
      />
    </div>
  );
};

// 自己畫的填充圖示（不用任何真實 app 的圖示）
const DrawnIcon: React.FC<{ kind: Drawn; size: number }> = ({ kind, size }) => {
  const inner = size * 0.805; // 圖示本體佔 512 畫布的 412
  const bg: Record<Drawn, string> = {
    chat: "linear-gradient(180deg,#6be37a,#21b53c)",
    notes: "linear-gradient(180deg,#fff7d1,#f3e3a0)",
    music: "linear-gradient(180deg,#ff6b81,#e5254a)",
    mail: "linear-gradient(180deg,#5fb8ff,#1a74f0)",
    photos: "linear-gradient(180deg,#fafafa,#e7e7ea)",
  };
  const glyph: Record<Drawn, React.ReactNode> = {
    chat: (
      <svg viewBox="0 0 100 100" width="62%" height="62%">
        <path d="M50 16c-22 0-38 13-38 30 0 10 6 19 15 24l-3 13 14-8c4 1 8 1 12 1 22 0 38-13 38-30S72 16 50 16z" fill="#fff" />
      </svg>
    ),
    notes: (
      <svg viewBox="0 0 100 100" width="70%" height="70%">
        {[34, 50, 66].map((y) => (
          <rect key={y} x="18" y={y} width="64" height="4" rx="2" fill="#c9b56a" />
        ))}
        <rect x="18" y="16" width="64" height="8" rx="3" fill="#f2b632" />
      </svg>
    ),
    music: (
      <svg viewBox="0 0 100 100" width="58%" height="58%">
        <path d="M40 22l38-8v52a11 9 0 1 1-6-8V30l-26 6v38a11 9 0 1 1-6-8z" fill="#fff" />
      </svg>
    ),
    mail: (
      <svg viewBox="0 0 100 100" width="66%" height="66%">
        <rect x="14" y="26" width="72" height="50" rx="6" fill="#fff" />
        <path d="M16 30l34 26 34-26" stroke="#1a74f0" strokeWidth="5" fill="none" />
      </svg>
    ),
    photos: (
      <svg viewBox="0 0 100 100" width="76%" height="76%">
        {["#f5a623", "#f8e71c", "#7ed321", "#50e3c2", "#4a90e2", "#9013fe", "#e5254a", "#ff6b81"].map((c, i) => (
          <ellipse key={c} cx="50" cy="31" rx="10" ry="19" fill={c} opacity="0.85" transform={`rotate(${i * 45} 50 50)`} />
        ))}
      </svg>
    ),
  };
  return (
    <div style={{ width: size, height: size, display: "flex", alignItems: "center", justifyContent: "center" }}>
      {/* 用真圖示的輪廓當遮罩，圓角跟 macOS 圖示一致 */}
      <div style={{ width: size, height: size, filter: `drop-shadow(0 ${size * 0.015}px ${size * 0.025}px rgba(0,0,0,0.35))` }}>
        <div
          style={{
            width: size,
            height: size,
            background: bg[kind],
            maskImage: `url(${staticFile("gen/mask/claude.png")})`,
            WebkitMaskImage: `url(${staticFile("gen/mask/claude.png")})`,
            maskSize: "100% 100%",
            WebkitMaskSize: "100% 100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div style={{ width: inner, height: inner, display: "flex", alignItems: "center", justifyContent: "center" }}>{glyph[kind]}</div>
        </div>
      </div>
    </div>
  );
};

// ---------- 字幕 ----------
const Caption: React.FC<{ f: number; from: number; to: number; children: React.ReactNode; y?: number; size?: number }> = ({
  f,
  from,
  to,
  children,
  y = 120,
  size = 76,
}) => {
  if (f < from - 1 || f > to + 1) return null;
  const inT = ease(Math.min(1, Math.max(0, (f - from) / 16)));
  const outT = ease(Math.min(1, Math.max(0, (to - f) / 12)));
  const o = Math.min(inT, outT);
  return (
    <div
      style={{
        position: "absolute",
        top: y,
        left: 0,
        width: W,
        textAlign: "center",
        fontFamily: FONT,
        fontWeight: 700,
        fontSize: size,
        letterSpacing: "-0.025em",
        color: "#f5f5f7",
        opacity: o,
        transform: `translateY(${(1 - inT) * 24}px)`,
      }}
    >
      {children}
    </div>
  );
};
const Dim: React.FC<{ children: React.ReactNode }> = ({ children }) => <span style={{ color: "#86868b" }}>{children}</span>;

// macOS 指標
const Cursor: React.FC<{ x: number; y: number; o: number }> = ({ x, y, o }) => (
  <svg width="34" height="48" viewBox="0 0 17 24" style={{ position: "absolute", left: x, top: y, opacity: o }}>
    <path d="M1 1v19l5-5 3.5 8 3-1.3L9 14h7z" fill="#000" stroke="#fff" strokeWidth="1.3" strokeLinejoin="round" />
  </svg>
);

// 懸停卡片：從圖示上方淡入
const HoverCard: React.FC<{ src: string; w: number; h: number; cx: number; bottom: number; f: number; from: number; to: number }> = ({
  src,
  w,
  h,
  cx,
  bottom,
  f,
  from,
  to,
}) => {
  if (f < from || f > to) return null;
  const a = ease(Math.min(1, (f - from) / 10));
  const b = ease(Math.min(1, (to - f) / 8));
  const o = Math.min(a, b);
  return (
    <div
      style={{
        position: "absolute",
        left: cx - w / 2,
        top: bottom - h,
        width: w,
        height: h,
        opacity: o,
        transform: `scale(${0.94 + 0.06 * a})`,
        transformOrigin: "50% 100%",
        borderRadius: 22,
        background: "rgba(44,44,46,0.92)",
        boxShadow: "0 18px 40px rgba(0,0,0,0.55), inset 0 0 0 1px rgba(255,255,255,0.08)",
      }}
    >
      <Img src={staticFile(src)} style={{ width: w, height: h, display: "block" }} />
    </div>
  );
};

// ---------- 場景 ----------
const DockScene: React.FC<{ f: number }> = ({ f }) => {
  const cam = camAt(f);
  const rise = ease(Math.min(1, Math.max(0, (f - 6) / 40)));
  const fadeOut = 1 - ease(Math.min(1, Math.max(0, (f - 790) / 16)));
  if (fadeOut <= 0) return null;

  const chromeS = toScreen(cam, centers.chrome, ICON_Y - D * 0.4025);
  const chatS = toScreen(cam, centers.chat, ICON_Y - D * 0.4025);
  const chatC = toScreen(cam, centers.chat, ICON_Y);
  const chromeC = toScreen(cam, centers.chrome, ICON_Y);

  // 指標：從右邊滑到 Chrome，再滑到聊天圖示
  let cur: { x: number; y: number; o: number } | null = null;
  if (f >= 612 && f < 820) {
    const p1 = ease(Math.min(1, Math.max(0, (f - 612) / 22)));
    const p2 = ease(Math.min(1, Math.max(0, (f - 732) / 20)));
    const off = D * cam.s * 0.22;
    const ax = chromeC.x + off * 3, ay = chromeC.y + off * 1.5;
    const bx = chromeC.x + off, by = chromeC.y + off;
    const cx = chatC.x + off, cy = chatC.y + off;
    const x = ax + (bx - ax) * p1 + (cx - bx) * p2;
    const y = ay + (by - ay) * p1 + (cy - by) * p2;
    cur = { x, y, o: Math.min(1, (f - 612) / 8) };
  }

  return (
    <AbsoluteFill style={{ opacity: fadeOut }}>
      <AbsoluteFill
        style={{
          transform: `translate(${W / 2}px, ${H / 2}px) scale(${cam.s}) translate(${-cam.x}px, ${-cam.y}px) translateY(${(1 - rise) * 220}px)`,
          transformOrigin: "0 0",
          opacity: rise,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: DOCK_X,
            top: DOCK_Y,
            width: DOCK_W,
            height: DOCK_H,
            borderRadius: 30,
            background: "rgba(255,255,255,0.10)",
            border: "1px solid rgba(255,255,255,0.18)",
            boxShadow: "0 30px 80px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.12)",
          }}
        />
        {SLOTS.map((s) => {
          const cx = centers[s.id];
          if (s.id === "divider")
            return (
              <div
                key="div"
                style={{ position: "absolute", left: cx - 0.5, top: DOCK_Y + PAD + 14, width: 1, height: D - 28, background: "rgba(255,255,255,0.25)" }}
              />
            );
          const slot = s as Exclude<Slot, { id: "divider" }>;
          return (
            <div key={slot.id} style={{ position: "absolute", left: cx - D / 2, top: ICON_Y - D / 2, width: D, height: D }}>
              {slot.track ? <TrackIcon name={slot.track} plain={slot.plain!} f={f} size={D} /> : <DrawnIcon kind={slot.drawn!} size={D} />}
              {slot.running && (
                <div style={{ position: "absolute", left: D / 2 - 2.5, top: D + 6, width: 5, height: 5, borderRadius: 3, background: "rgba(255,255,255,0.7)" }} />
              )}
            </div>
          );
        })}
      </AbsoluteFill>

      <HoverCard src="gen/top.png" w={496} h={364} cx={chromeS.x} bottom={chromeS.y - 22} f={f} from={640} to={728} />
      <HoverCard src="gen/note.png" w={520} h={130} cx={chatS.x} bottom={chatS.y - 22} f={f} from={755} to={812} />
      {cur && <Cursor {...cur} />}
    </AbsoluteFill>
  );
};

const STYLES = ["ascii", "liquid", "dots", "ring"];
const STYLE_START = 802;
const STYLE_EACH = 35;
const StyleScene: React.FC<{ f: number; labels: string[] }> = ({ f, labels }) => {
  if (f < STYLE_START || f > 945) return null;
  const local = f - STYLE_START;
  const inO = ease(Math.min(1, local / 18));
  const outO = 1 - ease(Math.min(1, Math.max(0, (f - 926) / 16)));
  const active = Math.min(3, Math.floor(local / STYLE_EACH));
  const size = 560;
  return (
    <AbsoluteFill style={{ opacity: Math.min(inO, outO) }}>
      <div style={{ position: "absolute", left: (W - size) / 2, top: 300, width: size, height: size, transform: `scale(${0.92 + 0.08 * inO})` }}>
        {STYLES.map((st, i) => {
          const into = i === 0 ? 1 : ease(Math.min(1, Math.max(0, (local - i * STYLE_EACH) / 8)));
          if (into <= 0) return null;
          const idx = Math.min(local, 139);
          return (
            <Img
              key={st}
              src={frameSrc(`style-${st}`, idx)}
              style={{
                position: "absolute",
                inset: 0,
                width: size,
                height: size,
                opacity: into,
                maskImage: `url(${staticFile("gen/mask/claude.png")})`,
                WebkitMaskImage: `url(${staticFile("gen/mask/claude.png")})`,
                maskSize: "100% 100%",
                WebkitMaskSize: "100% 100%",
              }}
            />
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          top: 880,
          width: W,
          display: "flex",
          justifyContent: "center",
          gap: 56,
          fontFamily: FONT,
          fontWeight: 600,
          fontSize: 36,
          letterSpacing: "0.01em",
        }}
      >
        {STYLES.map((st, i) => (
          <span key={st} style={{ color: i === active ? "#f5f5f7" : "rgba(245,245,247,0.28)" }}>
            {labels[i]}
          </span>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const Words: React.FC<{ f: number; words: string[] }> = ({ f, words }) => {
  if (f < 938 || f > 1014) return null;
  const out = 1 - ease(Math.min(1, Math.max(0, (f - 1000) / 12)));
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: out }}>
      <div style={{ display: "flex", gap: 44, fontFamily: FONT, fontWeight: 700, fontSize: 128, letterSpacing: "-0.03em", color: "#f5f5f7" }}>
        {words.map((w, i) => {
          const t = ease(Math.min(1, Math.max(0, (f - 941 - i * 17.4) / 10)));
          return (
            <span key={w} style={{ opacity: t, transform: `translateY(${(1 - t) * 30}px)`, color: i === 2 ? "#f5f5f7" : "#a1a1a6" }}>
              {w}
            </span>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC<{ f: number; tagline: string }> = ({ f, tagline }) => {
  if (f < 1011) return null;
  const a = ease(Math.min(1, (f - 1011) / 22));
  const b = ease(Math.min(1, Math.max(0, (f - 1028) / 18)));
  const c = ease(Math.min(1, Math.max(0, (f - 1046) / 18)));
  return (
    <AbsoluteFill style={{ alignItems: "center", fontFamily: FONT, color: "#f5f5f7" }}>
      <Img
        src={staticFile("gen/appicon.png")}
        style={{ position: "absolute", top: 190, width: 300, height: 300, opacity: a, transform: `scale(${0.85 + 0.15 * a})` }}
      />
      <div style={{ position: "absolute", top: 520, fontSize: 104, fontWeight: 700, letterSpacing: "-0.03em", opacity: b, transform: `translateY(${(1 - b) * 20}px)` }}>
        Dock Usage
      </div>
      <div style={{ position: "absolute", top: 660, fontSize: 48, fontWeight: 600, color: "#a1a1a6", letterSpacing: "-0.01em", opacity: c }}>
        {tagline}
      </div>
      <div style={{ position: "absolute", top: 820, fontSize: 32, fontWeight: 500, color: "#6e6e73", letterSpacing: "0.01em", opacity: c }}>
        dockusage.dorara.app
      </div>
    </AbsoluteFill>
  );
};


// ---------- 聲音 ----------
// 配樂：Mixkit「Coffee or Tea」103.36 BPM，鼓在曲子 9.474s 進來；從 5.974s 開始放，讓鼓落在第 105 格（BAR 0）
const MUSIC_FROM = Math.round(5.974 * 30);
const beat = (k: number) => Math.round(105 + k * 17.415); // 第 k 拍（從 BAR 0 算）
type Cue = { at: number; src: string; vol: number };
const sweep = (peakAt: number, vol = 0.32): Cue => ({ at: peakAt - 9, src: "sfx-small-sweep.wav", vol }); // 峰值在 0.30s
const ticks = (from: number, to: number, vol = 0.16): Cue[] => {
  const out: Cue[] = [];
  for (let k = 0; k < 64; k++) {
    const at = beat(k);
    if (at >= from && at <= to) out.push({ at, src: "sfx-click-tone.wav", vol: vol * (0.7 + 0.3 * ((at - from) / Math.max(1, to - from))) });
  }
  return out;
};
const CUES: Cue[] = [
  { at: 40 - 22, src: "sfx-air-woosh.wav", vol: 0.42 }, // Dock 升起，峰值 0.72s 落在到位那格
  sweep(118),
  ...ticks(130, 220),
  sweep(256, 0.26),
  ...ticks(250, 325, 0.13),
  { at: 330, src: "sfx-negative-tap.wav", vol: 0.3 }, // 過 80% 變紅
  sweep(392, 0.24),
  { at: 388, src: "sfx-long-pop.wav", vol: 0.5 }, // 紅點
  sweep(453, 0.28),
  ...ticks(460, 520, 0.13),
  sweep(523, 0.28),
  ...ticks(528, 588, 0.13),
  sweep(593, 0.26),
  ...ticks(600, 680, 0.12),
  { at: 640, src: "sfx-device-click.wav", vol: 0.22 }, // 熱門網站卡
  sweep(742, 0.22),
  { at: 755, src: "sfx-device-click.wav", vol: 0.22 }, // 通知卡
  ...[837, 872, 907].map((f): Cue => ({ at: f - 13, src: "sfx-short-sweep.wav", vol: 0.42 })), // 樣式切換，峰值 0.45s
  ...[0, 1, 2].map((i): Cue => ({ at: Math.round(941 + i * 17.4), src: "sfx-light-pop.wav", vol: 0.26 })),
  { at: 1011, src: "sfx-interface-start.wav", vol: 0.4 }, // 片尾圖示
];
const Soundtrack: React.FC = () => (
  <>
    <Audio
      src={staticFile("audio/music-coffee-or-tea.mp3")}
      startFrom={MUSIC_FROM}
      volume={(f) =>
        0.62 *
        interpolate(f, [0, 12], [0, 1], { extrapolateRight: "clamp" }) *
        interpolate(f, [1070, 1139], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.in(Easing.quad) })
      }
    />
    {CUES.map((c, i) => (
      <Sequence key={i} from={Math.max(0, c.at)} durationInFrames={120} layout="none">
        <Audio src={staticFile(`audio/${c.src}`)} volume={c.vol} />
      </Sequence>
    ))}
  </>
);

type Lang = "en" | "zh";
const CAPTIONS = [[18, 100], [120, 238], [258, 378], [392, 448], [462, 517], [532, 587], [605, 726], [740, 798], [812, 935]];
// [主句, 灰色後半, 後半是否紅字]
const T: Record<Lang, { captions: [string, string, boolean?][]; words: string[]; tagline: string; styles: string[] }> = {
  en: {
    captions: [
      ["Your Dock already knows ", "where to look."],
      ["Your AI limits, ", "on the icon."],
      ["Past 80%, ", "it turns red.", true],
      ["Sessions ", "waiting for you."],
      ["Disk space, ", "at a glance."],
      ["The Trash, ", "filling up."],
      ["Where today ", "went."],
      ["The last message, ", "on hover."],
      ["Four looks.", ""],
    ],
    words: ["Private.", "Local.", "Free."],
    tagline: "Your Dock, alive.",
    styles: ["ASCII", "Liquid", "LED", "Glow"],
  },
  zh: {
    captions: [
      ["你每天都在看 Dock，", "讓它多說一點。"],
      ["AI 額度，", "直接畫在圖示上。"],
      ["過了 80%，", "整個變紅。", true],
      ["有對話", "在等你回。"],
      ["磁碟空間，", "一眼就知道。"],
      ["垃圾桶", "滿到哪了。"],
      ["今天的時間，", "花去哪了。"],
      ["最新一則通知，", "游標停上去就有。"],
      ["四種樣子。", ""],
    ],
    words: ["不連網", "存本機", "免費"],
    tagline: "讓 Dock 活起來。",
    styles: ["ASCII", "液體", "LED 點陣", "光邊"],
  },
};

export const Intro: React.FC<{ lang?: Lang; noCaptions?: boolean }> = ({ lang = "en", noCaptions = false }) => {
  const f = useCurrentFrame();
  const glow = interpolate(f, [0, 60], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <AbsoluteFill
        style={{
          opacity: glow,
          background: "radial-gradient(ellipse 70% 55% at 50% 100%, rgba(70,80,140,0.35), rgba(20,20,35,0.15) 55%, rgba(0,0,0,0) 80%)",
        }}
      />
      <DockScene f={f} />

      {!noCaptions &&
        CAPTIONS.map(([from, to], i) => {
          const [a, b, red] = T[lang].captions[i];
          return (
            <Caption key={i} f={f} from={from} to={to}>
              {a}
              {b && (red ? <span style={{ color: "#ff453a" }}>{b}</span> : <Dim>{b}</Dim>)}
            </Caption>
          );
        })}

      <StyleScene f={f} labels={T[lang].styles} />
      <Words f={f} words={T[lang].words} />
      <EndCard f={f} tagline={T[lang].tagline} />
      <Soundtrack />
    </AbsoluteFill>
  );
};
