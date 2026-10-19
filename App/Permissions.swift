import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

enum Permissions {
    static func microphoneGranted() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static func requestMicrophone() async -> Bool {
        if microphoneGranted() { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func promptForAccessibility() -> Bool {
        // The Carbon constant is a mutable global. The key itself is this string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    static func listenEventGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestListenEvent() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
