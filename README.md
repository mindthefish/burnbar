# Burnbar

A minimal, read-only macOS menu bar for subscription usage. Each configured profile
shows its remaining quota and reset time. All bars show remaining budget:
100% before any usage, 0% when exhausted. Credentials stay in their existing locations.

## Configuration

Open the popover's gear button to show **Settings**. Choose **Add subscription**,
select Codex or Claude, and choose the provider's existing configuration folder.
Enter a display name and a 1–2 character abbreviation, then choose a color with
the native macOS color picker. Settings also lets you edit, enable/disable, and
remove entries. Removing an entry leaves the provider's credentials untouched.

New configurations start empty; there is no automatic profile scan. Existing
configuration files are retained. Burnbar monitors already signed-in profiles;
it does not log in or renew their credentials.

The settings window saves to `~/.config/burnbar/config.json`. **Open config…**
opens this readable file for manual editing; **Reload** applies those changes.
Profile fields are written in a stable order: provider, name, indicator, home,
color, enabled, then the technical ID. The array order controls display order. Editing a subscription in Settings
preserves external edits to other entries and refuses a save if that subscription
changed in the file while its editor was open.

Example configuration:

```json
{
  "refreshIntervalMinutes": 5,
  "profiles": [
    {
      "provider": "claude",
      "name": "Claude",
      "indicator": "C",
      "home": "~/.claude",
      "color": "#E86E05",
      "enabled": true,
      "id": "claude"
    },
    {
      "provider": "codex",
      "name": "Privat",
      "indicator": "P",
      "home": "~/.codex",
      "color": "#29C270",
      "enabled": true,
      "id": "private"
    },
    {
      "provider": "codex",
      "name": "Arbeit",
      "indicator": "W",
      "home": "~/.codex-business",
      "color": "#7D33E8",
      "enabled": true,
      "id": "work"
    }
  ]
}
```

- Add profiles in Settings or by adding objects to `profiles`.
- Optional `color` is an opaque `#RRGGBB` value. Existing entries without a color
  retain their original provider accent.
- IDs must be unique and indicators must contain 1–2 non-whitespace characters.
- `home` is the provider's configuration directory, using an absolute path or `~/`.
  Choose the configuration folder (for example `~/.codex`), not the app installation directory.
  No symlink or credential-source setting is needed.
- `refreshIntervalMinutes` is global, defaults to 5 when omitted, and accepts integer
  values from 5 to 1440. Provider rate-limit backoff can delay scheduled requests further.
  The refresh button bypasses that backoff, but never prompts for credential access.
- Disabled profiles perform no credential reads or usage requests. All-disabled
  configurations keep a Burnbar icon so settings remain accessible.
- Invalid files show an error and retain the last valid configuration in memory.
  At startup without a valid file, the subscription list stays empty.

Codex reads only `<home>/auth.json`. Claude prefers a valid `<home>/.credentials.json`,
then looks up the matching macOS Keychain item. Custom Claude config directories use
separate Keychain service names. Background reads never display permission dialogs;
when needed, click **Allow credential access…** in the affected profile's card.
Only that explicit action permits a macOS access dialog. Burnbar does not renew tokens.

## Limit windows

No limit setup is required. Codex window durations come from `limit_window_seconds`;
any positive duration is displayed, including `8.75h`. The menu bar tracks the
shortest reported window, with a longer-window outline when it extends beyond the
short-window fill. Claude currently supplies named `five_hour` and `seven_day`
windows; unsupported duration metadata is not guessed. The popover lists the
available windows with remaining percentages and reset times.

## Boundaries

Burnbar must not:

- log in, switch, refresh, or manage provider accounts;
- start CLIs, sessions, prompts, or background agents;
- inspect prompts, transcripts, source code, costs, token history, or projects;
- log or persist OAuth tokens;
- send data anywhere except the provider usage endpoint for the credential being read;
- use analytics, telemetry, automatic updates, or third-party runtime dependencies.

Unavailable, expired, malformed, or unsupported data is **unavailable**, never zero usage.
A failed refresh retains any last-known quota as stale.

Each card shows the last successful update. Failed requests keep that timestamp
and dim the retained bars; the header reports the oldest displayed data. Reloading
an unchanged configuration does not trigger another refresh. Profiles sharing the
same provider folder perform one request per refresh cycle. Scheduled Codex requests
back off after HTTP 429 and honor Retry-After (up to one day); manual refresh bypasses
backoff. Network sessions use no disk cache, stored cookies, or credential storage.

## Build and install

Requires macOS 14 or newer and an Xcode toolchain with Swift 6. Burnbar uses only
system frameworks. Both Apple Silicon and Intel are supported.

```sh
swift test
Scripts/test-build-app.sh
CODESIGN_IDENTITY=- Scripts/build-app.sh
```

The build script installs to `/Applications` by default; pass another existing,
writable directory to build there. It signs and verifies a staged bundle before
replacing an existing installation, and restores the previous app on failure.
It does not restart a running copy. Quit Burnbar from its popover and reopen the
installed app to use a new build.

Local builds use ad-hoc signing by default. Set `CODESIGN_IDENTITY` to a valid
certificate for stable Keychain authorization across rebuilds. An explicitly
requested missing identity fails the build. Public downloads require Developer ID
signing and notarization; ad-hoc signing does not provide Gatekeeper trust.

Burnbar registers as a login item when launched from an app bundle. Disable it in
System Settings → General → Login Items. To uninstall, quit Burnbar, disable its
login item, and remove Burnbar.app. The optional `~/.config/burnbar` configuration
can be removed separately; provider credentials remain untouched.

## Versions and releases

Use `main` for development and immutable `vMAJOR.MINOR.PATCH` tags for releases.
A separate long-lived release branch is unnecessary for this first version.
Before 1.0, increment the minor version for features or incompatible config changes
and the patch version for compatible fixes. Start the Family & Friends series at
`0.1.0`; the old hard-coded bundle version was not a published release.

GitHub Actions runs tests and a native build for pushes and pull requests. A version
tag builds a Universal app for Apple Silicon and Intel, packages it, and creates a
**draft** prerelease. Check the app and release notes before publishing the draft.
CI builds are ad-hoc signed and not notarized; the draft states this explicitly.

For a notarized download, use `Scripts/release-app.sh` with a Developer ID Application
identity and a previously configured notary Keychain profile. This builds, signs
with hardened runtime, notarizes, staples, verifies, and creates a local ZIP.
It does not publish a release or upload credentials to GitHub.

Version, build number, and architecture can be supplied through `BURNBAR_VERSION`,
`BURNBAR_BUILD`, and `BURNBAR_ARCH`; see the scripts for supported values. Record
user-facing changes in CHANGELOG.md. Tags and release artifacts should never be
replaced after publication.

## Provider compatibility

Burnbar reads existing local credentials and uses first-party usage endpoints.
These are not a stable public integration contract. Claude subscription OAuth
integration in third-party software requires clarification with Anthropic before
public support is promised. Family & Friends builds are experimental; Burnbar
never logs in, rotates credentials, or imitates the official provider clients.

## License

MIT. See [LICENSE](LICENSE).
