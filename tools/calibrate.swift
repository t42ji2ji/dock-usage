// 校準：等 Dock 滑出且 Claude／ChatGPT 項目位置停穩 0.5 秒，截圖＋記錄 AX 框。用法：calibrate <輸出資料夾> [張數]
import Cocoa
let out = CommandLine.arguments[1]; let want = Int(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "3")!
let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first!.processIdentifier
func ax(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func frames() -> [String: CGRect] {
  var r: [String: CGRect] = [:]
  for l in ax(AXUIElementCreateApplication(dock), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    for it in ax(l, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      guard let u = ax(it, kAXURLAttribute) as? URL, ["Claude.app", "ChatGPT.app"].contains(u.lastPathComponent) else { continue }
      var p = CGPoint.zero, s = CGSize.zero
      AXValueGetValue(ax(it, kAXPositionAttribute) as! AXValue, .cgPoint, &p); AXValueGetValue(ax(it, kAXSizeAttribute) as! AXValue, .cgSize, &s)
      r[u.lastPathComponent] = CGRect(origin: p, size: s)
    }
  }
  return r
}
var prev: [String: CGRect] = [:], stable = 0, got = 0, armed = true
while got < want {
  let f = frames()
  let vis = f.values.contains { $0.minX >= 0 }
  if !vis { armed = true; stable = 0 }
  if vis && armed { stable = (f == prev) ? stable + 1 : 0
    if stable >= 10 {
      let u = f.values.reduce(f.values.first!) { $0.union($1) }.insetBy(dx: -20, dy: -20)
      let path = "\(out)/cal-\(got).png"
      let t = Process(); t.launchPath = "/usr/sbin/screencapture"; t.arguments = ["-x", "-R", "\(Int(u.minX.rounded(.down))),\(Int(u.minY.rounded(.down))),\(Int(u.width.rounded(.up))),\(Int(u.height.rounded(.up)))", path]; t.launch(); t.waitUntilExit()
      let info = f.map { "\($0.key) \($0.value.minX) \($0.value.minY) \($0.value.width) \($0.value.height)" }.joined(separator: "\n")
      try! "origin \(Int(u.minX.rounded(.down))) \(Int(u.minY.rounded(.down)))\n\(info)\n".write(toFile: "\(out)/cal-\(got).txt", atomically: true, encoding: .utf8)
      print("captured", got, f); fflush(stdout); got += 1; armed = false; stable = 0 } }
  prev = f; usleep(50_000)
}
