import Cocoa
import ServiceManagement

// MARK: - Kind（同一支執行檔，靠 Info.plist 的 MeterKind 分成 Claude / GPT 兩個 app）

enum Kind: String {
    case claude, gpt, finder, trash

    var appPaths: [String] {
        switch self {
        case .claude: return ["/Applications/Claude.app"]
        case .gpt: return ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        case .finder: return ["/System/Library/CoreServices/Finder.app"]
        case .trash: return ["trash"]          // dockItems() 用這個名字記垃圾桶
        }
    }
    /// Finder／垃圾桶：顯示硬碟用量，畫得比 AI 用量淡
    var isDisk: Bool { self == .finder || self == .trash }
    var icon: NSImage? {
        // Dock 自己畫的垃圾桶比系統圖示小一圈，優先用 Dock 的素材
        if self == .trash { return NSImage(contentsOfFile: "/System/Library/CoreServices/Dock.app/Contents/Resources/s-trashfull-background@2x.png") ?? NSImage(named: NSImage.trashFullName) }
        return appPaths.first { FileManager.default.fileExists(atPath: $0) }.map { NSWorkspace.shared.icon(forFile: $0) }
    }
    var tint: NSColor {
        switch self {
        case .claude: return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // #D97757
        case .gpt: return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)     // #10A37F
        case .finder, .trash: return NSColor(srgbRed: 0.25, green: 0.60, blue: 1.00, alpha: 1)
        }
    }
}

// MARK: - Data

struct Window: Equatable {
    var pct: Double       // 0...100
    var resetsAt: Date?
}

struct Usage: Equatable {
    var short: Window?    // 5 小時
    var long: Window?     // 7 天
    var updated: Date?
}

/// 已經過了重置時間的視窗，舊數字不算數，當作歸零。
func fresh(_ w: Window?) -> Window? {
    guard var w else { return nil }
    if let r = w.resetsAt, r < Date() { w.pct = 0; w.resetsAt = nil }
    return w
}

func date(_ v: Any?) -> Date? {
    if let n = v as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
    if let n = v as? Int { return Date(timeIntervalSince1970: Double(n)) }
    if let s = v as? String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    return nil
}

func window(_ v: Any?, pctKey: String) -> Window? {
    guard let d = v as? [String: Any], let p = d[pctKey] as? Double ?? (d[pctKey] as? Int).map(Double.init) else { return nil }
    return Window(pct: p, resetsAt: date(d["resets_at"]))
}

let home = FileManager.default.homeDirectoryForCurrentUser

/// Claude：Claude Code 狀態列腳本寫出的 rate_limits（~/.claude/dock-usage/claude.json）
func loadClaude() -> Usage {
    let url = home.appendingPathComponent(".claude/dock-usage/claude.json")
    guard let data = try? Data(contentsOf: url),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Usage() }
    let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    return Usage(short: window(j["five_hour"], pctKey: "used_percentage"),
                 long: window(j["seven_day"], pctKey: "used_percentage"),
                 updated: mtime)
}

