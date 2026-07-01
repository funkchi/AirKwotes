# AirKwotes

A macOS menu-bar app that tracks your AI subscription quotas and (optionally)
exposes those subscriptions as local OpenAI/Gemini-compatible endpoints.

The menu bar shows a **ring** for one chosen provider's remaining quota; click
it for a dropdown of every provider. Keys live in the macOS Keychain; most
quota readers are **zero-config** — they reuse the logins Claude Code / Codex /
Gemini CLI already store on your machine.

> ⚠️ **Terms-of-service notice.** AirKwotes reads rate-limit logs and, for the
> relay, forwards requests to upstream subscriptions (OpenAI Codex, Google
> Gemini Code Assist) using credentials those CLIs already store. This may
> violate the terms of Anthropic, OpenAI, and/or Google. Use it only for
> personal, research, and interoperability purposes, and review each provider's
> agreement yourself. All risk is yours; the author takes no responsibility for
> account bans, service interruption, or any other consequence.

---

## What it tracks / relays

### Quota providers
| Provider | How it's read | Notes |
| --- | --- | --- |
| **Claude Code** | OAuth token from Claude Code's Keychain item / `~/.claude` → Anthropic API rate-limit headers (5h + 7d windows). Falls back to statusline/log snapshots. | Zero-config, keyless |
| **Codex** | `~/.codex/sessions/**/*.jsonl` `rate_limits` (5h + weekly) | Zero-config, keyless |
| **DeepSeek** | `GET /user/balance` | API key |
| **Kimi (Moonshot)** | `GET /v1/users/me/balance` | API key |
| **GLM (Zhipu / Z.ai)** | `/api/monitor/usage/quota/limit` (5h token window + monthly MCP) | Anthropic-auth-token |
| **OpenRouter** | `GET /api/v1/key` (spend limit + usage) | API key |
| **SiliconFlow** | `GET /v1/user/info` (balance + total) | API key |
| OpenAI, Gemini (key), Qwen, Anthropic (key), Mistral, xAI | Key validation only | No public quota API |

### Relay (subscription → local API)
| Upstream | Local endpoint | Status |
| --- | --- | --- |
| **Codex (ChatGPT)** | `http://127.0.0.1:8787/v1/...` | OAuth + models; forwarding in progress |
| **Gemini (Code Assist)** | `http://127.0.0.1:8787/v1beta/...` | Forwards to `cloudcode-pa.googleapis.com` (needs the account onboarded) |

The relay is **loopback-only** and authenticated by a local `sk-…` key you copy
from the Relay tab.

---

## Install

### Option A — Homebrew (unsigned 0.1.0)
```sh
brew tap funkchi/airkwotes
brew install --cask airkwotes
```
The cask strips the Gatekeeper quarantine flag on install. On the very first
launch, right-click the app → **Open** → **Open** (or run
`xattr -dr com.apple.quarantine /Applications/AirKwotes.app`).

### Option B — Direct download
Grab `AirKwotes-0.1.0.dmg` from the
[releases page](https://github.com/funkchi/AirKwotes/releases), drag to
**Applications**, then right-click → **Open** the first time (Gatekeeper
prompt — the app is not yet notarized).

### Option C — Build from source
Requires macOS 14+ and the Xcode command-line tools.
```sh
git clone https://github.com/funkchi/AirKwotes.git
cd AirKwotes
make cert      # one-time: local self-signed identity (stops Keychain prompts)
make run       # build, sign, launch
```

---

## Using it

1. The menu-bar ring shows one provider. Click it for the dropdown of all.
2. Open **Manage** (or the setup window) → **Providers** tab → **+** to add a
   provider and paste its key (stored in Keychain). For Claude Code / Codex /
   Gemini CLI users, no key is needed — the local reader works automatically.
3. **Settings** tab: polling interval, launch-at-login, low-quota
   notifications + threshold, menu-bar appearance.
4. **Relay** tab: sign in with ChatGPT and/or Google (or reuse an existing
   Codex/Gemini CLI login), toggle the server, then point your tools at
   `http://127.0.0.1:8787/v1` (OpenAI-style) or `/v1beta` (Gemini-style).

---

## Architecture

- **SwiftUI** menu-bar app (`LSUIElement`, no Dock icon), built with a
  zero-dependency `Makefile` (`swiftc` → `.app`). `project.yml` is included for
  [xcodegen](https://github.com/yonaskolb/XcodeGen) users (`make xcode`).
- `Sources/Providers/` — one `QuotaProvider` per upstream; keyless local
  readers (Claude/Codex) parse JSONL rate-limit logs or live API headers.
- `Sources/Relay/` — `LoopbackHTTPServer` (Network.framework) +
  `RelayServer` (routes) + per-upstream OAuth clients and forwarders.
- `Sources/State/` — `AppState` (providers, snapshots, polling, reminders),
  `RelayManager` (OAuth + server lifecycle), `KeychainStore` (all secrets).

See [`docs/providers.md`](docs/providers.md) and [`docs/relay.md`](docs/relay.md).

---

## Releasing (maintainers)

One command cuts a GitHub Release with a `.dmg`:
```sh
scripts/release.sh 0.2.0
```
This bumps `Info.plist`, tags `v0.2.0`, builds + packages the dmg, computes its
sha256, updates the Homebrew cask, and uploads the asset via `gh`.

Releases are currently **unsigned**. With an Apple Developer ID:
```sh
make release SIGN_IDENTITY="Developer ID Application: funkchi"
make notarize   # needs AC_TEAM_ID + AC_KEYCHAIN_PROFILE (xcrun notarytool)
```

---

## License

[MIT](LICENSE) — Copyright © 2026 funkchi.
