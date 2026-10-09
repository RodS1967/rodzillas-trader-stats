RodZillaTraderStats = {}
RodZillaTraderStats.name = "RodZillaTraderStats"
RodZillaTraderStats.version = "0.1.0"

local RZTS = RodZillaTraderStats

-- Data layer: aggregated per-item stats only (count, gold total, min/max/avg, last N sale timestamps).
-- Deliberately NOT storing the raw event log long-term -- keeps SavedVariables/memory footprint
-- small regardless of guild sales volume, and console has a 100MB total addon size cap plus
-- less available memory than PC.
function RZTS.InitializeSavedVars()
    RZTS.savedVars = ZO_SavedVars:NewAccountWide("RodZillaTraderStats_SavedVars", 1, nil, {
        selectedGuildId = nil,
    })
end

-- Builds the current character's guild list (name + id pairs) for the guild
-- picker. ESO caps a character at 5 guilds, so this table is always tiny --
-- not a memory concern regardless of how it's built. Called once from
-- RegisterAddonMenu rather than on every dropdown interaction.
function RZTS.BuildGuildList()
    local names, ids = {}, {}
    for i = 1, GetNumGuilds() do
        local guildId = GetGuildId(i)
        names[i] = GetGuildName(guildId)
        ids[i] = guildId
    end
    return names, ids
end

local function FormatDate(timestampS, format)
    local ok, text = pcall(os.date, format or "%Y-%m-%d", timestampS)
    return ok and text or tostring(timestampS)
end

-- Most recent scheduled hire at or before `now` (Tuesdays 19:00 UTC), as epoch seconds.
-- Pure UTC arithmetic: 1970-01-01 was a Thursday, so (days + 4) % 7 gives 0 = Sunday.
local function LastHireCutoff(now)
    local days = math.floor(now / 86400)
    local weekday = (days + 4) % 7
    local cutoff = (days - (weekday - 2) % 7) * 86400 + 19 * 3600
    if cutoff > now then cutoff = cutoff - 7 * 86400 end
    return cutoff
end

-- Only totals are kept, never the events themselves. Sales are bucketed by weekly hire
-- period; RZTS.traderStats is the one live summary and is replaced on every scan or guild change.
RZTS.traderStats = nil
RZTS.traderProcessor = nil
RZTS.panel = nil
RZTS.tableLabels = nil
RZTS.statsParent = nil -- the LAM custom control the table is drawn on; set once in its createFunc

-- Fixed-height block (see STATS_CONTROL_HEIGHT below), embedded directly in the settings
-- panel via a LAM "custom" widget rather than a separate window -- so switching guilds in
-- the dropdown just redraws this block in place, with no window to open or close.
local WEEK_SECONDS = 7 * 86400
local TABLE_MAX_ROWS = 14
local TABLE_ROW_TOP = 70
local TABLE_ROW_HEIGHT = 24
local TABLE_ROWS_BOTTOM = TABLE_ROW_TOP + TABLE_MAX_ROWS * TABLE_ROW_HEIGHT
local STATS_CONTROL_HEIGHT = 500
-- Left/right padding for everything in this block (table columns, status text, progress
-- bar). The panel's real content width was unknown all day (two guesses, 740 then 710,
-- were both too wide) until actually measured in-game 2026-10-09: parent:GetWidth() = 585.
-- Left margin set to 0 (2026-10-09) to line up flush with "Guild" above, which LAM anchors
-- at zero padding -- see RegisterAddonMenu's dropdown comment for why these two don't share
-- a layout system and can't just inherit each other's padding automatically.
local MEASURED_PANEL_WIDTH = 585 -- RZTS.statsParent:GetWidth(), confirmed in-game 2026-10-09
local TABLE_LEFT_MARGIN = 0
-- Right margin dropped to 0 2026-10-09 -- there was visible spare room even with "kiosk"
-- widened once already. Worth watching for: a scrollbar has shown up at this same right
-- edge in earlier screenshots, and it's not confirmed whether MEASURED_PANEL_WIDTH already
-- accounts for its space or not.
local TABLE_RIGHT_MARGIN = 0
local TABLE_CONTENT_WIDTH = MEASURED_PANEL_WIDTH - TABLE_LEFT_MARGIN - TABLE_RIGHT_MARGIN

