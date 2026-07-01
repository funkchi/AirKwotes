# Changelog

## 0.1.0

First public release.

- Menu-bar ring showing one provider's remaining quota; click for a dropdown of all providers.
- Quota providers: Claude Code, Codex, DeepSeek, Kimi (Moonshot), GLM (Zhipu / Z.ai), OpenRouter, SiliconFlow; key-validation for OpenAI / Gemini-key / Qwen / Anthropic / Mistral / xAI.
- Keyless readers for Claude Code and Codex (reuse local CLI logins/tokens).
- Weekly/secondary window shown in the dropdown and detail panel.
- Settings: polling interval, launch-at-login, low-quota notifications + threshold, menu-bar appearance.
- Reminders: arm a one-shot macOS Reminder from the popover / Providers tab, fired on the next refresh.
- Relay: local loopback server on `127.0.0.1:8787`, OpenAI-style (`/v1`) and Gemini-style (`/v1beta`) endpoints, Codex OAuth + Gemini (Code Assist) OAuth with reuse-existing-login.
- Secrets in the macOS Keychain; provider/relay preferences in UserDefaults.
