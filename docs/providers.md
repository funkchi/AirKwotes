# Providers

Each provider conforms to `QuotaProvider` (`Sources/Providers/QuotaProvider.swift`)
and returns a `QuotaSnapshot` (remaining %, used/total, reset time, optional
secondary window, status). The registry lives in `Providers.registry()`.

## Keyless (zero-config) local readers

These need no API key. They reuse credentials/logs the CLIs already store.

### Claude Code — `ClaudeCodeProvider`
Resolution order (first hit wins):
1. **Live headers** (`ClaudeSubscriptionUsage`): discovers the OAuth token, sends
   `POST /v1/messages` (`claude-haiku-4-5`, `max_tokens: 1`) and reads the
   **`anthropic-ratelimit-unified-*`** response headers for the 5h / 7d windows.
2. **Statusline capture**: `~/.claude/airkwotes-rate-limits.json` (written by a
   statusline hook).
3. **Transcript logs**: tail-reads `~/.claude/projects/**/*.jsonl` for
   `rate_limits` objects.

Credentials (`ClaudeCodeCredentials`) — genuine Anthropic OAuth only (it
deliberately does **not** read `ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_API_KEY`, so it
won't hijack a GLM/Z.ai gateway):
- macOS Keychain item `Claude Code-credentials`, or
- `~/.claude/.credentials.json`.

Both store `{ claudeAiOauth: { accessToken, expiresAt } }`. Auth uses
`Authorization: Bearer …` + `anthropic-version: 2023-06-01` +
`anthropic-beta: oauth-2025-04-20`.

### Codex — `CodexProvider`
Reads `~/.codex/sessions/**/*.jsonl` (tail 2 MB × 120 newest files) for
`token_count.rate_limits` (primary 5h + secondary weekly). Timestamps are
ISO-8601 with fractional seconds. Falls back to
`~/.codex-usage-tracker/allowance.json`.

## API-key providers

| Provider | Endpoint | Returns |
| --- | --- | --- |
| DeepSeek | `GET api.deepseek.com/user/balance` | account balance (CNY) |
| Kimi (Moonshot) | `GET api.moonshot.ai/v1/users/me/balance` | balance |
| GLM (Zhipu) | `GET open.bigmodel.cn/api/monitor/usage/quota/limit` | 5h token window + monthly MCP |
| GLM (Z.ai) | `GET api.z.ai/api/monitor/usage/quota/limit` | as above |
| OpenRouter | `GET openrouter.ai/api/v1/key` | spend limit + usage (USD) |
| SiliconFlow | `GET api.siliconflow.cn/v1/user/info` | balance + total |

## Key-validation-only providers
OpenAI, Gemini (API key), Qwen, Anthropic, Mistral, xAI have no public quota
API; the app validates the key against a lightweight `/models` call and reports
"key valid".

## Snapshot model
`QuotaSnapshot` carries `remainingPercent` (drives the ring), `remainingDisplay`,
`usedDisplay`, `totalDisplay`, `resetAt`, a `status`
(`ok`/`low`/`critical`/`invalid`/`unsupported`/`error`), and an optional
secondary window (`secondaryRemainingPercent` + `secondaryLabel`) shown for
Codex/Claude weekly and GLM monthly MCP.

Transient failures are suppressed: `AppState` keeps the last good snapshot until
a provider fails `failureThreshold` (3) consecutive times, so the UI doesn't
flicker "sync failed" on a network blip.
