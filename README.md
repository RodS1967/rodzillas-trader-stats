# RodZilla's Trader Stats

> **Work in progress.** The PC version below is stable and feature-complete. Console (Xbox/PlayStation) support is published and running on real hardware, but the console screen itself is still being redesigned — see **Status** below for what's incomplete there.

RodZilla's Trader Stats is a focused guild trader add-on for the Elder Scrolls Online: a weekly sales table (date range, kiosk, sales count, gold total, tax) plus Top 3 Sellers leaderboards for the current period and all time, built straight from your guild's trader history. Hit Refresh any time for an up-to-date snapshot. No bundled unrelated features, no bloat — just your numbers.

**Status:** feature-complete on PC. Settings -> Add-Ons entry (or `/rzts`) with a guild picker, a weekly sales table capped at the 6 most recent weeks, and side-by-side Top Sellers sections for the current period and overall. Each scan is a point-in-time snapshot (not a live tracker) — switch guilds or hit Refresh for a fresh one. Published and running on Xbox/PlayStation (see **Platforms** below), but the console UI is still under active development — the current screen has no way to scroll past the Guild/Refresh controls, so a redesigned, scrollable console screen is in progress.

## Requirements

- [LibHistoire](https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html) and its dependencies (LibAsync, LibCustomMenu, LibDebugLogger, LibAddonMenu-2.0) — easiest installed via [Minion](https://www.minion.gg)

## Installing (development builds)

Copy the `RodZillaTraderStats` folder into:
```
Documents\Elder Scrolls Online\live\AddOns\
```

## Platforms

Built PC-first. Xbox Series X|S / PS5 support is implemented in the same codebase, not a separate fork — the add-on detects at runtime whether it's running under ESO's keyboard-UI (PC) or gamepad-native console UI and renders accordingly, the same way LibAddonMenu-2.0 itself handles the PC/console split internally. Published to console via ZOS's console Add-On Uploader and confirmed running on real hardware, but the console screen itself is still under active development (see **Status** above).

## More detail

See [PROJECT_BRIEF.md](PROJECT_BRIEF.md) for the full history: design decisions, researched technical constraints, and progress log.

## License

MIT — see [LICENSE](LICENSE).
