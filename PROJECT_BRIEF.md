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
- **LibHistoire** (by sirinsidiator, license **Artistic-2.0** — confirmed, permissive, fine for a free add-on) is the community-standard caching layer built specifically to solve the rate-limit/server-destabilization problem. Declared as a manifest dependency (not bundled) — standard practice so multiple add-ons sharing it don't duplicate/conflict. Exact API now verified (see **LibHistoire Trader Data** section below).

## Weekly Trader Table (developer decisions, 2026-10-05)

- **Layout:** one row per weekly hire period, newest first. Columns: Date Range (MM/DD-MM/DD), Kiosk, Sales, Sales Total (###,###,###g), Tax Total (###,###,###g).
- **Date range:** Tuesday 19:00 UTC to the next Tuesday 19:00 UTC.
- **Kiosk:** blank for any week where the kiosk is unknown. Sales records don't name the trader, so only the current week's kiosk can be filled, from `GetGuildOwnedKioskInfo`. (Proposed, not yet confirmed: fill the current week only.)
- **Depth:** show as many weeks as the cached history covers. Design for more than four, but expect about four. Memory is not a concern, since each week is only a few totals.
- **Sales count:** transactions only. Stack quantities are dropped.
- **Display:** the results window, not the settings panel, since the panel can't do aligned columns.

## Design Decisions (developer, 2026-10-05)

- **On-demand loading:** statistics are loaded when a guild is chosen, not kept running in the background.
- **Single-guild state:** when the guild changes, previous statistics are cleared and overwritten for the new guild. Only one guild's stats are held at a time. This also follows the minimal-memory constraint.
- **Target user is a guild master or the officer who hires traders.** Regular members get whatever subset of information their permissions allow. Missing access is expected: the add-on should work with what's available and not fail when something is hidden.
- **More information allows finer breakdowns.** Design every view so it degrades gracefully: sales-only if hiring history isn't accessible, and so on.

**Implementation implications (not yet built):**
- Changing guild must stop the previous guild's LibHistoire processors and clear their callbacks, so a late callback can't write into the new guild's stats.
- LibHistoire keeps its own cache in its SavedVariables, which is outside our footprint. Our part is the aggregated stats only.

## TODO: Empty-Guild Test

- Empty-guild handling is implemented but untested. A guild with no trader history should show "up to date" with zero sales, based on LibHistoire's `CATEGORY_LINKED` callback, which the add-on records per session.
- To test: create a solo guild (developer alone, no trader history) and select it in the picker.
- Known limitation: `CATEGORY_LINKED` fires once per session per category. If a guild was already linked before the add-on loaded, it won't fire again this session. Empty guilds may show "fetching" until the next login.

## Permission Test Results (2026-10-05)

- Test button (LAM, "Test: Trader Hirings (chat)") streams the BANKED_CURRENCY category for the selected guild and reports kiosk purchases.
- Result: started, then stopped with **0 events scanned**, 0 hirings.
- Trader sales test: **0 events**, while the in-game guild history UI shows about 4 days of trader history. The developer joined the guild 4 days ago, which may explain the 4 days. So access to the data is not the problem. LibHistoire's own cache is empty or not yet filled.
- Why the test returned 0: `SetStopOnLastCachedEvent(true)` stops as soon as the cache runs out. With an empty cache, that's immediately, before LibHistoire has fetched anything. The test stopped too early.
- Next step: wait for LibHistoire to establish the managed range (`Callbacks.MANAGED_RANGE_FOUND`, which passes guildId and category) or watch `GetPendingEventMetrics()`, then stream. Verify that the cache fills for the guild before drawing conclusions about banked-currency access.
- Fix found along the way: processors default to listening for future events and never stop. Needed `SetStopOnLastCachedEvent(true)` before `StartStreaming`.

- **Result (2026-10-05, after the progress-reporting fix):** trader sales are visible through LibHistoire: **over 6,000 sales** scanned. Access was never the problem; the earlier zero came from LibHistoire's cache not being filled yet.
- **Resolved (2026-10-05):** the date span confirms about 4 days of sales, matching the developer's membership start. So the visible window appears to start at membership, not at the guild's full retention. Retention depth is still unknown: a long-standing member would show more, and that's the test to run later. Volume is high: over 6,000 sales in about 4 days.

- **Hiring history: zero is expected for this developer, not proof of no access.** Traders are hired weekly (Tuesdays, 19:00 UTC), and the developer joined after the last hire, so the 4-day window contains no hirings. Verification: re-run the banked-currency scan after the Tuesday 2026-10-06 19:00 UTC hire. A kiosk purchase with that timestamp would confirm access.
- **Design implication:** hirings are rare, so a single scan will often find none. Hiring history has to be recorded as it happens, or collected over the window the player can see. Members who joined after a hire will never see it.

## LibHistoire Trader Data (verified 2026-10-05)

Sources: LibHistoire's own `doc/api_reference.txt` (master branch), and ESO base-game `esoui/ingame/guildhistory/guildhistory_data.lua` (esoui/esoui master) — the latter is the authoritative field list for trader events.

**Access pattern:**
- `LibHistoire:CreateGuildHistoryProcessor(guildId, GUILD_HISTORY_EVENT_CATEGORY_TRADER, addonName)` → processor. One processor per guild per category.
- Use `processor:StartStreaming(lastProcessedId, eventCallback)` (or `SetNextEventCallback` + `Start`). Events arrive asynchronously, in eventId order.
- Resume support is built in: `lastProcessedId` / `SetAfterEventId`, plus `processor:GetKey()` (server + guild + category) for storing a resume point. This fits the rate-limited, resumable loading design above.
- Wait for `LibHistoire:OnReady(callback)` or `IsReady()` before calling anything.
- Callback event objects **must not be stored** (per the API doc) — aggregate on arrival. Fits the minimal-memory constraint.

**Fields per trader event** (from `ZO_GuildHistoryTraderEventData`, backed by `GetGuildHistoryTraderEventInfo(guildId, eventIndex)`):
- `eventId` — stable, sortable ID (resume point)
- `timestampS` — seconds
- `isRedacted` — boolean; redacted events exist but their details are hidden
- `eventType` — what kind of trader event (sale vs. other). **Enum values not yet verified** — needed to filter to actual sales.
- `sellerDisplayName`, `buyerDisplayName`
- `itemLink` — full item link (identity, name, quality)
- `quantity`
- `price` — total gold for the transaction
- `tax` — gold tax taken

**Derived, not given:** per-unit price = `price / quantity`. Use per-unit for min/max/avg so different stack sizes compare fairly — a design decision to confirm.

**Still unknown / to verify before building:**
- `eventType` enum values (which mean "item sold")
- What `isRedacted` hides, and whether redacted events count toward stats
- How far back guild trader history is retained. Not in either primary source. A secondary search summary cited ~30 days; developer recalls 2–3 weeks, possibly 28 days (same as bank history). **Treat as unverified** — confirm in-game (guild history panel) or from a primary source before relying on it.
- **Current trader — available, but only as a snapshot.** `GetGuildOwnedKioskInfo(guildId)` returns the name of the guild's currently hired trader, or nil if none (verified from ESO base-game `guildhome_keyboard.lua`, `RefreshTraderOwnership`). It shows what's there now, not what was there at a past sale time, and it's not verified whether the name includes a location. To attribute past sales to a trader, the add-on would have to record the trader name over time itself (e.g. on login and when it changes) and match sales by timestamp. Attribution would only go forward from when tracking started.
- **Trader hiring history — available, via the BANKED_CURRENCY category (verified 2026-10-05).** LibHistoire's `compatibility.lua` maps `GUILD_HISTORY_BANKED_CURRENCY_EVENT_KIOSK_PURCHASED`, `..._KIOSK_BID`, and `..._KIOSK_BID_REFUND` to events carrying `displayName` (who acted), `amount`, and `kioskName`. The base game's banked-currency event fields (`guildhistory_data.lua`) include `kioskName`. So a kiosk purchase (hiring a trader) records the trader's name, the buyer, the cost, and a timestamp. Also `GUILD_EVENT_GUILD_KIOSK_PURCHASE_REFUND` exists. **Not yet verified:** that `kioskName` matches the string `GetGuildOwnedKioskInfo` returns; whether a trader being removed or replaced appears as an event; and what the kiosk-lock/unlock milestone events mean for this.
- **Trader sale event type resolved:** the TRADER category's only supported event type is `GUILD_HISTORY_TRADER_EVENT_ITEM_SOLD` (LibHistoire `compatibility.lua`). The category is sales-only.
- **Which trader (location) made a sale — not visible in history.** The trader event has no location/kiosk field. Only `kioskName` exists, and only on banked-currency events, not trader events. The sale record identifies seller and buyer players, not the physical guild trader. So if traders move week to week, sales can't be attributed to a location from this data. Seller/buyer player names are the only identity available.
- **Design question for the developer:** the picker currently stores one guild ID, but the developer is in two guilds. Track one guild or both?
- **Data/memory strategy:** store aggregated per-item statistics only (count, gold total, min/max/avg price, last N sale timestamps) — not a permanent raw event log. Keeps footprint small regardless of guild sales volume, important given the console memory/size constraints above. Exact retention depth (how many recent sales to keep in detail) to be tuned once real data volume is observed.
- **Current APIVersion (as of 2026-09-04):** `101050` (live, patch "2026 Season 0 - Part 2"). Note: PTS is already on `101051` for a patch expected live **2026-09-28** — the manifest's `## APIVersion` will need updating around then to keep the add-on loading on live servers.
- **ESO base game is not free-to-play** — $19.99 on Steam, frequently on sale (as low as ~$5, historic low $1.99). Needed on PC for the dev/test loop.

## Current Scaffold

`RodZillaTraderStats/` contains:
- `RodZillaTraderStats.txt` — manifest (Title, Version, APIVersion, SavedVariables, `DependsOn: LibHistoire LibAddonMenu-2.0`)
- `RodZillaTraderStats.lua` — `EVENT_ADD_ON_LOADED` handler, `ZO_SavedVars` initialization (account-wide, aggregated `itemStats` table + `selectedGuildId`), a LibAddonMenu-2.0 panel registration (Settings -> Add-Ons entry + `/rzts` shortcut) with a guild-picker dropdown and "Open Stats Window" button, and a real `ZO_Scene`/`ZO_FadeSceneFragment` for the window (see Progress Log) so it behaves like a native ESO menu. Still a TODO: LibHistoire event wiring into `RZTS.RecordSale`.
- `RodZillaTraderStats.xml` — the window itself: a `TopLevelControl` with a backdrop, title, and `ZO_CloseButton`.

## Progress Log

- **2026-09-04:** ESO installed on PC (`C:\Games\Zenimax Online\The Elder Scrolls Online`, Steam). LibHistoire + its four sub-dependencies (LibAsync, LibCustomMenu, LibDebugLogger, LibAddonMenu-2.0 — Minion didn't auto-pull these, had to add manually, easy to find) installed via Minion into the correct location, `Documents\Elder Scrolls Online\live\AddOns\` — **not** the look-alike decoy `AddOns` folder that exists inside the game's install directory (a real gotcha: ESO creates that folder too, but doesn't read addons from it; Minion's install path setting had to be corrected to point at Documents instead). `RodZillaTraderStats` copied into the correct AddOns folder alongside them. **Confirmed: shows up as a valid, recognized addon in ESO's in-game Add-Ons menu, no errors** — manifest and `DependsOn: LibHistoire` dependency chain both resolved correctly. The chat "loaded" message wasn't visually confirmed yet — developer is testing via ESO's gamepad-UI accessibility mode (same underlying UI system as the Xbox build, so an early incidental gamepad-mode data point), where chat may be hidden by default. Not yet root-caused; low-priority since the addon-list validity check already confirms the real milestone (plumbing works end to end: manifest → dependencies → load, no runtime errors surfaced).
- **2026-09-05:** Repo created (private, GitHub, MIT license under "Team RodZilla LLC"). First real functionality: a custom window (`RodZillaTraderStatsWindow`) that opens and closes. Along the way: (1) discovered ESO's "Add-Ons" settings screen only enables/disables addons — it doesn't launch a UI, so a trigger mechanism is needed; initially used a `/rzts` slash command. (2) Learned the Xbox-style "pick an addon from a menu, interact with it" experience is actually **LibAddonMenu** (LAM, already installed transitively via LibHistoire) + **LibGamepad**/LibGamepadOptions for gamepad-mode access — not a console-exclusive feature. Added LAM registration (declared as an explicit dependency, plus its own dependency **LibStub**, which wasn't installed and needed adding) giving a native Settings -> Add-Ons entry with an "Open Stats Window" button, replacing the raw slash command as the primary trigger. (3) Hit a real bug: the close button's XML `OnClicked` calling `RodZillaTraderStats.HideWindow()` failed at runtime (`function expected instead of nil`) even though the identical-shaped `ShowWindow()` call from the LAM button worked fine — root cause not fully confirmed, but a real working addon's source (GuildStoreTools) showed the standard pattern calls `:SetHidden()` directly on the control from XML rather than routing through the addon's own table; switching to a direct call fixed it. (4) Discovered custom windows don't auto-close on Escape or combat by default (confirmed via research) — fixed Escape by converting the window into a genuine `ZO_Scene` + `ZO_FadeSceneFragment` (verified against the actual base-game source at github.com/esoui/esoui, not just addon examples), which gets Escape-to-close for free since that's the scene manager's own built-in behavior, no custom keybind code needed. Side effect (expected, not a bug): opening the window now closes other open menus/scenes, since ESO scenes are mutually exclusive by design — confirmed this matches the original "modal" vision. Combat auto-close is still an open TODO (`EVENT_PLAYER_COMBAT_STATE`, confirmed not automatic). Decided (per developer) that a LAM settings panel is the right home for input controls (guild picker, "gather" button, once built), while the custom window/scene stays reserved for displaying actual results later, once LibHistoire wiring exists — not an either/or. Developer has no PC guild yet (feelers out), so guild-list/data-gathering work is blocked until that's resolved.

- **2026-10-01:** Developer applied to two sister trading guilds, explaining the project, hoping to join and unblock guild-access-dependent work. Awaiting replies — not yet confirmed.
- **2026-10-02: Unblocked.** Accepted into both guilds, and confirmed able to see **guild trader (sales) history** specifically — the actual data source this addon needs, not just general guild membership/roster history. Guild-picker UI and LibHistoire data-layer work are no longer blocked.
- **2026-10-02: Guild picker built.** Added `RZTS.BuildGuildList()` (real ESO API, verified against actual shipped addon source before writing anything — `GetNumGuilds()`, `GetGuildId(luaindex)`, `GetGuildName(guildId)` — rather than guessed) and a LAM dropdown control (choices = guild names, stored value = guild ID in `selectedGuildId`) in the same settings panel as the "Open Stats Window" button. Also moved `RegisterAddonMenu()` from `EVENT_ADD_ON_LOADED` to `EVENT_PLAYER_ACTIVATED` — same reasoning already applied to `InitializeScene()`: guild membership is account data, not something to assume is populated before the player is actually in the world. **New standing constraint from developer (2026-10-02): keep memory footprint minimal for the rest of this project**, given the console memory/size limits already noted above — a live design constraint from here on, not just the data-layer principle already applied to `itemStats`. (Guild list itself is a non-issue either way — ESO caps a character at 5 guilds — the real discipline will matter once trader-history aggregation is built.)
- **2026-10-02: Deploy script added.** `Deploy RodZilla Trader Stats.bat` on the developer's Desktop copies the 3 addon files from the project folder straight to the live AddOns folder (auto-creates the destination if missing) — tested working. In-game, `/reloadui` picks up the change without needing to quit the game or even log out of the current character; full file reload only happens at UI init (effectively the first login/character-select screen each client session).
- **2026-10-02: Dropped the `LibStub` dependency.** Developer caught a real deprecation warning — **LibStub has been obsolete since the Summerset chapter**: ESO's own add-on version tracking made library-version-brokering redundant, and LibStub now prints a chat warning for any addon still calling it, with a full shutdown planned. Confirmed via two independent sources (LibAddonMenu's own ESOUI page, and the developer's own pasted copy of LibStub's ESOUI page). Fix: `local LAM = LibStub("LibAddonMenu-2.0")` → `local LAM = LibAddonMenu2` (the global LAM exposes directly), and removed `LibStub` from `## DependsOn:` entirely. **Current dependency list, corrected: 2 direct (`LibHistoire`, `LibAddonMenu-2.0`) + 3 transitive via LibHistoire (`LibAsync`, `LibCustomMenu`, `LibDebugLogger`) = 5 libraries total**, not 6/3-direct as stated earlier the same day before this was caught.

## Open / Next Steps

1. ~~Install ESO on PC~~ — done, see Progress Log.
2. ~~Get LibHistoire + dependencies installed and confirm the add-on loads~~ — done, see Progress Log.
3. ~~Confirm the "loaded" chat message / basic window open-close~~ — done; window now opens via Settings -> Add-Ons or `/rzts`, closes via close button or Escape (real `ZO_Scene`).
4. ~~Guild-picker dropdown in the LAM panel~~ — done 2026-10-02 (see Progress Log). The "gather" button/trigger is still open — depends on what shape the data-layer work below ends up needing.
5. **Next up:** research what LibHistoire actually exposes (guild trader sold-item history data — what fields, what pagination/event shape) and decide how to consolidate/display it, before wiring up real event registration in `RZTS.RecordSale` (currently a placeholder) — this is the main remaining "meat" of the addon. Pull the real API, don't guess at function signatures (same rule applied to the guild-picker functions).
6. Build gamepad-mode-safe UI panel once the data layer works.
7. Before console submission: verify how ZOS's uploader/curation handles third-party library dependencies like LibHistoire (not yet confirmed — flagged as a later checkpoint, not a v1 blocker).
