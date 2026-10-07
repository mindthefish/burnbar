# Burnbar

Your remaining Codex and Claude quota, at a glance in the macOS menu bar.
Click a bar to see usage limits, remaining percentages, and reset times.

[Download Burnbar](https://github.com/mindthefish/burnbar/releases) · [Report an issue](https://github.com/mindthefish/burnbar/issues)

## Install

Requires **macOS 14 or later**. Supports Apple Silicon and Intel Macs.

1. Download the ZIP from [Releases](https://github.com/mindthefish/burnbar/releases).
2. Unzip it and move **Burnbar.app** to **Applications**.
3. Open Burnbar. It starts in the menu bar.

The current preview is not notarized. If macOS blocks it, follow
[Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445).
Only approve the app if you trust its source.

To check a download, save the ZIP and `SHA256SUMS` from the same release in one
folder. Open Terminal in that folder and run `shasum -a 256 -c SHA256SUMS`.
The ZIP should report `OK`.

## Add a subscription

Sign in through Codex or Claude Code first. Then:

1. Click Burnbar in the menu bar and open **Settings** with the gear button.
2. Choose **Add subscription** and select Codex or Claude.
3. Choose that account's configuration folder: usually `~/.codex` for Codex or
   `~/.claude` for Claude Code. Use the matching folder for a custom account setup.
4. Choose a name, a short abbreviation, and a color, then save.

Add multiple accounts by selecting their respective folders. You can edit,
disable, or remove subscriptions in Settings. Removing a subscription from
Burnbar leaves its account and credentials untouched.

If a Claude subscription needs Keychain permission, click **Allow credential
access…** in its card. Background refreshes do not show permission dialogs.

## Read the bars

- A full bar means **100% remaining**; an empty bar means the quota is exhausted.
- Each subscription has one menu bar row, tracking its shortest available limit.
  An outline can show the remaining quota of a longer limit.
- Click Burnbar to see all limits and their reset times. Limits are detected
  automatically; there is nothing to configure for them.
- Dimmed bars show the last known values after a failed refresh. The popover
  shows the reason and when those values were last updated.

Usage refreshes automatically. Change the shared interval in Settings, or click
Refresh in the popover to check immediately. Provider rate limits can delay
background refreshes.

## Privacy

Burnbar reads existing credentials to request usage information directly from
Codex and Claude. It does not sign in, renew credentials, run prompts, or consume
model tokens. It does not read your conversations or projects, save credentials,
or collect analytics. Provider changes may affect compatibility.

## Preferences and removal

Burnbar starts at login. You can disable this in **System Settings → General →
Login Items**.

For manual editing, **Open config…** in Settings opens
`~/.config/burnbar/config.json`. Use **Reload** after saving changes.

To update, quit Burnbar, replace the app in Applications, and reopen it.
To uninstall, quit it, disable its login item, and remove Burnbar.app. You may
also remove `~/.config/burnbar`; provider credentials remain untouched.

## Build from source

Requires an Xcode toolchain with Swift 6. There are no external dependencies.

```sh
swift test
Scripts/build-app.sh
```

The build script installs to Applications. For another destination, pass an
existing writable directory as its argument.

## License

[MIT](LICENSE).
