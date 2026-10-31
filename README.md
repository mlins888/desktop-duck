# Desktop Duck

A little duck that wanders along the bottom of your Mac screen and keeps you company while you work.

## Run it

```sh
swift run
```

This needs Xcode's toolchain. If you get an `xcodebuild requires Xcode` error, prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or run `sudo xcode-select -s /Applications/Xcode.app` once.

To get a double-clickable app (and add it to Login Items so it starts with your Mac):

```sh
./make-app.sh
open build/DesktopDuck.app
```

## What it does

- Wanders left and right along the top of the Dock, stops to idle and blink.
- **Click** it to say hi. **Drag** it anywhere; it falls back down when you let go.
- Falls asleep after 5 minutes without keyboard/mouse input and wakes up when you're back.
- Pep talk every 15–30 minutes.
- Menu bar 🦆:
  - **Start 25-min focus**: countdown in the menu bar, check-ins every 8 min, cheers when done, then a 5-min break.
  - **Encourage me**, **Come here** (walks to your cursor), **Stay put**, **Quit**.

None of that needs special macOS permissions.

## Letting the duck see your work

Double-click the duck (or 🦆 → **What do you think?**) and it puts on its glasses, looks at the window
you're working in, and comments on it. With **Peek every 15 min** on, it also does this on its own.

- It **only looks at work sites and apps** listed in `Sources/DesktopDuck/WorkFilter.swift`
  (Claude, Canvas, Google Docs, Overleaf, Gradescope, Desmos, Notability, Notes, Preview, …). Anywhere else it
  won't look. Edit the lists to add your own.
- It captures **only the front window** of that app, never the whole screen. Nothing is saved.
- **Hint mode**: 🦆 → **Give me a hint**, or turn on **Hint mode for double-click**. The duck gives one small
  nudge toward the next step, never the answer.

Setup:

1. Get an API key at [console.anthropic.com](https://console.anthropic.com) (it needs a little credit).
2. 🦆 → **Set API key…** and paste it. It's stored in your macOS Keychain.
3. The first look asks for **Screen Recording** permission (System Settings → Privacy & Security). Turn it on
   for Desktop Duck, then quit and reopen the duck.
4. In a browser, macOS asks once whether Desktop Duck may control it. Allow it, since that's how the duck
   reads the current site. Safari, Chrome, Arc, Brave and Edge work. Firefox can't report its URL, so the duck
   won't look at Firefox.

Each look sends one screenshot to Claude. Comments use `claude-haiku-5-5` (a fraction of a cent each);
hints use `claude-opus-5-5` (around a cent) so the math is right. Both are set in `DuckBrain.swift`.
The prompts that set the duck's personality and hint rules are at the top of `DuckBrain.swift`.

`make-app.sh` signs the app with your Apple Development certificate if you have one, so permissions survive
rebuilds. Without one it's signed ad hoc, and macOS treats every rebuild as a new app: remove the old entry from
Screen Recording and grant it again.

To see what the duck is doing (handy when it says something went wrong):

```sh
/usr/bin/log stream --level info --predicate 'subsystem == "local.desktopduck"'
```

## Where things live

| File | What's in it |
| --- | --- |
| `Sources/DesktopDuck/Messages.swift` | Everything the duck says. Edit away. |
| `Sources/DesktopDuck/DuckView.swift` | The duck art (built from the SVGs in `art/`) and its poses/animation. |
| `Sources/DesktopDuck/DuckController.swift` | The window, wandering, sleeping, dragging. Timings at the top. |
| `Sources/DesktopDuck/AppDelegate.swift` | Menu bar item, focus timer, pep talk and peek schedule. |
| `Sources/DesktopDuck/WorkFilter.swift` | Which sites and apps the duck is allowed to look at. |
| `Sources/DesktopDuck/DuckBrain.swift` | The Claude request and the duck's prompts. |
| `Sources/DesktopDuck/Peeker.swift` | Ties it together: allowlist → screenshot → Claude → speech bubble. |

`swift run DesktopDuck --snapshot <dir>` renders each pose to PNG so you can check the art without launching.

## Swapping in Rive later

The duck is currently drawn and animated in code from your SVG parts, so it works without a `.riv` file.
`DuckArt` in `DuckView.swift` is the only piece that needs replacing. Everything else just sets
`model.pose` (`idle`, `walking`, `sleeping`, `cheering`, `held`) and `model.facingRight`.

Plan for the Rive file:

- One artboard facing **right** (the code mirrors it for walking left), transparent background.
- A state machine (e.g. `Duck`) with inputs that map to the poses, for example:
  `isWalking` (bool), `isSleeping` (bool), `isHeld` (bool), `cheer` (trigger).

Then add the `RiveRuntime` Swift package and replace `DuckArt` with a `RiveViewModel` view that sets those inputs
when `model.pose` changes.