/// Codex：最新一份 session 紀錄裡最後一筆 rate_limits
func loadCodex() -> Usage {
    let root = home.appendingPathComponent(".codex/sessions")
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return Usage() }
    var newest: (URL, Date)?
    for case let u as URL in en where u.pathExtension == "jsonl" {
        let m = (try? u.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
        if newest == nil || m > newest!.1 { newest = (u, m) }
    }
    guard let (file, mtime) = newest, let fh = try? FileHandle(forReadingFrom: file) else { return Usage() }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    try? fh.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
    guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return Usage() }
    for line in text.split(separator: "\n").reversed() where line.contains("\"used_percent\"") {
        guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let rl = (j["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { continue }
        return Usage(short: window(rl["primary"], pctKey: "used_percent"),
                     long: window(rl["secondary"], pctKey: "used_percent"),
                     updated: mtime)
    }
    return Usage()
}

// MARK: - Icon render

/// 字元排版很貴（每格 2ms）：同字元、同顏色、同尺寸只排一次，存成點陣圖再貼
var glyphCache: [String: CGImage] = [:]
func glyphImage(_ ch: Character, _ color: NSColor, _ font: NSFont, _ cell: CGFloat, _ key: String) -> CGImage {
    let k = "\(ch)|\(key)|\(Int(cell * 100))"
    if let img = glyphCache[k] { return img }
    let px = max(Int((cell * 2).rounded(.up)), 1)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: cell, height: cell)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let str = NSAttributedString(string: String(ch), attributes: [.font: font, .foregroundColor: color])
    let sz = str.size()
    str.draw(at: NSPoint(x: cell / 2 - sz.width / 2, y: cell / 2 - sz.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    let img = rep.cgImage!
    if glyphCache.count > 4000 { glyphCache.removeAll() }
    glyphCache[k] = img
    return img
}

var maskCache: [Kind: CGImage] = [:]
var maskBox: [Kind: CGRect] = [:]   // 圖示實際形狀的外框（0...1，左下原點）
/// 原 app 圖示的 alpha 轉成灰階遮罩（256px），裁切用
func iconMask(_ kind: Kind) -> CGImage? {
    if let m = maskCache[kind] { return m }
    guard let icon = kind.icon else { return nil }
    let n = 256
    let rgba = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rgba)
    icon.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
    NSGraphicsContext.restoreGraphicsState()
    guard let src = rgba.bitmapData else { return nil }
    var gray = [UInt8](repeating: 0, count: n * n)
    // 垃圾桶是半透明玻璃：alpha 放大 4 倍，桶身才會整片蓋滿
    var minX = n, minY = n, maxX = 0, maxY = 0
    for i in 0..<(n * n) {
        let v = min(255, Int(src[(i / n) * rgba.bytesPerRow + (i % n) * 4 + 3]) * 4)
        gray[i] = UInt8(v)
        if v > 128 { minX = min(minX, i % n); maxX = max(maxX, i % n); minY = min(minY, i / n); maxY = max(maxY, i / n) }
    }
    if maxX > minX { maskBox[kind] = CGRect(x: CGFloat(minX) / CGFloat(n), y: 1 - CGFloat(maxY + 1) / CGFloat(n), width: CGFloat(maxX - minX + 1) / CGFloat(n), height: CGFloat(maxY - minY + 1) / CGFloat(n)) }
    guard let provider = CGDataProvider(data: Data(gray) as CFData),
          let img = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
    maskCache[kind] = img
    return img
}

/// 原 app 圖示壓暗 + ASCII 字元格水位（5 小時）+ 兩側刻度（7 天）+ 百分比數字
func renderIcon(kind: Kind, base: NSImage?, short: Double?, long: Double?, phase: CGFloat, size: CGFloat = 512, showNumber: Bool = true, label: String? = nil) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size
        base?.draw(in: NSRect(x: 0, y: 0, width: s, height: s))

        // macOS 圖示格線：824/1024 的圓角方塊置中
        let inset = s * 100 / 1024
        var body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        // 不是圓角方塊的圖示（垃圾桶）：水位和字元格照它實際的外框
        if kind == .trash, iconMask(kind) != nil, let b = maskBox[kind] { body = NSRect(x: b.minX * s, y: b.minY * s, width: b.width * s, height: b.height * s) }

        guard let short else { return true }
        let p = CGFloat(min(max(short, 0), 100)) / 100
        let hot = short >= (kind.isDisk ? 90 : 80)      // 垃圾桶 27 樣以上轉紅
        let light: CGFloat = kind.isDisk ? 0.5 : 1      // 硬碟用量畫淡一點
        let color = hot ? NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1) : kind.tint

        NSGraphicsContext.saveGraphicsState()
        if let mask = iconMask(kind), let cg = NSGraphicsContext.current?.cgContext {
            // 用真實圖示的輪廓裁切（連續圓角），放大 3% 蓋住邊緣反光與半像素誤差
            let m = s * 0.015
            cg.clip(to: CGRect(x: -m, y: -m, width: s + m * 2, height: s + m * 2), mask: mask)
        } else {
            shape.addClip()
        }

        // 只有用掉的部分（水位以下）壓暗＋染色，上面維持原圖示：多少 % 就滿到多少；水面是流動的波浪
        let waterLevel = body.minY + body.height * p
        let amp = p > 0.01 && p < 0.99 ? s * 0.025 : 0
        func waveY(_ x: CGFloat, _ offset: CGFloat = 0, _ a: CGFloat? = nil, _ dir: CGFloat = 1) -> CGFloat {
            waterLevel + sin((x - body.minX) / body.width * .pi * 2 * 1.3 + phase * dir + offset) * (a ?? amp)
        }
        func wave(_ offset: CGFloat, _ a: CGFloat, _ dir: CGFloat = 1) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: body.minX - 2, y: body.minY - 2))
            var x = body.minX - 2
            while x <= body.maxX + 2 { path.line(to: NSPoint(x: x, y: waveY(x, offset, a, dir))); x += s / 64 }
            path.line(to: NSPoint(x: body.maxX + 2, y: body.minY - 2))
            path.close()
            return path
        }
        let back = wave(.pi * 0.7, amp, -0.7)          // 後層反向流，比前層高一點、淡一點
        let lift = NSAffineTransform(); lift.translateX(by: 0, yBy: s * 0.025); back.transform(using: lift as AffineTransform)
        NSColor.black.withAlphaComponent(0.20 * light).setFill()
        back.fill()
        color.withAlphaComponent(0.30).setFill()
        back.fill()
        let front = wave(0, amp)
        NSColor.black.withAlphaComponent(0.40 * light).setFill()
        front.fill()
        color.withAlphaComponent(0.22).setFill()
        front.fill()

        // ASCII 格子：用掉的部分由密字元填滿、隨機跳字＋白色閃光；水面那排淡字元翻騰；空的部分只留淡點
        let cols = 10
        let area = body
        let cell = area.width / CGFloat(cols)
        let tick = Int(phase * 4)                       // 每秒約 13 次換字
        let glyph = NSFont.monospacedSystemFont(ofSize: cell * 1.15, weight: .bold)
        func rnd(_ c: Int, _ r: Int, _ k: Int) -> CGFloat {
            var h = UInt64(truncatingIfNeeded: c &* 73856093 ^ r &* 19349663 ^ k &* 83492791)
            h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33
            return CGFloat(h % 10000) / 10000
        }
        let cg = NSGraphicsContext.current!.cgContext
        cg.saveGState()
        let dense = Array("@#%&*+=$"), surf = Array(".:-=~"), dim = Array(".:-+=")
        for r in 0..<cols {
            for c in 0..<cols {
                let rect = NSRect(x: area.minX + CGFloat(c) * cell, y: area.minY + CGFloat(r) * cell, width: cell, height: cell)
                let k = tick + (c * 7 + r * 13) % 5      // 每格換字的節拍錯開
                let x = rnd(c, r, k / 2)
                var ch: Character, col: NSColor, key: String, alpha: CGFloat
                let level = waveY(rect.midX)
                if rect.maxY <= level {
                    if rnd(c, r, tick &* 3 &+ 1) < 0.05 {
                        ch = "*"; col = .white; key = "w"; alpha = 0.7
                    } else {
                        ch = dense[Int(x * CGFloat(dense.count)) % dense.count]
                        let b = (rnd(c, r, k) * 4).rounded(.down) / 4          // 4 種亮度
                        col = color.blended(withFraction: 0.25 * b, of: .white)!; key = "d\(b)\(hot)\(kind)"
                        alpha = 0.6 + 0.3 * rnd(c, r, k + 9)
                    }
                } else if rect.minY < level {
                    ch = surf[Int(x * CGFloat(surf.count)) % surf.count]
                    col = color; key = "s\(hot)\(kind)"; alpha = 0.3 + 0.3 * rnd(c, r, tick)
                } else {
                    ch = dim[Int(x * CGFloat(dim.count)) % dim.count]
                    col = .white; key = "w"; alpha = 0.06 + 0.06 * rnd(c, r, k)
                }
                cg.setAlpha(alpha * (light < 1 ? 0.6 : 1))
                if rect.minY < level && rect.maxY > level {      // 水面那格只畫在波浪下
                    cg.saveGState(); front.addClip()
                    cg.draw(glyphImage(ch, col, glyph, cell, key), in: rect)
                    cg.restoreGState()
                } else {
                    cg.draw(glyphImage(ch, col, glyph, cell, key), in: rect)
                }
            }
        }

        cg.restoreGState()

        // 水面亮線
        let crest = NSBezierPath()
        var cx = body.minX - 2
        crest.move(to: NSPoint(x: cx, y: waveY(cx)))
        while cx <= body.maxX + 2 { cx += s / 64; crest.line(to: NSPoint(x: cx, y: waveY(cx))) }
        crest.lineWidth = s * 0.006
        NSColor.white.withAlphaComponent(amp > 0 ? 0.25 : 0).setStroke()
        crest.stroke()

        // 7 天刻度：兩側的小括號
        if let long {
            let y = area.minY + area.height * CGFloat(min(max(long, 0), 100)) / 100
            let w = body.width * 0.07, h = max(s * 0.025, 1)
            for x in [body.minX + body.width * 0.03, body.maxX - body.width * 0.03 - w] {
                let r = NSRect(x: x, y: y - h / 2, width: w, height: h)
                NSColor.black.withAlphaComponent(0.6).setFill()
                r.insetBy(dx: -s * 0.008, dy: -s * 0.008).fill()
                NSColor.white.setFill()
                r.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard showNumber, kind != .trash else { return true }   // 垃圾桶只用水位表示東西多不多，不寫數字
        // 數字（等寬）
        let num = label ?? "\(Int(short.rounded()))"
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = s * 0.03
        let font = NSFont.monospacedSystemFont(ofSize: s * 0.26, weight: .heavy)
        let str = NSMutableAttributedString(string: num, attributes: [.font: font, .foregroundColor: NSColor.white, .shadow: shadow])
        if label == nil { str.append(NSAttributedString(string: "%", attributes: [.font: NSFont.monospacedSystemFont(ofSize: s * 0.12, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: shadow])) }
        let sz = str.size()
        str.draw(at: NSPoint(x: body.midX - sz.width / 2, y: body.midY - sz.height / 2))
        return true
    }
}

// MARK: - Dock 位置

let dockPID: pid_t? = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier

func ax(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}

/// Dock 裡每個項目：app 檔名 → AX 元素
func dockItems() -> [String: AXUIElement] {
    guard let pid = dockPID else { return [:] }
    var out: [String: AXUIElement] = [:]
    for list in ax(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        for item in ax(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let url = ax(item, kAXURLAttribute) as? URL { out[url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path] = item }
            if ax(item, kAXSubroleAttribute) as? String == "AXTrashDockItem" { out["trash"] = item }
            if let t = ax(item, kAXTitleAttribute) as? String { out["title:" + t] = item }   // 通知用 app 名稱對應
        }
    }
    return out
}

/// 項目在螢幕上的框（AX 座標：主螢幕左上為原點）
func frame(of item: AXUIElement) -> CGRect? {
    var p = CGPoint.zero, sz = CGSize.zero
    guard let pv = ax(item, kAXPositionAttribute), let sv = ax(item, kAXSizeAttribute) else { return nil }
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &sz)
    return CGRect(origin: p, size: sz)
}

