// 量疊加層落後多少：Dock 滑出後 10 秒內，每 ~4ms 同時記 Claude 項目的 AX 框和 DockUsage 疊加視窗的實際位置。用法：lagmeter <out.txt>
import Cocoa
let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first!.processIdentifier
func ax(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
var claude: AXUIElement?
for l in ax(AXUIElementCreateApplication(dock), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
  for it in ax(l, kAXChildrenAttribute) as? [AXUIElement] ?? [] where (ax(it, kAXURLAttribute) as? URL)?.lastPathComponent == "Claude.app" { claude = it } }
func axFrame() -> CGRect { var p = CGPoint.zero, s = CGSize.zero
  AXValueGetValue(ax(claude!, kAXPositionAttribute) as! AXValue, .cgPoint, &p); AXValueGetValue(ax(claude!, kAXSizeAttribute) as! AXValue, .cgSize, &s); return CGRect(origin: p, size: s) }
let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "app.dorara.dockusage").first!.processIdentifier
func overlays() -> [CGRect] {
  let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  return l.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }.compactMap { CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary) }
}
while axFrame().minX < 0 { usleep(30_000) }
let t0 = CACurrentMediaTime(); var out = ""
while CACurrentMediaTime() - t0 < 10 {
  let a = axFrame(), o = overlays()
  let near = o.min { abs($0.midY - a.midY) < abs($1.midY - a.midY) }
  out += String(format: "%.4f ax %.2f %.2f %.2f ov %.2f %.2f %.2f\n", CACurrentMediaTime() - t0, a.minY, a.height, a.minX, near?.minY ?? -1, near?.height ?? -1, near?.minX ?? -1)
  usleep(4_000)
}
try! out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print("done")
