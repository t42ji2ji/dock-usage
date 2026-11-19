import Cocoa

/// 介面文字：系統語言是中文就用中文
let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
func L(_ en: String, _ zhText: String) -> String { zh ? zhText : en }

// MARK: - 功能開關

enum Feature: String, CaseIterable {
    case claude, gpt, cmuxDot, finder, trash, browsers, notifications

    /// 會讀到私人內容的（通知文字、瀏覽紀錄）新安裝時預設關
    var defaultOn: Bool { self != .browsers && self != .notifications }
    var readsPrivate: Bool { !defaultOn }

    var title: String {
        switch self {
        case .claude: return L("Claude usage", "Claude 用量")
        case .gpt: return L("ChatGPT usage", "ChatGPT 用量")
        case .cmuxDot: return L("Sessions waiting for you", "等你回覆的 session")
        case .finder: return L("Disk space", "硬碟空間")
        case .trash: return L("Trash", "垃圾桶")
        case .browsers: return L("Time in your browser", "瀏覽器用了多久")
        case .notifications: return L("Latest notification on hover", "滑過看最新通知")
        }
    }
    var detail: String {
        switch self {
        case .claude: return L("Your 5-hour limit fills the Claude icon. Read from Claude Code.", "5 小時額度用掉多少，Claude 圖示就滿多少。從 Claude Code 讀。")
        case .gpt: return L("Your Codex limit fills the ChatGPT icon. Read from Codex.", "Codex 額度用掉多少，ChatGPT 圖示就滿多少。從 Codex 讀。")
        case .cmuxDot: return L("A red dot on Claude counts cmux tabs waiting for you.", "Claude 圖示上的紅點，數 cmux 裡有幾個分頁在等你。")
        case .finder: return L("Finder fills up as your disk does.", "Finder 照硬碟用了多少鋪滿。")
        case .trash: return L("The Trash fills with how many things are in it.", "垃圾桶照裡面有幾樣東西鋪滿。")
        case .browsers: return L("Today's time fills the browser icon. Hover for your top sites.", "今天用了多久，瀏覽器圖示就滿多少。滑過去看最常去的網站。")
        case .notifications: return L("Rest the pointer on an app to see its last notification.", "滑鼠停在 app 上，看它最後跳出的通知。")
        }
    }
    /// 這台 Mac 用得到才列出來
    var applies: Bool {
        switch self {
        case .claude: return Kind.claude.installed || FileManager.default.fileExists(atPath: claudeHome.path)
        case .gpt: return Kind.gpt.installed
        case .cmuxDot: return !cmuxCLI.isEmpty
        case .browsers: return [Kind.ego, .chrome, .arc, .edge, .brave].contains { $0.installed }
        default: return true
        }
    }
    /// 列表上顯示的圖示
    var icon: NSImage? {
        switch self {
        case .claude: return Kind.claude.icon
        case .gpt: return Kind.gpt.icon
        case .cmuxDot: return cmuxCLI.isEmpty ? nil : NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: cmuxCLI).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)
        case .finder: return Kind.finder.icon
        case .trash: return Kind.trash.icon
        case .browsers: return [Kind.ego, .chrome, .arc, .edge, .brave].first { $0.installed }?.icon
        case .notifications: return NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
        }
    }
}

extension Notification.Name { static let prefsChanged = Notification.Name("DockUsagePrefsChanged") }

enum Prefs {
    static let d = UserDefaults.standard
    static func on(_ f: Feature) -> Bool { d.object(forKey: "feature." + f.rawValue) as? Bool ?? f.defaultOn }
    static func set(_ f: Feature, _ v: Bool) {
        d.set(v, forKey: "feature." + f.rawValue)
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }
    static func setStyle(_ s: MaskStyle) {
        currentStyle = s
        d.set(s.rawValue, forKey: "style")
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }
    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }
    /// 0.1.x 就在用的人：沒看過導覽，但所有功能本來就開著，不打擾他
    static func migrate() {
        guard d.object(forKey: "onboarded") == nil, d.bool(forKey: "didSetLoginItem") else { return }
        for f in Feature.allCases { d.set(true, forKey: "feature." + f.rawValue) }
        onboarded = true
    }
}

extension MaskStyle {
    var title: String {
        switch self {
        case .ascii: return "ASCII"
        case .liquid: return L("Liquid", "液體")
        case .dots: return L("LED", "LED 點陣")
        case .ring: return L("Glow", "光邊")
        }
    }
}

// MARK: - Claude 狀態列

/// 測試時用 DOCKUSAGE_CLAUDE_HOME 指到別的資料夾，不碰真的 ~/.claude
let claudeHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKUSAGE_CLAUDE_HOME"] ?? NSHomeDirectory() + "/.claude")

enum ClaudeSetup: Equatable {
    case ready                 // 已經讀得到用量
    case automatic             // 沒有狀態列，可以直接幫他設
    case manual(String)        // 已經有自己的狀態列指令，給他一段要加的
}

/// 手動加進既有狀態列腳本的片段：原樣存下 Claude Code 給的資料，不需要 jq
let claudeSnippet = """
mkdir -p "$HOME/.claude/dock-usage"
printf '%s' "$input" > "$HOME/.claude/dock-usage/claude.json.$$" && mv -f "$HOME/.claude/dock-usage/claude.json.$$" "$HOME/.claude/dock-usage/claude.json"
"""

func claudeSetupState() -> ClaudeSetup {
    if FileManager.default.fileExists(atPath: claudeHome.appendingPathComponent("dock-usage/claude.json").path) { return .ready }
    let settings = claudeHome.appendingPathComponent("settings.json")
    if let data = try? Data(contentsOf: settings),
       let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let line = j["statusLine"] as? [String: Any], let cmd = line["command"] as? String {
        return cmd.contains("dock-usage.sh") ? .ready : .manual(cmd)      // 我們設的：等下次用 Claude Code 就有資料
    }
    return .automatic
}

/// 沒有狀態列時：寫一支只負責存資料的腳本，設成 Claude Code 的狀態列。原本的 settings.json 先備份
func installClaudeStatusLine() -> Bool {
    let fm = FileManager.default
    try? fm.createDirectory(at: claudeHome, withIntermediateDirectories: true)
    let script = claudeHome.appendingPathComponent("dock-usage.sh")
    let body = """
    #!/bin/sh
    # Dock Usage：把 Claude Code 傳給狀態列的資料存起來，Dock Usage 從裡面讀方案用量
    d="$HOME/.claude/dock-usage"; mkdir -p "$d"
    cat > "$d/claude.json.$$" && mv -f "$d/claude.json.$$" "$d/claude.json"

    """
    guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return false }
    let settings = claudeHome.appendingPathComponent("settings.json")
    var j: [String: Any] = [:]
    if let data = try? Data(contentsOf: settings) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }   // 看不懂的檔案不碰
        j = parsed
        try? data.write(to: claudeHome.appendingPathComponent("settings.json.bak-dockusage"))
    }
    guard j["statusLine"] == nil else { return false }
    j["statusLine"] = ["type": "command", "command": "sh ~/.claude/dock-usage.sh"]
    guard let out = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return false }
    return (try? out.write(to: settings, options: .atomic)) != nil
}
