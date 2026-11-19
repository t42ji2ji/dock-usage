import Cocoa
import ServiceManagement

// MARK: - Kind（同一支執行檔，靠 Info.plist 的 MeterKind 分成 Claude / GPT 兩個 app）

enum Kind: String {
    case claude, gpt

    var appPaths: [String] {
        switch self {
        case .claude: return ["/Applications/Claude.app"]
        case .gpt: return ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        }
    }
    var tint: NSColor {
        switch self {
        case .claude: return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // #D97757
        case .gpt: return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)     // #10A37F
        }
    }
    var sourceName: String { self == .claude ? "Claude Code" : "Codex" }
}

func L(_ en: String, _ zh: String) -> String {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? zh : en
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

/// Claude：Claude Code 狀態列腳本寫出的 rate_limits（~/.claude/usage-meter/claude.json）
func loadClaude() -> Usage {
    let url = home.appendingPathComponent(".claude/usage-meter/claude.json")
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

/// 原 app 圖示 + 從底部漲起的水位（5 小時）+ 一條虛線刻度（7 天）+ 百分比數字
func renderIcon(kind: Kind, base: NSImage?, short: Double?, long: Double?, phase: CGFloat, size: CGFloat = 512) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size
        base?.draw(in: NSRect(x: 0, y: 0, width: s, height: s))

        // macOS 圖示格線：824/1024 的圓角方塊置中
        let inset = s * 100 / 1024
        let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

        guard let short else { return true }
        let p = CGFloat(min(max(short, 0), 100)) / 100
        let hot = short >= 80
        let color = hot ? NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1) : kind.tint

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()

        // 沒用到的部分壓暗，水面以下再把原圖示亮著畫回來
        NSColor.black.withAlphaComponent(0.58).setFill()
        body.fill()

        // 水面：兩層正弦波
        let level = body.minY + body.height * p
        let amp = p > 0.01 && p < 0.99 ? s * 0.018 : 0
        func wave(_ offset: CGFloat, _ a: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: body.minX, y: body.minY))
            var x = body.minX
            while x <= body.maxX + 1 {
                let t = (x - body.minX) / body.width
                path.line(to: NSPoint(x: x, y: level + sin(t * .pi * 2 * 1.3 + phase + offset) * a))
                x += s / 128
            }
            path.line(to: NSPoint(x: body.maxX, y: body.minY))
            path.close()
            return path
        }
        color.withAlphaComponent(0.35).setFill()
        wave(.pi * 0.7, amp * 0.8).fill()
        let front = wave(0, amp)
        NSGraphicsContext.saveGraphicsState()
        front.addClip()
        base?.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        NSGradient(starting: color.withAlphaComponent(hot ? 0.75 : 0.30), ending: color.blended(withFraction: 0.4, of: .black)!.withAlphaComponent(hot ? 0.9 : 0.6))!
            .draw(in: front, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        // 水面亮線
        let crest = NSBezierPath()
        var cx = body.minX
        while cx <= body.maxX + 1 {
            let t = (cx - body.minX) / body.width
            let pt = NSPoint(x: cx, y: level + sin(t * .pi * 2 * 1.3 + phase) * amp)
            if cx == body.minX { crest.move(to: pt) } else { crest.line(to: pt) }
            cx += s / 128
        }
        crest.lineWidth = s * 0.012
        NSColor.white.withAlphaComponent(p > 0.01 && p < 0.99 ? 0.8 : 0).setStroke()
        crest.stroke()

        // 7 天刻度線
        if let long {
            let y = body.minY + body.height * CGFloat(min(max(long, 0), 100)) / 100
            let line = NSBezierPath()
            line.move(to: NSPoint(x: body.minX, y: y))
            line.line(to: NSPoint(x: body.maxX, y: y))
            line.lineWidth = s * 0.012
            line.setLineDash([s * 0.03, s * 0.022], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.75).setStroke()
            line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // 數字
        let num = "\(Int(short.rounded()))"
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
        let big = NSFont.systemFont(ofSize: s * 0.30, weight: .heavy)
        let rounded = big.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: s * 0.30) } ?? big
        let str = NSMutableAttributedString(string: num, attributes: [.font: rounded, .foregroundColor: NSColor.white, .shadow: shadow])
        let smallFont = NSFont.systemFont(ofSize: s * 0.13, weight: .bold)
        str.append(NSAttributedString(string: "%", attributes: [.font: smallFont, .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: shadow]))
        let sz = str.size()
        str.draw(at: NSPoint(x: body.midX - sz.width / 2, y: body.minY + body.height * 0.08))
        return true
    }
}

