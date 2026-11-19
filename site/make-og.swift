// 分享預覽圖：影片封面當主視覺＋app 圖示和標語。swiftc make-og.swift -o /tmp/og && /tmp/og <appicon512.png> og-image.png
import AppKit
let poster = NSImage(contentsOfFile: "/Users/dora/me/usage-meter/site/assets/intro-poster.jpg")!
let W: CGFloat = 1200, H: CGFloat = 630
let img = NSImage(size: NSSize(width: W, height: H), flipped: false) { _ in
  NSColor.black.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
  // 影片畫面：Dock 和熱門網站卡，放在下方偏右
  let ps = poster.size, scale: CGFloat = 0.62
  let dw = ps.width * scale, dh = ps.height * scale
  poster.draw(in: NSRect(x: W - dw + 230, y: -70, width: dw, height: dh))
  // 左側漸層，讓字讀得清楚
  NSGradient(colors: [NSColor.black, NSColor.black.withAlphaComponent(0.85), NSColor.black.withAlphaComponent(0)], atLocations: [0, 0.38, 0.55], colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 0)
  let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
  icon.draw(in: NSRect(x: 72, y: 420, width: 120, height: 120))
  NSAttributedString(string: "Dock Usage", attributes: [.font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: 72, y: 300))
  NSAttributedString(string: "Your Dock, alive.", attributes: [.font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor(white: 0.65, alpha: 1)]).draw(at: NSPoint(x: 74, y: 245))
  NSAttributedString(string: "Free · Open source · macOS", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: NSColor(white: 0.45, alpha: 1)]).draw(at: NSPoint(x: 74, y: 80))
  return true }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: W, height: H)); NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
