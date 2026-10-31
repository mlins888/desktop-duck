import AppKit
import SwiftUI

MainActor.assumeIsolated {
    // `DesktopDuck --snapshot <dir>` renders each pose to PNG (handy for checking the art).
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
        let dir = URL(fileURLWithPath: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : ".")
        let poses: [(String, DuckPose, Double)] = [
            ("idle", .idle, 1), ("walk-a", .walking, 0.17), ("walk-b", .walking, 0.52),
            ("cheer", .cheering, 0.14), ("sleep", .sleeping, 0.3), ("held", .held, 0.2),
        ]
        for (name, pose, t) in poses {
            let renderer = ImageRenderer(content: DuckArt(pose: pose, t: t).padding(12).background(Color.white))
            renderer.scale = 4
            if let cg = renderer.cgImage {
                let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                try? data?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