/// 自動隱藏收起時項目在螢幕外
func onScreen(_ r: CGRect) -> Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).contains { CGDisplayBounds($0).insetBy(dx: 1, dy: 1).intersects(r) }
}

let logURL = home.appendingPathComponent("Library/Logs/DockUsage.log")
func log(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

// MARK: - 疊在 Dock 圖示上的透明視窗

/// 一個固定不動、蓋住整個主螢幕的透明視窗，裡面每個圖示一個 layer。
/// 移動視窗 WindowServer 每秒只套用約 60 次，移動 layer 則每格都跟得上（2026-11-19 實測）。
final class Host {
    static let shared = Host()
    let window: NSWindow
    let root: CALayer
    init() {
        let frame = NSScreen.screens.first?.frame ?? .zero
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false   // app 被隱藏（例如背景啟動）時疊加層也要照常顯示
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(origin: .zero, size: frame.size))
        v.wantsLayer = true
        window.contentView = v
        root = v.layer!
    }
    func setVisible(_ on: Bool) {
        if on && !window.isVisible { window.setFrame(NSScreen.screens.first?.frame ?? .zero, display: false); window.orderFrontRegardless() }
        if !on && window.isVisible { window.orderOut(nil) }
    }
}

/// cmux 裡有未讀通知的 Claude 分頁數：右上角紅點＋數字；app 自己有 macOS 紅點時讓到左上角
func drawAttention(_ count: Int, size s: CGFloat, phase: CGFloat, left: Bool = false) {
    guard count > 0 else { return }
    let r = s * 0.13, c = NSPoint(x: left ? s * 0.16 : s * 0.84, y: s * 0.84)
    let pulse = 0.85 + 0.15 * sin(phase * 1.2)
    let dot = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    NSColor.white.withAlphaComponent(pulse).setFill(); dot.fill()
    let inner = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.84, y: c.y - r * 0.84, width: r * 1.68, height: r * 1.68))
    NSColor(srgbRed: 0.93, green: 0.16, blue: 0.20, alpha: pulse).setFill(); inner.fill()
    let str = NSAttributedString(string: count > 9 ? "9+" : "\(count)", attributes: [.font: NSFont.systemFont(ofSize: r * (count > 9 ? 0.95 : 1.25), weight: .bold), .foregroundColor: NSColor.white])
    let sz = str.size()
    str.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
}