-- No x values -- positions are computed left-to-right below (ComputeColumnPositions), each
-- column starting exactly where the previous one ends. A previous version anchored the
-- right-aligned columns backward from the panel's right edge independently of these --
-- two separate calculations that could (and did) disagree, overlapping columns when the
-- real panel width was narrower than assumed. Pure left-to-right can't overlap by
-- construction: at worst, if the row is wider than the panel, only the last column runs
-- off the edge, same as the original bug, never into another column's space.
-- "kiosk" is deliberately the column allowed to clip (ellipsis) if a trader name is long --
-- date/sales/gold/tax are the actual numbers this addon exists to show and must stay whole.
-- Total here (520) plus 4 gaps (48) = 568, under the 585 available with both margins at 0 --
-- "kiosk" widened again 2026-10-09 (150 -> 190) now that the right margin is also gone,
-- keeping the same ~17px buffer after two earlier rounds of too-tight guesses.
local TABLE_COLUMNS = {
    { key = "date",  width = 85,  align = TEXT_ALIGN_LEFT },
    { key = "kiosk", width = 190, align = TEXT_ALIGN_LEFT },
    { key = "sales", width = 45,  align = TEXT_ALIGN_RIGHT },
    { key = "gold",  width = 105, align = TEXT_ALIGN_RIGHT },
    { key = "tax",   width = 95,  align = TEXT_ALIGN_RIGHT },
}
local TABLE_HEADERS = { date = "Date Range", kiosk = "Kiosk", sales = "Sales", gold = "Sales Total", tax = "Tax Total" }
local TABLE_COLUMN_GAP = 12

local function ComputeColumnPositions()
    local positions = {}
    local x = TABLE_LEFT_MARGIN -- matches the status text/progress bar's left edge below
    for _, column in ipairs(TABLE_COLUMNS) do
        positions[column.key] = x
        x = x + column.width + TABLE_COLUMN_GAP
    end
    return positions
end

local function FormatGold(amount)
    local digits = tostring(math.floor(amount)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return digits .. "g"
end

local function CreateTableCell(parent, column, x, y, font)
    local label = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    label:SetFont(font)
    label:SetWidth(column.width)
    label:SetHorizontalAlignment(column.align)
    -- Ellipsis mode alone still wraps to multiple lines before it starts truncating --
    -- confirmed 2026-10-09, a long kiosk name wrapped to 2 lines and collided with the row
    -- below instead of truncating. MaxLineCount(1) forces truncation on the first line.
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    label:SetMaxLineCount(1)
    label:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    label:SetText("")
    return label
end

function RZTS.EnsureTableControls(parent)
    if RZTS.tableLabels then return end
    local columnX = ComputeColumnPositions()
    local tableLabels = { rows = {} }
    for _, column in ipairs(TABLE_COLUMNS) do
        local header = CreateTableCell(parent, column, columnX[column.key], TABLE_ROW_TOP - 28, "ZoFontWinH5")
        header:SetText(TABLE_HEADERS[column.key])
    end
    for r = 1, TABLE_MAX_ROWS do
        local cells = {}
        for _, column in ipairs(TABLE_COLUMNS) do
            cells[column.key] =
                CreateTableCell(parent, column, columnX[column.key], TABLE_ROW_TOP + (r - 1) * TABLE_ROW_HEIGHT, "ZoFontGame")
        end
        tableLabels.rows[r] = cells
    end
    tableLabels.guild = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    tableLabels.guild:SetFont("ZoFontWinH4")
    tableLabels.guild:SetWidth(parent:GetWidth())
    tableLabels.guild:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    tableLabels.guild:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, 0)
    tableLabels.underline = WINDOW_MANAGER:CreateControl(nil, parent, CT_BACKDROP)
    tableLabels.underline:SetCenterColor(0.85, 0.85, 0.85, 0.9)
    tableLabels.underline:SetHeight(2)
    tableLabels.status = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    tableLabels.status:SetFont("ZoFontGame")
    tableLabels.status:SetWidth(TABLE_CONTENT_WIDTH)
    tableLabels.status:SetAnchor(TOPLEFT, parent, TOPLEFT, TABLE_LEFT_MARGIN, TABLE_ROWS_BOTTOM + 10)

    -- Progress bar: a determinate fill while draining already-cached events (a known count,
    -- via GetPendingEventMetrics), or a slow blink while waiting on the server (no known size,
    -- so no honest percentage to show). Hidden once a scan finishes or errors out.
    -- Offset +60 (not +32) below the status text to leave room for it to wrap to two lines --
    -- some of the status messages run long enough to wrap, and the bar must sit below both.
    tableLabels.progressTrack = WINDOW_MANAGER:CreateControl(nil, parent, CT_BACKDROP)
    tableLabels.progressTrack:SetDimensions(TABLE_CONTENT_WIDTH, 14)
    tableLabels.progressTrack:SetAnchor(TOPLEFT, parent, TOPLEFT, TABLE_LEFT_MARGIN, TABLE_ROWS_BOTTOM + 60)
    tableLabels.progressTrack:SetCenterColor(0.15, 0.15, 0.15, 0.9)
    tableLabels.progressTrack:SetHidden(true)
    tableLabels.progressFill = WINDOW_MANAGER:CreateControl(nil, parent, CT_BACKDROP)
    tableLabels.progressFill:SetHeight(14)
    tableLabels.progressFill:SetAnchor(TOPLEFT, tableLabels.progressTrack, TOPLEFT, 0, 0)
    tableLabels.progressFill:SetHidden(true)
    RZTS.tableLabels = tableLabels
