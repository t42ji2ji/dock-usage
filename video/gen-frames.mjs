// 用 app 的 CLI 產生每條 track 的透明 PNG 序列 → public/gen/<track>/0000.png…
// 只用假資料指令（--frames / --fake-top / --fake-note / --appicon），不讀任何真實紀錄
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, renameSync, readdirSync } from "node:fs";
import { join } from "node:path";
import spec from "./src/tracks.json" with { type: "json" };

const BIN = new URL("../.build/release/UsageMeter", import.meta.url).pathname;
const OUT = "public/gen";
const run = (...a) => execFileSync(BIN, a.map(String), { stdio: "inherit" });

for (const t of spec.tracks) {
  const dir = join(OUT, t.name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  let idx = 0;
  for (const s of t.segments) {
    const tmp = join(OUT, `_tmp`);
    rmSync(tmp, { recursive: true, force: true });
    // --phase0：波浪 phase 接著這條 track 已經輸出的影格數走，段落接縫不會跳
    const args = ["--frames", t.kind, t.style, s.from, s.to, s.n, tmp, t.size, "--phase0", idx];
    if (s.attn) args.push("--attn", s.attn);
    if (t.label) args.push("--label", t.label);
    run(...args);
    for (const f of readdirSync(tmp).sort()) {
      renameSync(join(tmp, f), join(dir, String(idx++).padStart(4, "0") + ".png"));
    }
    rmSync(tmp, { recursive: true, force: true });
  }
  console.log(t.name, idx);
}
run("--fake-top", join(OUT, "top.png"));
run("--fake-note", join(OUT, "note.png"));
run("--appicon", join(OUT, "appicon.png"), 1024);
mkdirSync(join(OUT, "plain"), { recursive: true });
execFileSync("swift", ["plain-icons.swift", join(OUT, "plain"), 768], { stdio: "inherit" });
// 圖示輪廓遮罩：CLI 的疊層角落比圖示方，用原圖示的不透明區把它裁成同一個形狀
mkdirSync(join(OUT, "mask"), { recursive: true });
for (const f of readdirSync(join(OUT, "plain"))) {
  execFileSync("magick", [join(OUT, "plain", f), "-alpha", "extract", "-threshold", "50%", "-blur", "0x0.7", "-background", "white", "-alpha", "shape", join(OUT, "mask", f)]);
}