/// 內容固定用 80pt（Dock 放大上限）畫成點陣圖；Dock 放大縮小時只改 layer 的框、GPU 縮放，不重畫
func renderImage(kind: Kind, level: Double?, tick: Double?, phase: CGFloat, attention: Int = 0, badgeLeft: Bool = false, label: String? = nil) -> CGImage? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 80, height: 80)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if level != nil { renderIcon(kind: kind, base: nil, short: level, long: tick, phase: phase, size: 80, label: label).draw(in: NSRect(x: 0, y: 0, width: 80, height: 80)) }
    drawAttention(attention, size: 80, phase: phase, left: badgeLeft)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

final class Overlay {
    let kind: Kind
    let layer = CALayer()
    var usage = Usage()
    var shown: Double = 0
    var item: AXUIElement?
    var lastTick = -1
    var prevRect: CGRect?
    static let lead = CGFloat(Double(ProcessInfo.processInfo.environment["DOCKUSAGE_LEAD"] ?? "") ?? 0.5)
    var lastLevel = 0.0
    var attention = 0
    var nativeBadge = false   // Dock 上這個 app 自己有紅點
    var lastAttention = 0
    var lastBadge = false

    init(kind: Kind) {
        self.kind = kind
        layer.contentsGravity = .resize
        layer.isHidden = true
        Host.shared.root.addSublayer(layer)
    }