end

function RZTS.RenderWeeklyTable()
    if not RZTS.statsParent then return end
    RZTS.EnsureTableControls(RZTS.statsParent)
    local tableLabels = RZTS.tableLabels

    local weeks = {}
    local s = RZTS.traderStats
    if s then
        for _, bucket in pairs(s.buckets) do
            weeks[#weeks + 1] = bucket
        end
    end
    table.sort(weeks, function(a, b) return a.start > b.start end)

    for r = 1, TABLE_MAX_ROWS do
        local cells = tableLabels.rows[r]
        local bucket = weeks[r]
        if bucket then
            local rangeEnd = bucket.start + WEEK_SECONDS
            cells.date:SetText(FormatDate(bucket.start, "!%m/%d") .. "-" .. FormatDate(rangeEnd, "!%m/%d"))
            cells.kiosk:SetText(bucket.kiosk or "")
            cells.sales:SetText(tostring(bucket.sales))
            cells.gold:SetText(FormatGold(bucket.gold))
            cells.tax:SetText(FormatGold(bucket.tax))
        else
            for _, column in ipairs(TABLE_COLUMNS) do
                cells[column.key]:SetText("")
            end
        end
    end

    tableLabels.guild:SetText(RZTS.savedVars.selectedGuildId and GetGuildName(RZTS.savedVars.selectedGuildId) or "No guild selected")
    local textWidth = tableLabels.guild:GetTextWidth()
    tableLabels.underline:SetWidth(textWidth)
    tableLabels.underline:SetAnchor(TOPLEFT, RZTS.statsParent, TOPLEFT, (RZTS.statsParent:GetWidth() - textWidth) / 2, tableLabels.guild:GetTextHeight() + 2)
    tableLabels.status:SetText(s and ("Status: " .. s.status .. (#weeks > TABLE_MAX_ROWS and " (showing newest " .. TABLE_MAX_ROWS .. " weeks)" or "")) or "")

    local showProgress = s and (s.phase == "loading" or s.phase == "waiting")
    tableLabels.progressTrack:SetHidden(not showProgress)
    tableLabels.progressFill:SetHidden(not showProgress)
    if showProgress then
        if s.phase == "loading" and s.loadTotal and s.loadTotal > 0 then
            -- Determinate: GetPendingEventMetrics gives a real count of already-cached
            -- events still to process, so the percentage is honest.
            local pct = zo_clamp((s.loadTotal - (s.loadRemaining or 0)) / s.loadTotal, 0, 1)
            tableLabels.progressFill:SetWidth(TABLE_CONTENT_WIDTH * pct)
            tableLabels.progressFill:SetCenterColor(0.3, 0.6, 1.0, 0.9)
        else
            -- Indeterminate: waiting on LibHistoire's background system, with no known size
            -- to show a percentage of, so just blink to signal "still working" rather than
            -- show a fake number.
            tableLabels.progressFill:SetWidth(TABLE_CONTENT_WIDTH)
            tableLabels.progressFill:SetCenterColor(0.9, 0.7, 0.2, s.blinkOn and 0.85 or 0.25)
        end
    end
end

function RZTS.RefreshTraderPanel()
    if RZTS.panel then
        CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", RZTS.panel)
    end
end

function RZTS.ClearTraderStats()
    if RZTS.traderProcessor then
        RZTS.traderProcessor:Stop()
        RZTS.traderProcessor = nil
    end
    RZTS.traderStats = nil
end

-- Refreshes both the results window and the settings panel after any change.
local function Publish()
    RZTS.RenderWeeklyTable()
    RZTS.RefreshTraderPanel()
end

-- "Up to date" means the guild's trader history has no gaps up to the present, the same
-- check the base game uses. A processor reaching the end of what's cached is not enough:
-- a guild that hasn't been fetched yet has an empty cache, which looks identical to a
-- finished one.
-- A guild with no trader sales never has gapless events to report, so LibHistoire's
-- CATEGORY_LINKED callback is the only "nothing left to fetch" signal. It fires once per
-- session per category, so it's recorded as it happens.
RZTS.linkedTraderGuilds = {}

function RZTS.RegisterLinkedCallback()
    LibHistoire:OnReady(function(lib)
        lib:RegisterCallback(lib.callback.CATEGORY_LINKED, function(guildId, category)
            if category == GUILD_HISTORY_EVENT_CATEGORY_TRADER then
                RZTS.linkedTraderGuilds[guildId] = true
            end
        end)
    end)
end

local function IsTraderHistoryUpToDate(guildId)
    return RZTS.linkedTraderGuilds[guildId] == true
        or GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(guildId, GUILD_HISTORY_EVENT_CATEGORY_TRADER) ~= nil
end

function RZTS.ComputeTraderStats()
    RZTS.ClearTraderStats()
    local guildId = RZTS.savedVars.selectedGuildId
    if not guildId then
        Publish()
        return
    end

    local now = os.time()
    local currentStart = LastHireCutoff(now)
    local kiosk = GetGuildOwnedKioskInfo(guildId)
    local stats = {
        kiosk = kiosk,
        currentStart = currentStart,
        buckets = { [currentStart] = { start = currentStart, kiosk = kiosk, sales = 0, gold = 0, tax = 0 } },
        salesSoFar = 0,
        status = "scanning",
        phase = "scanning", -- scanning (just starting) | waiting (LibHistoire not gapless yet) | loading (draining cache) | done | error
    }
    RZTS.traderStats = stats

    local function Fail(message)
        stats.status = message
        stats.phase = "error"
        Publish()
    end

    -- Don't touch LibHistoire's processor/request machinery at all until it reports this
    -- guild's trader history as gapless up to the present. Starting a processor earlier would
    -- register us for a share of the account-wide request priority (see GetRequestPriority in
    -- LibHistoire's GuildHistoryServerRequest.lua) and make us part of the same contention that
    -- can starve whichever guild isn't currently selected -- exactly the bug from 2026-10-07.
    -- Waiting costs nothing: it's a plain base-game lookup, not a network request.
    local function StartScan()
        if not LibHistoire:IsReady() then
            Fail("LibHistoire is not ready")
            return
        end

        local processor = LibHistoire:CreateGuildHistoryProcessor(guildId, GUILD_HISTORY_EVENT_CATEGORY_TRADER, RZTS.name)
        if not processor then
            Fail("no trader history available (not cached, or no access)")
            return
        end

        processor:SetNextEventCallback(function(event)
            local info = event:GetEventInfo()
            if info.eventType ~= GUILD_HISTORY_TRADER_EVENT_ITEM_SOLD then return end
            local start = LastHireCutoff(info.timestampS)
            local bucket = stats.buckets[start]
            if not bucket then
                bucket = { start = start, sales = 0, gold = 0, tax = 0 }
                stats.buckets[start] = bucket
            end
            bucket.sales = bucket.sales + 1
            bucket.gold = bucket.gold + info.price
            bucket.tax = bucket.tax + info.tax
            stats.salesSoFar = stats.salesSoFar + 1
        end)
        processor:SetOnStopCallback(function()
            if RZTS.traderStats == stats and stats.phase ~= "done" then
                Fail("stopped early")
            end
        end)

        if not processor:StartStreaming(nil) then
            Fail("could not start scanning")
            return
        end
        RZTS.traderProcessor = processor

        -- The guild is already confirmed gapless at this point, so this is purely a local
        -- cache read -- no further network wait, just however long it takes to drain what's
        -- already on disk. The determinate bar reflects that real, bounded amount of work.
        local function Poll()
            if RZTS.traderStats ~= stats or stats.phase == "error" then return end
            local remaining = processor:GetPendingEventMetrics()
            if remaining > 0 then
                stats.phase = "loading"
                stats.loadTotal = stats.loadTotal or remaining -- fix the denominator at the first reading
                stats.loadRemaining = remaining
                stats.status = string.format("loading cached sales (%d so far, %d queued)", stats.salesSoFar, remaining)
            else
                stats.phase = "done"
                stats.status = string.format("up to date (%d sales)", stats.salesSoFar)
                Publish()
                return
            end
            Publish()
            zo_callLater(Poll, 1000)
        end
        zo_callLater(Poll, 500)
    end

    local function WaitUntilReady()
        if RZTS.traderStats ~= stats then return end
        if IsTraderHistoryUpToDate(guildId) then
            StartScan()
        else
            stats.phase = "waiting"
            stats.blinkOn = not stats.blinkOn
            stats.status = "LibHistoire is still loading this guild's trader history in the background " ..
                "(not something this add-on can speed up). Check back in a few minutes."
            Publish()
            zo_callLater(WaitUntilReady, 5000)
        end
    end
    WaitUntilReady()
end

-- LibAddonMenu-2.0 registration: gives us a "RodZilla's Trader Stats" entry under
-- Settings -> Add-Ons (works in both keyboard/mouse and gamepad UI, since that's an existing
-- native ESO menu, not something we built), with the weekly table drawn directly on the page
-- via a "custom" LAM widget -- see controls/custom.lua in LibAddonMenu-2.0 -- rather than a
-- separate window. That way switching the guild dropdown just redraws the table in place;
-- there's nothing to open or close. Plus a "/rzts" shortcut straight to the page.
function RZTS.RegisterAddonMenu()
    -- LibAddonMenu2 global, not LibStub -- LibStub is deprecated/obsolete since the
    -- Summerset chapter (ESO's own add-on versioning made it redundant); confirmed
    -- 2026-10-02 against LibAddonMenu's own ESOUI page.
    local LAM = LibAddonMenu2

    local panelData = {
        type = "panel",
        name = "RodZilla's Trader Stats",
        displayName = "RodZilla's Trader Stats",
        author = "Team RodZilla LLC",
        version = RZTS.version,
        slashCommand = "/rzts",
        registerForRefresh = true,
    }

    local guildNames, guildIds = RZTS.BuildGuildList()

    local optionsTable = {
        [1] = {
            type = "dropdown",
            name = "Guild",
            tooltip = "Choose which guild's trader history to track.",
            choices = guildNames,
            choicesValues = guildIds,
            getFunc = function() return RZTS.savedVars.selectedGuildId end,
            -- Switching guilds here is now the only trigger needed -- it starts the scan
            -- immediately, so there's no separate "show" step.
            setFunc = function(value)
                if value ~= RZTS.savedVars.selectedGuildId then
                    RZTS.savedVars.selectedGuildId = value
                    RZTS.ComputeTraderStats()
                end
            end,
            width = "full",
            warning = (#guildNames == 0) and "You are not in any guilds." or nil,
        },
        [2] = {
            type = "button",
            name = "Refresh",
            tooltip = "Re-checks this guild's trader history. Mainly useful to retry after an error.",
            func = function() RZTS.ComputeTraderStats() end,
            width = "half",
            -- Disabled while a scan is actively running, so a second press can't restart it
            -- mid-flight. Re-enabled once it finishes (done) or gives up (error), for a retry.
            disabled = function()
                local s = RZTS.traderStats
                return s ~= nil and s.phase ~= "done" and s.phase ~= "error"
            end,
        },
        [3] = {
            -- The weekly table itself, drawn directly on the settings page. See
            -- controls/custom.lua in LibAddonMenu-2.0 for what this widget type provides.
            type = "custom",
            reference = "RodZillaTraderStatsTable",
            width = "full",
            minHeight = STATS_CONTROL_HEIGHT,
            maxHeight = STATS_CONTROL_HEIGHT,
            createFunc = function(control)
                RZTS.statsParent = control
                RZTS.EnsureTableControls(control)
                RZTS.RenderWeeklyTable()
            end,
            refreshFunc = function() RZTS.RenderWeeklyTable() end,
        },
    }

    RZTS.panel = LAM:RegisterAddonPanel(RZTS.name, panelData)
    LAM:RegisterOptionControls(RZTS.name, optionsTable)
end

function RZTS.OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED)

    -- Deferred to here rather than OnAddOnLoaded: RegisterAddonMenu reads the account's guild
    -- list (GetNumGuilds/GetGuildId/GetGuildName) for the guild-picker dropdown, and that's
    -- account data, not something to assume is populated this early.
    RZTS.RegisterAddonMenu()
    RZTS.RegisterLinkedCallback()

    d("|c00FF00RodZilla's Trader Stats|r loaded (v" .. RZTS.version .. "). See Settings -> Add-Ons, or type /rzts.")
end

function RZTS.OnAddOnLoaded(_, addonName)
    if addonName ~= RZTS.name then return end
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_ADD_ON_LOADED)

    RZTS.InitializeSavedVars()
    EVENT_MANAGER:RegisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED, RZTS.OnPlayerActivated)
end

EVENT_MANAGER:RegisterForEvent(RodZillaTraderStats.name, EVENT_ADD_ON_LOADED, RodZillaTraderStats.OnAddOnLoaded)
