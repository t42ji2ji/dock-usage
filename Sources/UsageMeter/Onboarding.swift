import SwiftUI
import ServiceManagement

// MARK: - 會動的圖示預覽（用跟 Dock 上一樣的 renderer）

func previewImage(_ kind: Kind, level: Double, style: MaskStyle, phase: CGFloat, size: CGFloat = 160) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        kind.icon?.draw(in: r)
        renderIcon(kind: kind, base: nil, short: level, long: nil, phase: phase, size: size, showNumber: true, style: style).draw(in: r)
        return true
    }
}

struct LiveIcon: View {
    let kind: Kind
    let level: Double
    var style: MaskStyle? = nil
    var size: CGFloat = 96
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let ph = CGFloat(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) * 3.2)
            Image(nsImage: previewImage(kind, level: level, style: style ?? currentStyle, phase: ph))
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
    }
}

/// 示範用的三個圖示：這台 Mac 上有的才放
func heroKinds() -> [(Kind, Double)] {
    var out: [(Kind, Double)] = []
    if Kind.claude.installed { out.append((.claude, 57)) }
    if Kind.gpt.installed { out.append((.gpt, 38)) }
    out.append((.finder, 73))
    if let b = [Kind.ego, .chrome, .arc, .edge, .brave].first(where: { $0.installed }), out.count < 3 { out.append((b, 45)) }
    return out
}

// MARK: - 共用的設定元件（導覽和設定視窗都用）

final class PrefsModel: ObservableObject {
    @Published var features: [Feature: Bool] = Dictionary(uniqueKeysWithValues: Feature.allCases.map { ($0, Prefs.on($0)) })
    @Published var style = currentStyle
    @Published var claude = claudeSetupState()
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var trusted = AXIsProcessTrusted()

    func toggle(_ f: Feature, _ v: Bool) { features[f] = v; Prefs.set(f, v) }
    func pick(_ s: MaskStyle) { style = s; Prefs.setStyle(s) }
    func setLogin(_ v: Bool) {
        login = v
        if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}

struct FeatureRow: View {
    let f: Feature
    @ObservedObject var m: PrefsModel
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let img = f.icon { Image(nsImage: img).resizable().interpolation(.high) }
                else { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)) }
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(f.title).font(.system(size: 14, weight: .semibold))
                    if f.readsPrivate {
                        Text(L("Stays on this Mac", "只在這台 Mac"))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .help(L("Reads private data, so it's off until you turn it on. Nothing is sent anywhere.", "會讀到私人內容，所以預設關閉。資料不會傳到任何地方。"))
                    }
                }
                Text(f.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(get: { m.features[f] ?? false }, set: { m.toggle(f, $0) }))
                .toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { m.toggle(f, !(m.features[f] ?? false)) }
    }
}

struct StylePicker: View {
    @ObservedObject var m: PrefsModel
    var size: CGFloat = 92
    @Namespace private var ns
    var body: some View {
        let k = heroKinds().first?.0 ?? .finder
        HStack(spacing: 12) {
            ForEach(MaskStyle.allCases, id: \.self) { st in
                StyleCard(style: st, kind: k, size: size, selected: m.style == st, ns: ns) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { m.pick(st) }
                }
            }
        }
    }
}

