<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Muxy Island</h3>
  <p align="center">
    A macOS menu-bar companion that surfaces <a href="https://github.com/muxy-app/muxy">Muxy</a>-hosted
    Claude Code (and Codex, OpenCode) sessions in a Dynamic-Island-style notch panel —
    with one-click pane jumps, in-panel chat, and tool approval workflows.
  </p>
</div>

<p align="center">
  <a href="https://github.com/tod-zhang/muxy-island/releases/latest">
    <img src="https://img.shields.io/github/v/release/tod-zhang/muxy-island?style=flat&color=white&labelColor=000000&label=release" alt="Release" />
  </a>
  <img src="https://img.shields.io/github/license/tod-zhang/muxy-island?style=flat&color=white&labelColor=000000" alt="License" />
</p>

## What it is

Muxy Island is a fork of [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch)
(Apache 2.0) with deep integration into the [Muxy](https://github.com/muxy-app/muxy)
terminal. Vibe Notch shows your Claude Code sessions as a notch-style overlay; this
fork extends it so the overlay can *drive* Muxy directly — click a session to jump to
its pane, type into the chat to send prompts to the Claude running there, and approve
tool permissions without switching windows.

Also supports **Codex CLI** (OpenAI) and **OpenCode** (sst) alongside Claude Code.

## Install

Download the latest DMG from the [Releases page](https://github.com/tod-zhang/muxy-island/releases/latest)
and drag `Vibe Notch.app` to `/Applications`.

**First launch**: the app is ad-hoc signed (no paid Apple Developer cert), so
macOS Gatekeeper will warn about an unidentified developer. Right-click the app
→ **Open** → confirm. Subsequent launches work normally.

Auto-updates are wired to a Sparkle appcast at
`docs/appcast.xml` on this repo. Click **Check for Updates** in the menu to
download + install the next release in place.

## Setup

### 1. Enable Muxy remote access (required for Muxy integration)

Open **Muxy → Settings → Mobile** and toggle on **Allow mobile device connection**.
This starts a local WebSocket server on port 4865 that Muxy Island talks to.

Without this, session-jumping and in-panel chat send won't work for Muxy panes —
the app will still show Claude sessions and handle tool approvals, it just can't
reach into Muxy.

### 2. Pair Muxy Island with Muxy (one time)

The **first time** you click a session row to jump into its Muxy pane, Muxy
will pop up a pairing request asking you to approve a new device named
"Vibe Notch". Click **Approve**. The pairing is cached — you won't be asked again.

### 3. Hooks install themselves

On launch, Muxy Island installs a hook script into `~/.claude/hooks/` and
registers it in the relevant config files for each installed tool:

| Tool | Config touched |
| --- | --- |
| Claude Code | `~/.claude/settings.json` — adds a `command` hook for all events |
| Codex CLI | `~/.codex/hooks.json` — same hook script, different provider tag |
| OpenCode | `~/.opencode/plugins/muxy-island-notify.js` — dropped in the plugins dir |

All registrations are marker-based and coexist with other hooks you may
already have installed (e.g., other Claude desktop tools).

You can disable everything from the menu's **Hooks** toggle.

## Using the app

### Panel behavior

- **Hover** the notch → panel expands instantly (0 ms delay)
- **Move mouse off the panel** → collapses instantly (if opened by hover)
- **Notification** (task done, approval needed) → panel pops open automatically
  and auto-collapses after 5s (configurable in Settings → Auto-close)
- **Click anywhere else on screen** → panel closes

### Session row

Each Claude / Codex / OpenCode session appears as a row with:

- State indicator (processing spinner, ready checkmark, or approval prompt)
- Session title + last activity or pending tool call
- **Single-click** the row → jumps to the Muxy pane (or uses yabai for tmux sessions)
- **Chat bubble icon** → opens an in-panel chat view where you can read history
  and send new prompts (Muxy or tmux sessions only)
- **Archive icon** → removes the session from the list (only when idle/ready)

### Tool approvals

When Claude / Codex requests permission for a tool, the approval bar gives
four options:

| Button | What happens |
| --- | --- |
| **Deny** | Reject this single request |
| **Allow Once** | Approve just this request |
| **Allow All** | Approve + remember this tool for this project's cwd; future sessions in the same project auto-allow it (persisted) |
| **Bypass** | Approve + turn on a session-wide "no more approvals" flag for this session only (not persisted) |

"Allow All" persistence is stored in UserDefaults keyed by cwd. There's
currently no UI to review or revoke individual rules — delete
`com.celestial.ClaudeIsland` from `~/Library/Preferences` to wipe them.

### Sending messages from the chat panel

Click the chat bubble on any Muxy or tmux session. The input field sends
typed text to the actual terminal:

- **Muxy** sessions → via the `terminalInput` WebSocket API (briefly takes
  pane ownership, sends, releases — invisible to you)
- **tmux** sessions → via `tmux paste-buffer` (needs yabai to focus back)

OpenCode sessions have the chat bubble hidden because OpenCode's plugin API
doesn't expose a way to inject input back.

## Settings

Open the menu (hamburger icon, top-right of opened panel):

- **Screen** — which display the notch lives on
- **Ready Sound** — plays when Claude finishes a turn
- **Approval Sound** — plays when a tool approval is requested
- **Auto-close** — Off / 3 / 5 / 10 / 30 seconds for notification panels
- **Claude Directory** — override for non-default `.claude` dirs
  (e.g., enterprise distros that use `.claude-internal`)
- **Launch at Login** / **Hooks** toggles

Sounds are only played when the session's terminal isn't currently visible on
your space — no noise spam while you're already looking at Claude.

## System requirements

- macOS 15.6+
- At least one of: [Claude Code CLI](https://github.com/anthropics/claude-code),
  [Codex CLI](https://github.com/openai/codex), or
  [OpenCode](https://github.com/sst/opencode)
- For the Muxy integration: [Muxy](https://github.com/muxy-app/muxy) installed
  and running with mobile-device access enabled
- For tmux session support: [tmux](https://github.com/tmux/tmux) and
  [yabai](https://github.com/koekeishiya/yabai) (only needed if you want
  non-Muxy tmux sessions focusable from the panel)

## Build from source

```bash
git clone https://github.com/tod-zhang/muxy-island.git
cd muxy-island
xcodebuild -scheme ClaudeIsland -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO build
```

Build output lands in `build/Build/Products/Release/Vibe Notch.app`.

To cut a Release (bumps the build number, packages a signed DMG, updates the
Sparkle appcast, and creates the GitHub release):

```bash
./scripts/create-release.sh 0.5.0 "Your release notes"
```

Requires `gh` CLI authenticated to your repo and a Sparkle EdDSA key pair
at `.sparkle-keys/eddsa_private_key` (generate with `scripts/generate-keys.sh`).

## Credits

- Built on top of [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch)
  (Apache 2.0)
- [Muxy](https://github.com/muxy-app/muxy) — the terminal this integrates with
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update framework

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
