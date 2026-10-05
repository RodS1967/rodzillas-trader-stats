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
        itemStats = {},
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

local WEEK_SECONDS = 7 * 86400
local TABLE_MAX_ROWS = 14
local TABLE_ROW_TOP = 110
local TABLE_ROW_HEIGHT = 24
local TABLE_COLUMNS = {
    { key = "date",  x = 40,  width = 120, align = TEXT_ALIGN_LEFT },
    { key = "kiosk", x = 170, width = 230, align = TEXT_ALIGN_LEFT },
    { key = "sales", x = 410, width = 70,  align = TEXT_ALIGN_RIGHT },
    { key = "gold",  x = 490, width = 130, align = TEXT_ALIGN_RIGHT },
    { key = "tax",   x = 630, width = 110, align = TEXT_ALIGN_RIGHT },
}
local TABLE_HEADERS = { date = "Date Range", kiosk = "Kiosk", sales = "Sales", gold = "Sales Total", tax = "Tax Total" }

local function FormatGold(amount)
    local digits = tostring(math.floor(amount)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return digits .. "g"
end

local function CreateTableCell(parent, column, y, font)
    local label = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    label:SetFont(font)
    label:SetWidth(column.width)
    label:SetHorizontalAlignment(column.align)
    label:SetAnchor(TOPLEFT, parent, TOPLEFT, column.x, y)
    label:SetText("")
    return label
end

function RZTS.EnsureTableControls()
    if RZTS.tableLabels then return end
    local parent = RodZillaTraderStatsWindow
    local tableLabels = { header = {}, rows = {} }
    for _, column in ipairs(TABLE_COLUMNS) do
        local header = CreateTableCell(parent, column, TABLE_ROW_TOP - 28, "ZoFontWinH5")
        header:SetText(TABLE_HEADERS[column.key])
    end
    for r = 1, TABLE_MAX_ROWS do
        local cells = {}
        for _, column in ipairs(TABLE_COLUMNS) do
            cells[column.key] = CreateTableCell(parent, column, TABLE_ROW_TOP + (r - 1) * TABLE_ROW_HEIGHT, "ZoFontGame")
        end
        tableLabels.rows[r] = cells
    end
    tableLabels.guild = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    tableLabels.guild:SetFont("ZoFontWinH4")
    tableLabels.guild:SetWidth(760)
    tableLabels.guild:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    tableLabels.guild:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, 52)
    tableLabels.underline = WINDOW_MANAGER:CreateControl(nil, parent, CT_BACKDROP)
    tableLabels.underline:SetCenterColor(0.85, 0.85, 0.85, 0.9)
    tableLabels.underline:SetHeight(2)
    tableLabels.status = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    tableLabels.status:SetFont("ZoFontGame")
    tableLabels.status:SetWidth(680)
    tableLabels.status:SetAnchor(TOPLEFT, parent, TOPLEFT, 40, TABLE_ROW_TOP + TABLE_MAX_ROWS * TABLE_ROW_HEIGHT + 10)
    RZTS.tableLabels = tableLabels
end