    var primary: Window? { usage.short ?? usage.long }

    /// 每格：追 Dock 項目位置，水位往目標靠，換字時重畫
    func step(phase: CGFloat, dt: Double) -> Bool {
        let fake = ProcessInfo.processInfo.environment["DOCKUSAGE_FAKE"].map { v -> CGRect in
            let n = v.split(separator: ",").compactMap { Double($0) }
            let wobble = n.count > 4 ? sin(CACurrentMediaTime() * 6) * n[4] : 0   // 測試用：上下擺動
            return CGRect(x: n[0], y: n[1] + (kind == .gpt ? n[3] : 0) + wobble, width: n[2], height: n[3]) }
        guard let r = fake ?? item.flatMap(frame), fake != nil || onScreen(r), primary != nil || attention > 0 else {
            layer.isHidden = true
            prevRect = nil
            return false
        }
        // 讀到的位置要等下一格才畫得出來：照上一格的移動量往前推半格（大跳就不推，避免出現/消失時亂飛）
        var pr = r
        if let p = prevRect, abs(r.minY - p.minY) < 40, abs(r.height - p.height) < 20 {
            pr = CGRect(x: r.minX + (r.minX - p.minX) * Self.lead, y: r.minY + (r.minY - p.minY) * Self.lead,
                        width: r.width + (r.width - p.width) * Self.lead, height: r.height + (r.height - p.height) * Self.lead)
        }
        prevRect = r
        let to = primary?.pct ?? 0
        shown += (to - shown) * (1 - pow(0.88, dt * 30))
        if abs(to - shown) < 0.05 { shown = to }
        let t = Int(phase * (kind.isDisk ? 6 : 12))      // 約 38 次/秒重畫，波浪才順；字元仍約 13 次/秒換（硬碟的減半）
        if t != lastTick || abs(shown - lastLevel) > 0.01 || attention != lastAttention || nativeBadge != lastBadge {
            lastTick = t; lastLevel = shown; lastAttention = attention; lastBadge = nativeBadge
            layer.contents = renderImage(kind: kind, level: primary == nil ? nil : shown, tick: usage.short == nil ? nil : usage.long?.pct, phase: phase, attention: attention, badgeLeft: nativeBadge)
        }
        // 圖示在 Dock 項目框裡置中，邊長＝框的短邊減 2pt（tilesize 37 時框高 39；2026-11-19 校準截圖量過）
        // AX 座標左上為原點；host 視窗蓋住主螢幕，layer 座標左下為原點
        let screenH = Host.shared.window.frame.height
        let side = min(pr.width, pr.height) - 2
        layer.frame = CGRect(x: pr.midX - side / 2, y: screenH - pr.midY - side / 2, width: side, height: side)
        layer.isHidden = false
        return true
    }
}

// MARK: - 通知：記下每個 app 最新跳出的通知橫幅，滑鼠停在它的 Dock 圖示上時顯示

struct Note: Equatable { var title: String; var body: String }

