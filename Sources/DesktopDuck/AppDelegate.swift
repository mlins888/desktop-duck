import AppKit

/// Menu bar item, focus timer, and the occasional unprompted pep talk or peek.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Session {
        case none
        case focus(until: Date, nextCheckIn: Date)
        case rest(until: Date)
    }

    private let focusLength: TimeInterval = 25 * 60
    private let breakLength: TimeInterval = 5 * 60
    private let peekEvery: TimeInterval = 15 * 60

    private let duck = DuckController()
    private lazy var peeker = Peeker(duck: duck)
    private var statusItem: NSStatusItem!
    private var focusItem: NSMenuItem!
    private var stayPutItem: NSMenuItem!
    private var hintModeItem: NSMenuItem!
    private var autoPeekItem: NSMenuItem!
    private var session: Session = .none
    private var nextPepTalk = Date.now + .random(in: 15...30) * 60
    private var nextPeek = Date.now + 15 * 60

    // Saved settings.
    private var hintMode: Bool {
        get { UserDefaults.standard.bool(forKey: "hintMode") }
        set { UserDefaults.standard.set(newValue, forKey: "hintMode") }
    }
    private var autoPeek: Bool {
        get { UserDefaults.standard.object(forKey: "autoPeek") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPeek") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🦆"

        let menu = NSMenu()
        focusItem = menu.addItem(withTitle: "Start 25-min focus", action: #selector(toggleFocus), keyEquivalent: "f")
        menu.addItem(withTitle: "Encourage me", action: #selector(encourage), keyEquivalent: "e")
        menu.addItem(withTitle: "Come here", action: #selector(comeHere), keyEquivalent: "h")
        stayPutItem = menu.addItem(withTitle: "Stay put", action: #selector(toggleStayPut), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "What do you think? (double-click duck)", action: #selector(lookNow), keyEquivalent: "l")
        menu.addItem(withTitle: "Give me a hint", action: #selector(hintNow), keyEquivalent: "")
        hintModeItem = menu.addItem(withTitle: "Hint mode for double-click", action: #selector(toggleHintMode), keyEquivalent: "")
        autoPeekItem = menu.addItem(withTitle: "Peek every 15 min", action: #selector(toggleAutoPeek), keyEquivalent: "")
        menu.addItem(withTitle: "Set API key…", action: #selector(setAPIKey), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
        hintModeItem.state = hintMode ? .on : .off
        autoPeekItem.state = autoPeek ? .on : .off

        WorkFilter.startTracking()
        duck.onDoubleTap = { [weak self] in self?.lookNow() }
        duck.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everySecond() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func everySecond() {
        let now = Date.now

        if autoPeek, now >= nextPeek {
            if case .allowed = WorkFilter.check() {
                nextPeek = now + peekEvery + .random(in: -120...120)
                Task { await peeker.peek(.comment, unprompted: true) }
            } else {
                nextPeek = now + 60 // not on a work site; check again in a minute
            }
        }

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

    @objc private func lookNow() {
        nextPeek = .now + peekEvery
        Task { await peeker.peek(hintMode ? .hint : .comment) }
    }

    @objc private func hintNow() {
        nextPeek = .now + peekEvery
        Task { await peeker.peek(.hint) }
    }

    @objc private func toggleHintMode() {
        hintMode.toggle()
        hintModeItem.state = hintMode ? .on : .off
        duck.say(hintMode ? "hint mode on! double-click me when you're stuck" : "hint mode off, i'll just be silly")
    }

    @objc private func toggleAutoPeek() {
        autoPeek.toggle()
        autoPeekItem.state = autoPeek ? .on : .off
        nextPeek = .now + peekEvery
    }

    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Anthropic API key"
        alert.informativeText = "Paste a key from console.anthropic.com. It's stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        APIKey.save(key)
        duck.cheer("got it! double-click me on canvas or docs and i'll take a look")
    }
}
