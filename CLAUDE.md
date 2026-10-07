# Burnbar project rules

## Product boundary

Burnbar is a passive, read-only usage monitor. Never add account switching, account onboarding, credential writes, CLI launching, session execution, usage forecasts, history, notifications, telemetry, or automatic updating.

## Security

- OAuth tokens are sensitive input. Never print, log, cache, copy, or commit them.
- Read each credential source only when refreshing its matching provider. The Claude token may be held in memory for the process lifetime and re-read when the API rejects it, because Claude Code rotates the token and rewrites the Keychain item, which otherwise re-prompts on every refresh. Never write a token anywhere.
- Send a token only to the matching first-party usage endpoint over HTTPS.
- Do not fall back from one account to another.
- Model unavailable data explicitly. Never invent a percentage, reset timestamp, or plan name.

## Implementation

- Target native macOS with Swift and system frameworks only.
- Keep the app dependency-free: no package manager dependencies and no embedded web runtime.
- Keep the menu bar passive: configured subscription bars only, no numbers. Bar fill shows remaining quota.
- Keep the click popover accessible and compact; it is the only place that shows percentages and exact reset timestamps.
- Source code, comments, identifiers, and commit messages are English.

## Verification

- Add tests before each behaviour slice.
- Run focused tests, the full test suite, formatter/linter if configured, and `git diff --check` before a commit.
- Do not commit credentials, generated secrets, local caches, or user-specific usage snapshots.

## Continuity

Before resuming work, read this file, README.md, and `git status`. Local plans and handoffs are not product documentation and must remain uncommitted.