/// 讀畫面上正在顯示的通知橫幅（用的是同一個輔助使用權限）。回傳 [app 名稱: 通知]
func visibleBanners() -> [String: Note] {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier else { return [:] }
    var out: [String: Note] = [:]
    func walk(_ e: AXUIElement, _ d: Int) {
        if ax(e, kAXSubroleAttribute) as? String == "AXNotificationCenterBanner" {
            let app = (ax(e, kAXDescriptionAttribute) as? String ?? "").components(separatedBy: ", ").first ?? ""
            var n = Note(title: "", body: "")
            for c in ax(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                let v = ax(c, kAXValueAttribute) as? String ?? ""
                switch ax(c, kAXIdentifierAttribute) as? String {
                case "title": n.title = v
                case "body": n.body = v
                default: break
                }
            }
            if !app.isEmpty, !(n.title.isEmpty && n.body.isEmpty) { out[app] = n }
            return
        }
        if d < 6 { for c in ax(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(c, d + 1) } }
    }
    for w in ax(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
    where ax(w, kAXSubroleAttribute) as? String == "AXSystemDialog" { walk(w, 0) }
    return out
}

func renderNote(_ app: String, _ n: Note) -> NSImage {
    let w: CGFloat = 260, pad: CGFloat = 10
    let s = NSMutableAttributedString(string: n.title.isEmpty ? app : n.title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
    if !n.body.isEmpty { s.append(NSAttributedString(string: "\n" + n.body, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])) }
    let maxH: CGFloat = 16 * 4 + 2
    let h = min(ceil(s.boundingRect(with: NSSize(width: w - pad * 2, height: 1000), options: [.usesLineFragmentOrigin]).height), maxH)
    return NSImage(size: NSSize(width: w, height: h + pad * 2), flipped: false) { r in
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        s.draw(with: NSRect(x: pad, y: pad, width: w - pad * 2, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        return true
    }
}

// MARK: - 硬碟

/// 垃圾桶裡有幾樣東西。列出內容要完整磁碟取用權，但資料夾本身的 stat 讀得到：
/// APFS 上資料夾的連結數＝裡面的項目數＋2
func trashCount() -> Int? {
    var st = stat()
    guard stat(NSHomeDirectory() + "/.Trash", &st) == 0 else { return nil }
    return max(0, Int(st.st_nlink) - 2)
}

func diskUsedPct() -> Double? {
    guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
          let total = v.volumeTotalCapacity, total > 0, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
    return 100 * (1 - Double(free) / Double(total))
}

// MARK: - cmux 通知

let cmuxCLI = "/Applications/cmux.app/Contents/Resources/bin/cmux"

func unreadClaudeTabs() -> Int {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmuxCLI)
    p.arguments = ["list-notifications", "--json"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return 0 }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    if p.terminationStatus != 0 { log("cmux list-notifications exit \(p.terminationStatus): \(String(data: data.prefix(200), encoding: .utf8) ?? "")") }
    guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
    let surfaces = list.filter { ($0["is_read"] as? Bool) == false && ($0["title"] as? String) == "Claude Code" }.compactMap { $0["surface_id"] as? String }
    return Set(surfaces).count
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlays = [Overlay(kind: .claude), Overlay(kind: .gpt), Overlay(kind: .finder), Overlay(kind: .trash)]
    var phase: CGFloat = 0
    var timer: Timer?
    var link: CADisplayLink?
    var fast = false
    var lastFrame = CACurrentMediaTime()
    var lastScan = Date.distantPast
    var notes: [String: Note] = [:]
    var lastTrash: Int?? = .none
    var titleItems: [String: AXUIElement] = [:]
    let noteLayer = CALayer()
    var shownNote: String?
    let queue = DispatchQueue(label: "dockusage.load", qos: .utility)

    func applicationDidFinishLaunching(_ n: Notification) {
        if !AXIsProcessTrusted() {
            // 讀 Dock 圖示位置要「輔助使用」權限；第一次會跳系統的授權視窗
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        // 第一次開啟時設成登入自動開；之後使用者關掉就尊重
        if !UserDefaults.standard.bool(forKey: "didSetLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetLoginItem")
            try? SMAppService.mainApp.register()
        }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        if FileManager.default.isExecutableFile(atPath: cmuxCLI) {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshAttention() }
        }
        schedule(fast: false)
        noteLayer.isHidden = true
        Host.shared.root.addSublayer(noteLayer)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            guard let self else { return }
            for (app, n) in visibleBanners() where self.notes[app] != n {
                self.notes[app] = n
                log("note from \(app) (dock item: \(self.titleItems["title:" + app] != nil))")
            }
        }
        // 打開那個 app 就算看過了
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let name = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName { self?.notes[name] = nil }
        }
    }

    /// 沒有任何介面：在 Finder 再開一次時，給一個能結束、能切換登入開啟的對話框
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        let a = NSAlert()
        a.messageText = zh ? "Dock Usage 正在執行" : "Dock Usage is running"
        a.informativeText = AXIsProcessTrusted()
            ? (zh ? "用量會疊在 Dock 裡的 Claude 和 ChatGPT 圖示上。" : "Usage is drawn on the Claude and ChatGPT icons in your Dock.")
            : (zh ? "需要在「系統設定 › 隱私權與安全性 › 輔助使用」允許 Dock Usage，才能找到 Dock 圖示的位置。" : "Allow Dock Usage in System Settings › Privacy & Security › Accessibility so it can find the icons in your Dock.")
        a.addButton(withTitle: zh ? "繼續執行" : "Keep Running")
        a.addButton(withTitle: zh ? "結束" : "Quit")
        let login = NSButton(checkboxWithTitle: zh ? "登入時開啟" : "Open at Login", target: nil, action: nil)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        a.accessoryView = login
        NSApp.activate()
        let r = a.runModal()
        if login.state == .on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        if r == .alertSecondButtonReturn { NSApp.terminate(nil) }
        return false
    }

    /// 跟 cmux 分頁上的紅點同一個來源：cmux 的通知（每回合結束、要權限、閒置等輸入），點進分頁才算讀過
    func refreshAttention() {
        queue.async {
            let n = unreadClaudeTabs()
            DispatchQueue.main.async {
                if n != self.overlays[0].attention { log("attention=\(n)") }
                self.overlays[0].attention = n
            }
        }
    }

    func refresh() {
        queue.async {
            let c = loadClaude(), g = loadCodex(), disk = diskUsedPct(), trash = trashCount()
            let fix = { (u: Usage) in Usage(short: fresh(u.short), long: fresh(u.long), updated: u.updated) }
            DispatchQueue.main.async {
                self.overlays[0].usage = fix(c)
                self.overlays[1].usage = fix(g)
                self.overlays[2].usage = disk.map { Usage(short: Window(pct: $0)) } ?? Usage()
                // 垃圾桶：裡面有幾樣東西，30 樣算滿；空的就不畫
                if trash != self.lastTrash { self.lastTrash = trash; log("trash items \(trash.map(String.init) ?? "nil")") }
                self.overlays[3].usage = trash.map { $0 > 0 ? Usage(short: Window(pct: min(Double($0), 30) / 30 * 100)) : Usage() } ?? Usage()
            }
        }
    }

    /// Dock 看得到時跟螢幕刷新同步（120Hz 螢幕就每秒 120 次）追位置和動畫；收起時每秒看 20 次
    func schedule(fast: Bool) {
        self.fast = fast
        timer?.invalidate(); timer = nil
        link?.invalidate(); link = nil
        if fast, let screen = NSScreen.main {
            link = screen.displayLink(target: self, selector: #selector(linkFired))
            link?.add(to: .main, forMode: .common)
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.frameTick() }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }
    var ticks = 0, tickWindow = CACurrentMediaTime()
    @objc func linkFired() {
        let a = CACurrentMediaTime()
        frameTick()
        ticks += 1
        tickCost += CACurrentMediaTime() - a
        if a - tickWindow > 2, ProcessInfo.processInfo.environment["DOCKUSAGE_FAKE"] != nil {
            log(String(format: "ticks/s %.1f  avg tick %.2fms", Double(ticks) / (a - tickWindow), tickCost / Double(ticks) * 1000))
            ticks = 0; tickCost = 0; tickWindow = a
        }
    }
    var tickCost = 0.0

    /// 滑鼠停在有通知的 Dock 圖示上：在圖示旁邊顯示最新一則（避開 Dock 自己的名稱標籤）
    func hoverNote(visible: Bool) {
        let m = NSEvent.mouseLocation
        let screenH = Host.shared.window.frame.height
        var hit: (String, CGRect)?
        if visible {
            for name in notes.keys {
                guard let item = titleItems["title:" + name], let r = frame(of: item) else { continue }
                let f = CGRect(x: r.minX, y: screenH - r.maxY, width: r.width, height: r.height)
                if f.contains(m) { hit = (name, f); break }
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let (name, f) = hit, let n = notes[name] else { noteLayer.isHidden = true; shownNote = nil; return }
        if shownNote != name + n.title + n.body {
            shownNote = name + n.title + n.body
            let img = renderNote(name, n)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width * 2), pixelsHigh: Int(img.size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = img.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(origin: .zero, size: img.size))
            NSGraphicsContext.restoreGraphicsState()
            noteLayer.contents = rep.cgImage
            noteLayer.bounds = CGRect(origin: .zero, size: img.size)
        }
        let size = noteLayer.bounds.size
        let screenW = Host.shared.window.frame.width
        // Dock 在左：放右邊、名稱標籤下方；在右：放左邊；在下：放上方、名稱標籤上面
        let origin: CGPoint
        if f.midX < screenW / 3 { origin = CGPoint(x: f.maxX + 6, y: f.midY - 16 - size.height) }
        else if f.midX > screenW * 2 / 3 { origin = CGPoint(x: f.minX - 6 - size.width, y: f.midY - 16 - size.height) }
        else { origin = CGPoint(x: min(max(f.midX - size.width / 2, 8), screenW - size.width - 8), y: f.maxY + 34) }
        noteLayer.frame = CGRect(origin: origin, size: size)
        noteLayer.isHidden = false
    }

    var lastTrusted: Bool?
    func frameTick() {
        let t = AXIsProcessTrusted()
        if t != lastTrusted { lastTrusted = t; log("trusted=\(t)") }
        guard t else { return }
        if Date().timeIntervalSince(lastScan) > 2 || overlays.contains(where: { $0.item == nil && Date().timeIntervalSince(lastScan) > 0.5 }) {
            lastScan = Date()
            let items = dockItems()
            titleItems = items.filter { $0.key.hasPrefix("title:") }
            for o in overlays {
                o.item = o.kind.appPaths.lazy.compactMap { items[$0] }.first
                o.nativeBadge = o.item.flatMap { ax($0, "AXStatusLabel") as? String }.map { !$0.isEmpty } ?? false
            }
        }
        // 收起時只讀一個圖示的位置，還在螢幕外就不做別的
        if !fast, ProcessInfo.processInfo.environment["DOCKUSAGE_FAKE"] == nil, let item = overlays.lazy.compactMap({ $0.item }).first,
           let pv = ax(item, kAXPositionAttribute) {
            var p = CGPoint.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &p)
            if !onScreen(CGRect(origin: p, size: CGSize(width: 40, height: 40))) { lastFrame = CACurrentMediaTime(); return }
        }
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now
        phase += 3.2 * CGFloat(dt)   // 約 2 秒流過一個波
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let anyVisible = overlays.map { $0.step(phase: phase, dt: dt) }.contains(true)
        CATransaction.commit()
        hoverNote(visible: anyVisible)
        Host.shared.setVisible(anyVisible)
        if anyVisible != fast {
            log("visible=\(anyVisible) " + overlays.map { o in "\(o.kind) item=\(o.item != nil) frame=\(o.item.flatMap(frame).map { "\($0)" } ?? "-") layer=\(o.layer.frame) level=\(o.primary?.pct ?? -1)" }.joined(separator: " | "))
            schedule(fast: anyVisible)
        }
    }
}