// MARK: - Dock 有沒有滑出來

/// 有「輔助使用」權限時讀 Dock 第一個圖示的位置：自動隱藏收起時它在螢幕外，這時不重畫省電。
/// 沒權限就當作一直看得到。
func dockVisible() -> Bool {
    guard AXIsProcessTrusted(),
          let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return true }
    func children(_ e: AXUIElement) -> [AXUIElement] {
        var v: AnyObject?
        AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
        return v as? [AXUIElement] ?? []
    }
    guard let item = children(AXUIElementCreateApplication(dock.processIdentifier)).first.flatMap({ children($0).first }) else { return true }
    var v: AnyObject?
    var p = CGPoint.zero, sz = CGSize.zero
    AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &v)
    if let v { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &v)
    if let v { AXValueGetValue(v as! AXValue, .cgSize, &sz) }
    let r = CGRect(origin: p, size: sz)
    var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).contains { CGDisplayBounds($0).intersects(r) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let kind: Kind
    let base: NSImage?
    let appURL: URL?
    var usage = Usage()
    var shown: Double = 0            // 目前畫出來的水位（做漲退動畫）
    var phase: CGFloat = 0
    var anim: Timer?
    var launchedAt = Date()
    let queue = DispatchQueue(label: "meter.load", qos: .utility)

    init(kind: Kind) {
        self.kind = kind
        let path = kind.appPaths.first { FileManager.default.fileExists(atPath: $0) }
        appURL = path.map { URL(fileURLWithPath: $0) }
        // icns 有一堆尺寸，每格重解很貴：先壓成一張 256px 點陣圖
        base = path.map { p in
            let icon = NSWorkspace.shared.icon(forFile: p)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            icon.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
            NSGraphicsContext.restoreGraphicsState()
            let img = NSImage(size: NSSize(width: 256, height: 256)); img.addRepresentation(rep); return img
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        draw()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [kind] in
            let raw = kind == .claude ? loadClaude() : loadCodex()
            let u = Usage(short: fresh(raw.short), long: fresh(raw.long), updated: raw.updated)
            DispatchQueue.main.async { self.apply(u) }
        }
    }

    func apply(_ u: Usage) {
        guard u != usage else { return }
        usage = u
        if anim == nil { animate() }
    }

    /// 水面一直流動；數字變了水位會慢慢漲／退過去
    func animate() {
        anim = Timer.scheduledTimer(withTimeInterval: 1.0 / Self.fps, repeats: true) { [weak self] _ in
            guard let self else { return }
            let to = self.primary?.pct ?? 0
            self.shown += (to - self.shown) * 0.12
            if abs(to - self.shown) < 0.05 { self.shown = to }
            self.phase += 0.9 / CGFloat(Self.fps)   // 約 7 秒流過一個波
            self.tick += 1
            if self.tick % 6 == 0 { self.dockShown = dockVisible() }
            if self.dockShown { self.draw() }
        }
    }
    static let fps = 12.0
    var tick = 0
    var dockShown = true

    /// 水位：有 5 小時就用 5 小時、7 天畫虛線；只有 7 天（Claude 有時只給這格）就用 7 天當水位
    var primary: Window? { usage.short ?? usage.long }

    func draw() {
        let level = primary == nil ? nil : shown
        let tick = usage.short == nil ? nil : usage.long?.pct
        let img = renderIcon(kind: kind, base: base, short: level, long: tick, phase: phase, size: Self.px)
        // 自己畫進 8-bit 點陣圖再交出去；直接給延遲繪製的 NSImage，AppKit 會用 16-bit 浮點每格重畫好幾次
        let ctx = NSGraphicsContext(bitmapImageRep: frame)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.clear(CGRect(x: 0, y: 0, width: Self.px, height: Self.px))
        img.draw(in: NSRect(x: 0, y: 0, width: Self.px, height: Self.px))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: Self.px, height: Self.px))
        out.addRepresentation(frame.copy() as! NSBitmapImageRep)
        // Dock 走 contentView（便宜）；⌘Tab 只認 applicationIconImage（貴），隔 5 秒才換一次
        tileView.image = out
        NSApp.dockTile.display()
        if Date().timeIntervalSince(lastAppIcon) > 5 {
            lastAppIcon = Date()
            NSApp.applicationIconImage = out
        }
    }
    var lastAppIcon = Date.distantPast
    lazy var tileView: NSImageView = {
        let v = NSImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
        v.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = v
        return v
    }()
    static let px: CGFloat = 192
    let frame = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    // 點 Dock 圖示或 ⌘Tab 切過來 → 打開真正的 app
    func openReal() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { openReal(); return false }
    func applicationDidBecomeActive(_ n: Notification) {
        if Date().timeIntervalSince(launchedAt) > 2 { openReal() }
    }

    // 右鍵 Dock 圖示的選單
    func applicationDockMenu(_ s: NSApplication) -> NSMenu? {
        let m = NSMenu()
        func line(_ label: String, _ w: Window?) -> String {
            guard let w else { return "\(label)  —" }
            var t = "\(label)  \(Int(w.pct.rounded()))%"
            if let r = w.resetsAt {
                let f = DateFormatter()
                f.dateFormat = Calendar.current.isDateInToday(r) ? "HH:mm" : "EEE HH:mm"
                t += "  · " + L("resets ", "重置 ") + f.string(from: r)
            }
            return t
        }
        for t in [line(L("5 hours", "5 小時"), usage.short), line(L("7 days", "7 天"), usage.long)] {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i)
        }
        let src: String
        if let u = usage.updated {
            let f = RelativeDateTimeFormatter()
            src = L("From \(kind.sourceName), updated ", "來自 \(kind.sourceName)，更新於") + f.localizedString(for: u, relativeTo: Date())
        } else {
            src = L("No data yet — use \(kind.sourceName) once", "還沒有資料——先用一次 \(kind.sourceName)")
        }
        let s = NSMenuItem(title: src, action: nil, keyEquivalent: ""); s.isEnabled = false; m.addItem(s)
        m.addItem(.separator())
        let login = NSMenuItem(title: L("Open at Login", "登入時開啟"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        return m
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
    }
}

