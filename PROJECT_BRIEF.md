# Project Brief: RodZilla's Trader Stats (ESO Add-on)

## Concept

A focused ESO add-on that consolidates guild trader sales history into a clean statistics view — count, totals, min/max/average price per item. Motivated by existing bundled trading toolkits (e.g. Arkadius' Trade Tools) being unstable and cluttered with unrelated features; this add-on does the one thing, well.

## Locked-In Decisions (as of 2026-09-04)

- **Name:** RodZilla's Trader Stats (display title). Internal code-safe namespace: `RodZillaTraderStats`.
- **Platform sequencing:** PC first (fast local test loop via the `AddOns` folder), Xbox Series X|S/PS5 second (official ZOS uploader tool required to test on console, no local sideload). Design decisions below made with Xbox constraints in mind from the start so the PC version doesn't need a late rework.
- **Not this project:** the earlier TamMaps standalone companion app (on hold — see `../tammaps/PROJECT_BRIEF.md`). This is a separate, smaller, and much lower-legal-risk project: it's an in-game UI add-on distributed through ZeniMax's own official add-on system, not a third-party app reproducing their assets externally.

## Key Technical Facts (researched — don't re-litigate casually)

- **ESO console add-on support** launched with Update 46 (June 2025), Xbox Series X|S and PS5 only (not Xbox One/PS4, not PC — PC already had add-ons separately for years). UI add-ons only, no gameplay/asset changes.
- **Console constraints to design around from day one:**
  - Gamepad-mode UI required (controller navigation, keybind-strip actions — not mouse-hover/keyboard-only).
  - 100MB total add-on size cap (all installed add-ons combined) and less available memory than PC.
  - No screenshot / base-game-settings API access on console (not relevant to this add-on).
  - Console add-ons are submitted/tested via ZOS's official Add-On Uploader tool, distributed through Bethesda.net rather than ESOUI — no manual file-drop test loop like PC.
- **Guild History API is rate-limited by the game itself, not addon-specific:** ~1 page per minute per guild. Any add-on reading guild trader sales history hits this; it's why initial history loads take a long time for active guilds. Design around it (background/resumable loading), don't fight it.
- **LibHistoire** (by sirinsidiator, license **Artistic-2.0** — confirmed, permissive, fine for a free add-on) is the community-standard caching layer built specifically to solve the rate-limit/server-destabilization problem. Declared as a manifest dependency (not bundled) — standard practice so multiple add-ons sharing it don't duplicate/conflict. **LibHistoire's exact event-registration API still needs to be pulled and verified before wiring up `RZTS.RecordSale` — do not guess at function signatures.**
- **Data/memory strategy:** store aggregated per-item statistics only (count, gold total, min/max/avg price, last N sale timestamps) — not a permanent raw event log. Keeps footprint small regardless of guild sales volume, important given the console memory/size constraints above. Exact retention depth (how many recent sales to keep in detail) to be tuned once real data volume is observed.
- **Current APIVersion (as of 2026-09-04):** `101050` (live, patch "2026 Season 0 - Part 2"). Note: PTS is already on `101051` for a patch expected live **2026-09-28** — the manifest's `## APIVersion` will need updating around then to keep the add-on loading on live servers.
- **ESO base game is not free-to-play** — $19.99 on Steam, frequently on sale (as low as ~$5, historic low $1.99). Needed on PC for the dev/test loop.

## Current Scaffold

`RodZillaTraderStats/` contains:
- `RodZillaTraderStats.txt` — manifest (Title, Version, APIVersion, SavedVariables, `DependsOn: LibHistoire LibStub LibAddonMenu-2.0`)
- `RodZillaTraderStats.lua` — `EVENT_ADD_ON_LOADED` handler, `ZO_SavedVars` initialization (account-wide, aggregated `itemStats` table), a LibAddonMenu-2.0 panel registration (Settings -> Add-Ons entry + `/rzts` shortcut), and a real `ZO_Scene`/`ZO_FadeSceneFragment` for the window (see Progress Log) so it behaves like a native ESO menu. Still a TODO: LibHistoire event wiring into `RZTS.RecordSale`.
- `RodZillaTraderStats.xml` — the window itself: a `TopLevelControl` with a backdrop, title, and `ZO_CloseButton`.

## Progress Log

- **2026-09-04:** ESO installed on PC (`C:\Games\Zenimax Online\The Elder Scrolls Online`, Steam). LibHistoire + its four sub-dependencies (LibAsync, LibCustomMenu, LibDebugLogger, LibAddonMenu-2.0 — Minion didn't auto-pull these, had to add manually, easy to find) installed via Minion into the correct location, `Documents\Elder Scrolls Online\live\AddOns\` — **not** the look-alike decoy `AddOns` folder that exists inside the game's install directory (a real gotcha: ESO creates that folder too, but doesn't read addons from it; Minion's install path setting had to be corrected to point at Documents instead). `RodZillaTraderStats` copied into the correct AddOns folder alongside them. **Confirmed: shows up as a valid, recognized addon in ESO's in-game Add-Ons menu, no errors** — manifest and `DependsOn: LibHistoire` dependency chain both resolved correctly. The chat "loaded" message wasn't visually confirmed yet — developer is testing via ESO's gamepad-UI accessibility mode (same underlying UI system as the Xbox build, so an early incidental gamepad-mode data point), where chat may be hidden by default. Not yet root-caused; low-priority since the addon-list validity check already confirms the real milestone (plumbing works end to end: manifest → dependencies → load, no runtime errors surfaced).
- **2026-09-05:** Repo created (private, GitHub, MIT license under "Team RodZilla LLC"). First real functionality: a custom window (`RodZillaTraderStatsWindow`) that opens and closes. Along the way: (1) discovered ESO's "Add-Ons" settings screen only enables/disables addons — it doesn't launch a UI, so a trigger mechanism is needed; initially used a `/rzts` slash command. (2) Learned the Xbox-style "pick an addon from a menu, interact with it" experience is actually **LibAddonMenu** (LAM, already installed transitively via LibHistoire) + **LibGamepad**/LibGamepadOptions for gamepad-mode access — not a console-exclusive feature. Added LAM registration (declared as an explicit dependency, plus its own dependency **LibStub**, which wasn't installed and needed adding) giving a native Settings -> Add-Ons entry with an "Open Stats Window" button, replacing the raw slash command as the primary trigger. (3) Hit a real bug: the close button's XML `OnClicked` calling `RodZillaTraderStats.HideWindow()` failed at runtime (`function expected instead of nil`) even though the identical-shaped `ShowWindow()` call from the LAM button worked fine — root cause not fully confirmed, but a real working addon's source (GuildStoreTools) showed the standard pattern calls `:SetHidden()` directly on the control from XML rather than routing through the addon's own table; switching to a direct call fixed it. (4) Discovered custom windows don't auto-close on Escape or combat by default (confirmed via research) — fixed Escape by converting the window into a genuine `ZO_Scene` + `ZO_FadeSceneFragment` (verified against the actual base-game source at github.com/esoui/esoui, not just addon examples), which gets Escape-to-close for free since that's the scene manager's own built-in behavior, no custom keybind code needed. Side effect (expected, not a bug): opening the window now closes other open menus/scenes, since ESO scenes are mutually exclusive by design — confirmed this matches the original "modal" vision. Combat auto-close is still an open TODO (`EVENT_PLAYER_COMBAT_STATE`, confirmed not automatic). Decided (per developer) that a LAM settings panel is the right home for input controls (guild picker, "gather" button, once built), while the custom window/scene stays reserved for displaying actual results later, once LibHistoire wiring exists — not an either/or. Developer has no PC guild yet (feelers out), so guild-list/data-gathering work is blocked until that's resolved.

## Open / Next Steps

1. ~~Install ESO on PC~~ — done, see Progress Log.
2. ~~Get LibHistoire + dependencies installed and confirm the add-on loads~~ — done, see Progress Log.
3. ~~Confirm the "loaded" chat message / basic window open-close~~ — done; window now opens via Settings -> Add-Ons or `/rzts`, closes via close button or Escape (real `ZO_Scene`).
4. Blocked: guild-picker dropdown + "gather" button in the LAM panel — needs developer to actually be in a PC guild first.
4. Pull LibHistoire's actual API docs and wire up real event registration in `RZTS.RecordSale` (currently a placeholder) — this is the main remaining "meat" of the addon.
5. Build gamepad-mode-safe UI panel once the data layer works.
6. Before console submission: verify how ZOS's uploader/curation handles third-party library dependencies like LibHistoire (not yet confirmed — flagged as a later checkpoint, not a v1 blocker).
