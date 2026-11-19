// 收集 Dock 放大資料：Dock 滑出後 15 秒內，每 50ms 記滑鼠＋所有 AX 項目框，每 ~300ms 截 Dock 條。用法：magsample <輸出資料夾>
import Cocoa
let out = CommandLine.arguments[1]
let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first!.processIdentifier
func ax(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func items() -> [(String, CGRect)] {
  var r: [(String, CGRect)] = []
  for l in ax(AXUIElementCreateApplication(dock), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    for it in ax(l, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      var p = CGPoint.zero, s = CGSize.zero
      guard let pv = ax(it, kAXPositionAttribute), let sv = ax(it, kAXSizeAttribute) else { continue }
      AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
      r.append(((ax(it, kAXTitleAttribute) as? String ?? "?").replacingOccurrences(of: " ", with: "_"), CGRect(origin: p, size: s)))
    }
  }
  return r
}
let H = CGDisplayBounds(CGMainDisplayID()).height
func now() -> Double { Date().timeIntervalSince1970 }
// 等 Dock 滑出
while !(items().first.map { $0.1.minX >= 0 } ?? false) { usleep(50_000) }
usleep(400_000)
let t0 = now()
var log = ""
var shot = 0, lastShot = 0.0
let q = DispatchQueue(label: "shot")
let g = DispatchGroup()
while now() - t0 < 15 {
  let m = NSEvent.mouseLocation
  let line = String(format: "%.3f mouse %.1f %.1f ", now() - t0, m.x, H - m.y) + items().map { "\($0.0) \($0.1.minX) \($0.1.minY) \($0.1.width) \($0.1.height)" }.joined(separator: " | ")
  log += line + "\n"
  if now() - lastShot > 0.3 {
    lastShot = now(); let i = shot; shot += 1
    g.enter()
    q.async {
      let a = now() - t0
      let p = Process(); p.launchPath = "/usr/sbin/screencapture"; p.arguments = ["-x", "-R", "0,0,120,\(Int(H))", "\(out)/s\(i).png"]; p.launch(); p.waitUntilExit()
      let b = now() - t0
      try? String(format: "%.3f %.3f\n", a, b).write(toFile: "\(out)/s\(i).t", atomically: true, encoding: .utf8)
      g.leave()
    }
  }
  usleep(50_000)
}
g.wait()
try! log.write(toFile: "\(out)/log.txt", atomically: true, encoding: .utf8)
print("done", shot)