function RZTS.RenderWeeklyTable()
    if not RodZillaTraderStatsWindow then return end
    RZTS.EnsureTableControls()
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
    tableLabels.underline:SetAnchor(TOPLEFT, RodZillaTraderStatsWindow, TOPLEFT, (760 - textWidth) / 2, 52 + tableLabels.guild:GetTextHeight() + 2)
    tableLabels.status:SetText(s and ("Status: " .. s.status .. (#weeks > TABLE_MAX_ROWS and " (showing newest " .. TABLE_MAX_ROWS .. " weeks)" or "")) or "")
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
    }
    RZTS.traderStats = stats

    if not LibHistoire:IsReady() then
        stats.status = "LibHistoire is not ready"
        Publish()
        return
    end

    local processor = LibHistoire:CreateGuildHistoryProcessor(guildId, GUILD_HISTORY_EVENT_CATEGORY_TRADER, RZTS.name)
    if not processor then
        stats.status = "no trader history available (not cached, or no access)"
        Publish()
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
        if RZTS.traderStats == stats and stats.status ~= "up to date" then
            stats.status = "stopped early"
            Publish()
        end
    end)

    if not processor:StartStreaming(nil) then
        stats.status = "could not start scanning"
        Publish()
        return
    end
    RZTS.traderProcessor = processor

    local function Poll()
        if RZTS.traderStats ~= stats or stats.status == "stopped early" then return end
        local remaining = processor:GetPendingEventMetrics()
        if remaining > 0 then
            stats.status = string.format("loading cached sales (%d so far, %d queued)", stats.salesSoFar, remaining)
        elseif IsTraderHistoryUpToDate(guildId) then
            stats.status = string.format("up to date (%d sales)", stats.salesSoFar)
            Publish()
            return
        else
            stats.status = string.format("fetching guild history from the game (%d sales so far)", stats.salesSoFar)
        end
        Publish()
        zo_callLater(Poll, 1000)
    end
    zo_callLater(Poll, 2000)
end

function RZTS.TraderStatsText()
    local s = RZTS.traderStats
    if not s then
        return "Choose a guild, then press Show Current Trader Stats."
    end
    local current = s.buckets[s.currentStart] or { sales = 0, gold = 0, tax = 0 }
    return string.format(
        "Kiosk: %s\nThis hire period since: %s\nSales: %d\nSales total: %s\nTax total: %s\nStatus: %s",
        s.kiosk or "none hired",
        FormatDate(s.currentStart, "!%a %Y-%m-%d %H:%M UTC"),
        current.sales, FormatGold(current.gold), FormatGold(current.tax), s.status)
end

-- TODO: LibHistoire integration.
-- LibHistoire (Artistic-2.0, by sirinsidiator) is declared as a dependency in the manifest but its
-- exact event-registration API hasn't been pulled/verified yet -- do that before wiring this up
-- rather than guessing at function names/signatures. Goal: register for guild trader sold-item
-- history events per guild, feed each into RZTS.RecordSale() below.
function RZTS.RecordSale(itemLink, guildId, price, timestamp)
    -- placeholder aggregation logic
end

-- Window control: RodZillaTraderStatsWindow, defined in RodZillaTraderStats.xml.
-- Keyboard/mouse UI only for now -- gamepad-mode version is a later TODO.
--
-- Registered as a real ZO_Scene (see RZTS.InitializeScene below) rather than just shown/hidden
-- directly, so Escape closes it automatically -- that's the scene manager's own built-in
-- behavior (returning to the base/HUD scene), not something we hook ourselves.
function RZTS.ShowWindow()
    SCENE_MANAGER:Show(RZTS.name)
end

function RZTS.HideWindow()
    SCENE_MANAGER:ShowBaseScene()
end

function RZTS.InitializeScene()
    RZTS.scene = ZO_Scene:New(RZTS.name, SCENE_MANAGER)
    RZTS.fragment = ZO_FadeSceneFragment:New(RodZillaTraderStatsWindow)
    RZTS.scene:AddFragment(RZTS.fragment)
end

-- LibAddonMenu-2.0 registration: gives us a "RodZilla's Trader Stats" entry under
-- Settings -> Add-Ons (works in both keyboard/mouse and gamepad UI, since that's an existing
-- native ESO menu, not something we built) with a button to open our actual window, plus
-- a "/rzts" shortcut straight to that settings page.
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
            setFunc = function(value)
                if value ~= RZTS.savedVars.selectedGuildId then
                    RZTS.savedVars.selectedGuildId = value
                    RZTS.ClearTraderStats()
                    RZTS.RefreshTraderPanel()
                end
            end,
            width = "full",
            warning = (#guildNames == 0) and "You are not in any guilds." or nil,
        },
        [2] = {
            type = "button",
            name = "Show Current Trader Stats",
            tooltip = "Opens the weekly trader table for this guild.",
            func = function()
                RZTS.ComputeTraderStats()
                RZTS.ShowWindow()
            end,
            width = "full",
        },
        [3] = {
            type = "description",
            text = function() return RZTS.TraderStatsText() end,
            width = "full",
        },
    }

    RZTS.panel = LAM:RegisterAddonPanel(RZTS.name, panelData)
    LAM:RegisterOptionControls(RZTS.name, optionsTable)
end

-- Custom windows don't auto-close on combat by default (confirmed via research) -- only close
-- our own window if it's actually the one showing, so we don't interfere with anything else.
function RZTS.OnCombatState(_, inCombat)
    if inCombat and RZTS.scene:IsShowing() then
        RZTS.HideWindow()
    end
end

function RZTS.OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED)

    -- Deferred to here rather than OnAddOnLoaded: SCENE_MANAGER isn't guaranteed ready yet at
    -- EVENT_ADD_ON_LOADED time, so scene/fragment setup needs to wait until the player is
    -- actually in the world. Same reasoning for RegisterAddonMenu -- it reads the account's
    -- guild list (GetNumGuilds/GetGuildId/GetGuildName) for the guild-picker dropdown, and
    -- that's account data, not something to assume is populated this early.
    RZTS.InitializeScene()
    RZTS.RegisterAddonMenu()
    RZTS.RegisterLinkedCallback()
    EVENT_MANAGER:RegisterForEvent(RZTS.name, EVENT_PLAYER_COMBAT_STATE, RZTS.OnCombatState)

    d("|c00FF00RodZilla's Trader Stats|r loaded (v" .. RZTS.version .. "). See Settings -> Add-Ons, or type /rzts.")
end

function RZTS.OnAddOnLoaded(_, addonName)
    if addonName ~= RZTS.name then return end
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_ADD_ON_LOADED)

    RZTS.InitializeSavedVars()
    EVENT_MANAGER:RegisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED, RZTS.OnPlayerActivated)
end

EVENT_MANAGER:RegisterForEvent(RodZillaTraderStats.name, EVENT_ADD_ON_LOADED, RodZillaTraderStats.OnAddOnLoaded)
