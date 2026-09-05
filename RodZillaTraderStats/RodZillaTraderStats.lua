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

function RZTS.OnAddOnLoaded(_, addonName)
    if addonName ~= RZTS.name then return end
    EVENT_MANAGER:UnregisterForEvent(RZTS.name, EVENT_ADD_ON_LOADED)

    RZTS.InitializeSavedVars()
    -- TODO: gamepad-mode-safe UI panel -- deferred until the data layer (LibHistoire wiring +
    -- aggregation) is proven out. Gather-and-summarize first, present second.

    d("|c00FF00RodZilla's Trader Stats|r loaded (v" .. RZTS.version .. ")")
end

EVENT_MANAGER:RegisterForEvent(RodZillaTraderStats.name, EVENT_ADD_ON_LOADED, RodZillaTraderStats.OnAddOnLoaded)
