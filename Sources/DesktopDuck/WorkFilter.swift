import AppKit

/// Decides whether the duck is allowed to look at what's in front right now.
/// It only ever looks at the sites and apps listed here. Edit freely.
enum WorkFilter {
    /// Websites the duck may look at. Subdomains count too (e.g. "instructure.com" covers "duke.instructure.com").
    static let sites = [
        "claude.ai",
        "canvas.duke.edu", "instructure.com",          // Canvas
        "docs.google.com", "drive.google.com",
        "overleaf.com",
        "gradescope.com",
        "desmos.com", "wolframalpha.com", "symbolab.com",
        "notion.so",
        "khanacademy.org",
    ]

    /// Apps (by bundle ID) the duck may look at.
    static let apps = [
        "com.anthropic.claudefordesktop": "Claude",
        "com.apple.Preview": "Preview",
        "com.apple.Notes": "Notes",
        "com.gingerlabs.notability.desktop": "Notability",
        "com.microsoft.onenote.mac": "OneNote",
        "com.microsoft.Word": "Word",
        "com.apple.iWork.Pages": "Pages",
        "notion.id": "Notion",
    ]

    /// Browsers we can ask for the current tab's URL (via AppleScript).
    private static let browserScripts = [
        "com.apple.Safari": "URL of front document",
        "com.google.Chrome": "URL of active tab of front window",
        "company.thebrowser.Browser": "URL of active tab of front window", // Arc
        "com.brave.Browser": "URL of active tab of front window",
        "com.microsoft.edgemac": "URL of active tab of front window",
    ]

    struct Context {
        /// Where they are, e.g. "docs.google.com" or "Notability".
        let label: String
        let pid: pid_t
    }

    enum Verdict {
        case allowed(Context)
        case notWork
        case cantReadBrowser(String)   // browser name; Automation permission denied or unsupported
    }

    /// The last app you actually used. Our own dialogs and system prompts (like the Keychain
    /// password sheet) briefly become the front app, so `frontmostApplication` alone isn't reliable.
    @MainActor private static var lastUsedApp: NSRunningApplication?
    private static let ignoredApps: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.notificationcenterui",
    ]

    @MainActor
    static func startTracking() {
        func note(_ app: NSRunningApplication?) {
            guard let app, app.processIdentifier != getpid(),
                  !ignoredApps.contains(app.bundleIdentifier ?? "") else { return }
            lastUsedApp = app
        }
        note(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { note(app) }
        }
    }

    @MainActor
    static func check() -> Verdict {
        guard let app = lastUsedApp, !app.isTerminated, let bundleID = app.bundleIdentifier else {
            return .notWork
        }
        if let name = apps[bundleID] {
            return .allowed(Context(label: name, pid: app.processIdentifier))
        }
        guard let property = browserScripts[bundleID] else {
            return .notWork
        }
        let source = "tell application id \"\(bundleID)\" to return \(property)"
        var error: NSDictionary?
        guard
            let url = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue,
            let host = URL(string: url)?.host()?.lowercased()
        else {
            return .cantReadBrowser(app.localizedName ?? "your browser")
        }
        let allowed = sites.contains { host == $0 || host.hasSuffix("." + $0) }
        return allowed ? .allowed(Context(label: host, pid: app.processIdentifier)) : .notWork
    }
}