// MARK: - main

let args = CommandLine.arguments
// 離屏截圖驗證：DockUsage --note <out.png>
if args.count >= 3, args[1] == "--note" {
    let img = renderNote("LINE", Note(title: "小明", body: "晚上要不要一起吃飯？我訂了七點的位子，在你公司附近那家拉麵店，記得帶傘喔今天會下雨"))
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// 離屏截圖驗證：DockUsage --snapshot <claude|gpt> <水位%> <7d%|-> <out.png> [size] [--bare]
if args.count >= 6, args[1] == "--snapshot", let k = Kind(rawValue: args[2]) {
    let size = args.count > 6 ? CGFloat(Double(args[6]) ?? 512) : 512
    let bare = args.contains("--bare")
    let base = k.icon
    let attn = args.firstIndex(of: "--attn").flatMap { Int(args[$0 + 1]) } ?? 0
    let label = args.firstIndex(of: "--label").map { args[$0 + 1] }
    let core = renderIcon(kind: k, base: nil, short: Double(args[3]), long: Double(args[4]), phase: 0.8, size: size, label: label)
    let overlay = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        core.draw(in: r); drawAttention(attn, size: size, phase: 0.8); return true }
    // 模擬疊在真圖示上的樣子：先畫原圖示，再蓋透明層
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        if !bare { base?.draw(in: r) }
        overlay.draw(in: r)
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[5]))
    exit(0)
}
// App 圖示：深色圓角方塊＋ASCII 水位（不用任何人的商標）。DockUsage --appicon <out.png> [size]
if args.count >= 3, args[1] == "--appicon" {
    let size = args.count > 3 ? CGFloat(Double(args[3]) ?? 1024) : 1024
    let base = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let inset = size * 100 / 1024
        let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))!
            .draw(in: NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225), angle: -90)
        return true
    }
    let img = renderIcon(kind: .gpt, base: base, short: 62, long: nil, phase: 2.0, size: size, showNumber: false)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}