/// 一張樣式卡：會動的預覽＋名稱；選中的那張有一圈亮框，換選時框滑過去
struct StyleCard: View {
    let style: MaskStyle
    let kind: Kind
    let size: CGFloat
    let selected: Bool
    let ns: Namespace.ID
    let pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            VStack(spacing: 12) {
                LiveIcon(kind: kind, level: 62, style: style, size: size)
                    .scaleEffect(selected ? 1 : hover ? 1.04 : 0.96)
                    .opacity(selected || hover ? 1 : 0.8)
                HStack(spacing: 5) {
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .bold)).transition(.scale.combined(with: .opacity)) }
                    Text(style.title).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(selected ? 1 : hover ? 0.8 : 0.5))
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(selected ? 0.10 : hover ? 0.06 : 0.03))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(hover && !selected ? 0.14 : 0.06), lineWidth: 1)
                    if selected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                            .shadow(color: .white.opacity(0.18), radius: 8)
                            .matchedGeometryEffect(id: "selection", in: ns)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hover = h }
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ClaudeSetupView: View {
    @ObservedObject var m: PrefsModel
    @State var copied = false
    @State var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch m.claude {
            case .ready:
                Label(L("Claude Code is sharing your limits.", "已經讀得到 Claude Code 的用量。"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 14, weight: .semibold))
            case .automatic:
                Text(L("Claude Code shares your plan limits with its status line. Dock Usage can set that up for you.",
                       "Claude Code 會把方案額度傳給它的狀態列。Dock Usage 可以幫你設定好。"))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                HStack {
                    Button(L("Set Up for Me", "幫我設定")) {
                        if installClaudeStatusLine() { m.claude = .ready } else { failed = true }
                    }
                    .buttonStyle(PrimaryButton())
                    if failed { Text(L("Couldn't change settings.json. Add the status line yourself, see the README.", "改不了 settings.json，請照 README 自己加。")).font(.system(size: 12)).foregroundStyle(.orange) }
                }
                Text(L("Numbers show up the next time you use Claude Code.", "下次用 Claude Code 時數字就會出現。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            case .manual:
                Text(L("You already have a status line. Add these lines to it, after it reads its input into $input:",
                       "你已經有自己的狀態列。把這幾行加進去，放在它把輸入讀進 $input 之後："))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                Text(claudeSnippet).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35)))
                Button(copied ? L("Copied", "已複製") : L("Copy", "複製")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(claudeSnippet, forType: .string); copied = true
                }
                .buttonStyle(PrimaryButton())
            }
        }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : 1)))
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.3 : 0.45))
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

let backdrop = LinearGradient(colors: [Color(white: 0.11), Color(red: 0.07, green: 0.06, blue: 0.10)], startPoint: .top, endPoint: .bottom)

// MARK: - 導覽

enum Step: Int { case welcome, access, features, style, claude, done }

