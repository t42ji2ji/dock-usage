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

/// 原 app 圖示壓暗 + ASCII 字元格水位（5 小時）+ 兩側刻度（7 天）+ 百分比數字
func renderIcon(kind: Kind, base: NSImage?, short: Double?, long: Double?, phase: CGFloat, size: CGFloat = 512, showNumber: Bool = true) -> NSImage {
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

        // 整個圖示壓暗
        NSColor.black.withAlphaComponent(0.35).setFill()
        body.fill()

        // ASCII 格子：用掉的部分由密字元填滿、隨機跳字＋白色閃光；水面那排淡字元翻騰；空的部分只留淡點
        let cols = 10
        let area = body
        let cell = area.width / CGFloat(cols)
        let level = area.minY + area.height * p
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
                if rect.maxY <= level {
                    if rnd(c, r, tick &* 3 &+ 1) < 0.05 {
                        ch = "*"; col = .white; key = "w"; alpha = 0.7
                    } else {
                        ch = dense[Int(x * CGFloat(dense.count)) % dense.count]
                        let b = (rnd(c, r, k) * 4).rounded(.down) / 4          // 4 種亮度
                        col = color.blended(withFraction: 0.25 * b, of: .white)!; key = "d\(b)\(hot)\(kind)"
                        alpha = 0.45 + 0.2 * rnd(c, r, k + 9)
                    }
                } else if rect.minY < level {
                    ch = surf[Int(x * CGFloat(surf.count)) % surf.count]
                    col = color; key = "s\(hot)\(kind)"; alpha = 0.3 + 0.3 * rnd(c, r, tick)
                } else {
                    ch = dim[Int(x * CGFloat(dim.count)) % dim.count]
                    col = .white; key = "w"; alpha = 0.10 + 0.08 * rnd(c, r, k)
                }
                cg.setAlpha(alpha)
                cg.draw(glyphImage(ch, col, glyph, cell, key), in: rect)
            }
        }

        cg.restoreGState()

        // 7 天刻度：兩側的小括號
        if let long {
            let y = area.minY + area.height * CGFloat(min(max(long, 0), 100)) / 100
            NSColor.white.withAlphaComponent(0.9).setFill()
            let w = body.width * 0.07, h = max(s * 0.02, 1)
            NSRect(x: body.minX + body.width * 0.03, y: y - h / 2, width: w, height: h).fill()
            NSRect(x: body.maxX - body.width * 0.03 - w, y: y - h / 2, width: w, height: h).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard showNumber else { return true }
        // 數字（等寬）
        let num = "\(Int(short.rounded()))"
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = s * 0.03
        let font = NSFont.monospacedSystemFont(ofSize: s * 0.26, weight: .heavy)
        let str = NSMutableAttributedString(string: num, attributes: [.font: font, .foregroundColor: NSColor.white, .shadow: shadow])
        str.append(NSAttributedString(string: "%", attributes: [.font: NSFont.monospacedSystemFont(ofSize: s * 0.12, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: shadow]))
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

final class OverlayView: NSView {
    var kind: Kind = .claude
    var level: Double?
    var tick: Double?
    var phase: CGFloat = 0
    override func draw(_ dirty: NSRect) {
        // 圖示在 Dock 項目框裡置中，邊長＝框的短邊減 2pt（tilesize 37 時框高 39；2026-11-19 校準截圖量過）
        let side = min(bounds.width, bounds.height) - 2
        let r = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        renderIcon(kind: kind, base: nil, short: level, long: tick, phase: phase, size: side).draw(in: r)
    }
}

final class Overlay {
    let kind: Kind
    let window: NSWindow
    let view = OverlayView()
    var usage = Usage()
    var shown: Double = 0
    var item: AXUIElement?
    var lastTick = -1
    var prevRect: CGRect?
    static let lead = CGFloat(Double(ProcessInfo.processInfo.environment["DOCKUSAGE_LEAD"] ?? "") ?? 1.0)
    var lastLevel = 0.0

    init(kind: Kind) {
        self.kind = kind
        view.kind = kind
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false   // app 被隱藏（例如背景啟動）時疊加層也要照常顯示
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
    }

    var primary: Window? { usage.short ?? usage.long }

    /// 每格：追 Dock 項目位置，水位往目標靠，重畫
    func step(phase: CGFloat, dt: Double) -> Bool {
        let fake = ProcessInfo.processInfo.environment["DOCKUSAGE_FAKE"].map { v -> CGRect in
            let n = v.split(separator: ",").compactMap { Double($0) }; return CGRect(x: n[0], y: n[1] + (kind == .gpt ? n[3] : 0), width: n[2], height: n[3]) }
        guard let r = fake ?? item.flatMap(frame), fake != nil || onScreen(r), primary != nil else {
            if window.isVisible { window.orderOut(nil) }
            prevRect = nil
            return false
        }
        // Dock 讀到的位置要等下一格才畫得出來：照上一格的移動量往前推一格（大跳就不推，避免出現/消失時亂飛）
        var pr = r
        if let p = prevRect, abs(r.minY - p.minY) < 40, abs(r.height - p.height) < 20 {
            pr = CGRect(x: r.minX + (r.minX - p.minX) * Self.lead, y: r.minY + (r.minY - p.minY) * Self.lead,
                        width: r.width + (r.width - p.width) * Self.lead, height: r.height + (r.height - p.height) * Self.lead)
        }
        prevRect = r
        let primaryH = CGDisplayBounds(CGMainDisplayID()).height
        let f = NSRect(x: pr.minX, y: primaryH - pr.maxY, width: pr.width, height: pr.height)
        let to = primary?.pct ?? 0
        shown += (to - shown) * (1 - pow(0.88, dt * 30))
        if abs(to - shown) < 0.05 { shown = to }
        view.level = shown
        view.tick = usage.short == nil ? nil : usage.long?.pct
        view.phase = phase
        // 字元每秒換約 13 次：只有換字、水位在動或尺寸變了才重畫
        let t = Int(phase * 4)
        if t != lastTick || abs((view.level ?? 0) - lastLevel) > 0.01 || window.frame.size != f.size {
            lastTick = t; lastLevel = view.level ?? 0
            view.needsDisplay = true
        }
        if window.frame != f { window.setFrame(f, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
        return true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlays = [Overlay(kind: .claude), Overlay(kind: .gpt)]
    var phase: CGFloat = 0
    var timer: Timer?
    var link: CADisplayLink?
    var fast = false
    var lastFrame = CACurrentMediaTime()
    var lastScan = Date.distantPast
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
        schedule(fast: false)
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
    @objc func linkFired() { frameTick() }

    var lastTrusted: Bool?
    func frameTick() {
        let t = AXIsProcessTrusted()
        if t != lastTrusted { lastTrusted = t; log("trusted=\(t)") }
        guard t else { return }
        if Date().timeIntervalSince(lastScan) > 2 || overlays.contains(where: { $0.item == nil && Date().timeIntervalSince(lastScan) > 0.5 }) {
            lastScan = Date()
            let items = dockItems()
            for o in overlays {
                o.item = o.kind.appPaths.lazy.compactMap { items[$0] }.first
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
        let anyVisible = overlays.map { $0.step(phase: phase, dt: dt) }.contains(true)
        if anyVisible != fast {
            log("visible=\(anyVisible) " + overlays.map { o in "\(o.kind) item=\(o.item != nil) frame=\(o.item.flatMap(frame).map { "\($0)" } ?? "-") win=\(o.window.frame) level=\(o.primary?.pct ?? -1)" }.joined(separator: " | "))
            schedule(fast: anyVisible)
        }
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
