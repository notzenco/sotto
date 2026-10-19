import Foundation

public enum AppClass: String, Equatable, Sendable {
    case terminal
    case code
    case chat
    case email
    case browser
    case word
    case remote
    case other
}

public enum AppIdentity {
    public static func classify(bundleID: String?, domain: String?) -> AppClass {
        let bundle = bundleID ?? ""
        if isTerminal(bundle) { return .terminal }
        if isRemote(bundle) { return .remote }
        if isWord(bundle) { return .word }
        if isEmailApp(bundle) { return .email }
        if isChatApp(bundle) { return .chat }
        if isCode(bundle) { return .code }
        if isBrowser(bundle) {
            let host = domain?.lowercased() ?? ""
            if host == "mail.google.com" || host.hasSuffix(".mail.google.com")
                || host == "outlook.office.com" || host.hasSuffix(".outlook.office.com")
                || host == "outlook.live.com"
            {
                return .email
            }
            if host == "app.slack.com" || host.hasSuffix(".slack.com") {
                return .chat
            }
            return .browser
        }
        return .other
    }

    public static func defaultMode(bundleID: String?, domain: String?) -> DictationMode {
        switch classify(bundleID: bundleID, domain: domain) {
        case .terminal, .code:
            .literal
        case .chat, .email, .browser, .word, .remote, .other:
            .prose
        }
    }

    public static func prefersPaste(_ bundleID: String?) -> Bool {
        switch classify(bundleID: bundleID, domain: nil) {
        case .remote, .word, .chat, .code, .browser:
            true
        case .terminal, .email, .other:
            false
        }
    }

    /// How long to leave the transcript on the clipboard before putting the previous contents back.
    public static func pasteRestoreNanoseconds(bundleID: String?) -> UInt64 {
        switch classify(bundleID: bundleID, domain: nil) {
        case .remote:
            5_000_000_000
        case .word, .chat, .code:
            2_000_000_000
        default:
            500_000_000
        }
    }

    public static func isTerminal(_ bundleID: String) -> Bool {
        let terminals = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
        ]
        return terminals.contains(bundleID)
    }

    private static func isRemote(_ bundleID: String) -> Bool {
        let remotes = [
            "com.microsoft.rdc.macos",
            "com.citrix.receiver.icaviewer.mac",
            "com.citrix.XenAppViewer",
            "com.vmware.fusion",
            "com.parallels.desktop.console",
        ]
        return remotes.contains(bundleID)
    }

    private static func isWord(_ bundleID: String) -> Bool {
        bundleID == "com.microsoft.Word"
    }

    private static func isEmailApp(_ bundleID: String) -> Bool {
        bundleID == "com.apple.mail" || bundleID == "com.microsoft.Outlook"
    }

    private static func isChatApp(_ bundleID: String) -> Bool {
        let chats = [
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "com.apple.MobileSMS",
        ]
        return chats.contains(bundleID)
    }

    private static func isCode(_ bundleID: String) -> Bool {
        let codes = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.todesktop.230313mzl4w4u92",
            "com.apple.dt.Xcode",
            "com.sublimetext.4",
            "com.jetbrains.intellij",
        ]
        if codes.contains(bundleID) { return true }
        return bundleID.hasPrefix("com.jetbrains.") || bundleID.hasPrefix("com.todesktop.")
    }

    private static func isBrowser(_ bundleID: String) -> Bool {
        let browsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
        ]
        return browsers.contains(bundleID)
    }
}
