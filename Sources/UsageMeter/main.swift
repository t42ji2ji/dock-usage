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
        let front = wave(0, amp)
        // 沒用到的部分壓暗（疊在真圖示上時只壓水面以上）
        let dark = NSBezierPath(rect: body)
        if base == nil { dark.append(front); dark.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.55).setFill()
        dark.fill()
        color.withAlphaComponent(0.35).setFill()
        wave(.pi * 0.7, amp * 0.8).fill()
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

// MARK: - 疊在 Dock 圖示上的透明視窗

final class OverlayView: NSView {
    var kind: Kind = .claude
    var level: Double?
    var tick: Double?
    var phase: CGFloat = 0
    override func draw(_ dirty: NSRect) {
        let side = min(bounds.width, bounds.height)
        let img = renderIcon(kind: kind, base: nil, short: level, long: tick, phase: phase, size: side)
        img.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side))
    }
}

final class Overlay {
    let kind: Kind
    let window: NSWindow
    let view = OverlayView()
    var usage = Usage()
    var shown: Double = 0
    var item: AXUIElement?

    init(kind: Kind) {
        self.kind = kind
        view.kind = kind
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
    }

    var primary: Window? { usage.short ?? usage.long }

    /// 每格：追 Dock 項目位置，水位往目標靠，重畫
    func step(phase: CGFloat) -> Bool {
        guard let item, let r = frame(of: item), onScreen(r), primary != nil else {
            if window.isVisible { window.orderOut(nil) }
            return false
        }
        let primaryH = CGDisplayBounds(CGMainDisplayID()).height
        let f = NSRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
        if window.frame != f { window.setFrame(f, display: false) }
        let to = primary?.pct ?? 0
        shown += (to - shown) * 0.12
        if abs(to - shown) < 0.05 { shown = to }
        view.level = shown
        view.tick = usage.short == nil ? nil : usage.long?.pct
        view.phase = phase
        view.needsDisplay = true
        if !window.isVisible { window.orderFrontRegardless() }
        return true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlays = [Overlay(kind: .claude), Overlay(kind: .gpt)]
    var phase: CGFloat = 0
    var timer: Timer?
    var fast = false
    var lastScan = Date.distantPast
    let queue = DispatchQueue(label: "dockusage.load", qos: .utility)

    func applicationDidFinishLaunching(_ n: Notification) {
        if !AXIsProcessTrusted() {
            // 讀 Dock 圖示位置要「輔助使用」權限；第一次會跳系統的授權視窗
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        schedule(fast: false)
    }

    func refresh() {
        queue.async {
            let c = loadClaude(), g = loadCodex()
            let fix = { (u: Usage) in Usage(short: fresh(u.short), long: fresh(u.long), updated: u.updated) }
            DispatchQueue.main.async {
                self.overlays[0].usage = fix(c)
                self.overlays[1].usage = fix(g)
            }
        }
    }

    /// Dock 看得到時 30 格／秒追位置和動畫；收起時每 0.25 秒看一眼就好
    func schedule(fast: Bool) {
        self.fast = fast
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 30 : 0.25, repeats: true) { [weak self] _ in self?.frameTick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func frameTick() {
        guard AXIsProcessTrusted() else { return }
        if Date().timeIntervalSince(lastScan) > 2 || overlays.contains(where: { $0.item == nil && Date().timeIntervalSince(lastScan) > 0.5 }) {
            lastScan = Date()
            let items = dockItems()
            for o in overlays {
                o.item = o.kind.appPaths.lazy.compactMap { items[$0] }.first
            }
        }
        phase += 0.9 / 30
        let anyVisible = overlays.map { $0.step(phase: phase) }.contains(true)
        if anyVisible != fast { schedule(fast: anyVisible) }
    }
}

// MARK: - main

let args = CommandLine.arguments
// 離屏截圖驗證：DockUsage --snapshot <claude|gpt> <水位%> <7d%|-> <out.png> [size] [--bare]
if args.count >= 6, args[1] == "--snapshot", let k = Kind(rawValue: args[2]) {
    let path = k.appPaths.first { FileManager.default.fileExists(atPath: $0) }
    let size = args.count > 6 ? CGFloat(Double(args[6]) ?? 512) : 512
    let bare = args.contains("--bare")
    let base = path.map { NSWorkspace.shared.icon(forFile: $0) }
    let overlay = renderIcon(kind: k, base: nil, short: Double(args[3]), long: Double(args[4]), phase: 0.8, size: size)
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
