// 原圖示（沒有疊層）：swift plain-icons.swift <outdir> <size>
import AppKit
let out = CommandLine.arguments[1], size = Int(CommandLine.arguments[2])!
let icons: [(String, NSImage?)] = [
    ("claude", NSWorkspace.shared.icon(forFile: "/Applications/Claude.app")),
    ("gpt", NSWorkspace.shared.icon(forFile: FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") ? "/Applications/ChatGPT.app" : "/Applications/Codex.app")),
    ("finder", NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")),
    ("chrome", NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")),
    ("trash", NSImage(contentsOfFile: "/System/Library/CoreServices/Dock.app/Contents/Resources/s-trashfull-background@2x.png")),
]
for (name, img) in icons {
    guard let img else { continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
