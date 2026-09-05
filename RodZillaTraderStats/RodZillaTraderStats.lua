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
    })
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
    local LAM = LibStub("LibAddonMenu-2.0")

    local panelData = {
        type = "panel",
        name = "RodZilla's Trader Stats",
        displayName = "RodZilla's Trader Stats",
        author = RZTS.name,
        version = RZTS.version,
        slashCommand = "/rzts",
        registerForRefresh = true,
    }

    local optionsTable = {
        [1] = {
            type = "button",
            name = "Open Stats Window",
            tooltip = "Opens the RodZilla's Trader Stats window.",
            func = function() RZTS.ShowWindow() end,
            width = "full",
        },
    }

    LAM:RegisterAddonPanel(RZTS.name, panelData)
    LAM:RegisterOptionControls(RZTS.name, optionsTable)
end

function RZTS.OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED)

    -- Deferred to here rather than OnAddOnLoaded: SCENE_MANAGER isn't guaranteed ready yet at
    -- EVENT_ADD_ON_LOADED time, so scene/fragment setup needs to wait until the player is
    -- actually in the world.
    RZTS.InitializeScene()

    d("|c00FF00RodZilla's Trader Stats|r loaded (v" .. RZTS.version .. "). See Settings -> Add-Ons, or type /rzts.")
end

function RZTS.OnAddOnLoaded(_, addonName)
    if addonName ~= RZTS.name then return end
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_ADD_ON_LOADED)

    RZTS.InitializeSavedVars()
    RZTS.RegisterAddonMenu()
    EVENT_MANAGER:RegisterForEvent(RZTS.name, EVENT_PLAYER_ACTIVATED, RZTS.OnPlayerActivated)
end

EVENT_MANAGER:RegisterForEvent(RodZillaTraderStats.name, EVENT_ADD_ON_LOADED, RodZillaTraderStats.OnAddOnLoaded)
