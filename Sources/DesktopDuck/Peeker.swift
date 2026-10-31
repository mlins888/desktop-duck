import Foundation
import os

/// See what the duck is doing: `log stream --predicate 'subsystem == "local.desktopduck"'`
let duckLog = Logger(subsystem: "local.desktopduck", category: "peek")

/// The "duck looks at your work" feature: checks the allowlist, takes a screenshot of the
/// front window, asks Claude, and puts the answer in the speech bubble.
@MainActor
final class Peeker {
    private let duck: DuckController
    private var busy = false
    private var recentlySaid: [String] = []

    init(duck: DuckController) {
        self.duck = duck
    }

    /// `unprompted` peeks (the timer) stay quiet when they can't look; ones you asked for explain why.
    func peek(_ mode: DuckBrain.Mode, unprompted: Bool = false) async {
        guard !busy, !(unprompted && duck.isAsleep) else { return }

        duckLog.info("peek requested (hint: \(mode == .hint), unprompted: \(unprompted))")

        // Check where you are first, before anything (like a Keychain prompt) can take focus.
        let context: WorkFilter.Context
        switch WorkFilter.check() {
        case .allowed(let c):
            duckLog.info("allowed: \(c.label, privacy: .public)")
            context = c
        case .notWork:
            duckLog.info("front app/site isn't on the work list")
            if !unprompted { duck.say("i only peek at schoolwork! open canvas, docs or claude and ask me again") }
            return
        case .cantReadBrowser(let name):
            duckLog.error("couldn't read the URL from \(name, privacy: .public)")
            if !unprompted {
                duck.say("i can't tell what site this is. allow Desktop Duck to control \(name) in System Settings → Privacy & Security → Automation", for: 10)
            }
            return
        }

        guard let apiKey = APIKey.load() else {
            duckLog.error("no API key")
            if !unprompted { duck.say("i need an API key to see! 🦆 menu → Set API key…") }
            return
        }

        guard ScreenPeek.hasPermission else {
            duckLog.error("no Screen Recording permission")
            ScreenPeek.requestPermission()
            if !unprompted {
                duck.say("i need Screen Recording permission to see. turn it on for Desktop Duck in Privacy & Security, then restart me", for: 12)
            }
            return
        }

        busy = true
        duck.model.wearingGlasses = true
        duck.say(mode == .hint ? "hmm, let me take a look…" : "ooh what are we working on…", for: 90)
        defer {
            busy = false
            duck.model.wearingGlasses = false
        }

        do {
            let jpeg = try await ScreenPeek.captureFrontWindow(of: context.pid)
            duckLog.info("captured \(jpeg.count) bytes, asking Claude")
            let line = try await DuckBrain.say(
                about: jpeg, at: context.label, mode: mode,
                recentlySaid: recentlySaid, apiKey: apiKey
            )
            recentlySaid = Array((recentlySaid + [line]).suffix(5))
            duck.cheer(line)
        } catch {
            duckLog.error("peek failed: \(String(describing: error), privacy: .public)")
            duck.say(Self.message(for: error), for: 8)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case DuckBrain.BrainError.badKey: "my API key isn't working :( try 🦆 menu → Set API key…"
        case DuckBrain.BrainError.noCredit: "i'm out of duck food! add API credit at console.anthropic.com"
        case DuckBrain.BrainError.busy: "too many ducks asking at once, try again in a sec"
        case DuckBrain.BrainError.refused: "hmm, i'd better not comment on that one"
        case ScreenPeek.PeekError.noWindow: "i couldn't find a window to look at"
        case is URLError: "i can't reach the internet right now"
        default: "my glasses fogged up, something went wrong"
        }
    }
}
