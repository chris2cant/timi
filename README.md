# Timi

Timi is a deliberately small, native macOS desktop mascot. It displays an animated transparent floating panel, supports eight screen anchors, can be dragged and snapped to any screen edge, remembers its placement and visibility between launches, and offers an optional local Apple Intelligence conversation.

## Requirements

- macOS 26 or later
- Xcode 26 or later (the full app from the App Store, opened once: the Command Line Tools alone cannot build Timi). No Apple account or paid developer program is needed.
- Optional: Apple Intelligence enabled, for the conversation bubble and dictation cleanup. Everything else, including the Claude Code sessions, works without it.

There is no prebuilt download yet: Timi is built from this repository on your Mac.

## Install

### With Claude Code (recommended)

Open Claude Code anywhere and ask:

> Setup Timi from https://github.com/chris2cant/timi

Claude follows [Setup instructions for agents](#setup-instructions-for-agents) below: it checks the requirements, builds and installs Timi, starts it and installs the Claude Code hooks. When it is done, restart your Claude Code sessions (including the one that ran the setup) so they load the hooks.

### By hand

```sh
git clone https://github.com/chris2cant/timi.git ~/Developer/timi
cd ~/Developer/timi
./scripts/install.sh
```

`./scripts/install.sh` builds Timi in Release, installs it in `/Applications` (`~/Applications` if `/Applications` is not writable), launches it and runs `./scripts/claude-hooks.sh install`. The first build takes a few minutes (Swift Package Manager downloads Sparkle). Run it again after `git pull` to update; it replaces the installed copy.

The commands work the same in zsh, bash and fish.

### Setup instructions for agents

Follow these steps in order when a user asks you to set up Timi. Use POSIX shell syntax in your own tool calls. Never run `sudo` yourself: give the command to the user and wait.

1. **Check the Mac.** `sw_vers -productVersion` must be 26 or later. `xcode-select -p` must end with `.app/Contents/Developer` and `xcodebuild -version` must report Xcode 26 or later. If not, stop and tell the user to install Xcode from the App Store, open it once, then run `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept`.
2. **Get the code.** If the working directory already contains `Timi.xcodeproj` and `scripts/install.sh`, use it (`git pull --ff-only` when the tree is clean). Otherwise `git clone https://github.com/chris2cant/timi.git ~/Developer/timi`, unless the user names another place, and work from there.
3. **Install.** Run `./scripts/install.sh` with a timeout of at least 10 minutes. It quits a running Timi, replaces the installed app and is safe to rerun. It prints `error: …` with the fix when something is missing.
4. **Verify.** All three must succeed:
   - `pgrep -x Timi`
   - `test -S "$HOME/Library/Application Support/Timi/claude-hooks.sock"`
   - `./scripts/claude-hooks.sh status` (exit code 0 means the 11 hook events are installed)

   Then check the whole chain with a fake session; a small Timi named after the current folder appears, then disappears:

   ```sh
   sock="$HOME/Library/Application Support/Timi/claude-hooks.sock"
   curl -s -m 1 --unix-socket "$sock" --data-binary '{"hook_event_name":"Stop","session_id":"timi-setup-check","cwd":"'"$PWD"'"}' http://timi/claude-hook
   sleep 3
   curl -s -m 1 --unix-socket "$sock" --data-binary '{"hook_event_name":"SessionEnd","session_id":"timi-setup-check"}' http://timi/claude-hook
   ```
5. **Tell the user**, briefly:
   - Restart running Claude Code sessions, this one included: hooks are read when a session starts.
   - What a click on a small Timi does in the terminal they use (see [Terminals](#terminals)). Detect it from your own session's environment instead of asking: `CMUX_WORKSPACE_ID` set means cmux, `HERDR_PANE_ID` set means herdr (both can be set: herdr inside cmux), `TMUX` set means tmux, otherwise `TERM_PROGRAM` names the app (`Apple_Terminal`, `iTerm.app`, `ghostty`, `vscode`, `WarpTerminal`…). Ask only if the user says they use several terminals.
   - Microphone, Input Monitoring and Accessibility are only for dictation and are asked when first needed (or from **Timi > Settings…**). Conversation needs Apple Intelligence.
   - Updating is `git pull` then `./scripts/install.sh` in the checkout; removal is described in [Uninstall](#uninstall).

The hooks are written to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). The script keeps every other hook, never duplicates the Timi entry, refuses invalid JSON and writes `settings.json.bak-timi` first. Hooks exit immediately when Timi is not running, so Claude Code is never blocked.

### Uninstall

```sh
./scripts/claude-hooks.sh uninstall
pkill -x Timi
rm -rf /Applications/Timi.app ~/Applications/Timi.app
# Optional, local data: dictation vocabulary and history, then preferences.
rm -rf ~/Library/Application\ Support/Timi
defaults delete io.github.chris2cant.Timi
```

## Terminals

The hooks are the same for every terminal. Only the click on a small Timi differs:

| Claude Code runs in | Click on its small Timi |
|---|---|
| cmux | Selects its cmux workspace and brings cmux forward |
| herdr | Focuses its herdr pane, then brings the hosting terminal forward |
| Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor, … | Brings that app forward (not the exact window or tab) |
| Claude Desktop | Opens the conversation in Claude Desktop |
| tmux | No app is found in its process tree: brings cmux forward if it is open, otherwise nothing |

States are shown the same way everywhere. Details: [docs/claude-code-sessions.md](docs/claude-code-sessions.md).

## Development

1. Open `Timi.xcodeproj` in Xcode.
2. Select the `Timi` scheme and the `My Mac` destination.
3. Press **Run** (`⌘R`).
4. Open **Timi > Settings…** (`⌘,`) to move the mascot.

Without Xcode, `./scripts/run.sh` builds in Debug into `build/`, quits any running Timi and launches the new build. Logs: `log stream --predicate 'subsystem == "io.github.chris2cant.Timi"'`.

## Usage

Move Timi from **Timi > Settings…** (`⌘,`) or drag it directly, including onto the menu bar or Dock area. Releasing it near a screen edge snaps it flush to that edge. Selecting a new anchor resets the manual offset; Settings includes a dedicated reset button and a visibility toggle as well. Decorative movement follows the macOS **Reduce motion** accessibility setting.

Timi's eyes follow the pointer anywhere on screen (read with `NSEvent.mouseLocation`, so no extra permission) and rest when Reduce Motion is on.

Click Timi to open the conversation bubble. Responses come from Apple's on-device Foundation Model and are streamed into the bubble; no account, API key, or network service is added by Timi (the Claude Code integration below only uses a local Unix socket). Press Escape or click elsewhere to close the bubble. On unsupported systems, the bubble explains why conversation is unavailable while the rest of Timi continues to work.

The microphone button uses Apple's on-device `SpeechTranscriber` for live dictation and falls back to the system dictation model when the newer model does not support the current locale. Click once to start, speak, then click the stop button to finalize the text before sending it. Timi requests microphone access only when dictation is first used and stops recording when the conversation bubble closes.

Timi also provides global local dictation. Press `Control-Space` from another app (the shortcut can be changed in Settings): a short press toggles dictation, while holding records until release. The mascot temporarily replaces its eyes with the elapsed time and a microphone-driven level meter. After final transcription, a separate Apple Intelligence session performs faithful cleanup and Timi pastes into the focused non-secure text field. If Accessibility is unavailable or the field cannot accept text, the result is left on the clipboard without interrupting recording with a permission prompt. Accessibility can be requested explicitly from Settings. Timi never stores audio or the text surrounding the cursor.

Vocabulary, confirmed heard-to-wanted corrections, and up to 100 dictations for 30 days are stored as one versioned JSON file in Application Support. Settings can search, edit, disable, or clear that local data. Input Monitoring is required for the global shortcut and Accessibility is required for compatible keyboard paste; App Sandbox remains disabled while these desktop-wide primitives are evaluated for distribution.

When a response finishes, Timi reads it aloud with `AVSpeechSynthesizer`. It detects the response language and selects the highest-quality matching system voice installed on the Mac, preferring the user's regional variant and excluding novelty and personal voices. Settings can override the automatic choice with any compatible voice that is actually available to the app and preview it; responses in other languages still use automatic selection. Starting another response or closing the conversation stops the current speech.

The app intentionally keeps a normal Dock icon in V0 so Settings and Quit remain easy to find.

## Claude Code sessions

Timi can show one small Timi per running Claude Code session, lined up next to the main mascot. Each one shows whether its session is working, needs you (urgent) or has finished its turn (gentle), and a click focuses its terminal ([Terminals](#terminals)). Events come from Claude Code hooks through a local Unix socket: no network port. States and limits: [docs/claude-code-sessions.md](docs/claude-code-sessions.md).

## Tests

Run the `TimiTests` test target in Xcode (`⌘U`), or `xcodebuild -project Timi.xcodeproj -scheme Timi -destination "platform=macOS,arch=$(uname -m)" test`.

## Code map

- Mascot appearance: `Timi/Mascot/MascotView.swift`
- Pure anchor geometry: `Timi/Mascot/PositionCalculator.swift`
- Floating AppKit panel: `Timi/Mascot/MascotWindowController.swift`
- Claude Code sessions (hook socket, state machine, store, herdr/cmux focus): `Timi/ClaudeSessions/`
- Session mascots (pure layout, view, `NSPanel`s): `Timi/Mascot/SessionMascotLayout.swift`, `Timi/Mascot/SessionMascotView.swift`, `Timi/Mascot/SessionMascotsWindowController.swift`
- Conversation state and Apple Intelligence integration: `Timi/Chat/ChatState.swift`
- On-device speech transcription and microphone capture: `Timi/Chat/SpeechInputController.swift`
- Global dictation coordination, shortcut, insertion, and local catalog: `Timi/Dictation/`
- Native speech synthesis and voice selection: `Timi/Chat/SpeechOutputController.swift`
- Conversation UI and AppKit panel: `Timi/Chat/ChatView.swift`, `Timi/Chat/ChatWindowController.swift`
- Pure conversation-bubble geometry: `Timi/Chat/ChatPositionCalculator.swift`
- Persistent state: `Timi/App/AppState.swift`
- Native Settings UI: `Timi/Settings/SettingsView.swift`
- Install and Claude Code hook scripts: `scripts/install.sh`, `scripts/claude-hooks.sh`
- Native decisions and Apple references: `docs/architecture.md`

The only third-party dependency is [Sparkle](https://sparkle-project.org) 2 (Swift Package Manager), used for in-app updates: it is the de-facto standard macOS updater, verifies EdDSA signatures, and avoids writing a security-critical installer ourselves. Timi checks `appcast.xml` in this repository over HTTPS (your IP is visible to GitHub; no other data is sent) and always asks before installing. See [RELEASING.md](RELEASING.md).
