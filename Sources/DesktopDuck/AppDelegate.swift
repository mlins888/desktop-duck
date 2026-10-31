import AppKit

/// Menu bar item, focus timer, and the occasional unprompted pep talk.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Session {
        case none
        case focus(until: Date, nextCheckIn: Date)
        case rest(until: Date)
    }

    private let focusLength: TimeInterval = 25 * 60
    private let breakLength: TimeInterval = 5 * 60

    private let duck = DuckController()
    private var statusItem: NSStatusItem!
    private var focusItem: NSMenuItem!
    private var stayPutItem: NSMenuItem!
    private var session: Session = .none
    private var nextPepTalk = Date.now + .random(in: 15...30) * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🦆"

        let menu = NSMenu()
        focusItem = menu.addItem(withTitle: "Start 25-min focus", action: #selector(toggleFocus), keyEquivalent: "f")
        menu.addItem(withTitle: "Encourage me", action: #selector(encourage), keyEquivalent: "e")
        menu.addItem(withTitle: "Come here", action: #selector(comeHere), keyEquivalent: "h")
        stayPutItem = menu.addItem(withTitle: "Stay put", action: #selector(toggleStayPut), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu

        duck.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everySecond() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func everySecond() {
        let now = Date.now
        switch session {
        case .none:
            statusItem.button?.title = "🦆"
            if now >= nextPepTalk {
                nextPepTalk = now + .random(in: 15...30) * 60
                if !duck.isAsleep { duck.cheer(Messages.encouragement.randomElement()) }
            }

        case .focus(let until, let nextCheckIn):
            statusItem.button?.title = "🦆 " + countdown(to: until)
            if now >= until {
                duck.cheer(Messages.focusDone.randomElement(), for: 3)
                session = .rest(until: now + breakLength)
            } else if now >= nextCheckIn {
                session = .focus(until: until, nextCheckIn: now + 8 * 60)
                if !duck.isAsleep { duck.say(Messages.focusCheckIn.randomElement()!) }
            }

        case .rest(let until):
            statusItem.button?.title = "☕️ " + countdown(to: until)
            if now >= until {
                duck.cheer(Messages.breakDone.randomElement(), for: 2)
                endSession()
            }
        }
    }

    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func endSession() {
        session = .none
        focusItem.title = "Start 25-min focus"
        statusItem.button?.title = "🦆"
    }

    @objc private func toggleFocus() {
        if case .none = session {
            session = .focus(until: .now + focusLength, nextCheckIn: .now + 8 * 60)
            focusItem.title = "Stop focus"
            duck.cheer(Messages.focusStart.randomElement())
        } else {
            endSession()
            duck.say("ok, stopping the timer")
        }
    }

    @objc private func encourage() {
        duck.cheer(Messages.encouragement.randomElement())
    }

    @objc private func comeHere() {
        duck.comeToMouse()
    }

    @objc private func toggleStayPut() {
        duck.stayPut.toggle()
        stayPutItem.state = duck.stayPut ? .on : .off
    }
}
