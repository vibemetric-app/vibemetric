# Vibemetric

A small native macOS app that scores **how well you work with AI**. It reads your local Claude Code and Codex history and returns an **AI Native Score** card: 10 dimensions scored 0–10, with evidence-based reasons, one improvement to make first, and a roadmap.

[![CI](https://github.com/vibemetric-app/vibemetric/actions/workflows/ci.yml/badge.svg)](https://github.com/vibemetric-app/vibemetric/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This repository is the complete free app, open source under the [MIT license](LICENSE). Scoring runs on your Mac with your own Claude Code or Codex CLI.

**Pro features** (deep dives, Pro Reviews, recommendations) use Vibemetric's hosted service and are available only in the official app from [vibemetric.app](https://vibemetric.app). Builds from source include the complete free app.

**Trademark:** the code is open source; the Vibemetric name and logo are not. Forks must use a different name and icon.

## Installation

### Requirements

- **macOS 14 Sonoma or later**, on Apple Silicon or Intel.
- **Claude Code or Codex CLI, installed and signed in.** Choose the scoring engine on the first-assessment screen or in **Settings → Scoring engine**. Both engines assess Claude Code and Codex history, using your selected engine’s account and plan or API credits.
  - [Claude Code](https://claude.com/claude-code): check `claude --version`, then run `claude` to sign in.
  - [Codex CLI](https://developers.openai.com/codex/cli): check `codex --version`, then run `codex login`. Use a version that supports `exec fork` and `--ignore-user-config --ignore-rules --strict-config --output-schema`; Vibemetric checks these capabilities and selects the newest working installation, including the CLI bundled with the ChatGPT desktop app. On 2026-09-30, GPT-6 Sol worked with the bundled 0.158.0-alpha.2.1 CLI; the older npm 0.145.0 installation rejected the same request.

- **Some Claude Code or Codex history** in `~/.claude/projects` or `~/.codex/sessions`. The more sessions, the better the evidence.

### Option 1: download the app

If a prebuilt `Vibemetric.dmg` is available (from the Vibemetric website or this repository's Releases page):

1. Open the `.dmg` and drag **Vibemetric** onto the **Applications** folder in the window that appears.
2. Open it from Applications. The app is signed and notarized, so macOS asks only once whether to open an app from the internet. Click **Open**. Later versions install through **Check for Updates…**.

### Option 2: build from source

You need **Xcode 15.3 or later** (Swift 5.10+). The build script produces one app that runs on both Apple Silicon and Intel.

```bash
git clone https://github.com/vibemetric-app/vibemetric.git
cd vibemetric
./scripts/build-app.sh                    # builds build/Vibemetric.app (Apple Silicon + Intel) and build/Vibemetric.dmg
cp -R build/Vibemetric.app /Applications/
open /Applications/Vibemetric.app
```

An app you build yourself isn't quarantined, so macOS opens it without a warning. It has no Pro features and doesn't check for updates; update it with `git pull` and a new build.

### First run

1. Open Vibemetric. It scans your history in about a second and shows how many sessions it found.
2. Choose **Claude Code** or **Codex** under **Run the assessment**, then click **Score me**. Scoring takes a few minutes while the selected engine reads your session evidence. The same choice is saved in Settings and used for daily scores. A new installation waits for an engine choice or a first manual score before starting automatic scores.
3. Your score appears in the window and in the menu bar at the top right of the screen. Click it for the 10 dimensions and your next improvement.

After that, each run is compared with a compatible previous result from the same engine and model selection. Switching engines starts a separate comparison baseline. A dimension only changes when new sessions give evidence for it, and the card says what changed and why.

Useful shortcuts: **⌘N** goes to the new-assessment screen; **⌘+ / ⌘- / ⌘0** change the text size, and the size is remembered.

To start Vibemetric at login, open **System Settings → General → Login Items** and add it.

### Updating

Download or build the new version and replace `/Applications/Vibemetric.app`. Quit the running app first (menu bar score → **Quit**). Your saved results are kept.

When building from source:

```bash
git pull
./scripts/build-app.sh
rm -rf /Applications/Vibemetric.app && cp -R build/Vibemetric.app /Applications/
```

### Uninstalling

Quit Vibemetric, then remove the app and the data it created:

```bash
rm -rf /Applications/Vibemetric.app
rm -rf ~/Library/Application\ Support/Vibemetric   # saved results and their evidence packs
rm -rf ~/Library/Caches/Vibemetric                  # temporary files from versions before 0.1.1
defaults delete app.vibemetric.prod                 # preferences such as text size
```

Vibemetric does not modify your original transcript files. The selected CLI saves each scoring session in its own history (`~/.claude/projects` or `~/.codex/sessions`), like any other session; Vibemetric leaves those sessions out of later scores. Uninstalling Vibemetric does not remove them. The installed CLIs may maintain their own authentication caches and runtime logs.

### Troubleshooting

- **The scoring engine is not ready.** Install and sign in to the selected CLI, then click **Check again** on the first-assessment screen or in Settings. Vibemetric checks common install locations and your login shell’s PATH. An outdated Codex CLI shows an update message. An installed command still needs a valid sign-in.
- **No sessions found.** Use Claude Code or Codex for a while first. Vibemetric reads only `~/.claude/projects` and `~/.codex/sessions`.
- **Scoring stops with an error.** Common causes are being signed out, an unavailable model, or reaching your selected account’s usage limit. Check the selected CLI in Terminal. Vibemetric never automatically switches providers after a failure.
- **The selected Codex model is unavailable.** Check the CLI version shown in Vibemetric and update Codex, then click **Check again**. Older CLIs can reject GPT-6 models even when the same account works in a newer CLI. If the error remains with an updated CLI, check your account’s model access. Vibemetric keeps your chosen model.

## How it works

1. **Scan (local, about a second).** Parses `~/.claude/projects/**/*.jsonl` (subagent transcripts are folded into their parent session) and `~/.codex/sessions/**/rollout-*.jsonl` into normalized session timelines. Also computes heuristic signals such as spec language, memory writes and reads, verification after edits, fix→rerun loops, subagents, hooks, permission denials, and corrections.
2. **Evidence pack (local).** Writes a redacted digest to `~/Library/Application Support/Vibemetric/packs/<run>/`: `overview.md`, `sessions.tsv`, `leads.md`, `settings.md`, and one timeline per session under `sessions/`. Successful runs keep their evidence until the result is deleted; failed runs remove their pack.
3. **Assessment (your selected local CLI).** Both engines use the same [`rubric.md`](Sources/VibemetricCore/Resources/rubric.md), evidence pack, score-card schema and local totals.
   - **Claude Code:** `claude -p`, `stream-json`, `--json-schema`, tools restricted to `Read`, `Grep`, `Glob`, `--permission-mode dontAsk`, and `--setting-sources project`.
   - **Codex:** `codex exec --json --sandbox read-only --skip-git-repo-check`, `--output-schema` and `--output-last-message`. The prompt is sent through stdin. Personal config and execpolicy rules are skipped; hooks, plugins, apps, web search, multi-agent work and memory features are disabled for scoring. Saved CLI authentication is reused. Codex reads evidence through sandboxed shell commands.
   - Claude offers **Default (Sonnet)**, **Opus**, **Sonnet**, and **Haiku**. Default explicitly requests `sonnet`. Codex offers **Default (GPT 6.1 Sol)**, **Astra**, **Sol**, and **Luna**. Default explicitly requests `gpt-6.1-sol`; the named choices retain `gpt-6-astra`, `gpt-6-sol`, and `gpt-6-luna`. Availability depends on your CLI sign-in. Model preferences are saved separately per engine and also apply to automatic scores.
   - Results record the engine, requested model, CLI version, rubric version and saved CLI session ID, plus the actual model when the CLI reports it. Pro deep dives fork that session using the original engine and a copy of its saved evidence. Legacy results load as Claude Code results.

The selected CLI sends the digest and any transcript excerpts it reads to **Anthropic or OpenAI** under your own account. A build from this source makes no network calls of its own. The official app makes one kind on the free plan: about once a day, it checks `vibemetric.app/appcast.xml` for a new version, sending only the app version. In the official app, if you add a Vibemetric Pro key, the app checks your plan with the Vibemetric API, sending the key but never your sessions or transcripts. The key is stored in the macOS Keychain. Pro deep dives may also search the web for public documentation (**Settings → Account → Allow web research in deep dives**, on by default). Claude Code can open pages only on a fixed list of documentation sites; Codex uses its own web search. The prompt forbids putting transcripts or private project details into searches.

## Development

```bash
swift run VibemetricApp        # run the app from source
./scripts/build-app.sh         # build/Vibemetric.app (universal, ad-hoc signed)
VARIANT=dev ./scripts/build-app.sh   # "build/Vibemetric Dev.app"
swift test
```

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md); report security issues as described in [SECURITY.md](SECURITY.md).

### Optional modules and plug-in points

The app attaches optional features through the plug-in points in [`Extensions.swift`](Sources/VibemetricAppKit/Extensions.swift). In a build from this source they are all empty. The official app adds a private Pro module from a git-ignored `Pro/` folder: `Package.swift` adds it only when `Pro/` exists, and `build-app.sh` then turns Pro on. You never need `Pro/` to build, run or test the app.

### Release and dev builds

| | Release (`VARIANT=prod`, default) | Dev (`VARIANT=dev`) |
|---|---|---|
| App | `Vibemetric.app` | `Vibemetric Dev.app` |
| Bundle ID | `app.vibemetric.prod` | `app.vibemetric.dev` |
| Data folders | `~/Library/Application Support/Vibemetric`, `~/Library/Caches/Vibemetric` | `… /Vibemetric Dev` |
| Default API | production | develop |

The two builds keep separate preferences, Pro keys and privacy answers, so both can be installed together. Override the API with `defaults write <bundle ID> apiBaseURL <url>`. Builds before this split used the bundle ID `dev.vibemetric.app`; on its first launch, the release build copies the preferences and the saved Pro key from that ID once.

### Signing and notarization (for releases)

`build-app.sh` signs with a **Developer ID Application** certificate when one is in the keychain (or set `SIGN_IDENTITY`), and falls back to an ad-hoc signature otherwise. Ad-hoc builds work, but macOS forgets privacy answers (Documents access, notifications) after every rebuild.

To make a release that opens without warnings:

```bash
# once per Mac: store notarization credentials (prompts for an app-specific password)
xcrun notarytool store-credentials "vibemetric-notary" --apple-id you@example.com --team-id TEAMID

NOTARIZE=1 ./scripts/build-app.sh      # signs, notarizes and staples the app and build/Vibemetric.dmg
```

### Automatic updates (Sparkle)

Official release builds (with `Pro/`) check `https://vibemetric.app/appcast.xml` once a day with [Sparkle](https://sparkle-project.org) and offer new versions; **Vibemetric → Check for Updates…** checks immediately. Sparkle installs only updates signed with the project's EdDSA private key. Builds from source, dev builds and `swift run` never check.

One-time setup on the release Mac:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys          # stores the private key in the login Keychain, prints the public key
# save the printed public key in Resources/sparkle-public-key.txt and commit it
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key   # back up the private key somewhere safe, not in git
```

If the private key is lost, installed apps cannot accept new updates. To release:

```bash
VERSION=0.2.0 ./scripts/release.sh     # notarized build, website DMG, public/updates/, signed appcast
```

Then commit and deploy `vibemetric-web`. The build number (`CFBundleVersion`) is the commit count plus 100, so release from a committed state. `release.sh` stops unless `Pro/` is present, clean, and at its `origin/main`. If `swift package resolve` stops at "Downloading binary artifact", run `swift package resolve --disable-keychain`.

A command-line tool is included for development:

```bash
swift run vibemetric scan
swift run vibemetric pack --out /tmp/pack
swift run vibemetric assess --engine claude [--model opus|sonnet|haiku] [--out DIR]
swift run vibemetric assess --engine codex [--model MODEL_ID] [--out DIR]
```

Results are saved in `~/Library/Application Support/Vibemetric/results/`.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/VibemetricCore` | Parsers, signals, evidence pack, Claude Code/Codex runners, score-card model, Markdown renderer |
| `Sources/VibemetricAppKit` | SwiftUI app as a library: home/scan, live run view, score card, PNG share card |
| `Sources/VibemetricAppKit/Extensions.swift` | Plug-in points for optional modules (a stable interface) |
| `Sources/VibemetricApp` | Launcher: `main.swift` starts `VibemetricMain` from VibemetricAppKit |
| `Sources/vibemetric` | Development command-line tool |
| `scripts/build-app.sh` | Packages the `.app` bundle and the `.dmg` |
| `scripts/dmg-settings.py`, `scripts/make-dmg-background.swift` | DMG window layout and its background image |

## Not yet supported

- Cursor and Grok transcripts.
- Hosted share links.

### Optional live Codex check

`swift test` uses fixture CLIs and never spends model usage. To verify the installed Codex end to end with a single fictional session (no real transcripts), run:

```bash
VIBEMETRIC_LIVE_CODEX=1 swift test --filter LiveCodexTests
# Short synthetic persistence/fork checks (1 = both engines, or codex / claude):
VIBEMETRIC_LIVE_FORK=1 swift test --filter LiveSessionForkTests
```

This opt-in test requests `gpt-6-sol` using your signed-in Codex account and may consume plan usage or API credits. It requires that model to be available to the CLI account.

## License

[MIT](LICENSE). The Vibemetric name and logo are trademarks and are not covered by the license. The Claude Code and Codex icons in `Sources/VibemetricAppKit/Resources/Brand` belong to their owners; see `SOURCES.md` there.
