# Relay (subscription → local API)

The relay exposes an OpenAI/Gemini subscription as local endpoints so tools
like opencode can point at `http://127.0.0.1:8787`.

## Pieces
- `Sources/Relay/LoopbackHTTPServer.swift` — minimal HTTP/1.1 server on
  `Network.framework`, bound to **127.0.0.1 only**. Supports full-body and
  streaming (SSE) responses.
- `Sources/Relay/RelayServer.swift` — routes:
  - `GET /` — human-facing landing page (status, accounts, opencode snippet).
  - `GET /health` — JSON status.
  - `GET /v1/models`, `POST /v1/responses`, `/v1/chat/completions` — OpenAI-style.
  - `GET /v1beta/models`, `POST /v1beta/models/{model}:generateContent`
    / `:streamGenerateContent` — Gemini-style.
  - All `/v1*` / `/v1beta*` routes require `Authorization: Bearer <local-sk>`.
- `Sources/Relay/RelayManager.swift` — `@MainActor` store: OAuth lifecycle,
  server start/stop, lazy Keychain reads, token refresh, project resolution.
- `CodexOAuth.swift`, `GeminiOAuth.swift` — PKCE OAuth flows that mirror the
  official CLIs (public Codex client id; Google "Gemini Code Assist" client).
- `CodeAssistClient.swift` — Gemini forwarding to `cloudcode-pa.googleapis.com`
  (wrap standard request → Code Assist `{model, project, user_prompt_id,
  request:{…}}`, unwrap `{response:{…}}`; streaming via `alt=sse`).

## Behavior
- **Loopback-only**; never binds a public interface (no firewall prompt).
- Local `sk-airkwotes-…` key minted on first relay start, stored in Keychain.
- Auto-starts on launch if enabled (persisted in UserDefaults), with a one-shot
  retry to survive the relaunch port race.
- Reuse-existing-login: reads `~/.codex/auth.json` and `~/.gemini/oauth_creds.json`
  so users of those CLIs need no extra sign-in.

## Status (0.1.0)
- **Codex** (`/v1/responses`): OAuth + model list implemented; request
  forwarding to `chatgpt.com/backend-api/codex/responses` is in progress.
- **Gemini** (`/v1beta/...`): forwards to Code Assist and returns the real
  upstream result. `generativelanguage.googleapis.com` rejects the subscription
  OAuth scopes (403), so the internal Code Assist protocol is required. An
  account must be **onboarded** (`onboardUser`) for `generateChat` to be
  permitted; if not, the relay surfaces the upstream 403 verbatim.

## Why loopback and not "interception"
The relay is a **local endpoint you point tools at** (set `OPENAI_BASE_URL` /
`OPENAI_API_KEY`, or the Gemini base). It does not MITM running clients — that
would require a system TLS proxy and a trusted CA, which is fragile and nasty.
