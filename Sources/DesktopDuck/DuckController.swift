import AppKit
import SwiftUI

/// Owns the duck's transparent window and decides where it goes and what it does.
@MainActor
final class DuckController {
    let model = DuckModel()

    /// Keeps the duck where it is (no wandering) when true.
    var stayPut = false

    private enum Behavior {
        case idle(until: Date)
        case walking(toX: CGFloat)
        case cheering(until: Date)
        case sleeping
        case dragging(grab: CGPoint)
        case falling(vy: CGFloat)
    }

    private let scale: CGFloat = 1.3
    private let walkSpeed: CGFloat = 45   // points per second
    private let sleepAfter: TimeInterval = 5 * 60
    private let windowSize = CGSize(width: 220, height: 180)

    private let panel: NSPanel
    private var behavior: Behavior = .idle(until: .now + 2)
    /// The duck's true position. macOS rounds window origins down to whole points, so reading
    /// back `panel.frame.origin` loses sub-point walking steps and the duck stalls walking right.
    private var position = CGPoint.zero
    private var timer: Timer?
    private var lastTick = Date.now
    private var messageToken = 0

    private var duckSize: CGSize {
        CGSize(width: DuckParts.size.width * scale, height: DuckParts.size.height * scale)
    }

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // Fixed size: by default the hosting view resizes the window to fit its content,
        // which pushed the duck (at the window's bottom edge) off the screen.
        let hosting = NSHostingView(
            rootView: DuckRootView(model: model, scale: scale)
                .frame(width: windowSize.width, height: windowSize.height)
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(windowSize)

        model.onTap = { [weak self] in self?.poked() }
        model.onDragChanged = { [weak self] in self?.dragChanged() }
        model.onDragEnded = { [weak self] in self?.dragEnded() }
    }

    func start() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.midX - windowSize.width / 2
        position = CGPoint(x: x, y: screen.visibleFrame.minY)
        panel.setFrameOrigin(position)
        panel.orderFrontRegardless()

        lastTick = .now
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        say("hi! I'm here to keep you company :)")
    }

    // MARK: - Things other parts of the app can ask for

    func say(_ text: String, for duration: TimeInterval = 5) {
        messageToken += 1
        let token = messageToken
        model.message = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if self?.messageToken == token { self?.model.message = nil }
        }
    }

    func cheer(_ text: String? = nil, for duration: TimeInterval = 1.5) {
        if case .dragging = behavior { return }
        if let text { say(text) }
        set(.cheering(until: .now + duration))
    }

    func comeToMouse() {
        let mouseX = NSEvent.mouseLocation.x
        if currentScreen.frame.contains(NSEvent.mouseLocation) {
            set(.walking(toX: clampX(mouseX - windowSize.width / 2)))
        }
    }

    var isAsleep: Bool {
        if case .sleeping = behavior { return true }
        return false
    }

    // MARK: - Per-frame update

    private func tick() {
        let now = Date.now
        let dt = CGFloat(min(now.timeIntervalSince(lastTick), 0.1))
        lastTick = now
        var origin = position
        let ground = currentScreen.visibleFrame.minY

        updateClickThrough()
        handleSleepAndWake()

        switch behavior {
        case .idle(let until):
            if origin.y > ground + 1 { set(.falling(vy: 0)) }
            else if now >= until { chooseNextThing() }

        case .walking(let toX):
            let dx = toX - origin.x
            if abs(dx) < 1 {
                set(.idle(until: now + .random(in: 3...10)))
            } else {
                model.facingRight = dx > 0
                origin.x += min(abs(dx), walkSpeed * dt) * (dx > 0 ? 1 : -1)
            }

        case .cheering(let until):
            if now >= until { set(.idle(until: now + .random(in: 2...6))) }

        case .sleeping:
            break

        case .dragging(let grab):
            // SwiftUI can miss the mouse-up once the window moves under the cursor,
            // so check the button directly.
            if NSEvent.pressedMouseButtons & 1 == 0 {
                dragEnded()
            } else {
                let mouse = NSEvent.mouseLocation
                origin = NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y)
            }

        case .falling(var vy):
            vy -= 2000 * dt
            origin.y = max(ground, origin.y + vy * dt)
            if origin.y <= ground {
                cheer(for: 0.5)
            } else {
                behavior = .falling(vy: vy)
            }
        }

        if origin != position {
            position = origin
            panel.setFrameOrigin(origin)
        }
    }

    private func chooseNextThing() {
        if stayPut || Double.random(in: 0...1) < 0.35 {
            set(.idle(until: .now + .random(in: 4...12)))
        } else {
            let frame = currentScreen.visibleFrame
            set(.walking(toX: clampX(.random(in: frame.minX...frame.maxX))))
        }
    }

    private func handleSleepAndWake() {
        let idleFor = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0) ?? .mouseMoved
        )
        if isAsleep {
            if idleFor < 1 { cheer(Messages.wakeUp.randomElement()) }
        } else if idleFor > sleepAfter, case .idle = behavior {
            model.message = nil
            set(.sleeping)
        }
    }

    /// Clicks only hit the window when the cursor is over the duck itself,
    /// so the rest of the (transparent) panel never blocks other apps.
    private func updateClickThrough() {
        if case .dragging = behavior { return }
        let duckRect = NSRect(
            x: panel.frame.minX + (windowSize.width - duckSize.width) / 2,
            y: panel.frame.minY,
            width: duckSize.width,
            height: duckSize.height
        )
        let overDuck = duckRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == overDuck {
            panel.ignoresMouseEvents = !overDuck
        }
    }

    // MARK: - Mouse

    private func poked() {
        if isAsleep {
            cheer(Messages.wakeUp.randomElement())
        } else {
            cheer(Messages.poked.randomElement())
        }
    }

    private func dragChanged() {
        if case .dragging = behavior { return }
        let mouse = NSEvent.mouseLocation
        set(.dragging(grab: CGPoint(x: mouse.x - position.x, y: mouse.y - position.y)))
    }

    private func dragEnded() {
        set(.falling(vy: 0))
    }

    // MARK: - Helpers

    private func set(_ new: Behavior) {
        behavior = new
        switch new {
        case .idle, .falling: model.pose = .idle
        case .walking: model.pose = .walking
        case .cheering: model.pose = .cheering
        case .sleeping: model.pose = .sleeping
        case .dragging: model.pose = .held
        }
    }

    private var currentScreen: NSScreen {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.minY + 10)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        let frame = currentScreen.visibleFrame
        return min(max(x, frame.minX), frame.maxX - windowSize.width)
    }
}
