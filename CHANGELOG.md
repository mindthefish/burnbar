# Changelog

## 0.3.0 — 2026-10-13

- Give quota windows more separation when fewer subscriptions are visible: three physical pixels for one subscription, two for two, and one for three.
- Draw quota fills in front of the outline in the menu bar and popover.
- Add Heart to the built-in subscription symbols.
- Change the macOS bundle identifier to `es.tuschy.burnbar`; the existing configuration location is unchanged.

## 0.2.0 — 2026-10-13

- Show each subscription's quota windows as separate fills inside one menu bar capsule, ordered from shortest to longest.
- Improve readability with pixel-aligned fills, neutral tracks, subtle outlines, and label sizes adapted to the number of active subscriptions.
- Optionally color each limit by its remaining quota, with configurable full and empty colors. The full color also identifies the subscription in Settings.
- Choose a two-character abbreviation, emoji, or a built-in SF Symbol for each subscription.
- Reorder subscriptions by dragging their handles in Settings; the same order appears in the menu bar and popover.
- Refresh the Settings layout so three subscriptions fit without scrolling, with at most three active at a time.
- Keep all profiles from older configurations; if more than three were active, keep the first three active in their saved order.
- Preserve the existing dimmed last-known values and dashed unavailable indicators.

## 0.1.0 — 2026-10-07

First preview release for macOS 14 and later, supporting Apple Silicon and Intel.

- Monitor remaining quota for Codex and Claude accounts in the menu bar.
- View all available limits, remaining percentages, and reset times in the popover.
- Add and manage subscriptions with folder selection, names, abbreviations, and colors.
- Start quietly in the menu bar, with optional launch at login.
- Keep the last known values visible when a refresh fails, with an explanation and data age.
- Refresh automatically or manually, with a shared interval in Settings.
- Verify downloads with SHA-256 checksums and signed build provenance.