// MARK: - main

let args = CommandLine.arguments
// 離屏截圖驗證：UsageMeter --snapshot <claude|gpt> <5h%> <7d%> <out.png> [size]
if args.count >= 6, args[1] == "--snapshot", let k = Kind(rawValue: args[2]) {
    let path = k.appPaths.first { FileManager.default.fileExists(atPath: $0) }
    let size = args.count > 6 ? CGFloat(Double(args[6]) ?? 512) : 512
    let short = args[3] == "-" ? nil : Double(args[3])
    let img = renderIcon(kind: k, base: path.map { NSWorkspace.shared.icon(forFile: $0) }, short: short, long: Double(args[4]), phase: 0.8, size: size)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[5]))
    exit(0)
}
if args.count >= 2, args[1] == "--dock" { print("trusted:", AXIsProcessTrusted(), "visible:", dockVisible()); exit(0) }
if args.count >= 2, args[1] == "--dump", args.count >= 3, let k = Kind(rawValue: args[2]) {
    let raw = k == .claude ? loadClaude() : loadCodex()
    print("raw:", raw)
    print("fresh short:", fresh(raw.short) as Any, "long:", fresh(raw.long) as Any)
    exit(0)
}

let kind = Kind(rawValue: Bundle.main.object(forInfoDictionaryKey: "MeterKind") as? String ?? "") ?? .claude
let app = NSApplication.shared
let delegate = AppDelegate(kind: kind)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
