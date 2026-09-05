# RodZilla's Trader Stats

A focused Elder Scrolls Online add-on that tracks your guild trader sales history and turns it into clean statistics — count, totals, min/max/average price per item. No bundled unrelated features, no bloat.

**Status:** early development. The add-on loads in-game and initializes its saved data, but the actual guild-history tracking (via [LibHistoire](https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html)) and the UI are still being built.

## Requirements

- [LibHistoire](https://www.esoui.com/downloads/info2817-LibHistoire-GuildHistory.html) and its dependencies (LibAsync, LibCustomMenu, LibDebugLogger, LibAddonMenu-2.0) — easiest installed via [Minion](https://www.minion.gg)

## Installing (development builds)

Copy the `RodZillaTraderStats` folder into:
```
Documents\Elder Scrolls Online\live\AddOns\
```

## Platforms

Built PC-first, with Xbox Series X|S / PS5 support planned — same codebase for both (ESO's gamepad-mode UI support makes this a single add-on, not separate platform forks).

## More detail

See [PROJECT_BRIEF.md](PROJECT_BRIEF.md) for the full history: design decisions, researched technical constraints, and progress log.

## License

MIT — see [LICENSE](LICENSE).
