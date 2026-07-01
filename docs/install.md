# Install AirKwotes on macOS

This guide is for people who just want the app running, without building from
source or touching developer tools.

## Download

1. Open the [AirKwotes Releases page](https://github.com/funkchi/AirKwotes/releases).
2. Download the newest file ending in `.dmg`.
3. Double-click the downloaded `.dmg` file.
4. Drag **AirKwotes** into **Applications**.

## First Launch

AirKwotes is currently not notarized by Apple, so macOS may block the first
launch.

1. Open **Applications** in Finder.
2. Right-click **AirKwotes**.
3. Choose **Open**.
4. Click **Open** again in the macOS warning dialog.

After that first approval, you can open AirKwotes normally.

## Add Providers

1. Look for the AirKwotes ring in the macOS menu bar.
2. Click it, then choose **Manage**.
3. Open the **Providers** tab.
4. Add the providers you use.

Claude Code, Codex, and Gemini can usually work without an API key because
AirKwotes reads local usage signals from those tools on your Mac.

For API-key providers such as OpenRouter, DeepSeek, Kimi, GLM, or SiliconFlow,
paste your key when prompted. AirKwotes stores secrets in the macOS Keychain.

## Optional: Local Relay

The Relay tab is for advanced local workflows. It lets tools connect to
AirKwotes at `http://127.0.0.1:8787` using a local `sk-...` key.

You can ignore this tab if you only want quota tracking.

## Common Fixes

If the app does not open, make sure you used right-click -> **Open** for the
first launch.

If a provider says it is waiting for usage, run that provider's normal CLI app
once, then ask AirKwotes to refresh.

If macOS asks for Keychain access, choose **Always Allow** for AirKwotes so it
can read the keys or tokens you saved for tracking.