struct Onboarding: View {
    @ObservedObject var m: PrefsModel
    @State var step: Step
    let finish: () -> Void
    let relaunch: (Step) -> Void
    let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var steps: [Step] {
        var s: [Step] = [.welcome, .access, .features, .style]
        if Feature.claude.applies, m.features[.claude] == true, m.claude != .ready { s.append(.claude) }
        return s + [.done]
    }
    func next() { if let i = steps.firstIndex(of: step), i + 1 < steps.count { withAnimation(.easeInOut(duration: 0.35)) { step = steps[i + 1] } } }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .access: access
                    case .features: features
                    case .style: styles
                    case .claude: claude
                    case .done: done
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
                footer
            }
            .padding(.horizontal, 44).padding(.top, 40).padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .frame(width: 720, height: 540)
        .onReceive(poll) { _ in
            let t = AXIsProcessTrusted()
            // 權限要重開才生效：允許的那一刻自動重開，回到下一步
            if t && !m.trusted && step == .access { relaunch(.features) }
            m.trusted = t
        }
    }

    var footer: some View {
        HStack {
            if step != .done && step != .welcome {
                Button(L("Set Up Later", "稍後設定")) { finish() }.buttonStyle(QuietButton())
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { s in
                    Capsule().fill(.white.opacity(s == step ? 0.9 : 0.2)).frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            Button(primaryTitle) { step == .done ? finish() : next() }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .disabled(step == .access && !m.trusted)
                .opacity(step == .access && !m.trusted ? 0.4 : 1)
        }
    }
    var primaryTitle: String {
        switch step {
        case .welcome: return L("Get Started", "開始")
        case .done: return L("Done", "完成")
        default: return L("Continue", "繼續")
        }
    }

    func title(_ t: String, _ sub: String) -> some View {
        VStack(spacing: 10) {
            Text(t).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
            Text(sub).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
    }

    var welcome: some View {
        VStack(spacing: 34) {
            Spacer()
            HStack(spacing: 22) { ForEach(heroKinds(), id: \.0) { k, lv in LiveIcon(kind: k, level: lv, size: 120) } }
            title(L("Your Dock, alive.", "讓 Dock 活起來。"),
                  L("Usage, disk space and time, drawn right on the icons you already have.", "用量、硬碟、時間，直接畫在你本來就有的圖示上。"))
            Spacer()
        }
    }

    var access: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: m.trusted ? "checkmark.seal.fill" : "accessibility")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(m.trusted ? .green : .white)
            title(L("Find your icons", "找到你的圖示"),
                  L("Dock Usage needs Accessibility to see where each icon sits in your Dock. Nothing leaves your Mac.",
                    "Dock Usage 要「輔助使用」權限，才知道每個圖示在 Dock 的哪裡。資料不會離開這台 Mac。"))
            if m.trusted {
                Text(L("Allowed", "已允許")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
            } else {
                Button(L("Open System Settings", "打開系統設定")) {
                    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(PrimaryButton())
                Text(L("Turn on Dock Usage in the list. It restarts by itself and comes back here.", "在清單裡打開 Dock Usage。它會自己重開，回到這裡。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
    }

    var features: some View {
        VStack(spacing: 20) {
            title(L("Pick what to show", "選要顯示什麼"), L("Change these any time by opening Dock Usage again.", "之後再打開 Dock Usage 就能改。"))
            ScrollView {
                VStack(spacing: 8) { ForEach(Feature.allCases.filter { $0.applies }, id: \.self) { FeatureRow(f: $0, m: m) } }
            }
            .scrollIndicators(.never)
        }
    }

    var styles: some View {
        VStack(spacing: 30) {
            Spacer()
            title(L("Choose a look", "選一種樣子"), L("Your Dock switches as you click.", "點一下，Dock 上就跟著換。"))
            StylePicker(m: m)
            Spacer()
        }
    }

    var claude: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            HStack(spacing: 16) {
                if let i = Kind.claude.icon { Image(nsImage: i).resizable().frame(width: 56, height: 56) }
                Text(L("Connect Claude Code", "接上 Claude Code")).font(.system(size: 28, weight: .bold))
            }
            ClaudeSetupView(m: m)
            Spacer()
        }
        .frame(maxWidth: 560)
    }

    var done: some View {
        VStack(spacing: 30) {
            Spacer()
            HStack(spacing: 22) { ForEach(heroKinds(), id: \.0) { k, lv in LiveIcon(kind: k, level: lv, size: 96) } }
            title(L("Look at your Dock.", "看看你的 Dock。"),
                  L("Icons fill up as you go. Open Dock Usage again from Applications to change anything.",
                    "圖示會隨著用量滿起來。要改設定，從「應用程式」再打開 Dock Usage。"))
            Toggle(L("Open at login", "登入時開啟"), isOn: Binding(get: { m.login }, set: { m.setLogin($0) }))
                .toggleStyle(.switch)
            Spacer()
        }
    }
}

// MARK: - 設定（再打開一次 app 時）

struct SettingsView: View {
    @ObservedObject var m: PrefsModel
    let showWelcome: () -> Void

    func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).textCase(.uppercase)
            c()
        }
    }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dock Usage").font(.system(size: 22, weight: .bold))
                            Text(m.trusted ? L("Running", "執行中") : L("Needs Accessibility to find your icons", "需要「輔助使用」權限才找得到圖示"))
                                .font(.system(size: 12)).foregroundStyle(m.trusted ? .green : .orange)
                        }
                    }
                    section(L("Show", "顯示")) {
                        VStack(spacing: 8) { ForEach(Feature.allCases.filter { $0.applies }, id: \.self) { FeatureRow(f: $0, m: m) } }
                    }
                    section(L("Look", "樣子")) { StylePicker(m: m, size: 72) }
                    if Feature.claude.applies && m.features[.claude] == true {
                        section("Claude Code") { ClaudeSetupView(m: m) }
                    }
                    section(L("General", "一般")) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(L("Open at login", "登入時開啟"), isOn: Binding(get: { m.login }, set: { m.setLogin($0) })).toggleStyle(.switch)
                            HStack(spacing: 16) {
                                Button(L("Show Welcome Again", "重看導覽")) { showWelcome() }.buttonStyle(QuietButton())
                                Spacer()
                                Button(L("Quit Dock Usage", "結束 Dock Usage")) { NSApp.terminate(nil) }.buttonStyle(PrimaryButton())
                                    .help(L("Quit (⌘Q)", "結束 (⌘Q)"))
                            }
                        }
                    }
                }
                .padding(32)
            }
            .scrollIndicators(.never)
        }
        .foregroundStyle(.white)
        .frame(width: 600, height: 640)
    }
}

// MARK: - 視窗

func makeWindow<V: View>(_ view: V, size: NSSize, title: String) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.title = title
    w.isMovableByWindowBackground = true
    w.appearance = NSAppearance(named: .darkAqua)
    w.contentView = NSHostingView(rootView: view)
    w.isReleasedWhenClosed = false
    w.center()
    return w
}

/// LSUIElement 沒有選單列，⌘Q／⌘W 要自己接
func installMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: L("Quit Dock Usage", "結束 Dock Usage"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let winItem = NSMenuItem(); main.addItem(winItem)
    let winMenu = NSMenu(title: "Window")
    winMenu.addItem(withTitle: L("Close", "關閉"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    winItem.submenu = winMenu
    NSApp.mainMenu = main
}
