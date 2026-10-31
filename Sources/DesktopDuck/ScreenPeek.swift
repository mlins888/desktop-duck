import AppKit
import ScreenCaptureKit

/// Takes a screenshot of one app's front window (never the whole screen). Nothing is saved to disk.
enum ScreenPeek {
    enum PeekError: Error {
        case noWindow
        case encodeFailed
    }

    /// Longest side sent to Claude; larger images just get downscaled server-side.
    private static let maxSide: CGFloat = 1568

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards it's a toggle in System Settings.
    static func requestPermission() { CGRequestScreenCaptureAccess() }

    /// JPEG of the frontmost normal window belonging to `pid`.
    static func captureFrontWindow(of pid: pid_t) async throws -> Data {
        guard let windowID = frontWindowID(of: pid) else { throw PeekError.noWindow }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw PeekError.noWindow
        }

        let config = SCStreamConfiguration()
        let pixelScale = min(2, maxSide / max(window.frame.width, window.frame.height))
        config.width = Int(window.frame.width * pixelScale)
        config.height = Int(window.frame.height * pixelScale)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: config
        )
        guard let jpeg = NSBitmapImageRep(cgImage: image)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { throw PeekError.encodeFailed }
        return jpeg
    }

    /// The window list is ordered front to back, so the first layer-0 window for the app is its front window.
    private static func frontWindowID(of pid: pid_t) -> CGWindowID? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let match = windows.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        return match?[kCGWindowNumber as String] as? CGWindowID
    }
}