if args.count >= 2, args[1] == "--bench" {
    // 畫一格的耗時（疊加層實際尺寸 39pt @2x）與 AX 讀位置的耗時
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 78, pixelsHigh: 78, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    var t = CACurrentMediaTime()
    for i in 0..<300 { renderIcon(kind: .claude, base: nil, short: 57, long: 30, phase: CGFloat(i) * 0.3, size: 39).draw(in: NSRect(x: 0, y: 0, width: 39, height: 39)) }
    print("draw ms/frame:", (CACurrentMediaTime() - t) / 300 * 1000)
    let items = dockItems()
    t = CACurrentMediaTime()
    for _ in 0..<300 { for (_, it) in items.prefix(2) { _ = frame(of: it) } }
    print("ax ms/frame (2 items):", (CACurrentMediaTime() - t) / 300 * 1000)
    exit(0)
}
if args.count >= 2, args[1] == "--dock" {
    for (path, item) in dockItems() where Kind.claude.appPaths.contains(path) || Kind.gpt.appPaths.contains(path) {
        let r = frame(of: item)
        print(path, r as Any, "onScreen:", r.map(onScreen) as Any)
    }
    exit(0)
}
if args.count >= 3, args[1] == "--dump", let k = Kind(rawValue: args[2]) {
    let raw = k == .claude ? loadClaude() : loadCodex()
    print("raw:", raw)
    print("fresh short:", fresh(raw.short) as Any, "long:", fresh(raw.long) as Any)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
