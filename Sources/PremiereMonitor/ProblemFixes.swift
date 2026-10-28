import AppKit

/// The one-click fix for each permissionWarnings key, shared by the warning banner in
/// the main window and PermissionGateView, so the two can't drift apart. nil means
/// there's nothing to click — fix it outside Reprise, then "Test again".
struct ProblemFix {
    let label: String
    let icon: String
    let action: () -> Void
}

@MainActor
enum ProblemFixes {
    static func fix(for key: String) -> ProblemFix? {
        let engine = MonitorEngine.shared
        switch key {
        case "download-folder":
            return ProblemFix(label: "Open System Settings", icon: "gearshape") {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_DownloadsFolder")
            }
        case "cookie-access":
            return ProblemFix(label: "Open System Settings", icon: "gearshape") {
                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            }
        case "external-tools":
            return ProblemFix(label: "Install via Homebrew", icon: "terminal") { engine.installMissingTools() }
        case "ytdlp-outdated":
            return ProblemFix(label: "Update yt-dlp", icon: "arrow.down.circle") { engine.updateYtDlp() }
        case "disk-space":
            return ProblemFix(label: "Open Storage", icon: "internaldrive") {
                openSettings("x-apple.systempreferences:com.apple.settings.Storage")
            }
        case "cookie-login":
            // A network error has no in-app fix — logging in again wouldn't help.
            guard !engine.lastCookieTestWasNetworkError else { return nil }
            return ProblemFix(label: "Log in to YouTube", icon: "person.crop.circle") { engine.openYouTubeLogin() }
        default:
            return nil
        }
    }

    private static func openSettings(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
