---@diagnostic disable: undefined-global, undefined-field

--- EOC full-window controller and presentation layer.
-- @module eoc_settings
-- @architecture X4 Lua owns rendering, navigation, transient selection, and
-- button callbacks. Mission Director XML remains authoritative for persistent
-- game state, station scans, cases, evidence, and bounded gameplay actions.
-- @transport JKEOC_Settings_Interface.xml serializes MD records into positional
-- Lua arrays. The v(record, index, default) helper is the compatibility boundary;
-- changing a field position requires synchronized MD and Lua updates.
-- @state menu contains transient UI state only. Persistent state must live in
-- documented global.$JKEOC_* MD globals and return through the interface.
-- @refresh Same-page rebuilds must capture and restore live table IDs, top rows,
-- and selected rows. Button wrappers must never rebuild before their handlers.
-- @performance Do not add per-frame scans, unbounded tables, or background
-- polling. Existing timed data collection is page-scoped or MD-owned and bounded.
-- @authority A UI click is a request, not proof. Only fresh MD evidence may mark
-- an EOC-owned checklist step verified or resolve an operational case.

-- Major regions in this file:
--   1. X4 FFI declarations and menu state
--   2. transport/event decoders from Mission Director
--   3. reusable table, button, formatting, and scroll helpers
--   4. Cases / Diagnostics / Reports / Fleet / Construction / KPI renderers
--   5. Docked full-window lifecycle and refresh orchestration

local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
    float GetTextHeight(const char*const text, const char*const fontname, const float fontsize, const float wordwrapwidth);
    typedef struct {
        const char* macro;
        const char* ware;
        const char* productionmethodid;
    } UIBlueprint;
    typedef struct {
        BuildTaskID id;
        UniverseID buildingcontainer;
        UniverseID component;
        const char* macro;
        const char* factionid;
        UniverseID buildercomponent;
        int64_t price;
        bool ismissingresources;
        uint32_t queueposition;
    } BuildTaskInfo;
    typedef struct {
        BlacklistTypeID* blacklists;
        uint32_t numblacklists;
        FightRuleTypeID* fightrules;
        uint32_t numfightrules;
        const char* paintmodwareid;
    } AddBuildTask6Container;
    BuildTaskID AddBuildTask6(UniverseID containerid, UniverseID defensibleid, const char* macroname, UILoadout2 uiloadout, int64_t price, CrewTransferInfo2 crewtransfer, bool immediate, const char* customname, AddBuildTask6Container* additionalinfo);
    bool CanGenerateValidLoadout(UniverseID containerid, const char* macroname);
    void GenerateShipLoadout2(UILoadout2* result, UniverseID containerid, UniverseID shipid, const char* macroname, float level);
    void GenerateShipLoadoutCounts2(UILoadoutCounts2* result, UniverseID containerid, UniverseID shipid, const char* macroname, float level);
    uint32_t GetNumPlayerShipBuildTasks(bool isinprogress, bool includeupgrade);
    uint32_t GetPlayerShipBuildTasks(BuildTaskInfo* result, uint32_t resultlen, bool isinprogress, bool includeupgrade);
    uint32_t GetNumBuildTasks(UniverseID containerid, UniverseID buildmoduleid, bool isinprogress, bool includeupgrade);
    UniverseID GetPlayerID(void);
    double GetContainerWareConsumption(UniverseID containerid, const char* wareid, bool ignorestate);
    double GetContainerWareProduction(UniverseID containerid, const char* wareid, bool ignorestate);
    uint32_t GetNumBlueprints(const char* set, const char* category, const char* macroname);
    uint32_t GetBlueprints(UIBlueprint* result, uint32_t resultlen, const char* set, const char* category, const char* macroname);
]]

local menu = {
    name = "JKEOC_SettingsMenu",
    title = "EOC - EXECUTIVE OPERATIONS CENTER",
    page = "dashboard",
    selected = 1,
    analysisRunning = false,
    actions = {},
    reports = {},
    selectedReport = 1,
}

local config = {
    layer = 6,
    widthRatio = 0.76,
    -- Build 292: Build 291 live logs proved the populated Solution Planner
    -- required 1574 physical pixels while 0.80 left 1552, so X4 rejected the
    -- table. At Razor's 2160-pixel viewport, 0.82 adds about 44 physical pixels
    -- and clears the proven 22-pixel deficit without changing planner content.
    heightRatio = 0.82,
    minWidth = 1060,
    -- 600 logical pixels remains below the 1508 physical-pixel budget observed
    -- at Razor's current UI scale; 650 scaled to 1558 and X4 rejected the table.
    minHeight = 600,
    maxWidth = 1840,
    maxHeight = 1100,
}

local roles = {
    "SHIPYARD",
    "WHARF",
    "DEFENSE",
    "FACTORY",
    "MINING HUB",
    "TRADING HUB",
    "FOOD",
    "TECHNOLOGY",
    "HEADQUARTERS",
    "HYBRID",
}

local frameBackground = { r = 0, g = 0, b = 0, a = 95 }
local activeTabBackground = { r = 0, g = 149, b = 203, a = 100 }
local selectedModeBackground = { r = 0, g = 116, b = 153, a = 100 }
local availableModeBackground = { r = 49, g = 69, b = 83, a = 60 }
local inactiveModeBackground = { r = 32, g = 32, b = 32, a = 100 }
local currentChoiceBackground = { r = 20, g = 92, b = 48, a = 100 }
local pendingChoiceBackground = { r = 125, g = 82, b = 12, a = 100 }
local unavailableChoiceBackground = { r = 105, g = 32, b = 32, a = 100 }
local investigationPassColor = { r = 90, g = 220, b = 120, a = 100 }
local investigationFailColor = { r = 255, g = 92, b = 92, a = 100 }
local investigationUnknownColor = { r = 255, g = 190, b = 72, a = 100 }
local investigationNeutralColor = { r = 175, g = 185, b = 195, a = 100 }
local navigationStoryColor = { r = 125, g = 200, b = 235, a = 100 }
local EOC_IDENTITY_BB = "$JKEOC_CommandIntelligenceIdentity"
-- EOC owns every color used by this window. Do not read an optional shared
-- helper color table: some UI frameworks supply it, but it is absent in a
-- standalone X4 session, which would abort page rendering on access.
local EOC_OS_BUILD = 262
menu.supplyBlackboardKey = "$JKEOC_B277SupplyModel"
menu.supplyPages = {}
local EOC_CHECKLIST_SCHEMA = 4
local KPI_REFRESH_SECONDS = 30
-- Cash sampling runs every 30 seconds. Retain a bounded hour so the player can
-- compare more than the former 30-minute window without creating a background
-- watcher or persisting an unbounded session history.
menu.KPI_HISTORY_LIMIT = 128
menu.KPI_REFRESH_INTERVALS = { cash = 30, shipyard = 30, construction = 60, trade = 60, storage = 120, earners = 120, drains = 120, attention = 120 }
function menu.kpiRefreshInterval(view) return menu.KPI_REFRESH_INTERVALS[view or "cash"] or KPI_REFRESH_SECONDS end
local EOC_OS_BOOT_DELAY = 1.35
local EOC_OS_RANDOM_MESSAGE_COUNT = 5
local EOC_OS_MESSAGE_POOL = {
    "Reviewing the empire for pirates, infiltrators, and suspiciously well-informed faction agents...",
    "Checking stations for disease, pollution, and unapproved break-room experiments...",
    "Verifying the space hamsters are engaged and the emergency wheels are turning...",
    "Counting cargo drones. Recounting the one that keeps moving...",
    "Asking station managers whether they have tried turning production off and on again...",
    "Inspecting airlocks for misplaced spacesuits and suspicious lunch containers...",
    "Calibrating the executive coffee dispenser for maximum strategic clarity...",
    "Checking whether the Xenon have submitted the required visitor paperwork...",
    "Confirming all Teladi invoices contain the traditional number of hidden fees...",
    "Searching personnel records for anyone named Definitely Not A Pirate...",
    "Polishing the red warning lights. They work better when dramatic...",
    "Testing the emergency klaxon at a volume approved by nobody...",
    "Making sure the Boron hydration systems are not connected to the coffee supply...",
    "Reviewing Split motivational procedures. Medical staff placed on standby...",
    "Checking Paranid geometry for an unnecessary third dimension...",
    "Auditing cargo manifests for crates labeled Totally Normal Spaceflies...",
    "Reassuring the autopilot that asteroid collisions are not a navigation feature...",
    "Locating the missing ten-millimeter maintenance spanner. Search remains ongoing...",
    "Confirming defense platforms know which direction the enemy usually comes from...",
    "Checking ship captains for expired licenses and heroic levels of optimism...",
    "Removing duplicate meetings from the empire calendar. Productivity increased...",
    "Scanning ventilation ducts for spies, spaceflies, and escaped sandwiches...",
    "Verifying miners remember that stations prefer resources delivered inside the station...",
    "Negotiating a temporary ceasefire between Accounting and Logistics...",
    "Checking whether any manager has allocated the entire budget to decorative plants...",
    "Synchronizing clocks across the empire. Argon Prime is still three minutes smug...",
    "Testing backup systems for the backup systems. Primary backup appears surprised...",
    "Ensuring construction drones have not built another storage module around themselves...",
    "Reviewing trade routes for scenic detours through active war zones...",
    "Feeding the executive dashboard. It prefers clean data and occasional praise...",
}

local function resultColor(state)
    state = string.upper(tostring(state or ""))
    if state == "PASS" or state == "RESOLVED" or state == "IMPROVING" then return investigationPassColor end
    if state == "FAIL" or state == "WORSENING" or state == "RELAPSED" then return investigationFailColor end
    if state == "UNKNOWN" or state == "UNCHANGED" or state == "MORE OBSERVATION REQUIRED" then return investigationUnknownColor end
    return investigationNeutralColor
end

local function commandIdentityStore()
    if menu.commandIdentityCacheDirty and type(menu.commandIdentityCache) == "table" then
        return menu.commandIdentityCache
    end
    local store
    pcall(function() store = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), EOC_IDENTITY_BB) end)
    if type(store) ~= "table" then store = menu.commandIdentityCache or {} end
    menu.commandIdentityCache = store
    return store
end

local function saveCommandIdentityStore(store)
    menu.commandIdentityCache = store
    menu.commandIdentityCacheDirty = true
    pcall(function() SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), EOC_IDENTITY_BB, store) end)
end

local function playerDisplayName()
    local name = "Commander"
    pcall(function() name = GetComponentData(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "name") or name end)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "Commander"
end

local function intelligenceName()
    local name = tostring(commandIdentityStore().name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "EOC"
end

local EOC_NARRATIVE_BB = "$JKEOC_NarrativeHistory"

local function narrativeStore()
    local store
    pcall(function() store = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), EOC_NARRATIVE_BB) end)
    if type(store) ~= "table" then store = menu.narrativeCache or { lastReview = 0 } end
    store.lastReview = tonumber(store.lastReview) or 0
    menu.narrativeCache = store
    return store
end

local function saveNarrativeStore(store)
    menu.narrativeCache = store
    pcall(function() SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), EOC_NARRATIVE_BB, store) end)
end

local function startupSequenceEnabled()
    if type(menu.startupPreference) == "boolean" then return menu.startupPreference end
    return commandIdentityStore().startupSequenceEnabled ~= false
end
local function buildOSBootStages()
    local available = {}
    for index, message in ipairs(EOC_OS_MESSAGE_POOL) do available[index] = message end
    local stages = { "Loading the EOC operating system..." }
    local elapsed = getElapsedTime()
    local seed = math.floor((tonumber(elapsed) or 0) * 1000) + (#playerDisplayName() * 97) + (#intelligenceName() * 193)
    for _ = 1, math.min(EOC_OS_RANDOM_MESSAGE_COUNT, #available) do
        seed = (seed * 1103515245 + 12345) % 2147483648
        local selected = (seed % #available) + 1
        stages[#stages + 1] = table.remove(available, selected)
    end
    stages[#stages + 1] = "STARTUP COMPLETE. EOC OS BUILD " .. tostring(EOC_OS_BUILD) .. " IS OPERATIONAL."
    return stages
end

local function raise(control, value)
    AddUITriggeredEvent(menu.name, control, value)
end

local function v(source, index, fallback)
    if type(source) == "table" and source[index] ~= nil then
        return source[index]
    end
    return fallback
end

local function text(value)
    if value == nil or value == "" then
        return "-"
    end
    return tostring(value)
end

function menu.playerDisplayText(value)
    local displayed = tostring(value or "")
    displayed = string.gsub(displayed, "—", " - ")
    displayed = string.gsub(displayed, "–", "-")
    displayed = string.gsub(displayed, "→", " -> ")
    displayed = string.gsub(displayed, "↔", " <-> ")
    displayed = string.gsub(displayed, "…", "...")
    return displayed
end

local formatNumber

local function managedActionForCase(caseData)
    if not caseData then return nil end
    local stationName = text(v(caseData, 1, ""))
    local wareName = text(v(caseData, 4, ""))
    for _, action in ipairs(menu.tradeOffers or {}) do
        if text(v(action, 1, "")) == stationName and text(v(action, 14, v(action, 3, ""))) == wareName then return action end
    end
    return nil
end

function menu.plannerAccessForCase(caseData)
    if not caseData then return false, "NO_CASE" end
    local action = managedActionForCase(caseData)
    local actionState = action and string.upper(text(v(action, 6, ""))) or ""
    if actionState == "RECOVERY EXHAUSTED - PLANNER AVAILABLE"
        or actionState == "INPUT DELIVERY TEST EXHAUSTED - LOCAL PRODUCTION CHECKS REMAIN" then
        return true, "RECOVERY_EXHAUSTED"
    end
    local readiness = menu.expansionReadiness
    if readiness
        and text(readiness.station) == text(v(caseData, 1, ""))
        and text(readiness.ware) == text(v(caseData, 4, "")) then
        return true, "RETAINED_READINESS"
    end
    if (tonumber(v(caseData, 34, 0)) or 0) > 0 then
        return true, "PLANNED_PRODUCTION_REVIEW"
    end
    return false, "RECOVERY_NOT_EXHAUSTED"
end

local function managedActionText(caseData)
    local action = managedActionForCase(caseData)
    if not action then
        if string.upper(text(menu.tradeMode)) == "MANAGED" then
            return "EOC has confirmed this case, but no managed action record is available yet. Run a fresh analysis so EOC can reconcile the station action.", investigationUnknownColor
        end
        return "EOC is reporting this case only. Managed / Do Everything authority is not enabled, so EOC has not started a station action.", investigationUnknownColor
    end
    local actionType = text(v(action, 2, "ACTION"))
    local wareName = text(v(action, 3, "WARE"))
    local amount = tonumber(v(action, 4, 0)) or 0
    local state = text(v(action, 6, "UNKNOWN"))
    local reason = text(v(action, 7, "No operational explanation is available."))
    local waiting = text(v(action, 8, "NEXT EMPIRE ANALYSIS"))
    local line = state .. ": EOC is managing a bounded " .. actionType .. " action for up to " .. formatNumber(amount) .. " " .. wareName .. ".\n" .. reason .. "\nWAITING FOR: " .. waiting .. ". EOC will compare the next live stock reading with this action before closing or escalating the case."
    return line, string.find(string.upper(state), "BLOCKED", 1, true) and investigationFailColor or navigationStoryColor
end

local formatGameTime
local pair
local captureNavigation

formatNumber = function(value)
    local number = tonumber(value)
    if not number then
        return text(value)
    end
    local formatted = tostring(math.floor(number))
    while true do
        local replaced
        formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then
            break
        end
    end
    return formatted
end

local function existingShipOrder(station, cargo)
    for _, record in ipairs(menu.shipOrderRecords or {}) do
        if text(v(record, 1, "")) == station and text(v(record, 2, "")) == cargo then
            return record
        end
    end
    return nil
end

local function queueEOCShipOrder(wharfId, macro, customName)
    local ok, success, result, queued, building, rawtask = pcall(function()
        if not wharfId or tostring(wharfId) == "" or not macro or macro == "" then
            return false, "Missing wharf or ship blueprint."
        end
        local wharf = ConvertStringTo64Bit(tostring(wharfId))
        if wharf == 0 then
            return false, "The recommended player wharf is no longer available."
        end
        if not GetComponentData(wharf, "isplayerowned") then
            return false, "The recommended wharf is no longer player-owned."
        end
        if not C.CanGenerateValidLoadout(wharf, macro) then
            return false, "X4 could not generate a valid owned-blueprint loadout at this wharf."
        end
        local plan = Helper.getLoadoutHelper2(C.GenerateShipLoadout2, C.GenerateShipLoadoutCounts2, "UILoadout2", wharf, 0, macro, 0.5)
        if not plan then
            return false, "X4 returned no valid ship loadout."
        end
        local additionalinfo = ffi.new("AddBuildTask6Container")
        local crewtransfer = ffi.new("CrewTransferInfo2")
        local callok, taskid = pcall(C.AddBuildTask6, wharf, 0, macro, plan, 0, crewtransfer, false, customName or "", additionalinfo)
        Helper.ffiClearNewHelper()
        if not callok then
            error(taskid)
        end
        -- Native player-wharf behavior: zero vendor payment, normal resource consumption, and captain/crew definitions preserved directly from the generated UILoadout2; the empty transfer means no separately hired or transferred crew.
        if taskid == 0 then
            return false, "X4 rejected the build task. Check wharf resources and build capacity."
        end
        local queued = tonumber(C.GetNumBuildTasks(wharf, 0, false, false)) or 0
        local building = tonumber(C.GetNumBuildTasks(wharf, 0, true, false)) or 0
        return true, tostring(taskid), queued, building, taskid
    end)
    if not ok then
        return false, "Internal X4 order call failed: " .. tostring(success)
    end
    return success, result, queued, building, rawtask
end

local FLEET_TEMPLATE_BB = "$JKEOC_FleetBuildTemplates"
local FLEET_MAX_SHIPS = 100
local FLEET_MAX_PER_ENTRY = 50

local function copySerializable(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        if type(key) == "number" or type(key) == "string" then
            local kind = type(item)
            if kind == "number" or kind == "string" or kind == "boolean" or kind == "table" then result[key] = copySerializable(item) end
        end
    end
    return result
end

local function fleetTemplateStore()
    local store
    pcall(function() store = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), FLEET_TEMPLATE_BB) end)
    if type(store) ~= "table" then store = menu.fleetTemplateCache or {} end
    menu.fleetTemplateCache = store
    return store
end

local function saveFleetTemplateStore(store)
    menu.fleetTemplateCache = store
    pcall(function() SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), FLEET_TEMPLATE_BB, store) end)
end

local function fleetShipCount(template)
    local count = 0
    for _, entry in ipairs((template and template.entries) or {}) do count = count + math.max(0, tonumber(entry.amount) or 0) end
    return count
end

local function findFleetTemplate(name)
    for index, template in ipairs(fleetTemplateStore()) do
        if template.name == name then return template, index end
    end
    return nil
end

local function storeFleetTemplate(draft, originalName)
    local name = tostring((draft and draft.name) or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local total = fleetShipCount(draft)
    if name == "" then return false, "Enter a fleet template name." end
    if total < 1 then return false, "Add at least one ship before saving." end
    if total > FLEET_MAX_SHIPS then return false, "A fleet template is limited to " .. FLEET_MAX_SHIPS .. " ships." end
    local store = fleetTemplateStore()
    for index = #store, 1, -1 do
        if store[index].name == name or (originalName and store[index].name == originalName) then table.remove(store, index) end
    end
    store[#store + 1] = { name = name, entries = copySerializable(draft.entries) }
    table.sort(store, function(a, b) return tostring(a.name) < tostring(b.name) end)
    saveFleetTemplateStore(store)
    return true, name
end

local function deleteFleetTemplate(name)
    local store = fleetTemplateStore()
    for index = #store, 1, -1 do if store[index].name == name then table.remove(store, index) end end
    saveFleetTemplateStore(store)
end

local function allFleetYards()
    local yards, seen = {}, {}
    for _, route in ipairs(menu.shipWharfRoutes or {}) do
        local id = tostring(v(route, 10, ""))
        if id ~= "" then
            local yard = seen[id]
            if not yard then
                yard = { id=id, name=text(v(route,2,"Unknown shipyard")), sector=text(v(route,3,"Unknown sector")), queued=tonumber(v(route,6,0)) or 0, building=tonumber(v(route,7,0)) or 0, macros={} }
                seen[id] = yard
                yards[#yards + 1] = yard
            end
            yard.macros[tostring(v(route, 9, ""))] = true
        end
    end
    return yards
end

local function computeFleetBuildPlan(template, distribute)
    local plan = { name=template.name, distribute=distribute, jobs={}, skipped={}, total=0, yards=0 }
    local yards = allFleetYards()
    if not distribute then
        local candidates = {}
        for _, yard in ipairs(yards) do
            local valid = true
            for _, entry in ipairs(template.entries or {}) do if not yard.macros[tostring(entry.macro)] then valid=false break end end
            if valid then candidates[#candidates + 1] = yard end
        end
        table.sort(candidates, function(a,b) return (a.queued+a.building) < (b.queued+b.building) end)
        local yard = candidates[1]
        if not yard then plan.error="No single player shipyard can build every hull in this template. Choose distributed construction."; return plan end
        for _, entry in ipairs(template.entries or {}) do
            local amount=math.max(1,math.min(FLEET_MAX_PER_ENTRY,tonumber(entry.amount) or 1))
            plan.jobs[#plan.jobs+1]={yard=yard,entry=entry,amount=amount}
            plan.total=plan.total+amount
        end
        plan.yards=1
        return plan
    end
    local used, assignedLoad = {}, {}
    for _, entry in ipairs(template.entries or {}) do
        local candidates={}
        for _, yard in ipairs(yards) do if yard.macros[tostring(entry.macro)] then candidates[#candidates+1]=yard end end
        if #candidates==0 then
            plan.skipped[#plan.skipped+1]=entry.name
        else
            local amount=math.max(1,math.min(FLEET_MAX_PER_ENTRY,tonumber(entry.amount) or 1))
            local buckets={}
            for _=1,amount do
                table.sort(candidates,function(a,b)
                    local al=(assignedLoad[a.id] or 0)+a.queued+a.building
                    local bl=(assignedLoad[b.id] or 0)+b.queued+b.building
                    if al==bl then return a.name<b.name end
                    return al<bl
                end)
                local yard=candidates[1]
                assignedLoad[yard.id]=(assignedLoad[yard.id] or 0)+1
                used[yard.id]=true
                local key=yard.id.."|"..tostring(entry.macro)
                if not buckets[key] then buckets[key]={yard=yard,entry=entry,amount=0};plan.jobs[#plan.jobs+1]=buckets[key] end
                buckets[key].amount=buckets[key].amount+1
                plan.total=plan.total+1
            end
        end
    end
    for _ in pairs(used) do plan.yards=plan.yards+1 end
    if plan.total==0 then plan.error="No compatible player shipyard can build any ship in this template." end
    return plan
end

local function executeFleetBuildPlan(plan)
    if not plan or plan.submitted then return false,"This preview has already been submitted." end
    plan.submitted=true
    local accepted,failed=0,{}
    for _,job in ipairs(plan.jobs or {}) do
        for _=1,job.amount do
            local success,result=queueEOCShipOrder(job.yard.id,job.entry.macro,"")
            if success then accepted=accepted+1 else failed[#failed+1]=job.entry.name.." at "..job.yard.name..": "..tostring(result) end
        end
    end
    plan.accepted=accepted
    plan.failed=failed
    if accepted==plan.total then return true,"X4 accepted all "..accepted.." fleet build task(s). Player shipyards now control resources and construction." end
    return false,"X4 accepted "..accepted.." of "..plan.total.." task(s). "..#failed.." failed; no failed task was retried."
end
local function minimumBuildBlueprint(role)
    local candidates = {}
    local ok, count = pcall(function() return C.GetNumBlueprints("", "", "") end)
    if not ok then return nil, "BLUEPRINT_DATA_UNAVAILABLE" end
    count = tonumber(count) or 0
    if count <= 0 then return nil, "NO_COMPATIBLE_OWNED_BLUEPRINT" end
    local blueprints = ffi.new("UIBlueprint[?]", count)
    local fetched, actual = pcall(function() return C.GetBlueprints(blueprints, count, "", "", "") end)
    if not fetched then return nil, "BLUEPRINT_DATA_UNAVAILABLE" end
    for i = 0, (tonumber(actual) or 0) - 1 do
        local macro = blueprints[i].macro ~= nil and ffi.string(blueprints[i].macro) or ""
        local lower = string.lower(macro)
        local compatible = (role == "MINING_SOLID" and string.find(lower, "_miner_solid_", 1, true) ~= nil)
            or (role == "MINING_LIQUID" and string.find(lower, "_miner_liquid_", 1, true) ~= nil)
            or ((role == "TRADE" or role == "BUILDSTORAGE") and string.find(lower, "_trans_", 1, true) ~= nil)
            or (role == "DEFENCE" and (string.find(lower, "fighter", 1, true) ~= nil or string.find(lower, "corvette", 1, true) ~= nil or string.find(lower, "frigate", 1, true) ~= nil or string.find(lower, "destroyer", 1, true) ~= nil))
        if compatible then
            local size = string.find(lower, "_m_", 1, true) and "M" or string.find(lower, "_s_", 1, true) and "S" or string.find(lower, "_l_", 1, true) and "L" or string.find(lower, "_xl_", 1, true) and "XL" or "UNKNOWN"
            candidates[#candidates + 1] = { name = tostring(GetMacroData(macro, "name") or macro), size = size, macro = macro }
        end
    end
    table.sort(candidates, function(a, b)
        local rank = { M = 1, S = 2, L = 3, XL = 4, UNKNOWN = 5 }
        local ar, br = rank[a.size] or 5, rank[b.size] or 5
        if ar == br then return a.name < b.name end
        return ar < br
    end)
    return candidates[1], candidates[1] and nil or "NO_COMPATIBLE_OWNED_BLUEPRINT"
end

local function minimumBuildStation(_, value)
    menu.minimumBuildRequest = menu.minimumBuildRequest or {}
    menu.minimumBuildRequest.station = tostring(value or "")
end

local function minimumBuildRole(_, value)
    menu.minimumBuildRequest = menu.minimumBuildRequest or {}
    menu.minimumBuildRequest.role = tostring(value or "")
end

local function minimumBuildCommit()
    local request = menu.minimumBuildRequest or {}
    menu.minimumBuildRequest = nil
    local role, station = tostring(request.role or ""), tostring(request.station or "")
    local blueprint, reason = minimumBuildBlueprint(role)
    if not blueprint then
        raise("minimum.build.result", { success = false, station = station, role = role, reason = reason or "BLUEPRINT_DATA_UNAVAILABLE" })
        return
    end
    raise("minimum.build.blueprint", { station=station, role=role, blueprint=blueprint.name, macro=blueprint.macro })
end
function menu.minimumBuildBlueprintName(_, value) menu.minimumBuildRequest = menu.minimumBuildRequest or {}; menu.minimumBuildRequest.blueprint = tostring(value or "") end
function menu.minimumBuildMacro(_, value) menu.minimumBuildRequest = menu.minimumBuildRequest or {}; menu.minimumBuildRequest.macro = tostring(value or "") end
function menu.minimumBuildYardName(_, value) menu.minimumBuildRequest = menu.minimumBuildRequest or {}; menu.minimumBuildRequest.yard = tostring(value or "") end
function menu.minimumBuildYardId(_, value) menu.minimumBuildRequest = menu.minimumBuildRequest or {}; menu.minimumBuildRequest.yardid = tostring(value or "") end
function menu.minimumBuildExecute()
    local request = menu.minimumBuildRequest or {}
    menu.minimumBuildRequest = nil
    local station, role = tostring(request.station or ""), tostring(request.role or "")
    if request.macro == nil or request.macro == "" or request.yardid == nil or request.yardid == "" then
        raise("minimum.build.result", { success=false, station=station, role=role, reason="BACKGROUND_BUILD_DATA_UNAVAILABLE" })
        return
    end
    local success, result, queued, building = queueEOCShipOrder(request.yardid, request.macro, "EOC Minimum " .. role)
    raise("minimum.build.result", { success=success and true or false, station=station, role=role, blueprint=request.blueprint, macro=request.macro, yard=request.yard, task=tostring(result or ""), queued=tonumber(queued) or 0, building=tonumber(building) or 0, reason=success and "X4_BUILD_TASK_ACCEPTED" or tostring(result or "X4_BUILD_TASK_REJECTED") })
end
local function actionState(action)
    menu.actions[action] = menu.actions[action] or {
        running = false,
        result = nil,
        lastRun = nil,
    }
    return menu.actions[action]
end

local function startAction(action)
    local state = actionState(action)
    if state.running then
        return false
    end
    state.running = true
    state.result = "WORKING"
    menu.refresh()
    return true
end

local function actionName(_, value)
    menu.pendingAction = { name = tostring(value or "unknown") }
end

local function actionResultReceived(_, value)
    menu.pendingAction = menu.pendingAction or { name = "unknown" }
    menu.pendingAction.result = tostring(value or "Completed; no additional action was required.")
end

local function actionTimeReceived(_, value)
    menu.pendingAction = menu.pendingAction or { name = "unknown" }
    menu.pendingAction.time = value
end

local function actionValueReceived(_, value)
    menu.pendingAction = menu.pendingAction or { name = "unknown" }
    menu.pendingAction.value = value
end

local function shippingRefreshBegin()
    menu.shippingRefresh = {
        registered = {},
        pending = {},
        registeredRow = {},
        pendingRow = {},
        mode = menu.shipmode,
    }
end

local function shippingRefreshState()
    if not menu.shippingRefresh then
        shippingRefreshBegin()
    end
    return menu.shippingRefresh
end

local function shippingRegisteredName(_, value) shippingRefreshState().registeredRow[1] = tostring(value or "Unknown ship") end
local function shippingRegisteredPurpose(_, value) shippingRefreshState().registeredRow[2] = tostring(value or "unknown") end
local function shippingRegisteredClass(_, value) shippingRefreshState().registeredRow[3] = tostring(value or "unknown") end
local function shippingRegisteredOperational(_, value) shippingRefreshState().registeredRow[4] = value and true or false end
local function shippingRegisteredStatus(_, value) shippingRefreshState().registeredRow[5] = tostring(value or "AVAILABLE") end
local function shippingRegisteredAssignment(_, value) shippingRefreshState().registeredRow[6] = tostring(value or "UNASSIGNED") end

local function shippingRegisteredCommit()
    local refresh = shippingRefreshState()
    table.insert(refresh.registered, refresh.registeredRow)
    refresh.registeredRow = {}
end

local function shippingPendingShip(_, value) shippingRefreshState().pendingRow[1] = tostring(value or "Unknown ship") end
local function shippingPendingStation(_, value) shippingRefreshState().pendingRow[2] = tostring(value or "Unknown station") end
local function shippingPendingCategory(_, value) shippingRefreshState().pendingRow[3] = tostring(value or "LOGISTICS ASSIGNMENT") end
local function shippingPendingStatus(_, value) shippingRefreshState().pendingRow[4] = tostring(value or "AWAITING APPROVAL") end

local function shippingPendingCommit()
    local refresh = shippingRefreshState()
    table.insert(refresh.pending, refresh.pendingRow)
    refresh.pendingRow = {}
end

menu.rawSourceUpdate = {}
function menu.rawSourceStation(_, value) menu.rawSourceUpdate.station = text(value) end
function menu.rawSourceWare(_, value) menu.rawSourceUpdate.ware = menu.supplyWareId(value) end
function menu.rawSourceStatus(_, value) menu.rawSourceUpdate.status = text(value) end
function menu.rawSourceShip(_, value) menu.rawSourceUpdate.ship = text(value) end
function menu.rawSourceDetail(_, value) menu.rawSourceUpdate.detail = text(value) end
function menu.rawSourceCommit()
    if menu.rawSourceUpdate.station and menu.rawSourceUpdate.ware then
        menu.rawSourceRecords = menu.rawSourceRecords or {}
        local status = menu.rawSourceUpdate.status or "BLOCKED"
        local ship = menu.rawSourceUpdate.ship or ""
        menu.rawSourceRecords[menu.rawSourceUpdate.station .. "|" .. menu.rawSourceUpdate.ware] = {
            status = status, ship = ship, detail = menu.rawSourceUpdate.detail or ""
        }
    end
    menu.rawSourceUpdate = {}
    if menu.frame ~= nil and type(menu.stations) == "table" then
        menu.refresh()
    else
        DebugError("[JKEOC][B326][RAW_SOURCE_FEEDBACK_DEFERRED] reason=MENU_CLOSED result_retained=1 redraw=NEXT_NORMAL_OPEN")
    end
end

function menu.agreedPlanKey(stationName, wareId)
    return text(stationName) .. "|" .. menu.supplyWareId(wareId)
end

function menu.agreedPlanStatus(_, value)
    menu.agreedPlanMessage = text(value)
    if menu.agreedPlanMessage == "SAVED" and menu.pendingAgreedPlan then
        menu.agreedBuildPlans = menu.agreedBuildPlans or {}
        menu.agreedBuildPlans[menu.pendingAgreedPlan.key] = menu.pendingAgreedPlan.plan
        menu.solutionAgreedKey = menu.pendingAgreedPlan.commandKey
        menu.agreedBuildPage = 1
        menu.agreedClearConfirm = nil
        menu.pendingAgreedPlan = nil
    elseif menu.agreedPlanMessage == "CLEARED" and menu.pendingAgreedClearKey then
        if menu.agreedBuildPlans then menu.agreedBuildPlans[menu.pendingAgreedClearKey] = nil end
        menu.pendingAgreedClearKey = nil
        menu.agreedClearConfirm = nil
        menu.solutionAgreedKey = nil
        menu.solutionAgreedStandaloneKey = nil
    elseif string.find(menu.agreedPlanMessage, "BLOCKED", 1, true) then
        menu.pendingAgreedPlan = nil
        menu.pendingAgreedClearKey = nil
    end
    if menu.frame ~= nil and type(menu.stations) == "table" then menu.refresh() end
end

local function shippingModeReceived(_, value)
    shippingRefreshState().mode = tostring(value or menu.shipmode)
end

local function shippingRefreshComplete()
    local refresh = shippingRefreshState()
    menu.registeredShips = refresh.registered
    menu.pendingAssignments = refresh.pending
    menu.shipmode = refresh.mode
    menu.shippingRefresh = nil
    menu.fleetPage = 1
    if menu.frame then
        menu.refresh()
    end
end

local function settingsConfirmed(_, value)
    menu.settingsChangeRunning = false
    menu.settingsStatus = "STATUS: " .. tostring(value or "Setting updated.")
    if menu.frame then
        menu.refresh()
    end
end

local function actionComplete()
    local payload = menu.pendingAction or { name = "unknown" }
    local action = payload.name
    local state = actionState(action)
    state.running = false
    state.result = text(payload.result)
    state.lastRun = formatGameTime(payload.time)
    if action == "trade.review" then
        menu.offers = tonumber(payload.value) or menu.offers
    end
    if action == "case.clearall" then
        menu.cases = {}
        menu.checklistProgress = {}
        menu.observations = {}
        menu.monitoredCases = {}
        menu.diagnosticCase = nil
        for _, station in ipairs(menu.stations or {}) do
            station[3] = "MONITORING"
            station[4] = "STABLE"
            station[5] = "LOW"
            station[6] = "INFO"
            station[7] = "Continue monitoring; no supported case or retained evidence currently requires intervention"
            station[8] = 0
            station[17] = 0
            station[18] = 0
            station[19] = 0
            station[20] = 0
            station[21] = 0
            station[22] = 0
        end
    end
    menu.pendingAction = nil
    if menu.frame then
        menu.refresh()
    end
end

local function actionLabel(action, readyLabel, runningLabel)
    local state = actionState(action)
    if state.running then
        return runningLabel
    end
    return readyLabel
end

local actionNextSteps = {
    ["shipping.register"] = "Open Fleet & Logistics > Registered Ships. If eligible ships are listed, run Scan Shipping Needs once. If none are listed, assign or free a compatible player-owned trade/mining ship or salvage tug, reopen EOC, register again once, and then scan. Do not repeat registration without changing ship eligibility.",
    ["shipping.scan"] = "Open Fleet & Logistics > Pending. In Approval Required mode, approve only the displayed exact assignment or do nothing. In Auto-Assign Registered mode, verify the result names the assigned ship and station; if no supported need was found, no repeat is required until station need or registered-ship availability changes.",
    ["shipping.approve"] = "Open Fleet & Logistics > Pending and confirm the exact row is gone, then review Registered Ships for the named ship's assignment. If the row remains or the result is blocked, correct the stated ownership, registration, cargo, commander, or station condition and submit approval once more; otherwise do not repeat.",
    ["trade.review"] = "Open Fleet & Logistics > EOC-Managed Offers. If the result reports verified offers, no repeat is required. If it reports blocked or removed records, correct the exact case, station rule, funds, range, or supplier condition named in the result, then run Review Trade Actions once after that condition changes.",
    ["station.auto"] = "Open Stations and inspect the Role column. If no station remains UNDEFINED, no repeat is required. If a station remains UNDEFINED, select that station, choose its exact role manually, and confirm once; do not repeatedly run automatic assignment against the unchanged station list.",
    ["station.role"] = "Review the selected station and confirm the requested role is displayed. If it is correct, no repeat is required. If the result is blocked or the old role remains, keep the same station selected, correct the ownership/identity condition stated in the result, and confirm the role change once more.",
    ["diagnostics.goal"] = "Run Refresh Bounded Analysis once, then read the retained result on this page. Do not repeat unless the selected station, evidence, or requested goal changes.",
    ["analysis.run"] = "Open Cases or View Stations Requiring Action and read the refreshed retained evidence. If the expected case is present, follow its exact Next Action. If no matching case exists, do not repeat immediately; continue normal operation and rerun only after station evidence changes.",
    ["diagnostics.status"] = "Open Player Information > Logbook > Tips and read the saved status. This is a report-only job; no repeat is required unless you intentionally want a later snapshot after evidence changes.",
    ["diagnostics.probe"] = "Read the retained mailbox result below. No gameplay change was authorized. If BLOCKED or EXPIRED, correct the named target/expiry condition and submit one new probe; if COMPLETE, no repeat is required.",
    ["diagnostics.proof"] = "Read the retained verification and rollback fields below. If both are proven, no repeat is required. If either is NOT PROVEN or BLOCKED, do not authorize gameplay use; correct the exact missing proof and run the proof job once more.",
    ["case.create"] = "Open the exact case now. Follow its Next Action once, then use its Verify Result page. If EOC opened an existing matching case, do not create another. If creation was blocked, satisfy the stated two-snapshot/evidence prerequisite before requesting once more.",
    ["case.close"] = "No further action is required for this player-requested case. Do not repeat Close. EOC-confirmed evidence remains separate and will reappear only if later analysis still proves an active condition.",
    ["case.monitor"] = "Do nothing and continue normal play. EOC owns the retained observation and will report the answer. Do not request another monitor or recheck while this result remains REQUESTED, CHECKING, WAITING, or IN PROGRESS.",
    ["case.clearall"] = "Review Cases after the automatic fresh analysis finishes. If the list is empty, no repeat is required. Any cases that return are newly supported by current evidence; open them and follow their exact Next Action instead of clearing again.",
    ["market.test"] = "Open the retained market-test result below. If the bounded EOC offer was created, leave it active for the stated operating cycle and do not create another. If blocked, correct the exact station, ware, funds, rule, range, or supplier condition named in the result, then submit one new test.",
    ["market.test.remove"] = "If the result confirms removal, no further action or repeat is required. If blocked, verify the same station, ware, direction, and EOC-owned offer still exist, then retry removal once; ordinary player offers and station rules must remain untouched.",
    ["minimum.build"] = "If X4 accepted the task, no repeat is required: the named player shipyard now owns normal resource delivery and construction. If blocked, open Fleet & Logistics > Fleet Staffing, correct the exact shortage, blueprint, shipyard, or native rejection named above, then allow the next bounded minimum scan; do not submit an extra manual EOC request.",
}

local actionResultRoutes = {
    ["analysis.run"] = { page = "cases", label = "VIEW RESULT: CASES" },
    ["shipping.register"] = { page = "fleet", view = "ships", label = "VIEW RESULT: REGISTERED SHIPS" },
    ["shipping.scan"] = { page = "fleet", view = "pending", label = "VIEW RESULT: SHIPPING STATUS" },
    ["shipping.approve"] = { page = "fleet", view = "pending", label = "VIEW RESULT: PENDING ASSIGNMENTS" },
    ["trade.review"] = { page = "fleet", view = "offers", label = "VIEW RESULT: TRADE OFFERS" },
    ["station.auto"] = { page = "stations", label = "VIEW RESULT: STATIONS" },
    ["station.role"] = { page = "stations", label = "VIEW RESULT: SELECTED STATION" },
    ["case.create"] = { page = "cases", label = "VIEW RESULT: CASE" },
}

local addButton

function menu.jobOutcomeGuidance(action, result)
    local value = string.upper(text(result, ""))
    local meaning
    if value == "WORKING" or string.find(value, "IN PROGRESS", 1, true) or string.find(value, "REQUESTED", 1, true) or string.find(value, "CHECKING", 1, true) or string.find(value, "WAITING", 1, true) then
        meaning = "THIS JOB IS STILL RUNNING. EOC does not have an answer yet. Do not press the same button again."
    elseif string.find(value, "BLOCKED", 1, true) or string.find(value, "FAILED", 1, true) or string.find(value, "REJECT", 1, true) or string.find(value, "UNAVAILABLE", 1, true) then
        meaning = "THIS JOB DID NOT FINISH. The result above names the problem that stopped it. Nothing was proven successful."
    elseif string.find(value, "COMPLETE", 1, true) or string.find(value, "VERIFIED", 1, true) or string.find(value, "ACCEPTED", 1, true) or string.find(value, "APPLIED", 1, true) or string.find(value, "ASSIGNED", 1, true) or string.find(value, "SAVED", 1, true) or string.find(value, "CLOSED", 1, true) then
        meaning = "THIS JOB FINISHED. The result above is the final answer. Do not repeat it just to get the same answer again."
    else
        meaning = "EOC RETURNED AN ANSWER. Read the result above. If information is missing, EOC does not know the answer yet and will not pretend the job succeeded."
    end
    return meaning, actionNextSteps[action] or "If the result says COMPLETE, stop. If it names a problem, fix that problem first. Run the job one more time only after something has changed."
end

local function actionResult(tableWidget, action, purpose)
    local state = actionState(action)
    local row = tableWidget:addRow(false)
    local message = state.result and ("RESULT: " .. state.result) or ("WHAT THIS DOES: " .. purpose)
    row[1]:setColSpan(4):createText(message, { wordwrap = true })
    if state.result then
        local meaning, nextStep = menu.jobOutcomeGuidance(action, state.result)
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("WHAT THIS MEANS: " .. meaning, { wordwrap = true })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("WHAT TO DO NEXT: " .. nextStep, { wordwrap = true })
    end
    local route = state.result and actionResultRoutes[action] or nil
    if route then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        row[1]:createButton({ active = true, bgColor = availableModeBackground }):setText(route.label)
        row[1].handlers.onClick = function()
            captureNavigation("RESULT - " .. action)
            if route.view then menu.fleetView = route.view end
            menu.page = route.page
            menu.activeTab = route.page
            menu.refresh()
        end
    end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Every variable-length player-facing list must pass through this boundary.
-- X4 calculates a table's complete minimum height before applying its scrollbar,
-- so maxVisibleHeight cannot protect an over-populated table. Derive the slice
-- from both the current content pixels and the shared 170-row engine pool.
function menu.adaptiveListWindow(total, pageKey, options)
    options = options or {}
    total = math.max(0, tonumber(total) or 0)
    local rowPitch = Helper.scaleY(Helper.standardTextHeight)
    local measured, measuredHeight = pcall(function()
        local fontsize = Helper.scaleFont(Helper.standardFont, Helper.standardFontSize)
        return math.ceil(C.GetTextHeight("Ag", Helper.standardFont, math.floor(fontsize), 0))
    end)
    if measured and type(measuredHeight) == "number" then rowPitch = math.max(rowPitch, Helper.scaleY(Helper.standardTextOffsety) + measuredHeight) end
    rowPitch = math.max(1, rowPitch + Helper.borderSize)
    local contentPixels = tonumber(options.contentPixels) or tonumber(menu.listContentHeight) or Helper.scaleY(config.maxHeight)
    -- Build 343 adds one heading and three plain-language guide rows to every
    -- main page. Reserve those four shared rows for every bounded list.
    local fixedRows = math.max(0, tonumber(options.fixedRows) or 0) + 4
    local rowUnits = math.max(1, tonumber(options.rowUnits) or 1)
    local columns = math.max(1, tonumber(options.columns) or 1)
    local pixelUnits = math.max(1, math.floor(contentPixels / rowPitch) - fixedRows)
    local poolUnits = math.max(1, (170 - 5 - 1) - fixedRows)
    local recordsPerPage = math.max(columns, math.floor(math.min(pixelUnits, poolUnits) / rowUnits) * columns)
    if options.maximum then recordsPerPage = math.min(recordsPerPage, math.max(columns, tonumber(options.maximum) or recordsPerPage)) end
    local pageCount = math.max(1, math.ceil(total / recordsPerPage))
    menu.listPages = menu.listPages or {}
    local page = clamp(tonumber(menu.listPages[pageKey]) or 1, 1, pageCount)
    menu.listPages[pageKey] = page
    local first = (page - 1) * recordsPerPage + 1
    return first, math.min(total, first + recordsPerPage - 1), page, pageCount, recordsPerPage
end

function menu.adaptiveListNavigation(tableWidget, pageKey, total, options)
    local first, last, page, pageCount, recordsPerPage = menu.adaptiveListWindow(total, pageKey, options)
    if pageCount > 1 then
        if pageCount > 2 then
            local firstPage = tableWidget:addRow(true)
            addButton(firstPage, 1, "RETURN TO PAGE 1", function() menu.listPages[pageKey] = 1; menu.refresh() end, page > 1)
        end
        local nav = tableWidget:addRow(true)
        addButton(nav, 1, "PREVIOUS", function() menu.listPages[pageKey] = math.max(1, page - 1); menu.refresh() end, page > 1)
        nav[2]:createText("PAGE " .. page .. " / " .. pageCount, { halign = "center" })
        addButton(nav, 3, "NEXT", function() menu.listPages[pageKey] = math.min(pageCount, page + 1); menu.refresh() end, page < pageCount)
        nav[4]:createText(total .. " RECORD(S) | " .. recordsPerPage .. " PER PAGE", { halign = "center" })
    end
    return first, last, page, pageCount, recordsPerPage
end

formatGameTime = function(value)
    local seconds = math.max(0, math.floor(tonumber(value) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("SAVE DAY %d, %02d:%02d:%02d", days + 1, hours, minutes, remainder)
end

local function importReports(source)
    local imported = {}
    if type(source) ~= "table" then
        return imported
    end
    for index = #source, 1, -1 do
        local report = source[index]
        table.insert(imported, {
            text(v(report, 1, "EOC REPORT")),
            text(v(report, 2, "No report text was returned.")),
            formatGameTime(v(report, 3, 0)),
            tonumber(v(report, 3, 0)) or 0,
        })
    end
    return imported
end

local function analysisOutputReceived(_, value)
    menu.pendingAnalysisOutput = tostring(value or "Analysis completed.")
end

local function analysisTimeReceived(_, value)
    menu.pendingAnalysisTime = value
end

local function verificationClassReceived(_, value) menu.pendingVerificationClass = text(value, "UNKNOWN") end
local function verificationResultReceived(_, value) menu.pendingVerificationResult = text(value, "UNKNOWN - no verification detail returned.") end

function menu.investigatedCaseBegin()
    menu.pendingInvestigatedCase = {}
    menu.caseEvidenceMissing = false
end

function menu.investigatedCaseField(index)
    return function(_, value)
        menu.pendingInvestigatedCase = menu.pendingInvestigatedCase or {}
        menu.pendingInvestigatedCase[index] = value
    end
end

function menu.investigatedCaseFound()
    if menu.pendingInvestigatedCase and #menu.pendingInvestigatedCase >= 11 then
        menu.diagnosticCase = menu.pendingInvestigatedCase
        menu.caseEvidenceMissing = false
        menu.caseEvidenceKey = menu.pendingCaseEvidenceKey
        menu.caseEvidenceHandoffMessage = "Fresh evidence was attached to this working case. EOC can now continue the diagnosis."
    end
    menu.pendingInvestigatedCase = nil
    menu.pendingCaseEvidenceKey = nil
end

function menu.investigatedCaseMissing()
    menu.pendingInvestigatedCase = nil
    menu.caseEvidenceMissing = true
    menu.caseEvidenceKey = menu.pendingCaseEvidenceKey
    menu.caseEvidenceHandoffMessage = "Fresh analysis completed, but it found no matching confirmed EOC case for this station and subject. EOC will not invent a cause."
    menu.pendingCaseEvidenceKey = nil
end

local function prerequisiteRows(caseData)
    local rows = {}
    local function add(label, state, evidence) table.insert(rows, { label = label, state = state, evidence = evidence }) end
    local family = string.upper(text(v(caseData, 3, "STATION ISSUE")))
    if string.upper(text(v(caseData, 2, ""))) == "PLAYER" then
        add("INCIDENT EVIDENCE", "NOT YET TESTED", text(v(caseData, 6, "Player-requested investigation created from retained observations; focused diagnostics have not run yet.")))
        return rows
    end
    local storageCase = string.find(family, "STORAGE", 1, true) ~= nil
    local logisticsCase = string.find(family, "LOGISTICS", 1, true) ~= nil or string.find(family, "SUPPORT SHIPS", 1, true) ~= nil
    local supplyCase = not storageCase and not logisticsCase
    local capacity, free = tonumber(v(caseData, 13, 0)) or 0, tonumber(v(caseData, 14, 0)) or 0
    local currentAmount = tonumber(v(caseData, 8, 0)) or 0
    local immediateNeed = tonumber(v(caseData, 30, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local ownSuppliers = tonumber(v(caseData, 19, 0)) or 0
    local npcSuppliers = tonumber(v(caseData, 20, 0)) or 0
    local traders = tonumber(v(caseData, 23, 0)) or 0
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    if supplyCase and npcSuppliers > 0 and compatible == 0 then
        add("DELIVERY PATH", "FAIL", npcSuppliers .. " NPC offer(s) known; " .. traders .. " trader(s) assigned; 0 cargo-compatible. Ware buy permission may also exclude NPC suppliers.")
    end
    if not logisticsCase then
        local capacityState = capacity > 0 and "PASS" or (currentAmount > 0 and "UNKNOWN" or "FAIL")
        add("STORAGE INSTALLED", capacityState, capacity > 0 and (text(v(caseData, 12, "UNKNOWN")) .. " capacity " .. formatNumber(capacity)) or (currentAmount > 0 and "Stock exists, but the last scan did not return a usable storage-capacity value." or "No compatible storage capacity was reported."))
        local freeState = capacity <= 0 and "UNKNOWN" or ((immediateNeed <= 0 or free >= immediateNeed) and "PASS" or "FAIL")
        add("STORAGE FREE SPACE", freeState, formatNumber(free) .. " physical free capacity; " .. formatNumber(immediateNeed) .. " required now. Ware allocation is reviewed separately in Logical Overview.")
    end
    if supplyCase then
        local stationFunds = tonumber(v(caseData, 32, 0)) or 0
        local minimumPrice = tonumber(v(caseData, 21, 0)) or 0
        local requiredBudget = immediateNeed > 0 and minimumPrice > 0 and (immediateNeed * minimumPrice) or 0
        local fundingState = requiredBudget > 0 and (stationFunds >= requiredBudget and "PASS" or "FAIL") or (stationFunds > 0 and "PASS" or "UNKNOWN")
        add("STATION OPERATING FUNDS", fundingState, formatNumber(stationFunds) .. " Cr available; estimated immediate purchase " .. formatNumber(requiredBudget) .. " Cr")
        add("REACHABLE SUPPLY", suppliers > 0 and "PASS" or "FAIL", suppliers .. " offers: own " .. text(v(caseData, 19, 0)) .. ", NPC " .. text(v(caseData, 20, 0)) .. "; NPC price " .. text(v(caseData, 21, 0)) .. "-" .. text(v(caseData, 22, 0)) .. " Cr")
    end
    if supplyCase or logisticsCase then
        add("STATION TRADER", compatible > 0 and "PASS" or "FAIL", traders .. " assigned; " .. compatible .. " compatible")
    end
    if supplyCase then
        local produces, paused = tonumber(v(caseData, 15, 0)) or 0, v(caseData, 29, false)
        add("LOCAL PRODUCTION", produces > 0 and (paused and "FAIL" or "PASS") or "NOT APPLICABLE", produces > 0 and (paused and "production is inactive; manual pause not confirmed" or text(v(caseData, 16, 0)) .. " module(s)") or "import case does not require local production")
        local missing = tonumber(v(caseData, 27, 0)) or 0
        add("PRODUCTION INPUTS", produces == 0 and "NOT APPLICABLE" or (missing == 0 and "PASS" or "FAIL"), produces == 0 and "no local production chain to inspect" or (missing > 0 and text(v(caseData, 28, "missing input unnamed")) or text(v(caseData, 26, "no missing input reported"))))
    end
    if #rows == 0 then add("CASE EVIDENCE", "UNKNOWN", "No family-specific prerequisite set is available; follow the case root cause and manual action.") end
    return rows
end
local function manualNextAction(caseData, rows)
    for _, check in ipairs(rows) do
        if check.state == "FAIL" or check.state == "UNKNOWN" or check.state == "NOT YET TESTED" then
            if check.state == "UNKNOWN" or check.state == "NOT YET TESTED" then
                return "Run a fresh Empire Analysis so EOC can collect the missing evidence. Do not change the station until EOC identifies a supported cause."
            elseif check.label == "INCIDENT EVIDENCE" then return text(v(caseData, 7, "Review the grouped retained evidence, then run a focused diagnostic before changing the station."))
            elseif check.label == "DELIVERY PATH" then return "Open the " .. text(v(caseData, 17, v(caseData, 4, "required ware"))) .. " buy offer first. Confirm its ware-specific trade rule permits the intended NPC supplier; then verify at least one assigned station trader can carry " .. text(v(caseData, 12, "the required cargo")) .. ". Change no station-wide rule unless you intend the wider effect."
            elseif check.label == "STORAGE INSTALLED" then return "Open the Station Build Plan and add compatible " .. text(v(caseData, 12, "cargo")) .. " storage; wait until it is operational."
            elseif check.label == "STORAGE FREE SPACE" then return "Open Logical Station Overview and move, sell, or reallocate stock until the required " .. text(v(caseData, 12, "cargo")) .. " storage space is free."
            elseif check.label == "STATION OPERATING FUNDS" then local required = math.max(0, ((tonumber(v(caseData, 30, 0)) or 0) * (tonumber(v(caseData, 21, 0)) or 0)) - (tonumber(v(caseData, 32, 0)) or 0)); return "Open the station Information account and transfer at least " .. formatNumber(required) .. " Cr for the immediate purchase. EOC will not move player credits."
            elseif check.label == "REACHABLE SUPPLY" then return "Open the station buy offer for " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " and verify trade rule, price, and manager range permit a supplier."
            elseif check.label == "STATION TRADER" then return "Assign one operational trader compatible with " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " to " .. text(v(caseData, 1, "the station")) .. "."
            elseif check.label == "LOCAL PRODUCTION" and v(caseData, 29, false) then return "1. Open the station's Logical Overview. 2. Find the production modules for " .. text(v(caseData, 4, "this ware")) .. ". 3. Check whether the modules are paused, missing workers, missing energy, or waiting for an input. 4. Fix the problem you find. 5. Let one normal production cycle finish."
            elseif check.label == "PRODUCTION INPUTS" then return "1. Open the station's Logical Overview. 2. Find " .. text(v(caseData, 28, "the missing production input")) .. ". 3. Restore its buy offer, delivery, or local production. 4. Wait until the input reaches the station. 5. Let one normal production cycle finish." end
        end
    end
    local caseType = string.upper(text(v(caseData, 3, "")))
    local subject = string.upper(text(v(caseData, 4, "")))
    if caseType == "STORAGE PRESSURE" then
        return "Do not add more of this ware. With Do Everything enabled, allow one station-manager trade cycle for EOC's bounded surplus sell offer. If stock does not fall, check for a permitted buyer, reduce the ware allocation, or increase local consumption; then run a fresh verification check."
    elseif subject == "ALLOGRAPHYNE" then
        return "The import path is ready, so allow one delivery cycle first. For a permanent local chain, add and operate the Allographyne Scrap Processor and its required recycling support, then verify that its inputs are supplied before changing ships or storage."
    end
    return "All reported prerequisites pass. With Do Everything enabled, allow one station-manager delivery cycle; EOC's buy offer and compatible assigned traders should handle the shortage. If stock remains unchanged, inspect the ware rule, price, manager range, and trader orders, then run a fresh verification check."
end
local function scoutRecoveryPlan(caseData, rows)
    local ware = text(v(caseData, 4, "the affected ware"))
    local wareUpper = string.upper(ware)
    local station = text(v(caseData, 1, "the station"))
    local caseType = string.upper(text(v(caseData, 3, "")))
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local plannedProduction = tonumber(v(caseData, 34, 0)) or 0
    local missingInputs = tonumber(v(caseData, 27, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    local paused = v(caseData, 29, false)
    local recommendation, checklist

    if caseType == "STORAGE PRESSURE" then
        recommendation = "Treat this as excess inventory, not a request for more supply. Let EOC's bounded sell action relieve the immediate pressure, then prevent recurrence by lowering unnecessary allocation or creating reliable consumption and export capacity. Add storage only when the ware has a real future demand that justifies it."
        checklist = {
            "Have EOC confirm the station's current overage evidence and managed export action.",
            "Let EOC relieve the overage first; allocation changes remain an optional vanilla-station fallback only if bounded export cannot resolve it.",
            "Keep a permitted sell offer and at least one compatible trader available.",
            "Have EOC report whether owned demand exists before treating an NPC sale as the only outlet.",
            "Verify that stock and storage pressure fall during the next trade cycle."
        }
    elseif wareUpper == "ALLOGRAPHYNE" then
        recommendation = "Treat Allographyne as project-driven strategic demand, not a normal station-health repair. EOC can maintain a bounded import offer, but it cannot make limited market supply permanent. Confirm the active project really needs it; then choose either a dedicated import route or the complete recycling production chain. If the project no longer needs it, remove or reduce the target instead of feeding a permanent false shortage."
        checklist = {
            "Confirm the active Terraforming or mission project is currently requesting Allographyne.",
            "If importing, permit the intended suppliers and reserve compatible traders for the route.",
            "If producing locally, complete the Allographyne recycling chain and supply every required input.",
            "Do not add generic storage or ships unless the evidence identifies them as the blocker.",
            "EOC will compare later project-delivery evidence automatically and report whether stock, deliveries, or project progress changed.",
            "If there is no active demand, lower the ware target so EOC stops treating zero stock as a fault."
        }
    elseif plannedProduction > 0 then
        recommendation = "The durable fix is already under construction. Your required task is to finish the planned " .. ware .. " production modules and any Planner-identified supporting modules. With Do Everything enabled, EOC owns temporary imports, input-recovery actions, and post-build verification."
        checklist = {
            "Finish the planned production modules in X4; EOC will detect when they become operational.",
            "Build any supporting production or storage modules named by Solution Planner; EOC will manage recoverable input supply and verify the resulting chain.",
            "EOC keeps its bounded temporary import active until local recovery is proven.",
            "EOC verifies whether " .. ware .. " stock and local production recover after construction.",
            "EOC retires its own unnecessary emergency offer when fresh evidence proves stable recovery."
        }
    elseif produces > 0 then
        if paused then
            recommendation = "Restore the existing local production line before buying more capacity. EOC sees installed production that is not operating, so the best long-term fix is to remove its actual input, workforce, damage, allocation, or pause constraint."
        elseif missingInputs > 0 then
            recommendation = "Repair the existing production chain. Adding another " .. ware .. " module would multiply the same input shortage; restore " .. text(v(caseData, 28, "the missing inputs")) .. " first."
        else
            recommendation = "Use the production capacity already installed at " .. station .. ". The evidence does not justify another module yet; first confirm that allocation, workforce, inputs, and module operation allow the existing line to meet demand."
        end
        checklist = {
            "Review EOC's limited module evidence: production is installed and whether a manual pause is reported.",
            "Let EOC manage every confirmed recoverable production-input shortage.",
            "EOC will report any remaining X4-only module, damage, workforce, or allocation boundary instead of asking for a generic player checkbox.",
            "EOC will evaluate the next complete production cycle when you run fresh verification.",
            "Reopen Solution Planner before adding capacity; build another module only when current evidence still proves a sustained deficit."
        }
    elseif suppliers > 0 and compatible > 0 then
        recommendation = "Use imports for immediate recovery, but treat repeated shortages as a capacity decision. If " .. ware .. " is a recurring strategic dependency, establish an owned source or dedicated route; otherwise keep the station-manager import path and correct any rule, range, price, or ship-order constraint that prevents delivery."
        checklist = {
            "Let EOC's bounded buy offer run through one manager delivery cycle.",
            "Confirm the ware buy rule, price, and manager range permit the visible suppliers.",
            "Confirm compatible assigned traders are free and actually accepting the ware order.",
            "Have EOC check current owned-supply evidence before recommending any dedicated route.",
            "Consider local production only after checking the full recipe, inputs, storage, and sustained demand.",
            "Verify that stock rises; if it does not, treat the delivery path as blocked and inspect the trader's live order."
        }
    elseif suppliers <= 0 then
        recommendation = "There is no proven market source for " .. ware .. ". Build or connect a reliable owned supply chain, or widen only the specific trade rule and operating range needed to reach a supplier."
        checklist = {
            "Confirm the ware is permitted by the station's buy rule and blacklist settings.",
            "Search for an owned station that can supply " .. ware .. ".",
            "If none exists, evaluate the complete production recipe and all upstream inputs before building.",
            "Provide matching storage and a compatible logistics route.",
            "Verify a real offer or local production cycle before adding further capacity."
        }
    else
        recommendation = "The shortage has supply but no proven delivery capacity. Restore one compatible station trader or dedicated logistics route before changing production or storage."
        checklist = {
            "Assign an operational ship with the correct cargo class.",
            "Confirm its assignment, trade rules, manager range, and current orders.",
            "Keep the bounded buy offer active for one delivery cycle.",
            "Verify that the ship accepts a route and stock rises.",
            "Escalate to owned production only if reliable delivery remains impossible."
        }
    end
    return recommendation, checklist
end
local function scoutChecklistText(items)
    local lines = {}
    for index, item in ipairs(items or {}) do lines[#lines + 1] = "[ ] " .. tostring(index) .. ". " .. item end
    return table.concat(lines, "\n")
end
local function rootCauseAssessment(caseData, rows)
    local facts, unknowns = {}, {}
    for _, check in ipairs(rows) do
        if check.state == "FAIL" then facts[#facts + 1] = check.label .. ": " .. check.evidence
        elseif check.state == "UNKNOWN" or check.state == "NOT YET TESTED" then unknowns[#unknowns + 1] = check.label .. ": " .. check.evidence end
    end
    local missing = tonumber(v(caseData, 27, 0)) or 0
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local inactive = v(caseData, 29, false)
    if missing > 0 then return "CONFIRMED", "Production is blocked by missing input: " .. text(v(caseData, 28, "unnamed input")) .. ".", "Restore the confirmed missing input; EOC will test the later station evidence automatically.", facts, unknowns end
    if #unknowns > 0 then return "CAUSE NOT YET KNOWN", "The current evidence is incomplete, so EOC cannot safely identify one cause yet.", "Run a fresh Empire Analysis. Do not change station funding, storage, trade, production, or ship assignments until the missing evidence is collected.", facts, unknowns end
    for _, check in ipairs(rows) do
        if check.state == "FAIL" and check.label ~= "LOCAL PRODUCTION" then return "CONFIRMED", check.label .. " failed: " .. check.evidence .. ".", manualNextAction(caseData, rows), facts, unknowns end
    end
    if produces > 0 and inactive then
        unknowns[#unknowns + 1] = "X4 reports inactive local production, but the current evidence does not prove the player manually paused it."
        return "MORE OBSERVATION REQUIRED", "Local production is inactive; manual pause is not confirmed. Inputs currently show no empty production input.", "Save this as a monitored case. EOC will compare later observations before recommending a change.", facts, unknowns
    end
    return "PROBABLE", text(v(caseData, 6, "No single blocker is confirmed.")), "Ask EOC once for verification. EOC will own the later comparison and return the answer before recommending a station change.", facts, unknowns
end

function menu.backgroundTestInstruction(backgroundTest, caseData, checks)
    local state = string.upper(text(backgroundTest and backgroundTest.status, "UNKNOWN"))
    local station = text(v(caseData, 1, "the selected station"))
    local subject = text(v(caseData, 4, "the selected subject"))
    local baseline = formatNumber(backgroundTest and backgroundTest.baseline or "unavailable")
    local samples = formatNumber(backgroundTest and backgroundTest.samples or 0)
    local result = text(backgroundTest and backgroundTest.result, "No result was returned.")
    local header = "WHAT EOC TESTED: " .. subject .. " at " .. station .. ".\nSTARTING VALUE: " .. baseline .. ". COMPLETED CHECKS: " .. samples .. "."
    if state == "REQUESTED" or state == "CHECKING" or state == "WAITING" then
        return header .. "\nWHAT THIS MEANS: The test is still running. EOC does not have an answer yet.\nWHAT TO DO NOW: 1. Keep playing normally. 2. Do not press the test button again. 3. Do not open Station Build mode. 4. Wait for TEST COMPLETE. EOC will update this page for you."
    elseif state == "RESOLVED" or state == "SUCCESS" then
        return header .. "\nRESULT: THE PROBLEM IS FIXED. " .. result .. "\nWHAT TO DO NOW: 1. Do not run this test again. 2. Return to Guided Recovery. 3. Close the case if EOC shows no other problem for it. Station Build mode is safe now."
    elseif state == "IMPROVING" or state == "PARTIAL" then
        return header .. "\nRESULT: THE STATION IS IMPROVING, BUT THE PROBLEM IS NOT FIXED YET. " .. result .. "\nWHAT TO DO NOW: 1. Leave the current fix and station orders alone. 2. Let one more normal operating cycle finish. 3. Return here and run this test one more time. 4. Follow the new result. Station Build mode is safe now."
    elseif state == "UNCHANGED" then
        return header .. "\nRESULT: NOTHING IMPROVED. " .. result .. "\nSTEPS TO FIX IT: " .. manualNextAction(caseData, checks) .. "\nWHEN THAT IS DONE: Return here and run this test one more time. Do not run it now. Station Build mode is safe now."
    elseif state == "WORSENING" or state == "FAILED" then
        return header .. "\nRESULT: THE PROBLEM GOT WORSE OR THE FIX FAILED. " .. result .. "\nSTEPS TO FIX IT: " .. manualNextAction(caseData, checks) .. "\nWHEN THAT IS DONE: Let one normal operating cycle finish, then run this test one time. Do not run it now. Station Build mode is safe unless the listed fix uses it."
    elseif state == "BLOCKED" or state == "ABORTED" or string.find(state, "INSUFFICIENT", 1, true) then
        return header .. "\nRESULT: EOC COULD NOT FINISH THE TEST. " .. result .. "\nWHAT TO DO NOW: 1. Open Next Action. 2. Run Fresh Empire Analysis once. 3. If this case disappears, stop; there is no proven problem to test. 4. If this case returns, complete the steps shown in Next Action. 5. Let one normal operating cycle finish. 6. Run this test one more time. Station Build mode is safe now."
    end
    return header .. "\nRESULT: EOC RECEIVED A RESULT IT CANNOT USE. " .. result .. "\nWHAT TO DO NOW: 1. Do not run the test again. 2. Open Next Action. 3. Run Fresh Empire Analysis once. 4. Follow the steps it gives you. 5. Run this test again only after the station condition changes. Station Build mode is safe now."
end

local function analysisComplete()
    menu.analysisRunning = false
    menu.analysisStatus = "ANALYSIS COMPLETE"
    menu.analysisStatusUntil = getElapsedTime() + 3

    menu.lastUpdated = formatGameTime(menu.pendingAnalysisTime)
    menu.analysisOutput = text(menu.pendingAnalysisOutput or "Analysis completed.")
    menu.pendingAnalysisOutput = nil
    menu.pendingAnalysisTime = nil


    local state = actionState("analysis.run")
    state.running = false
    state.result = menu.analysisOutput or "Analysis completed and EOC intelligence was refreshed."
    state.lastRun = menu.lastUpdated or formatGameTime(0)
    if menu.pendingChecklistRequest then
        local request = menu.pendingChecklistRequest
        menu.checklistProgress[request.progressKey] = "WAITING"
        raise("checklist.set", { key = request.key, station = request.station, subject = request.subject, casetype = request.casetype, plan = request.plan, step = request.step, state = "WAITING", text = request.text, schema = EOC_CHECKLIST_SCHEMA })
        menu.pendingChecklistRequest = nil
    end

    if menu.pendingVerificationKey then
        menu.verificationKey = menu.pendingVerificationKey
        menu.verificationClass = menu.pendingVerificationClass or "UNKNOWN"
        menu.verificationResult = menu.pendingVerificationResult or "UNKNOWN - the rescan completed without a comparison result."
        menu.pendingVerificationClass = nil
        menu.pendingVerificationResult = nil
        menu.pendingVerificationKey = nil
        if menu.forcedVerificationScrollLocked then menu.forcedVerificationRestoreReady = true end
    end

    if menu.frame then
        menu.refresh()
    end
end

local function reportTitleReceived(_, value)
    menu.pendingReportTitle = tostring(value or menu.pendingReport or "EOC REPORT")
end

local function reportTextReceived(_, value)
    menu.pendingReportText = tostring(value or "Report saved to Tips.")
end

local function reportTimeReceived(_, value)
    menu.pendingReportTime = value
end

local function reportSaved()
    menu.reportRunning = false
    menu.lastReport = text(menu.pendingReportTitle or menu.pendingReport or "EOC REPORT")
    menu.reportOutput = text(menu.pendingReportText or "Report saved to Tips.")
    local latest = menu.reports and menu.reports[1]
    local unchanged = latest and text(v(latest, 1, "")) == menu.lastReport and text(v(latest, 2, "")) == menu.reportOutput
    menu.reportStatus = unchanged and "REPORT UNCHANGED — LATEST COPY RETAINED. WHAT THIS MEANS: the new job returned the same report, so no duplicate was archived. DO THIS NEXT: read the selected report; no repeat is required until source evidence changes." or "REPORT SAVED TO TIPS. WHAT THIS MEANS: report generation completed and the newest retained output is selected below. DO THIS NEXT: read it now; this report-only job requires no repeat unless you intentionally want a later snapshot after evidence changes."
    menu.reportStatusUntil = getElapsedTime() + 4
    if not unchanged then
        table.insert(menu.reports, 1, {
            menu.lastReport,
            menu.reportOutput,
            formatGameTime(menu.pendingReportTime),
            tonumber(menu.pendingReportTime) or 0,
        })
    end
    while #menu.reports > 20 do
        table.remove(menu.reports)
    end
    menu.selectedReport = 1
    menu.page = "reports"
    menu.activeTab = "reports"
    menu.pendingReportTitle = nil
    menu.pendingReportText = nil
    menu.pendingReportTime = nil

    if menu.frame then
        menu.refresh()
    end
end

local function constructionRefreshBegin()
    menu.constructionRefresh = { record = {}, queue = {}, queueRow = {}, wares = {}, wareRow = {}, workforce = {}, workforceRow = {} }
end
local function constructionRefreshState()
    if not menu.constructionRefresh then constructionRefreshBegin() end
    return menu.constructionRefresh
end
local function constructionField(slot, value) constructionRefreshState().record[slot] = value end
local function constructionName(_, value) constructionField(1, tostring(value or "SELECTED STATION")) end
local function constructionIndex(_, value) constructionField(2, tonumber(value) or 0) end
local function constructionTotal(_, value) constructionField(3, tonumber(value) or 0) end
local function constructionPlanned(_, value) constructionField(4, tonumber(value) or 0) end
local function constructionBuilding(_, value) constructionField(5, tonumber(value) or 0) end
local function constructionBuilders(_, value) constructionField(6, tonumber(value) or 0) end
local function constructionStorageShips(_, value) constructionField(7, tonumber(value) or 0) end
local function constructionBudget(_, value) constructionField(9, tonumber(value) or 0) end
local function constructionWanted(_, value) constructionField(10, tonumber(value) or 0) end
local function constructionLastFunding(_, value) constructionField(12, tonumber(value) or 0) end
local function constructionLastFundingTime(_, value) constructionField(13, tonumber(value) or 0) end
local function constructionQueueName(_, value) constructionRefreshState().queueRow[1] = tostring(value or "Unknown module") end
local function constructionQueueType(_, value) constructionRefreshState().queueRow[2] = tostring(value or "MODULE") end
local function constructionQueueStatus(_, value) constructionRefreshState().queueRow[3] = tostring(value or "PLANNED") end
local function constructionQueueProgress(_, value) constructionRefreshState().queueRow[4] = tonumber(value) or 0 end
function menu.constructionQueueEffect(_, value) constructionRefreshState().queueRow[5] = tostring(value or "") end
function menu.constructionQueueStorageType(_, value) constructionRefreshState().queueRow[6] = tostring(value or "") end
function menu.constructionQueueCapacity(_, value) constructionRefreshState().queueRow[7] = tonumber(value) or 0 end
local function constructionQueueIndex(_, value) constructionRefreshState().queueRow[8] = tonumber(value) or 0 end
local function constructionQueueCommit()
    local refresh = constructionRefreshState(); table.insert(refresh.queue, refresh.queueRow); refresh.queueRow = {}
end
local function constructionWareName(_, value) constructionRefreshState().wareRow[1] = tostring(value or "Unknown ware") end
local function constructionWareCount(_, value) constructionRefreshState().wareRow[2] = tonumber(value) or 0 end
local function constructionWareCommit()
    local refresh = constructionRefreshState(); table.insert(refresh.wares, refresh.wareRow); refresh.wareRow = {}
end
function menu.constructionPeople(_, value) constructionField(14, tonumber(value) or 0) end
function menu.constructionWorkforceCapacity(_, value) constructionField(15, tonumber(value) or 0) end
function menu.constructionWorkforceOptimal(_, value) constructionField(16, tonumber(value) or 0) end
function menu.constructionHabitatName(_, value) constructionField(17, tostring(value or "NO COMPATIBLE HABITAT IDENTIFIED")) end
function menu.constructionHabitatCapacity(_, value) constructionField(18, tonumber(value) or 0) end
function menu.constructionHabitatProvisions(_, value) constructionField(19, tostring(value or "")) end
function menu.constructionHabitatStorage(_, value) constructionField(20, tostring(value or "")) end
function menu.constructionWorkforceSpecies(_, value) constructionRefreshState().workforceRow[1] = tostring(value or "Unknown species") end
function menu.constructionWorkforceProvision(_, value) constructionRefreshState().workforceRow[2] = tostring(value or "NO PROVISION WARE") end
function menu.constructionWorkforceCurrent(_, value) constructionRefreshState().workforceRow[3] = tonumber(value) or 0 end
function menu.constructionWorkforceTarget(_, value) constructionRefreshState().workforceRow[4] = tonumber(value) or 0 end
function menu.constructionWorkforceCommit()
    local refresh = constructionRefreshState(); table.insert(refresh.workforce, refresh.workforceRow); refresh.workforceRow = {}
end
local function constructionRefreshComplete()
    local refresh = constructionRefreshState()
    local snapshot = refresh.record
    snapshot[8] = refresh.queue
    snapshot[11] = refresh.wares
    local target = tonumber(v(snapshot, 2, 0)) or 0
    local targetName = text(v(snapshot, 1, ""))
    local retained, priorSnapshot = {}, nil
    for _, record in ipairs(menu.constructionRecords or {}) do
        local sameIndex = target > 0 and (tonumber(v(record, 2, 0)) or 0) == target
        local sameName = targetName ~= "" and text(v(record, 1, "")) == targetName
        if sameIndex or sameName then priorSnapshot = record else table.insert(retained, record) end
    end
    local function plannerFingerprint(record, workforceRows, incoming)
        if not record then return "" end
        local parts = {}
        for _, slot in ipairs({3,4,5,14,15,16,17,18,19,20}) do parts[#parts + 1] = tostring(v(record, slot, "")) end
        for _, item in ipairs(v(record, 8, {})) do for _, slot in ipairs({1,2,3,4,5,7}) do parts[#parts + 1] = tostring(v(item, slot, "")) end end
        local workforceParts = {}
        for _, row in ipairs(workforceRows or {}) do
            if incoming then
                workforceParts[#workforceParts + 1] = table.concat({text(v(row,1,"")), text(v(row,2,"")), tostring(v(row,3,0)), tostring(v(row,4,0))}, "|")
            elseif text(v(row,1,"")) == targetName then
                workforceParts[#workforceParts + 1] = table.concat({text(v(row,2,"")), text(v(row,8,"")), tostring(v(row,9,0)), tostring(v(row,10,0))}, "|")
            end
        end
        table.sort(workforceParts)
        for _, part in ipairs(workforceParts) do parts[#parts + 1] = part end
        return table.concat(parts, "~")
    end
    local plannerEvidenceChanged = plannerFingerprint(priorSnapshot, menu.workforceRecords, false) ~= plannerFingerprint(snapshot, refresh.workforce, true)
    table.insert(retained, 1, snapshot)
    menu.constructionRecords = retained
    menu.activeConstructionSnapshot = snapshot
    local retainedWorkforce = {}
    for _, record in ipairs(menu.workforceRecords or {}) do
        if text(v(record, 1, "")) ~= targetName then table.insert(retainedWorkforce, record) end
    end
    for _, row in ipairs(refresh.workforce or {}) do
        table.insert(retainedWorkforce, { targetName, text(v(row, 1, "Unknown species")), tonumber(v(snapshot, 14, 0)) or 0, tonumber(v(snapshot, 15, 0)) or 0, tonumber(v(snapshot, 16, 0)) or 0, "REFRESHED", 0, text(v(row, 2, "NO PROVISION WARE")), tonumber(v(row, 3, 0)) or 0, tonumber(v(row, 4, 0)) or 0, math.max((tonumber(v(row, 4, 0)) or 0) - (tonumber(v(row, 3, 0)) or 0), 0), "REFRESHED" })
    end
    menu.workforceRecords = retainedWorkforce
    menu.constructionRefresh = nil
    menu.constructionRefreshing = false
    menu.constructionStatus = "REFRESH COMPLETE: Latest station construction facts loaded. WHAT THIS MEANS: this was a read-only job and no construction setting changed. DO THIS NEXT: read every checklist row below. If all required rows are MET, no repeat is required; if a row is NOT FUNDED, STALLED, or BLOCKED, complete that row's exact action and refresh exactly once afterward."
    local manualSavedListRefresh = menu.plannerManualRefreshPending == targetName
    if manualSavedListRefresh then menu.plannerManualRefreshPending = nil end
    -- A construction snapshot may arrive after the player has followed a newer
    -- route. Retain the data, but never let that stale completion redraw or
    -- replace the page the player is now using.
    if menu.frame and menu.page == "construction" then
        menu.refresh()
    elseif menu.frame and menu.page == "solution" then
        local caseData = menu.solutionCase or menu.diagnosticCase
        local standalone = menu.solutionAgreedStandaloneKey and menu.agreedBuildPlans and menu.agreedBuildPlans[menu.solutionAgreedStandaloneKey] or nil
        local visibleStation = caseData and text(v(caseData, 1, "")) or (standalone and standalone.station or "")
        if visibleStation == targetName and (plannerEvidenceChanged or manualSavedListRefresh) then
            if caseData and menu.expansionReadiness and menu.expansionReadiness.station == targetName then menu.runExpansionReadiness(caseData, true) end
            for _, state in pairs(menu.plannerModuleDrafts or {}) do if not state.dirty then state.result = nil end end
            menu.plannerRefreshStatus = manualSavedListRefresh and "MANUAL PROGRESS REFRESH COMPLETE: The exact saved-list station was read. Added/planned and remaining counts now use the latest available evidence." or "LIVE SAVED-LIST REFRESH: Construction, workforce, habitat, and provision evidence updated."
            menu.refresh()
        elseif visibleStation == targetName then
            DebugError("[JKEOC][B354][PLANNER_REFRESH_UNCHANGED_NO_REDRAW] station=" .. tostring(targetName))
        else
            DebugError("[JKEOC][B351][PLANNER_REFRESH_RETAINED_NO_REDRAW] visible_station=" .. tostring(visibleStation) .. " refreshed_station=" .. tostring(targetName))
        end
    else
        DebugError("[JKEOC][B351][CONSTRUCTION_REFRESH_RETAINED_NO_REDRAW] current_page=" .. tostring(menu.page) .. " station=" .. tostring(targetName))
    end
end
local function constructionFundingResult(_, value)
    local result = text(value or "Construction action completed.")
    menu.constructionFundingPending = nil
    if string.sub(result, 1, 29) == "CONFIRM BUILDER REASSIGNMENT:" then menu.constructionBuilderPending = true else menu.constructionBuilderPending = nil end
    local upper = string.upper(result)
    local nextStep
    if string.find(upper, "CONFIRM BUILDER REASSIGNMENT", 1, true) then
        nextStep = "WHAT THIS MEANS: EOC found a builder but has not changed its assignment. DO THIS NEXT: verify the named ship and station, then select CONFIRM BUILDER REASSIGNMENT once or leave it unchanged."
    elseif string.find(upper, "BLOCKED", 1, true) or string.find(upper, "FAILED", 1, true) then
        nextStep = "WHAT THIS MEANS: the requested funding or builder action was not applied. DO THIS NEXT: correct the exact queue, ownership, funds, builder, or station condition named above, then submit the action exactly once; do not repeat unchanged."
    else
        nextStep = "WHAT THIS MEANS: X4 returned a terminal construction-action result. DO THIS NEXT: refresh Construction Status exactly once and verify the corresponding budget or builder checklist row. If it is MET, no repeat is required; otherwise follow that row's stated correction."
    end
    menu.constructionStatus = result .. " " .. nextStep
    if menu.frame then menu.refresh() end
end
function menu.backgroundTestResultBegin()
    menu.backgroundTestResultIncoming = {}
end
function menu.backgroundTestResultState()
    if not menu.backgroundTestResultIncoming then menu.backgroundTestResultBegin() end
    return menu.backgroundTestResultIncoming
end
function menu.backgroundTestResultStation(_, value) menu.backgroundTestResultState().station = text(value, "") end
function menu.backgroundTestResultSubject(_, value) menu.backgroundTestResultState().subject = text(value, "") end
function menu.backgroundTestResultStatus(_, value) menu.backgroundTestResultState().status = text(value, "UNKNOWN") end
function menu.backgroundTestResultText(_, value) menu.backgroundTestResultState().result = text(value, "No result is available.") end
function menu.backgroundTestResultRequested(_, value) menu.backgroundTestResultState().requested = tonumber(value) or 0 end
function menu.backgroundTestResultCompleted(_, value) menu.backgroundTestResultState().completed = tonumber(value) or 0 end
function menu.backgroundTestResultBaseline(_, value) menu.backgroundTestResultState().baseline = tonumber(value) or 0 end
function menu.backgroundTestResultSeverity(_, value) menu.backgroundTestResultState().severity = text(value, "UNKNOWN") end
function menu.backgroundTestResultSamples(_, value) menu.backgroundTestResultState().samples = tonumber(value) or 0 end
function menu.backgroundTestResultCommit()
    local result = menu.backgroundTestResultState()
    local station, subject = text(result.station, ""), text(result.subject, "")
    if station == "" or subject == "" then
        DebugError("[JKEOC][B340][BACKGROUND_RESULT_REJECTED] reason=MISSING_IDENTITY station=" .. tostring(station) .. " subject=" .. tostring(subject))
        menu.backgroundTestResultIncoming = nil
        return
    end
    menu.backgroundTests = menu.backgroundTests or {}
    menu.backgroundTests[station .. "|" .. subject] = result
    menu.backgroundTestResultIncoming = nil
    if menu.frame and menu.page == "diagnostics" then
        menu.refresh()
    else
        DebugError("[JKEOC][B340][BACKGROUND_RESULT_RETAINED_NO_REDRAW] current_page=" .. tostring(menu.page) .. " station=" .. tostring(station) .. " subject=" .. tostring(subject) .. " status=" .. tostring(result.status))
    end
end
function menu.kpiRefreshBegin()
    menu.kpiRefreshIncoming = { stations = {}, station = {}, shipyards = {}, shipyard = {} }
end
function menu.kpiRefreshState()
    if not menu.kpiRefreshIncoming then menu.kpiRefreshBegin() end
    return menu.kpiRefreshIncoming
end
function menu.kpiPlayerCredits(_, value) menu.kpiRefreshState().credits = tonumber(value) or 0 end
function menu.kpiGameTime(_, value) menu.kpiRefreshState().time = tonumber(value) or 0 end
function menu.kpiStationName(_, value) menu.kpiRefreshState().station.name = tostring(value or "Unknown station") end
function menu.kpiStationMoney(_, value) menu.kpiRefreshState().station.money = tonumber(value) or 0 end
function menu.kpiStationCommit()
    local state = menu.kpiRefreshState()
    table.insert(state.stations, state.station)
    state.station = {}
end
function menu.kpiShipyardName(_, value) menu.kpiRefreshState().shipyard.name = tostring(value or "Unknown shipyard") end
function menu.kpiShipyardQueued(_, value) menu.kpiRefreshState().shipyard.queued = tonumber(value) or 0 end
function menu.kpiShipyardActive(_, value) menu.kpiRefreshState().shipyard.active = tonumber(value) or 0 end
function menu.kpiShipyardModules(_, value) menu.kpiRefreshState().shipyard.modules = tonumber(value) or 0 end
function menu.kpiShipyardCommit()
    local state = menu.kpiRefreshState()
    local yard = state.shipyard
    yard.total = (tonumber(yard.active) or 0) + (tonumber(yard.queued) or 0)
    table.insert(state.shipyards, yard)
    state.shipyard = {}
end
function menu.kpiRefreshComplete()
    local state = menu.kpiRefreshState()
    menu.kpiHistory = menu.kpiHistory or {}
    local previous = menu.kpiHistory[#menu.kpiHistory]
    local sample = { time = tonumber(state.time) or 0, credits = tonumber(state.credits) or 0, stations = state.stations or {}, caseCritical = 0, caseWarning = 0, caseOther = 0, constructionActive = 0, constructionProgress = 0, constructionStations = {}, caseStations = {}, tradeStations = {}, storageStations = {}, workforceStations = {}, shipyards = {} }
    local caseMap = {}
    for _, case in ipairs(menu.cases or {}) do
        local severity = string.upper(text(v(case, 2, "")))
        local stationName = text(v(case, 1, "Unknown station"))
        local caseItem = caseMap[stationName] or { name = stationName, critical = 0, warning = 0, other = 0 }
        if severity == "CRITICAL" then sample.caseCritical = sample.caseCritical + 1 elseif severity == "WARNING" then sample.caseWarning = sample.caseWarning + 1 else sample.caseOther = sample.caseOther + 1 end
        if severity == "CRITICAL" then caseItem.critical = caseItem.critical + 1 elseif severity == "WARNING" then caseItem.warning = caseItem.warning + 1 else caseItem.other = caseItem.other + 1 end
        caseMap[stationName] = caseItem
    end
    for _, item in pairs(caseMap) do table.insert(sample.caseStations, item) end
    local progressTotal, progressCount = 0, 0
    for _, record in ipairs(menu.constructionRecords or {}) do
        if (tonumber(v(record, 3, 0)) or 0) > 0 then sample.constructionActive = sample.constructionActive + 1 end
        for _, item in ipairs(v(record, 8, {})) do
            if string.upper(text(v(item, 3, ""))) == "UNDER CONSTRUCTION" then progressTotal = progressTotal + (tonumber(v(item, 4, 0)) or 0); progressCount = progressCount + 1 end
        end
    end
    sample.constructionProgress = progressCount > 0 and (progressTotal / progressCount) or 0
    for _, record in ipairs(menu.constructionRecords or {}) do
        if (tonumber(v(record, 3, 0)) or 0) > 0 then
            local total, count = 0, 0
            for _, item in ipairs(v(record, 8, {})) do if string.upper(text(v(item, 3, ""))) == "UNDER CONSTRUCTION" then total = total + (tonumber(v(item, 4, 0)) or 0); count = count + 1 end end
            table.insert(sample.constructionStations, { name = text(v(record, 1, "Unknown station")), percent = count > 0 and total / count or 0 })
        end
    end
    local tradeMap = {}
    for _, offer in ipairs(menu.tradeOffers or {}) do local name=text(v(offer,1,"Unknown station")); tradeMap[name]=(tradeMap[name] or 0)+(tonumber(v(offer,4,0)) or 0) end
    for name, amount in pairs(tradeMap) do table.insert(sample.tradeStations,{name=name,amount=amount}) end
    for _, storage in ipairs(menu.storageRecords or {}) do local capacity=tonumber(v(storage,4,0)) or 0; table.insert(sample.storageStations,{name=text(v(storage,1,"Unknown station")),kind=text(v(storage,2,"STORAGE")),percent=capacity>0 and math.max(0,math.min(100,(tonumber(v(storage,3,0)) or 0)*100/capacity)) or 0}) end
    local workforceMap = {}
    for _, workforce in ipairs(menu.workforceRecords or {}) do
        local name=text(v(workforce,1,"Unknown station")); local item=workforceMap[name] or {name=name,current=0,optimal=0,provision=100}
        item.current=math.max(item.current,tonumber(v(workforce,3,0)) or 0); item.optimal=math.max(item.optimal,tonumber(v(workforce,5,0)) or 0)
        local target=tonumber(v(workforce,10,0)) or 0; if target>0 then item.provision=math.min(item.provision,math.max(0,math.min(100,(tonumber(v(workforce,9,0)) or 0)*100/target))) end; workforceMap[name]=item
    end
    for _, item in pairs(workforceMap) do item.percent=item.optimal>0 and item.current*100/item.optimal or 0; table.insert(sample.workforceStations,item) end
    if #(state.shipyards or {}) > 0 then sample.shipyards = state.shipyards else sample.shipyards = previous and previous.shipyards or {} end
    sample.creditChange = previous and (sample.credits - (tonumber(previous.credits) or sample.credits)) or 0
    table.insert(menu.kpiHistory, sample)
    while #menu.kpiHistory > menu.KPI_HISTORY_LIMIT do table.remove(menu.kpiHistory, 1) end
    menu.kpiRefreshIncoming = nil
    menu.kpiRefreshing = false
    menu.kpiLastRefreshAt = getElapsedTime()
    menu.kpiNextRefreshAt = menu.kpiLastRefreshAt + menu.kpiRefreshInterval(menu.kpiView)
    if menu.frame and menu.page == "kpi" and not menu.kpiControlDropdownActive then menu.refresh(true) end
end
function menu.PrepareMenuData()
    menu.initialized = true
end

local function init()
    Menus = Menus or {}

    for _, entry in ipairs(Menus) do
        if entry.name == menu.name then
            return
        end
    end

    table.insert(Menus, menu)

    if Helper and Helper.registerMenu then
        Helper.registerMenu(menu)
    else
    DebugError("[JKEOC][B224][LUA_ERROR] Helper.registerMenu unavailable")
    end

    AddUITriggeredEvent(menu.name, "INIT", nil)
    RegisterEvent(menu.name .. ".INIT", menu.PrepareMenuData)
    RegisterEvent(menu.name .. ".analysis.complete", analysisComplete)
    RegisterEvent(menu.name .. ".verification.class", verificationClassReceived)
    RegisterEvent(menu.name .. ".verification.result", verificationResultReceived)
    RegisterEvent(menu.name .. ".case.evidence.begin", menu.investigatedCaseBegin)
    for index = 1, 40 do RegisterEvent(menu.name .. ".case.evidence." .. tostring(index), menu.investigatedCaseField(index)) end
    RegisterEvent(menu.name .. ".case.evidence.found", menu.investigatedCaseFound)
    RegisterEvent(menu.name .. ".case.evidence.missing", menu.investigatedCaseMissing)
    RegisterEvent(menu.name .. ".analysis.output", analysisOutputReceived)
    RegisterEvent(menu.name .. ".analysis.time", analysisTimeReceived)
    RegisterEvent(menu.name .. ".report.saved", reportSaved)
    RegisterEvent(menu.name .. ".report.title", reportTitleReceived)
    RegisterEvent(menu.name .. ".report.text", reportTextReceived)
    RegisterEvent(menu.name .. ".report.time", reportTimeReceived)
    RegisterEvent(menu.name .. ".action.complete", actionComplete)
    RegisterEvent(menu.name .. ".action.name", actionName)
    RegisterEvent(menu.name .. ".action.result", actionResultReceived)
    RegisterEvent(menu.name .. ".action.time", actionTimeReceived)
    RegisterEvent(menu.name .. ".action.value", actionValueReceived)
    RegisterEvent(menu.name .. ".shipping.refresh.begin", shippingRefreshBegin)
    RegisterEvent(menu.name .. ".shipping.registered.name", shippingRegisteredName)
    RegisterEvent(menu.name .. ".shipping.registered.purpose", shippingRegisteredPurpose)
    RegisterEvent(menu.name .. ".shipping.registered.class", shippingRegisteredClass)
    RegisterEvent(menu.name .. ".shipping.registered.operational", shippingRegisteredOperational)
    RegisterEvent(menu.name .. ".shipping.registered.status", shippingRegisteredStatus)
    RegisterEvent(menu.name .. ".shipping.registered.assignment", shippingRegisteredAssignment)
    RegisterEvent(menu.name .. ".shipping.registered.commit", shippingRegisteredCommit)
    RegisterEvent(menu.name .. ".shipping.pending.ship", shippingPendingShip)
    RegisterEvent(menu.name .. ".shipping.pending.station", shippingPendingStation)
    RegisterEvent(menu.name .. ".shipping.pending.category", shippingPendingCategory)
    RegisterEvent(menu.name .. ".shipping.pending.status", shippingPendingStatus)
    RegisterEvent(menu.name .. ".shipping.pending.commit", shippingPendingCommit)
    RegisterEvent(menu.name .. ".shipping.mode", shippingModeReceived)
    RegisterEvent(menu.name .. ".shipping.refresh.complete", shippingRefreshComplete)
    RegisterEvent(menu.name .. ".settings.confirmed", settingsConfirmed)
    RegisterEvent(menu.name .. ".construction.refresh.begin", constructionRefreshBegin)
    RegisterEvent(menu.name .. ".construction.name", constructionName)
    RegisterEvent(menu.name .. ".construction.index", constructionIndex)
    RegisterEvent(menu.name .. ".construction.total", constructionTotal)
    RegisterEvent(menu.name .. ".construction.planned", constructionPlanned)
    RegisterEvent(menu.name .. ".construction.building", constructionBuilding)
    RegisterEvent(menu.name .. ".construction.builders", constructionBuilders)
    RegisterEvent(menu.name .. ".construction.storage", constructionStorageShips)
    RegisterEvent(menu.name .. ".construction.budget", constructionBudget)
    RegisterEvent(menu.name .. ".construction.wanted", constructionWanted)
    RegisterEvent(menu.name .. ".construction.lastfunding", constructionLastFunding)
    RegisterEvent(menu.name .. ".construction.lastfundingtime", constructionLastFundingTime)
    RegisterEvent(menu.name .. ".construction.queue.name", constructionQueueName)
    RegisterEvent(menu.name .. ".construction.queue.type", constructionQueueType)
    RegisterEvent(menu.name .. ".construction.queue.status", constructionQueueStatus)
    RegisterEvent(menu.name .. ".construction.queue.progress", constructionQueueProgress)
    RegisterEvent(menu.name .. ".construction.queue.effect", menu.constructionQueueEffect)
    RegisterEvent(menu.name .. ".construction.queue.storagetype", menu.constructionQueueStorageType)
    RegisterEvent(menu.name .. ".construction.queue.capacity", menu.constructionQueueCapacity)
    RegisterEvent(menu.name .. ".construction.queue.index", constructionQueueIndex)
    RegisterEvent(menu.name .. ".construction.queue.commit", constructionQueueCommit)
    RegisterEvent(menu.name .. ".construction.ware.name", constructionWareName)
    RegisterEvent(menu.name .. ".construction.ware.count", constructionWareCount)
    RegisterEvent(menu.name .. ".construction.ware.commit", constructionWareCommit)
    RegisterEvent(menu.name .. ".construction.people", menu.constructionPeople)
    RegisterEvent(menu.name .. ".construction.workforcecapacity", menu.constructionWorkforceCapacity)
    RegisterEvent(menu.name .. ".construction.workforceoptimal", menu.constructionWorkforceOptimal)
    RegisterEvent(menu.name .. ".construction.habitatname", menu.constructionHabitatName)
    RegisterEvent(menu.name .. ".construction.habitatcapacity", menu.constructionHabitatCapacity)
    RegisterEvent(menu.name .. ".construction.habitatprovisions", menu.constructionHabitatProvisions)
    RegisterEvent(menu.name .. ".construction.habitatstorage", menu.constructionHabitatStorage)
    RegisterEvent(menu.name .. ".construction.workforce.species", menu.constructionWorkforceSpecies)
    RegisterEvent(menu.name .. ".construction.workforce.provision", menu.constructionWorkforceProvision)
    RegisterEvent(menu.name .. ".construction.workforce.current", menu.constructionWorkforceCurrent)
    RegisterEvent(menu.name .. ".construction.workforce.target", menu.constructionWorkforceTarget)
    RegisterEvent(menu.name .. ".construction.workforce.commit", menu.constructionWorkforceCommit)
    RegisterEvent(menu.name .. ".construction.refresh.complete", constructionRefreshComplete)
    RegisterEvent(menu.name .. ".construction.funding.result", constructionFundingResult)
    RegisterEvent(menu.name .. ".background.result.begin", menu.backgroundTestResultBegin)
    RegisterEvent(menu.name .. ".background.result.station", menu.backgroundTestResultStation)
    RegisterEvent(menu.name .. ".background.result.subject", menu.backgroundTestResultSubject)
    RegisterEvent(menu.name .. ".background.result.status", menu.backgroundTestResultStatus)
    RegisterEvent(menu.name .. ".background.result.text", menu.backgroundTestResultText)
    RegisterEvent(menu.name .. ".background.result.requested", menu.backgroundTestResultRequested)
    RegisterEvent(menu.name .. ".background.result.completed", menu.backgroundTestResultCompleted)
    RegisterEvent(menu.name .. ".background.result.baseline", menu.backgroundTestResultBaseline)
    RegisterEvent(menu.name .. ".background.result.severity", menu.backgroundTestResultSeverity)
    RegisterEvent(menu.name .. ".background.result.samples", menu.backgroundTestResultSamples)
    RegisterEvent(menu.name .. ".background.result.commit", menu.backgroundTestResultCommit)
    RegisterEvent(menu.name .. ".kpi.refresh.begin", menu.kpiRefreshBegin)
    RegisterEvent(menu.name .. ".kpi.time", menu.kpiGameTime)
    RegisterEvent(menu.name .. ".kpi.playercredits", menu.kpiPlayerCredits)
    RegisterEvent(menu.name .. ".kpi.station.name", menu.kpiStationName)
    RegisterEvent(menu.name .. ".kpi.station.money", menu.kpiStationMoney)
    RegisterEvent(menu.name .. ".kpi.station.commit", menu.kpiStationCommit)
    RegisterEvent(menu.name .. ".kpi.shipyard.name", menu.kpiShipyardName)
    RegisterEvent(menu.name .. ".kpi.shipyard.queued", menu.kpiShipyardQueued)
    RegisterEvent(menu.name .. ".kpi.shipyard.active", menu.kpiShipyardActive)
    RegisterEvent(menu.name .. ".kpi.shipyard.modules", menu.kpiShipyardModules)
    RegisterEvent(menu.name .. ".kpi.shipyard.commit", menu.kpiShipyardCommit)
    RegisterEvent(menu.name .. ".kpi.refresh.complete", menu.kpiRefreshComplete)
    RegisterEvent(menu.name .. ".minimum.build.station", minimumBuildStation)
    RegisterEvent(menu.name .. ".minimum.build.role", minimumBuildRole)
    RegisterEvent(menu.name .. ".minimum.build.commit", minimumBuildCommit)
    RegisterEvent(menu.name .. ".minimum.build.blueprintname", menu.minimumBuildBlueprintName)
    RegisterEvent(menu.name .. ".minimum.build.macro", menu.minimumBuildMacro)
    RegisterEvent(menu.name .. ".minimum.build.yardname", menu.minimumBuildYardName)
    RegisterEvent(menu.name .. ".minimum.build.yardid", menu.minimumBuildYardId)
    RegisterEvent(menu.name .. ".minimum.build.execute", menu.minimumBuildExecute)
    RegisterEvent(menu.name .. ".rawsource.station", menu.rawSourceStation)
    RegisterEvent(menu.name .. ".rawsource.ware", menu.rawSourceWare)
    RegisterEvent(menu.name .. ".rawsource.status", menu.rawSourceStatus)
    RegisterEvent(menu.name .. ".rawsource.ship", menu.rawSourceShip)
    RegisterEvent(menu.name .. ".rawsource.detail", menu.rawSourceDetail)
    RegisterEvent(menu.name .. ".rawsource.commit", menu.rawSourceCommit)
    RegisterEvent(menu.name .. ".agreed.status", menu.agreedPlanStatus)
end

function menu.resetTabToRoot(page)
    menu.navigationOrigin = nil
    menu.navigationStack = {}
    menu.reportOrigin = nil
    menu.restoreTablePage = nil
    menu.restoreTableTopRow = nil
    menu.restoreTableSelectedRow = nil
    menu.restoreNavigatorPage = nil
    menu.restoreNavigatorTopRow = nil
    menu.restoreNavigatorSelectedRow = nil

    if page == "kpi" then
        menu.kpiView = "cash"
        menu.kpiResultPage = 1
    elseif page == "supply" then
        menu.supplyView = "home"
        menu.supplyPages = {}
        menu.supplyPreview = nil
        menu.supplyBatchPreview = nil
        menu.supplyStationDetailWare = nil
        menu.supplyProducerDetailWare = nil
        menu.supplyCapacityDetailWare = nil
        menu.supplyOverviewDetailWare = {}
    elseif page == "fleet" then
        menu.fleetScope = "global"
        menu.fleetView = "coverage"
        menu.fleetPage = 1
        menu.coverageFilter = "action"
        menu.coverageSelected = nil
    elseif page == "cases" then
        menu.caseScope = "global"
        menu.caseSeverity = "all"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.clearCasesConfirm = false
        menu.diagnosticCase = nil
    elseif page == "diagnostics" then
        menu.diagnosticView = "recovery"
        menu.diagnosticCase = nil
        menu.marketChoiceNote = nil
        menu.marketTestPreview = nil
        menu.marketRemovePreview = nil
    elseif page == "solution" then
        menu.solutionCase = nil
        menu.plannerChecklistPage = 1
    elseif page == "reports" then
        menu.selectedReport = 1
    end
end

function menu.resetAllTabsToRoot()
    for _, page in ipairs({ "kpi", "supply", "fleet", "cases", "diagnostics", "solution", "reports" }) do
        menu.resetTabToRoot(page)
    end
end

function menu.onShowMenu()
    menu.analysisRunning = false
    menu.mode = v(menu.param, 3, "ADVISOR")
    menu.offers = v(menu.param, 4, 0)
    menu.shipmode = v(menu.param, 5, "APPROVAL REQUIRED")
    menu.summary = v(menu.param, 6, {})
    menu.stations = v(menu.param, 7, {})
    menu.inbox = v(menu.param, 8, {})
    menu.previousShipmode = v(menu.param, 9, "APPROVAL REQUIRED")
    menu.reports = importReports(v(menu.param, 10, menu.reports or {}))
    menu.cases = v(menu.param, 11, {})
    menu.registeredShips = v(menu.param, 12, {})
    menu.tradeOffers = v(menu.param, 13, {})
    menu.pendingAssignments = v(menu.param, 14, {})
    menu.stabilizationGoal = v(menu.param, 15, "OBSERVE AND ADVISE ONLY")
    menu.stabilizationFindings = tonumber(v(menu.param, 16, 0)) or 0
    menu.mailboxStatus = v(menu.param, 17, { "READY", "No engineering probe has been submitted." })
    menu.proofStatus = v(menu.param, 18, "READY")
    menu.shipBlueprints = v(menu.param, 19, {})
    menu.shipWharfRoutes = v(menu.param, 20, {})
    menu.shipOrderRecords = v(menu.param, 21, {})
    menu.observations = v(menu.param, 22, {})
    menu.missionContext = v(menu.param, 23, {})
    menu.constructionRecords = v(menu.param, 24, {})
    menu.constructionAuthority = v(menu.param, 25, "APPROVAL REQUIRED")
    menu.workforceRecords = v(menu.param, 27, {})
    menu.storageRecords = v(menu.param, 28, {})
    menu.minimums = { mining = tonumber(v(menu.param, 29, 0)) or 0, trade = tonumber(v(menu.param, 30, 0)) or 0, buildstorage = tonumber(v(menu.param, 31, 0)) or 0, defence = tonumber(v(menu.param, 32, 0)) or 0, escort = tonumber(v(menu.param, 33, 0)) or 0 }
    menu.availableUnregisteredShips = v(menu.param, 34, {})
    menu.checklistProgress = {}
    for _, record in ipairs(v(menu.param, 35, {})) do
        local key = text(v(record, 1, ""))
        local step = tonumber(v(record, 2, 0)) or 0
        if key ~= "-" and step > 0 then
            menu.checklistProgress[key .. "|" .. tostring(step)] = text(v(record, 3, "PENDING"))
        end
    end
    menu.rawSourceRecords = {}
    for _, record in ipairs(v(menu.param, 36, {})) do
        local key = text(v(record, 1, "")) .. "|" .. menu.supplyWareId(v(record, 2, ""))
        menu.rawSourceRecords[key] = { status = text(v(record, 4, "SOURCE REQUIRED")), ship = text(v(record, 5, "")), detail = text(v(record, 6, "")) }
    end
    menu.logisticsCoverage = v(menu.param, 37, {})
    menu.minimumStaffing = v(menu.param, 38, {})
    menu.capacityByRole = {}
    menu.capacityRecords = {}
    for _, record in ipairs(v(menu.param, 40, {})) do
        local station, role = text(v(record, 1, "")), text(v(record, 2, ""))
        local capacityRecord = {
            station=station, role=role,
            assigned=tonumber(v(record, 3, 0)) or 0, floor=tonumber(v(record, 4, 0)) or 0,
            recommended=tonumber(v(record, 5, 0)) or 0, status=text(v(record, 6, "LEARNING")),
            openorders=tonumber(v(record, 7, 0)) or 0, active=tonumber(v(record, 8, 0)) or 0,
            deals=tonumber(v(record, 9, 0)) or 0, capacity=tonumber(v(record, 10, 0)) or 0,
            average=tonumber(v(record, 11, 0)) or 0, openvolume=tonumber(v(record, 12, 0)) or 0,
            trend=text(v(record, 13, "LEARNING")), reason=text(v(record, 14, "No explanation is available.")),
            samples=tonumber(v(record, 15, 0)) or 0, confidence=text(v(record, 16, "LOW")), source=text(v(record, 17, "UNKNOWN"))
        }
        menu.capacityByRole[station .. "|" .. role] = capacityRecord
        table.insert(menu.capacityRecords, capacityRecord)
    end
    menu.backgroundTests = {}
    for _, record in ipairs(v(menu.param, 41, {})) do
        local station, subject = text(v(record, 1, "")), text(v(record, 2, ""))
        menu.backgroundTests[station .. "|" .. subject] = {
            station=station, subject=subject, status=text(v(record, 3, "UNKNOWN")),
            result=text(v(record, 4, "No result is available.")), requested=tonumber(v(record, 5, 0)) or 0,
            completed=tonumber(v(record, 6, 0)) or 0, baseline=tonumber(v(record, 7, 0)) or 0,
            severity=text(v(record, 8, "UNKNOWN")), samples=tonumber(v(record, 9, 0)) or 0
        }
    end
    menu.agreedBuildPlans = {}
    for _, record in ipairs(v(menu.param, 42, {})) do
        local rows = {}
        for _, savedRow in ipairs(v(record, 7, {})) do
            rows[#rows + 1] = {
                kind=text(v(savedRow, 1, "MODULE")), wareId=menu.supplyWareId(v(savedRow, 2, "")),
                ware=text(v(savedRow, 3, "Unknown ware")), module=text(v(savedRow, 4, "")),
                agreed=tonumber(v(savedRow, 5, 0)) or 0, baselinePlanned=tonumber(v(savedRow, 6, 0)) or 0,
                baselineProduction=tonumber(v(savedRow, 7, 0)) or 0, outputPerHour=tonumber(v(savedRow, 8, 0)) or 0,
                requiredRate=tonumber(v(savedRow, 9, 0)) or 0, transport=text(v(savedRow, 10, "UNKNOWN")),
                baselineCapacity=tonumber(v(savedRow, 11, 0)) or 0, capacityPerModule=tonumber(v(savedRow, 12, 0)) or 0,
                provisions=text(v(savedRow, 13, "")), species=text(v(savedRow, 14, ""))
            }
        end
        local plan = {
            station=text(v(record, 1, "")), wareId=menu.supplyWareId(v(record, 2, "")), ware=text(v(record, 3, "")),
            status=text(v(record, 4, "SAVED")), saved=tonumber(v(record, 5, 0)) or 0,
            evidence=text(v(record, 6, "")), rows=rows, warnings=v(record, 8, {})
        }
        menu.agreedBuildPlans[menu.agreedPlanKey(plan.station, plan.wareId)] = plan
    end
    menu.staffingFilter = menu.staffingFilter or "attention"
    menu.minimumDraft = menu.minimumDraft or { mining = menu.minimums.mining, trade = menu.minimums.trade, buildstorage = menu.minimums.buildstorage, defence = menu.minimums.defence, escort = menu.minimums.escort }
    local rawStartupPreference = v(menu.param, 26, 1)
    local restoredStartupPreference = tonumber(rawStartupPreference) ~= 0
    DebugError("[JKEOC][B233][STARTUP_PREFERENCE_LUA] raw=" .. tostring(rawStartupPreference) .. " decoded=" .. (restoredStartupPreference and "ON" or "OFF"))
    if type(menu.savedStartupPreference) ~= "boolean" then
        menu.savedStartupPreference = restoredStartupPreference
        menu.pendingStartupPreference = restoredStartupPreference
    end
    menu.startupPreference = menu.savedStartupPreference
    menu.kpiView = menu.kpiView or "cash"
    if menu.kpiView == "profit" then menu.kpiView = "cash" end
    if menu.kpiView == "logistics" or menu.kpiView == "growth" then menu.kpiView = "attention" end
    if menu.kpiView == "shortages" then menu.kpiView = "cash" end
    menu.kpiHistory = menu.kpiHistory or {}
    menu.kpiNextRefreshAt = getElapsedTime()
    local persistedIdentity = commandIdentityStore()
    persistedIdentity.startupSequenceEnabled = menu.savedStartupPreference
    saveCommandIdentityStore(persistedIdentity)
    menu.shipOrderState = menu.shipOrderState or {}
    menu.pendingShipQueueRefresh = nil
    menu.probesRun = {}
    menu.lastProbeVerb = nil
    menu.pendingVerificationKey = nil
    menu.verificationKey = nil
    menu.verificationResult = nil
    menu.navigationStack = menu.navigationStack or {}
    menu.narrativeSessionStart = menu.narrativeSessionStart or 0
    menu.navigationOrigin = menu.navigationStack[#menu.navigationStack]
    menu.caseScope = menu.caseScope or "global"
    menu.caseSeverity = menu.caseSeverity or "all"
    menu.selectedCase = clamp(menu.selectedCase or 1, 1, math.max(1, #menu.cases))
    menu.casePage = math.max(1, tonumber(menu.casePage) or 1)
    menu.fleetScope = menu.fleetScope or "global"
    menu.fleetView = menu.fleetView or "coverage"
    menu.tradeActivityView = menu.tradeActivityView or "empire"
    menu.fleetPage = math.max(1, tonumber(menu.fleetPage) or 1)
    menu.diagnosticView = menu.diagnosticView or "recovery"
    if menu.diagnosticView == "engineering" then menu.diagnosticView = "recovery" end
    menu.selectedReport = clamp(menu.selectedReport or 1, 1, math.max(1, #menu.reports))
    local identity = commandIdentityStore()
    if not identity.initialized then
        menu.page = "identity"
        menu.activeTab = "identity"
    elseif not menu.sessionBootComplete and startupSequenceEnabled() then
        menu.page = "boot"
        menu.activeTab = "boot"
        menu.osBootStages = menu.osBootStages or buildOSBootStages()
        menu.osBootStage = menu.osBootStage or 1
        menu.osBootNextAt = menu.osBootNextAt or (getElapsedTime() + EOC_OS_BOOT_DELAY)
    elseif not menu.sessionBootComplete then
        menu.sessionBootComplete = true
    else
        menu.resetAllTabsToRoot()
        menu.page = "dashboard"
        menu.activeTab = "dashboard"
    end
    menu.analysisOutput = menu.analysisOutput or "Run Analyze Now to generate the current executive analysis."
    menu.reportOutput = menu.reportOutput or "Generate a report to preview its current output here."
    menu.selected = clamp(menu.selected or 1, 1, math.max(1, #menu.stations))
    menu.create()
    raise("opened", { mode = menu.mode })
end

local function acknowledgeClick(label)
    menu.lastClickedLabel = label
    menu.clickStatus = "INPUT RECEIVED: " .. label
    menu.clickStatusUntil = getElapsedTime() + 1.25
end

local function oneCycleFeedbackKey(label)
    local upper = string.upper(tostring(label or ""))
    if string.find(upper, "REFRESH THIS ANALYSIS", 1, true) or string.find(upper, "RUN THIS ANALYSIS", 1, true) then return "SUPPLY ANALYSIS" end
    if string.find(upper, "REFRESH CHECKLIST", 1, true) then return "CHECKLIST REFRESH" end
    if string.find(upper, "REFRESH CONSTRUCTION", 1, true) then return "CONSTRUCTION REFRESH" end
    if string.find(upper, "REFRESH STOCK & RATE", 1, true) then return "LOGISTICS EVIDENCE REFRESH" end
    if string.find(upper, "REFRESH VIEW", 1, true) then return "KPI VIEW REFRESH" end
    if string.find(upper, "GENERATE REPORT", 1, true) or string.find(upper, "GENERATE STATION REPORT", 1, true) then return "REPORT GENERATION" end
    if string.find(upper, "FRESH VERIFICATION", 1, true) or string.find(upper, "FRESH ANALYSIS", 1, true) or string.find(upper, "RUN EMPIRE ANALYSIS", 1, true) or upper == "RUN ANALYSIS" or string.find(upper, "ACTION: RUN EMPIRE ANALYSIS", 1, true) then return "ANALYSIS REFRESH" end
    return nil
end

addButton = function(row, column, label, handler, active, background, height, textColor, preserveBackground, cardText)
    local properties = { active = active ~= false, bgColor = background, height = height }
    menu.oneCycleFeedback = menu.oneCycleFeedback or {}
    local feedbackKey = oneCycleFeedbackKey(label)
    local feedbackActive = feedbackKey and (tonumber(menu.oneCycleFeedback[feedbackKey]) or 0) > 0
    if feedbackActive then
        properties.active = false
        properties.bgColor = inactiveModeBackground
    end
    if menu.reportRunning and (string.find(label, "GENERATE REPORT", 1, true) == 1 or string.find(label, "REPORT RUNNING", 1, true) == 1) then
        properties.active = false
    end
    if not preserveBackground and menu.lastClickedLabel == label and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
        properties.bgColor = selectedModeBackground
    end
    local textProperties = { color = textColor }
    if cardText then
        textProperties.halign = "left"
        textProperties.x = Helper.standardTextOffsetx
        -- X4 ignores an unsupported valign key for this button descriptor and
        -- vertically centers multiline text at y=0. Live Build 270/271 evidence
        -- established that positive y moves this exact text block upward.
        textProperties.y = Helper.standardTextHeight / 2
    end
    row[column]:createButton(properties):setText(menu.playerDisplayText(label), textProperties)
    if feedbackActive then menu.oneCycleFeedback[feedbackKey] = math.max(0, (tonumber(menu.oneCycleFeedback[feedbackKey]) or 0) - 1) end
    row[column].handlers.onClick = function()
        if feedbackActive then return end
        acknowledgeClick(label)
        if feedbackKey then menu.oneCycleFeedback[feedbackKey] = 1 end
        if string.find(label, "GENERATE REPORT", 1, true) == 1 then
            if menu.reportRunning then return end
            menu.reportRunning = true
            menu.reportStatus = "REPORT RUNNING - waiting for EOC result"
        end
        -- The handler owns any required rebuild. Refreshing here first destroys the
        -- live table position before same-page actions can preserve it.
        handler()
    end
end

function menu.addPrimaryButton(row, column, label, handler, active)
    addButton(row, column, label, handler, active, currentChoiceBackground)
end

function menu.supplyCardHeight()
    return math.ceil(3 * Helper.standardTextHeight + 2 * Helper.borderSize)
end

local function addModeButton(row, column, label, selected, enabled, handler, stateColor)
    local isEnabled = enabled ~= false
    local background = unavailableChoiceBackground

    if isEnabled then
        if selected then
            background = currentChoiceBackground
        else
            background = availableModeBackground
        end
    end

    row[column]:createButton({
        active = isEnabled,
        bgColor = background,
    }):setText(menu.playerDisplayText(label))
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
        -- Mode handlers explicitly rebuild after updating their state.
        handler()
    end
end

local function stationStatusColor(status)
    local value = string.upper(text(status))
    if value == "CRITICAL" or value == "DETERIORATING" or value == "RELAPSED" then
        return investigationFailColor
    elseif value == "WARNING" or value == "RECURRING" or value == "CHRONIC" or value == "TRANSIENT" then
        return investigationUnknownColor
    elseif value == "HEALTHY" or value == "MONITORING" or value == "STABLE" then
        return investigationPassColor
    end
    return investigationNeutralColor
end

local function addStationChoiceButton(row, column, label, current, confirming, handler)
    local background = availableModeBackground
    if current then
        background = currentChoiceBackground
    elseif confirming then
        background = pendingChoiceBackground
    end
    row[column]:createButton({ active = true, bgColor = background }):setText(menu.playerDisplayText(label))
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
        -- Apply the station choice before its handler performs the one required rebuild.
        handler()
    end
end

local function addTabButton(row, column, label, page)
    local properties = { active = true }

    if menu.page == page then
        properties.bgColor = activeTabBackground
    end

    row[column]:createButton(properties):setText(menu.playerDisplayText(label))
    row[column].handlers.onClick = function()
        menu.resetTabToRoot(page)
        DebugError("[JKEOC][B313][TAB_ROOT] page=" .. tostring(page) .. " explicit_tab_click=1")
        menu.page = page
        menu.activeTab = page
        menu.refresh()
    end
end

local function configureFourColumns(tableWidget, width)
    local columnWidth = math.floor((width - 4 * Helper.borderSize) / 4)
    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setDefaultCellProperties("text", { fontsize = Helper.standardFontSize })
end

local function section(tableWidget, label)
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(menu.playerDisplayText(label), {
        font = Helper.headerFont,
        fontsize = Helper.standardFontSize + 2,
    })
end

menu.playerPageGuides = {
    dashboard = { purpose = "This page shows the most important problems across your stations.", steps = "1. Read WHAT NEEDS ATTENTION. 2. Open the first critical or warning item. 3. Follow the Next Action shown for that item.", finish = "If no station needs attention, keep playing. You do not need to press anything." },
    stations = { purpose = "This page lets you choose one station, see its condition, and control only that station.", steps = "1. Choose a station on the left. 2. Read WHAT NEEDS ATTENTION. 3. Use the named button for the action you want. 4. Read the result before pressing another button.", finish = "Stop when the result says COMPLETE or when no action is required." },
    kpi = { purpose = "This page turns your empire data into simple totals and trends. It does not change your game.", steps = "1. Choose a report at the top. 2. Read the newest result below. 3. Open the named station or case only when the result tells you to act.", finish = "If the result shows no warning, there is nothing else to do." },
    supply = { purpose = "This page checks whether your stations make enough resources for your own empire.", steps = "1. Choose the view you want. 2. Press RUN THIS ANALYSIS. 3. Read the result. 4. Open a resource card for the exact shortage and next step.", finish = "Do not keep refreshing. Run it again only after production, demand, storage, or station selection changes." },
    fleet = { purpose = "This page shows which stations need ships and which registered ships EOC may use.", steps = "1. Read Coverage first. 2. Open Pending Assignments if a decision is waiting. 3. Approve only the exact ship and station you want. 4. Read the result.", finish = "If no need or pending assignment is shown, do nothing." },
    diagnostics = { purpose = "This page explains one station problem and tells you exactly what to check or fix.", steps = "1. Open Next Action. 2. Complete the listed steps. 3. Open Verify Result. 4. Ask EOC once and wait for TEST COMPLETE.", finish = "Never repeat a test until its result tells you what must change first." },
    solution = { purpose = "This page helps you plan a permanent production solution after simpler fixes have been checked.", steps = "1. Choose a supported case. 2. Complete each required check. 3. Review the proposed production chain. 4. Build only if you agree with the plan.", finish = "EOC does not place modules or spend credits from this page." },
    construction = { purpose = "This page shows active station construction, missing build resources, funding, and builder status.", steps = "1. Choose the station. 2. Read the first blocked or waiting item. 3. Use the exact funding, storage, or builder action shown. 4. Read the returned result.", finish = "If construction is moving and no blocker is shown, leave it alone." },
    cases = { purpose = "This page keeps a list of station problems that still need attention or proof of recovery.", steps = "1. Open a case. 2. Read why it is open. 3. Follow its Next Action. 4. Use Verify Result only after that action is complete.", finish = "Close a player-created case only when you are finished with it. EOC evidence may return if the problem still exists." },
    reports = { purpose = "This page stores completed EOC reports so you can read them again.", steps = "1. Choose a report. 2. Read the full result. 3. Use its named menu or action only if it tells you something needs attention.", finish = "Reports do not need to be generated again until you want newer information." },
    settings = { purpose = "This page controls what EOC is allowed to do automatically across your empire.", steps = "1. Read each authority before changing it. 2. Choose only the access you want EOC to have. 3. Save the settings. 4. Read the confirmation.", finish = "Leave a setting off when you do not want EOC to perform that action." },
}

function menu.addPlayerPageGuide(tableWidget, page)
    local guide = menu.playerPageGuides[page]
    if not guide then return end
    section(tableWidget, "START HERE")
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHAT THIS PAGE DOES: " .. guide.purpose, { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHAT TO DO: " .. guide.steps, { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHEN YOU ARE DONE: " .. guide.finish, { wordwrap = true })
end

local function checklistPlanId(caseData)
    local caseType = string.upper(text(v(caseData, 3, "")))
    local ware = string.upper(text(v(caseData, 4, "")))
    local plannedProduction = tonumber(v(caseData, 34, 0)) or 0
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local missingInputs = tonumber(v(caseData, 27, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    local paused = v(caseData, 29, false)
    if caseType == "STORAGE PRESSURE" then return "STORAGE_OVERAGE" end
    if ware == "ALLOGRAPHYNE" then return "ALLOGRAPHYNE_PROJECT" end
    if plannedProduction > 0 then return "PLANNED_PRODUCTION" end
    if produces > 0 then
        if paused then return "PAUSED_PRODUCTION" end
        if missingInputs > 0 then return "MISSING_INPUTS" end
        return "INSTALLED_PRODUCTION"
    end
    if suppliers > 0 and compatible > 0 then return "IMPORT_READY" end
    if suppliers <= 0 then return "SUPPLY_UNAVAILABLE" end
    return "LOGISTICS_MISSING"
end

local function checklistCaseKey(caseData)
    return table.concat({
        text(v(caseData, 1, "UNKNOWN STATION")),
        text(v(caseData, 3, "STATION ISSUE")),
        text(v(caseData, 4, "GENERAL OPERATIONS")),
        checklistPlanId(caseData),
        tostring(EOC_CHECKLIST_SCHEMA),
    }, "|")
end

local function expansionEvidenceKey(caseData)
    local action = managedActionForCase(caseData)
    return table.concat({
        checklistCaseKey(caseData),
        tostring(v(caseData, 13, 0)),
        tostring(v(caseData, 14, 0)),
        tostring(v(caseData, 15, 0)),
        text(v(caseData, 17, "")),
        tostring(v(caseData, 18, 0)),
        tostring(v(caseData, 19, 0)),
        tostring(v(caseData, 24, 0)),
        tostring(v(caseData, 27, 0)),
        text(v(caseData, 28, "")),
        tostring(v(caseData, 34, 0)),
        tostring(v(caseData, 39, false)),
        text(v(caseData, 40, "")),
        text(v(caseData, 41, "")),
        action and text(v(action, 6, "")) or "",
    }, "|")
end

function menu.focusCaseStation(caseData)
    local stationName = text(v(caseData, 1, ""))
    for index, station in ipairs(menu.stations or {}) do
        if text(v(station, 1, "")) == stationName then
            menu.selected = index
            return true
        end
    end
    return false
end

-- Build 286 preserves the same authoritative native path as X4's Station Build Plan.
-- GetBlueprints supplies only player-owned module macros. GetLibraryEntry then
-- supplies the selected macro's production cycles, resources and workforce.
-- No module name, blueprint state, recipe or rate is inferred from station text.
function menu.nativePlannerEvidence(caseData)
    local targetWare = menu.supplyWareId(v(caseData, 40, ""))
    if targetWare == "" then
        return { state = "CANNOT PROVE", reason = "The case did not retain the affected ware ID." }
    end

    local station64, stationProfileIndex
    local stationName = text(v(caseData, 1, ""))
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then
            station64 = menu.supplyStationId(profile)
            stationProfileIndex = tonumber(v(profile, 16, 0)) or 0
            break
        end
    end
    if not station64 then
        return { state = "CANNOT PROVE", ware = targetWare, reason = "The selected station could not be resolved to a live X4 component." }
    end

    local result = { state = "NOT OWNED", ware = targetWare, candidates = {}, recipesByWare = {}, station = station64, stationProfileIndex = stationProfileIndex }
    local ok, count = pcall(function() return C.GetNumBlueprints("", "", "") end)
    if not ok or (tonumber(count) or 0) <= 0 then
        result.reason = "X4 returned no player-owned blueprints."
        return result
    end
    local blueprints = ffi.new("UIBlueprint[?]", count)
    count = C.GetBlueprints(blueprints, count, "", "", "")
    for i = 0, count - 1 do
        local macro = blueprints[i].macro ~= nil and ffi.string(blueprints[i].macro) or ""
        local blueprintWare = blueprints[i].ware ~= nil and ffi.string(blueprints[i].ware) or ""
        local method = blueprints[i].productionmethodid ~= nil and ffi.string(blueprints[i].productionmethodid) or "default"
        local infolibrary = GetMacroData(macro, "infolibrary")
        if infolibrary == "moduletypes_production" or infolibrary == "moduletypes_processing" then
            local libraryOk, data = pcall(GetLibraryEntry, infolibrary, macro)
            if not libraryOk then data = nil end
            if type(data) == "table" and type(data.products) == "table" then
                local queueduration = 0
                for _, product in ipairs(data.products) do queueduration = queueduration + (tonumber(product.cycle) or 0) end
                for _, product in ipairs(data.products) do
                    local productWare = menu.supplyWareId(product.ware)
                    local outputPerHour = queueduration > 0 and ((tonumber(product.amount) or 0) * 3600 / queueduration) or 0
                    local resources = {}
                    for _, resource in ipairs(product.resources or {}) do
                        local resourceWare = menu.supplyWareId(resource.ware)
                        local amountPerHour = queueduration > 0 and ((tonumber(resource.amount) or 0) * 3600 / queueduration) or 0
                        local rname, transport = GetWareData(resourceWare, "name", "transport")
                        resources[#resources + 1] = { ware = resourceWare, name = tostring(rname or resourceWare), transport = string.upper(tostring(transport or "UNKNOWN")), amountPerHour = amountPerHour }
                    end
                    table.sort(resources, function(a, b) return a.name < b.name end)
                    local moduleName = GetMacroData(macro, "name")
                    local blueprintName = GetWareData(blueprintWare, "name")
                    local candidate = {
                        macro = macro,
                        name = tostring(moduleName or macro),
                        blueprintWare = blueprintWare,
                        blueprintName = tostring(blueprintName or blueprintWare),
                        method = method ~= "" and method or "default",
                        outputPerHour = outputPerHour,
                        resources = resources,
                        maxworkforce = tonumber(data.maxworkforce) or 0,
                    }
                    result.recipesByWare[productWare] = result.recipesByWare[productWare] or {}
                    result.recipesByWare[productWare][#result.recipesByWare[productWare] + 1] = candidate
                    if productWare == targetWare then result.candidates[#result.candidates + 1] = candidate end
                end
            end
        end
    end
    for _, recipes in pairs(result.recipesByWare) do
        table.sort(recipes, function(a, b)
            if a.outputPerHour == b.outputPerHour then return a.name < b.name end
            return a.outputPerHour > b.outputPerHour
        end)
    end
    table.sort(result.candidates, function(a, b)
        if a.outputPerHour == b.outputPerHour then return a.name < b.name end
        return a.outputPerHour > b.outputPerHour
    end)
    if #result.candidates == 0 then
        result.reason = "X4 returned no owned production-module blueprint whose native product is " .. targetWare .. "."
        return result
    end

    result.state = "OWNED"
    result.selected = result.candidates[1]
    result.consumptionPerHour = menu.supplySafeRate(station64, targetWare, false, true)
    result.productionPerHour = menu.supplySafeRate(station64, targetWare, true, true)
    result.deficitPerHour = math.max(0, result.consumptionPerHour - result.productionPerHour)
    result.moduleCount = result.selected.outputPerHour > 0 and math.ceil(result.deficitPerHour / result.selected.outputPerHour) or 0
    result.projectDemandUnmeasured = string.upper(text(v(caseData, 4, ""))) == "ALLOGRAPHYNE" and result.consumptionPerHour <= 0
    result.reason = "X4 returned an owned module blueprint and its native production library entry."
    result.checklist = menu.productionChainChecklist(result, caseData)
    DebugError("[JKEOC][B289][NATIVE_PLANNER] station=" .. stationName .. " ware=" .. targetWare .. " blueprint=OWNED macro=" .. result.selected.macro .. " method=" .. result.selected.method .. " output_h=" .. tostring(result.selected.outputPerHour) .. " consumption_h=" .. tostring(result.consumptionPerHour) .. " existing_output_h=" .. tostring(result.productionPerHour) .. " deficit_h=" .. tostring(result.deficitPerHour) .. " recommended_count=" .. tostring(result.moduleCount) .. " inputs=" .. tostring(#result.selected.resources))
    return result
end

function menu.plannerWorkforceFacts(stationName, profileIndex, queue)
    local facts = { people=0, capacity=0, optimal=0, habitatName="NO COMPATIBLE HABITAT IDENTIFIED", habitatCapacity=0, provisionPlan="", storageCheck="", plannedCapacity=0, plannedCount=0, species="", provisions="", provisionScope="" }
    local record
    for _, candidate in ipairs(menu.constructionRecords or {}) do
        if text(v(candidate, 1, "")) == stationName or (profileIndex > 0 and (tonumber(v(candidate, 2, 0)) or 0) == profileIndex) then record = candidate; break end
    end
    if record then
        facts.people = tonumber(v(record, 14, 0)) or 0
        facts.capacity = tonumber(v(record, 15, 0)) or 0
        facts.optimal = tonumber(v(record, 16, 0)) or 0
        facts.habitatName = text(v(record, 17, facts.habitatName))
        facts.habitatCapacity = tonumber(v(record, 18, 0)) or 0
        facts.provisionPlan = text(v(record, 19, ""))
        facts.storageCheck = text(v(record, 20, ""))
    end
    local speciesSeen, species, provisionsBySpecies = {}, {}, {}
    for _, workforce in ipairs(menu.workforceRecords or {}) do
        if text(v(workforce, 1, "")) == stationName then
            facts.people = math.max(facts.people, tonumber(v(workforce, 3, 0)) or 0)
            facts.capacity = math.max(facts.capacity, tonumber(v(workforce, 4, 0)) or 0)
            facts.optimal = math.max(facts.optimal, tonumber(v(workforce, 5, 0)) or 0)
            local race = text(v(workforce, 2, "Unknown species"))
            local provision = text(v(workforce, 8, "NO PROVISION WARE"))
            if not speciesSeen[race] then speciesSeen[race] = true; species[#species + 1] = race end
            provisionsBySpecies[race] = provisionsBySpecies[race] or { seen={}, rows={} }
            if provision ~= "NO PROVISION WARE" and not provisionsBySpecies[race].seen[provision] then
                provisionsBySpecies[race].seen[provision] = true
                provisionsBySpecies[race].rows[#provisionsBySpecies[race].rows + 1] = provision
            end
        end
    end
    table.sort(species)
    if #species == 1 then
        local currentSpeciesProvisions = provisionsBySpecies[species[1]] and provisionsBySpecies[species[1]].rows or {}
        table.sort(currentSpeciesProvisions)
        facts.species = species[1]
        facts.provisions = table.concat(currentSpeciesProvisions, ", ")
        facts.provisionScope = facts.provisions ~= "" and ("Current " .. species[1] .. " workforce supplies: " .. facts.provisions .. ".") or ("Current workforce population: " .. species[1] .. ". X4 returned no provision ware.")
    elseif #species > 1 then
        facts.species = tostring(#species) .. " CURRENT POPULATIONS"
        facts.provisions = ""
        facts.provisionScope = "This station has multiple workforce populations. EOC cannot prove which population the selected habitat will add, so no station-wide provision list is assigned to this habitat."
    else
        facts.provisionScope = "No current workforce population is available. Exact future provision wares remain unknown until workers arrive."
    end
    for _, item in ipairs(queue or {}) do
        local status = string.upper(text(v(item, 3, "PLANNED")))
        local moduleType = string.upper(text(v(item, 2, "")))
        local moduleEffect = string.upper(text(v(item, 5, "")))
        local moduleName = string.upper(text(v(item, 1, "")))
        if status ~= "COMPLETE" and status ~= "COMPLETED" and (string.find(moduleType, "HABIT", 1, true) or string.find(moduleEffect, "WORKFORCE", 1, true) or string.find(moduleName, "HABITAT", 1, true)) then
            facts.plannedCount = facts.plannedCount + 1
            facts.plannedCapacity = facts.plannedCapacity + math.max(tonumber(v(item, 7, 0)) or 0, 0)
        end
    end
    return facts
end

-- Build 293 derives a bounded, aggregate production-chain checklist from the
-- same explicit native blueprint/library scan. It never runs in background.
-- Shared upstream demand is combined before module counts are rounded, planned
-- output is subtracted once, and cycles/unsupported wares stop as boundaries.
function menu.productionChainChecklist(nativePlan, caseData)
    local stationName = text(v(caseData, 1, "Selected station"))
    local station64 = nativePlan.station
    local queue = {}
    local profileIndex = 0
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then profileIndex = tonumber(v(profile, 16, 0)) or 0; break end
    end
    local function matchingRecord(record)
        return text(v(record, 1, "")) == stationName or (profileIndex > 0 and (tonumber(v(record, 2, 0)) or 0) == profileIndex)
    end
    if menu.activeConstructionSnapshot and matchingRecord(menu.activeConstructionSnapshot) then queue = v(menu.activeConstructionSnapshot, 8, {}) end
    if #queue == 0 then
        for _, record in ipairs(menu.constructionRecords or {}) do if matchingRecord(record) then queue = v(record, 8, {}); break end end
    end
    local function plannedModules(recipe)
        if not recipe then return 0 end
        local wanted = string.lower(recipe.name or "")
        local count = 0
        for _, item in ipairs(queue or {}) do
            local status = string.upper(text(v(item, 3, "PLANNED")))
            if string.lower(text(v(item, 1, ""))) == wanted and status ~= "COMPLETE" and status ~= "COMPLETED" then count = count + 1 end
        end
        return count
    end
    local function wareFacts(ware)
        local name, transport = GetWareData(ware, "name", "transport")
        return tostring(name or ware), string.upper(tostring(transport or "UNKNOWN"))
    end
    local recipes = nativePlan.recipesByWare or {}
    local rootRecipe = nativePlan.selected
    local rootPlanned = math.max(tonumber(v(caseData, 34, 0)) or 0, plannedModules(rootRecipe))
    local rootNeeded = rootRecipe.outputPerHour > 0 and math.ceil(nativePlan.deficitPerHour / rootRecipe.outputPerHour) or 0
    local rootAdditional = math.max(rootNeeded - rootPlanned, 0)
    local rootInstalled = math.max(tonumber(v(caseData, 16, 0)) or 0, (tonumber(v(caseData, 15, 0)) or 0) > 0 and 1 or 0)
    local action = managedActionForCase(caseData)
    local actionStateText = action and string.upper(text(v(action, 6, ""))) or ""
    local recoveryExhausted = actionStateText == "RECOVERY EXHAUSTED - PLANNER AVAILABLE"
        or actionStateText == "INPUT DELIVERY TEST EXHAUSTED - LOCAL PRODUCTION CHECKS REMAIN"
    local recoveryWare = menu.supplyWareId(v(caseData, 41, ""))
    local recoveryResource
    if recoveryExhausted and recoveryWare ~= "" then
        for _, resource in ipairs(rootRecipe.resources or {}) do
            if menu.supplyWareId(resource.ware) == recoveryWare then recoveryResource = resource; break end
        end
    end
    -- A recovery-exhausted missing input is an absolute support requirement
    -- for the installed/planned final-output modules. It must not disappear
    -- merely because current final-output consumption produces a zero deficit.
    local recoveryMinimum = recoveryResource and ((recoveryResource.amountPerHour * rootInstalled) + (recoveryResource.amountPerHour * rootPlanned)) or 0
    -- Size the support chain to the proven requirement, never to an oversized
    -- queue. Surplus planned modules are flagged instead of creating a cascade.
    local rootFuture = recoveryResource and 0 or rootNeeded
    local moduleCounts, demandExtra, depth = {}, {}, {}
    local converged = false
    for _ = 1, 24 do
        local nextDemand, nextDepth, absoluteMinimum = {}, {}, {}
        local function addDemand(resource, amount, itemDepth)
            if resource.ware ~= "" and amount > 0 then
                nextDemand[resource.ware] = (nextDemand[resource.ware] or 0) + amount
                nextDepth[resource.ware] = math.min(nextDepth[resource.ware] or itemDepth, itemDepth)
            end
        end
        for _, resource in ipairs(rootRecipe.resources or {}) do addDemand(resource, resource.amountPerHour * rootFuture, 1) end
        if recoveryResource then
            nextDemand[recoveryResource.ware] = nextDemand[recoveryResource.ware] or 0
            nextDepth[recoveryResource.ware] = 1
            absoluteMinimum[recoveryResource.ware] = recoveryMinimum
        end
        for ware, counts in pairs(moduleCounts) do
            local recipe = recipes[ware] and recipes[ware][1]
            local future = counts.needed or 0
            if recipe and future > 0 then
                for _, resource in ipairs(recipe.resources or {}) do addDemand(resource, resource.amountPerHour * future, (depth[ware] or 1) + 1) end
            end
        end
        local changed = false
        local nextCounts = {}
        for ware, extra in pairs(nextDemand) do
            local recipe = recipes[ware] and recipes[ware][1]
            local consumption = menu.supplySafeRate(station64, ware, false, true)
            local production = menu.supplySafeRate(station64, ware, true, true)
            local totalDemand = math.max(consumption, absoluteMinimum[ware] or 0) + extra
            local planned = plannedModules(recipe)
            local uncoveredBeforePlan = math.max(totalDemand - production, 0)
            local needed = recipe and recipe.outputPerHour > 0 and math.ceil(uncoveredBeforePlan / recipe.outputPerHour) or 0
            local additional = math.max(needed - planned, 0)
            local gap = recipe and math.max(totalDemand - production - planned * recipe.outputPerHour, 0) or uncoveredBeforePlan
            nextCounts[ware] = { planned = planned, needed = needed, additional = additional, consumption = consumption, production = production, demand = totalDemand, gap = gap }
            local old = moduleCounts[ware]
            if not old or old.planned ~= planned or old.needed ~= needed or old.additional ~= additional or math.abs((demandExtra[ware] or 0) - extra) > 0.001 then changed = true end
        end
        moduleCounts, demandExtra, depth = nextCounts, nextDemand, nextDepth
        if not changed then converged = true; break end
    end

    local items, simplePlan = {}, {}
    local cascadePassed = not (recoveryExhausted and (tonumber(v(caseData, 27, 0)) or 0) > 0 and not recoveryResource)
    local cascadeReason = cascadePassed
        and "Every deeper tier has a supported native recipe or an explicit raw-resource boundary."
        or "The recovery-exhausted case did not transport a native missing-ware identity that matches the final-output recipe."
    local function addItem(state, label, evidence, itemDepth, sortName, action)
        items[#items + 1] = { state = state, label = label, evidence = evidence, depth = itemDepth or 0, sortName = sortName or label, action = action }
    end
    local rootState = nativePlan.projectDemandUnmeasured and "CANNOT PROVE" or (rootPlanned > rootNeeded and "SURPLUS PLAN" or (nativePlan.productionPerHour >= nativePlan.consumptionPerHour and "COMPLETE" or (rootPlanned >= rootNeeded and "PLANNED" or "REQUIRED")))
    local rootEvidence = nativePlan.projectDemandUnmeasured
        and "Project-driven demand exists, but X4 did not expose that demand as a measurable hourly station-consumption rate. EOC cannot convert the project target into a safe module count. Confirm the active project still requires this ware; do not treat the calculated zero as a capacity recommendation."
        or ("Need " .. tostring(rootNeeded) .. " module(s) for the measured " .. formatNumber(nativePlan.deficitPerHour) .. "/h deficit | installed output " .. formatNumber(nativePlan.productionPerHour) .. "/h | planned " .. tostring(rootPlanned) .. " | additional required " .. tostring(rootAdditional) .. (rootPlanned > rootNeeded and (" | remove or reconsider " .. tostring(rootPlanned - rootNeeded) .. " surplus planned module(s) before expanding support; downstream counts are sized to the proven need, not the oversized queue.") or "."))
    addItem(rootState, "FINAL OUTPUT - " .. text(v(caseData, 4, nativePlan.ware)), rootEvidence, 0, "")
    simplePlan[#simplePlan + 1] = {
        depth = 0,
        wareId = nativePlan.ware,
        ware = text(v(caseData, 4, nativePlan.ware)),
        module = rootRecipe.name,
        installed = rootInstalled,
        planned = rootPlanned,
        production = nativePlan.productionPerHour or 0,
        outputPerHour = rootRecipe.outputPerHour or 0,
        additional = rootAdditional,
        state = rootState,
        finalOutput = true,
    }
    for ware, counts in pairs(moduleCounts) do
        local recipe = recipes[ware] and recipes[ware][1]
        local name, transport = wareFacts(ware)
        local state, evidence
        if counts.demand <= counts.production + 0.001 then
            state = "COMPLETE"
            evidence = "Demand " .. formatNumber(counts.demand) .. "/h is covered by installed output " .. formatNumber(counts.production) .. "/h."
        elseif recipe and counts.planned > counts.needed then
            state = "SURPLUS PLAN"
            evidence = "Need " .. tostring(counts.needed) .. " " .. recipe.name .. " module(s), but " .. tostring(counts.planned) .. " are planned. Reconsider " .. tostring(counts.planned - counts.needed) .. " surplus module(s); deeper support is sized to the proven need."
        elseif recipe and counts.additional == 0 and counts.planned > 0 then
            state = "PLANNED"
            evidence = "Need " .. tostring(counts.needed) .. "; " .. tostring(counts.planned) .. " planned " .. recipe.name .. " module(s) cover the remaining rate; verify after construction."
        elseif recipe and counts.additional > 0 then
            state = "REQUIRED"
            evidence = "Demand " .. formatNumber(counts.demand) .. "/h | installed " .. formatNumber(counts.production) .. "/h | need " .. tostring(counts.needed) .. " total new module(s) | planned " .. tostring(counts.planned) .. " | add exactly " .. tostring(counts.additional) .. " " .. recipe.name .. " module(s) at " .. formatNumber(recipe.outputPerHour) .. "/h each."
        else
            state = "SOURCE REQUIRED"
            evidence = "Uncovered rate " .. formatNumber(counts.gap) .. "/h. X4 returned no owned production recipe in this explicit scan; prove an owned supplier, reachable market source, or raw-resource route."
        end
        local action
        if state == "SOURCE REQUIRED" and (transport == "SOLID" or transport == "LIQUID") then
            action = { ware = ware, name = name, transport = transport, rate = counts.gap }
            local record = menu.rawSourceRecords and menu.rawSourceRecords[stationName .. "|" .. menu.supplyWareId(ware)]
            if record then
                if record.status == "PINNED COVERAGE" or record.status == "PINNED - AWAITING DELIVERY" then
                    state = "PINNED COVERAGE"
                    evidence = (record.ship ~= "" and (record.ship .. " | ") or "") .. (record.detail ~= "" and record.detail or ("EOC has persistent exact-resource coverage for " .. name .. "."))
                elseif record.status == "MORE COVERAGE NEEDED" then
                    state = "MORE MINERS NEEDED"
                    evidence = record.detail ~= "" and record.detail or "EOC has pinned coverage, but repeated low-stock evidence supports another compatible registered miner."
                elseif record.status == "SHIP NEEDED" then
                    state = "MINER NEEDED"
                    evidence = record.detail ~= "" and record.detail or "No pinned compatible registered miner currently covers this resource."
                elseif record.status == "ASSIGNED - PIN NOT PROVEN" then
                    state = "PIN NOT PROVEN"
                    evidence = (record.ship ~= "" and (record.ship .. " | ") or "") .. (record.detail ~= "" and record.detail or "The station assignment exists, but exact resource pinning was not proven.")
                elseif record.status == "RESOURCE TEMPORARILY UNAVAILABLE" then
                    state = "RESOURCE UNAVAILABLE"
                    evidence = record.detail ~= "" and record.detail or "X4 returned no discoverable source at the bounded failure-triggered source check."
                elseif record.status == "ASSIGNED" or record.status == "EXISTING" then
                    state = "ASSIGNED"
                    evidence = (record.ship ~= "" and (record.ship .. " is assigned") or "A compatible miner is assigned") .. " to this station for " .. name .. ". EOC is awaiting live delivery/stock evidence; assignment alone is not proof of supply."
                elseif record.status == "PENDING APPROVAL" then
                    state = "APPROVAL REQUIRED"
                    evidence = record.ship .. " is cargo-compatible and reserved for explicit approval in Fleet & Logistics. No assignment has occurred."
                elseif record.status == "REQUESTED" or record.status == "REQUEST RECEIVED" or record.status == "ASSIGNING" or record.status == "ASSIGNING AND PINNING" then
                    state = "ASSIGNING"
                    evidence = record.detail ~= "" and record.detail or "EOC is resolving and verifying the exact registered-miner assignment."
                elseif record.status == "BLOCKED" then
                    evidence = record.detail ~= "" and record.detail or evidence
                end

            end
        end
        addItem(state, "INPUT - " .. name .. " [" .. transport .. "]", evidence, depth[ware] or 1, name, action)
        simplePlan[#simplePlan + 1] = {
            depth = depth[ware] or 1,
            wareId = ware,
            ware = name,
            module = recipe and recipe.name or "",
            planned = counts.planned or 0,
            production = counts.production or 0,
            outputPerHour = recipe and recipe.outputPerHour or 0,
            additional = recipe and counts.additional or nil,
            requiredRate = counts.gap or 0,
            state = state,
            transport = transport,
            recoveryPriority = menu.supplyWareId(ware) == recoveryWare,
        }
        if not recipe and transport ~= "SOLID" and transport ~= "LIQUID" then
            cascadePassed = false
            cascadeReason = "EOC reached " .. name .. " without an owned readable production recipe or a native raw-resource boundary."
        end
    end
    table.sort(items, function(a, b) if a.depth == b.depth then return a.sortName < b.sortName end return a.depth < b.depth end)
    table.sort(simplePlan, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        if a.recoveryPriority ~= b.recoveryPriority then return a.recoveryPriority == true end
        return (a.module ~= "" and a.module or a.ware) < (b.module ~= "" and b.module or b.ware)
    end)

    local storageSeen = {}
    local targetName, targetTransport = wareFacts(nativePlan.ware)
    storageSeen[targetTransport] = targetName
    for ware in pairs(moduleCounts) do local name, transport = wareFacts(ware); storageSeen[transport] = storageSeen[transport] or name end
    for transport, example in pairs(storageSeen) do
        local capacity, free = 0, 0
        for _, record in ipairs(menu.storageRecords or {}) do
            if text(v(record, 1, "")) == stationName and string.upper(text(v(record, 2, ""))) == transport then capacity = tonumber(v(record, 4, 0)) or 0; free = tonumber(v(record, 5, 0)) or 0; break end
        end
        local storageState = transport == "UNKNOWN" and "CANNOT PROVE" or ((capacity > 0 and free > 0) and "COMPLETE" or "REQUIRED")
        local storageEvidence
        if transport == "UNKNOWN" then
            storageEvidence = "X4 did not return a cargo class for " .. example .. "; verify it in the vanilla editor."
        elseif capacity > 0 and free > 0 then
            storageEvidence = formatNumber(capacity) .. " installed, " .. formatNumber(free) .. " currently free. X4's ware allocations remain authoritative; preserve room for " .. example .. " and every existing ware."
        elseif capacity > 0 then
            storageEvidence = formatNumber(capacity) .. " is installed but no free capacity is reported. Reallocate or add " .. transport .. " storage before relying on " .. example .. "."
        else
            storageEvidence = "No " .. transport .. " capacity is reported. Add compatible storage before relying on " .. example .. "."
        end
        addItem(storageState, "STORAGE CLASS PRESENT - " .. transport, storageEvidence, 90, transport)
    end

    local people, capacity, optimal = 0, 0, 0
    local provisions, seenProvision = {}, {}
    for _, record in ipairs(menu.workforceRecords or {}) do
        if text(v(record, 1, "")) == stationName then
            people = math.max(people, tonumber(v(record, 3, 0)) or 0)
            capacity = math.max(capacity, tonumber(v(record, 4, 0)) or 0)
            optimal = math.max(optimal, tonumber(v(record, 5, 0)) or 0)
            local provision = text(v(record, 8, "NO PROVISION WARE"))
            if provision ~= "NO PROVISION WARE" and not seenProvision[provision] then
                seenProvision[provision] = true
                provisions[#provisions + 1] = { name = provision, current = tonumber(v(record, 9, 0)) or 0, target = tonumber(v(record, 10, 0)) or 0 }
            end
        end
    end
    local incrementalWorkforce = rootFuture * (tonumber(rootRecipe.maxworkforce) or 0)
    for ware, counts in pairs(moduleCounts) do
        local recipe = recipes[ware] and recipes[ware][1]
        if recipe then incrementalWorkforce = incrementalWorkforce + (counts.needed or 0) * (tonumber(recipe.maxworkforce) or 0) end
    end
    local workforceFacts = menu.plannerWorkforceFacts(stationName, profileIndex, queue)
    people = math.max(people, workforceFacts.people)
    capacity = math.max(capacity, workforceFacts.capacity)
    optimal = math.max(optimal, workforceFacts.optimal)
    local plannedHabitation = workforceFacts.plannedCapacity
    local futureOptimal = optimal + incrementalWorkforce
    local workforceState = capacity >= futureOptimal and "COMPLETE" or ((capacity + plannedHabitation) >= futureOptimal and "PLANNED" or "REQUIRED")
    addItem(workforceState, "WORKFORCE CAPACITY", "Current " .. formatNumber(people) .. " people | habitat capacity " .. formatNumber(capacity) .. " | current optimal " .. formatNumber(optimal) .. " | added chain demand " .. formatNumber(incrementalWorkforce) .. " | future capacity target " .. formatNumber(futureOptimal) .. (plannedHabitation > 0 and (" | planned habitation capacity " .. formatNumber(plannedHabitation)) or "") .. ".", 91, "WORKFORCE")
    local habitatGap = math.max(futureOptimal - capacity - plannedHabitation, 0)
    local habitatCount = workforceFacts.habitatCapacity > 0 and math.ceil(habitatGap / workforceFacts.habitatCapacity) or nil
    if habitatGap > 0 and habitatCount == nil then
        cascadePassed = false
        cascadeReason = "The production cascade requires more workforce, but X4 did not return an owned compatible habitat blueprint."
        addItem("CANNOT PROVE", "HABITAT MODULE", "Need about " .. formatNumber(habitatGap) .. " more workforce capacity. Acquire a compatible habitation blueprint; EOC stopped instead of guessing a module type.", 91, "WORKFORCE HABITAT")
        simplePlan[#simplePlan + 1] = { depth=91, kind="HABITAT", wareId="__habitat__", ware="Workforce habitat", module=workforceFacts.habitatName, planned=workforceFacts.plannedCount, additional=nil, editable=false, requiredRate=habitatGap, capacityPerModule=0, baselineCapacity=capacity, species=workforceFacts.species, provisions=workforceFacts.provisions, provisionScope=workforceFacts.provisionScope }
    elseif (habitatCount or 0) > 0 then
        addItem("REQUIRED", "HABITAT MODULE - " .. workforceFacts.habitatName, "Add exactly " .. tostring(habitatCount) .. " module(s) at about " .. formatNumber(workforceFacts.habitatCapacity) .. " workforce capacity each after counting " .. tostring(workforceFacts.plannedCount) .. " queued habitat module(s). Workforce supplies are separate evidence, not module choices. " .. workforceFacts.provisionScope, 91, "WORKFORCE HABITAT")
        simplePlan[#simplePlan + 1] = { depth=91, kind="HABITAT", wareId="__habitat__", ware="Workforce habitat", module=workforceFacts.habitatName, planned=workforceFacts.plannedCount, additional=habitatCount, recommended=habitatCount, editable=true, requiredRate=habitatGap, capacityPerModule=workforceFacts.habitatCapacity, baselineCapacity=capacity, species=workforceFacts.species, provisions=workforceFacts.provisions, provisionScope=workforceFacts.provisionScope }
    else
        addItem("COMPLETE", "HABITAT CAPACITY", "No additional habitat is required by the current production-module estimate. No habitat input is shown in the simple calculator.", 91, "WORKFORCE HABITAT")
    end
    table.sort(provisions, function(a, b) return a.name < b.name end)
    for _, provision in ipairs(provisions) do
        local provisionResult = (provision.target <= 0 or provision.current >= provision.target) and "CURRENT TARGET MET" or "CURRENT TARGET SHORT"
        addItem("INFORMATION", "STATION WORKFORCE SUPPLY - NOT A MODULE COUNT - " .. provision.name, provisionResult .. ": " .. formatNumber(provision.current) .. " stored against the current X4 target of " .. formatNumber(provision.target) .. ". This is station-wide workforce evidence, not part of the production-module cascade. Future use from added workers remains unknown until they arrive; refresh after habitation fills.", 92, provision.name)
    end
    if not converged then
        cascadePassed = false
        cascadeReason = "The aggregate native recipe graph did not stabilize within 24 bounded passes."
        addItem("CANNOT PROVE", "CHAIN BOUNDARY", cascadeReason .. " EOC stopped instead of presenting a guessed module count.", 99, "ZZ")
    end
    DebugError("[JKEOC][B354][PRODUCTION_CHAIN_CHECKLIST] station=" .. stationName .. " ware=" .. nativePlan.ware .. " items=" .. tostring(#items) .. " simple_items=" .. tostring(#simplePlan) .. " root_needed=" .. tostring(rootNeeded) .. " root_planned=" .. tostring(rootPlanned) .. " root_additional=" .. tostring(rootAdditional) .. " recovery_ware=" .. tostring(recoveryWare) .. " recovery_minimum_h=" .. tostring(recoveryMinimum) .. " incremental_workforce=" .. tostring(incrementalWorkforce) .. " habitat_count=" .. tostring(habitatCount) .. " converged=" .. tostring(converged) .. " background_scan=0")
    return { items = items, simplePlan = simplePlan, converged = converged, cascadePassed = cascadePassed, cascadeReason = cascadeReason, rootNeeded = rootNeeded, rootPlanned = rootPlanned, rootAdditional = rootAdditional, incrementalWorkforce = incrementalWorkforce, recoveryWare = recoveryWare, recoveryMinimum = recoveryMinimum }
end

-- Build 354 also supports player-chosen final-output scenarios when X4 exposes
-- project demand without a measurable hourly rate. The player still controls
-- every Station Build Plan change.
function menu.evaluateModulePlan(nativePlan, caseData, draftCounts)
    local stationName = text(v(caseData, 1, "Selected station"))
    local station64 = nativePlan.station
    local recipes = nativePlan.recipesByWare or {}
    local rootRecipe = nativePlan.selected
    local rootWare = menu.supplyWareId(nativePlan.ware)
    local queue = {}
    local profileIndex = 0
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then profileIndex = tonumber(v(profile, 16, 0)) or 0; break end
    end
    local function matchingRecord(record)
        return text(v(record, 1, "")) == stationName or (profileIndex > 0 and (tonumber(v(record, 2, 0)) or 0) == profileIndex)
    end
    if menu.activeConstructionSnapshot and matchingRecord(menu.activeConstructionSnapshot) then queue = v(menu.activeConstructionSnapshot, 8, {}) end
    if #queue == 0 then
        for _, record in ipairs(menu.constructionRecords or {}) do if matchingRecord(record) then queue = v(record, 8, {}); break end end
    end
    local function plannedModules(recipe)
        if not recipe then return 0 end
        local wanted = string.lower(recipe.name or "")
        local count = 0
        for _, item in ipairs(queue or {}) do
            local status = string.upper(text(v(item, 3, "PLANNED")))
            if string.lower(text(v(item, 1, ""))) == wanted and status ~= "COMPLETE" and status ~= "COMPLETED" then count = count + 1 end
        end
        return count
    end
    local function intended(ware)
        local value = tonumber((draftCounts or {})[menu.supplyWareId(ware)]) or 0
        return math.max(0, math.min(999, math.floor(value + 0.5)))
    end
    local function wareFacts(ware)
        local name, transport = GetWareData(ware, "name", "transport")
        return tostring(name or ware), string.upper(tostring(transport or "UNKNOWN"))
    end
    local rootPlanned = math.max(tonumber(v(caseData, 34, 0)) or 0, plannedModules(rootRecipe))
    local rootInstalled = math.max(tonumber(v(caseData, 16, 0)) or 0, (tonumber(v(caseData, 15, 0)) or 0) > 0 and 1 or 0)
    local rootPlayer = intended(rootWare)
    local projectScenario = nativePlan.projectDemandUnmeasured == true
    local rootNeeded = rootRecipe.outputPerHour > 0 and math.ceil(nativePlan.deficitPerHour / rootRecipe.outputPerHour) or 0
    local rootRecommended = projectScenario and rootPlayer or math.max(rootNeeded - rootPlanned, 0)
    local baseDemand, baseDepth = {}, {}
    local rootFuture = rootPlanned + (projectScenario and rootPlayer or math.max(rootPlayer, rootRecommended))
    for _, resource in ipairs(rootRecipe.resources or {}) do
        local liveConsumption = menu.supplySafeRate(station64, resource.ware, false, true)
        baseDemand[resource.ware] = math.max(liveConsumption, resource.amountPerHour * rootInstalled) + resource.amountPerHour * rootFuture
        baseDepth[resource.ware] = 1
    end

    local moduleCounts, converged = {}, false
    for _ = 1, 24 do
        local nextDemand, nextDepth = {}, {}
        for ware, amount in pairs(baseDemand) do nextDemand[ware] = amount; nextDepth[ware] = baseDepth[ware] or 1 end
        for ware, counts in pairs(moduleCounts) do
            local recipe = recipes[ware] and recipes[ware][1]
            local futureModules = (counts.planned or 0) + math.max(counts.player or 0, counts.recommended or 0)
            if recipe and futureModules > 0 then
                for _, resource in ipairs(recipe.resources or {}) do
                    nextDemand[resource.ware] = (nextDemand[resource.ware] or 0) + resource.amountPerHour * futureModules
                    nextDepth[resource.ware] = math.min(nextDepth[resource.ware] or ((counts.depth or 1) + 1), (counts.depth or 1) + 1)
                end
            end
        end
        local changed, nextCounts = false, {}
        for ware, demand in pairs(nextDemand) do
            local recipe = recipes[ware] and recipes[ware][1]
            local consumption = menu.supplySafeRate(station64, ware, false, true)
            local production = menu.supplySafeRate(station64, ware, true, true)
            local totalDemand = (nextDepth[ware] or 1) == 1 and math.max(consumption, demand) or (consumption + demand)
            local planned = plannedModules(recipe)
            local uncovered = math.max(totalDemand - production, 0)
            local needed = recipe and recipe.outputPerHour > 0 and math.ceil(uncovered / recipe.outputPerHour) or 0
            local recommended = math.max(needed - planned, 0)
            local player = intended(ware)
            nextCounts[ware] = { recipe = recipe, demand = totalDemand, production = production, planned = planned, recommended = recommended, player = player, gap = recipe and math.max(totalDemand - production - (planned + player) * recipe.outputPerHour, 0) or uncovered, depth = nextDepth[ware] or 1 }
            local old = moduleCounts[ware]
            if not old or old.recommended ~= recommended or old.player ~= player or math.abs((old.demand or 0) - totalDemand) > 0.001 then changed = true end
        end
        moduleCounts = nextCounts
        if not changed then converged = true; break end
    end

    local rows, warnings, globalWarnings, moduleIssues = {}, {}, {}, 0
    rows[#rows + 1] = { depth = 0, wareId = rootWare, ware = text(v(caseData, 4, nativePlan.ware)), module = rootRecipe.name, installed = rootInstalled, planned = rootPlanned, recommended = rootRecommended, player = rootPlayer, editable = true, finalOutput = true, projectScenario = projectScenario, production = nativePlan.productionPerHour or 0, outputPerHour = rootRecipe.outputPerHour or 0 }
    if projectScenario and rootPlayer < 1 then
        local warning = "PLAYER SCENARIO: enter at least 1 " .. rootRecipe.name .. " module, press TAB, and check the plan so EOC can calculate the supporting chain."
        warnings[#warnings + 1] = warning
        globalWarnings[#globalWarnings + 1] = warning
        moduleIssues = moduleIssues + 1
    elseif not projectScenario then
        if rootPlayer > rootRecommended then warnings[#warnings + 1] = rootRecipe.name .. ": your plan adds " .. tostring(rootPlayer - rootRecommended) .. " more module(s) than current evidence supports."; moduleIssues = moduleIssues + 1 end
        if rootPlayer < rootRecommended then warnings[#warnings + 1] = rootRecipe.name .. ": your plan is short by about " .. tostring(rootRecommended - rootPlayer) .. " module(s)."; moduleIssues = moduleIssues + 1 end
    end
    local cascadePassed = converged
    local cascadeReason = converged and "The proposed module counts stabilized through the bounded native recipe cascade." or "The proposed dependency graph did not stabilize within 24 bounded passes."
    for ware, counts in pairs(moduleCounts) do
        local name, transport = wareFacts(ware)
        local recipe = counts.recipe
        rows[#rows + 1] = { depth = counts.depth, wareId = menu.supplyWareId(ware), ware = name, module = recipe and recipe.name or "", planned = counts.planned, recommended = recipe and counts.recommended or nil, player = recipe and counts.player or nil, requiredRate = counts.gap, editable = recipe ~= nil, transport = transport, production = counts.production or 0, outputPerHour = recipe and recipe.outputPerHour or 0 }
        if recipe then
            if counts.player > counts.recommended then warnings[#warnings + 1] = recipe.name .. ": your plan adds " .. tostring(counts.player - counts.recommended) .. " more module(s) than the current cascade requires."; moduleIssues = moduleIssues + 1 end
            if counts.player < counts.recommended then warnings[#warnings + 1] = recipe.name .. ": add about " .. tostring(counts.recommended - counts.player) .. " more module(s) for the current cascade."; moduleIssues = moduleIssues + 1 end
        elseif transport ~= "SOLID" and transport ~= "LIQUID" and counts.gap > 0 then
            cascadePassed = false
            cascadeReason = "No owned readable production recipe or raw-resource boundary was returned for " .. name .. "."
            local warning = name .. ": no defensible production-module count is available; provide about " .. formatNumber(counts.gap) .. "/h through the advanced source route."
            warnings[#warnings + 1] = warning
            globalWarnings[#globalWarnings + 1] = warning
        end
    end
    table.sort(rows, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        return (a.module ~= "" and a.module or a.ware) < (b.module ~= "" and b.module or b.ware)
    end)

    local addedWorkforce = rootPlayer * (tonumber(rootRecipe.maxworkforce) or 0)
    for _, counts in pairs(moduleCounts) do if counts.recipe then addedWorkforce = addedWorkforce + counts.player * (tonumber(counts.recipe.maxworkforce) or 0) end end
    local people, capacity, optimal = 0, 0, 0
    for _, record in ipairs(menu.workforceRecords or {}) do
        if text(v(record, 1, "")) == stationName then
            people = math.max(people, tonumber(v(record, 3, 0)) or 0)
            capacity = math.max(capacity, tonumber(v(record, 4, 0)) or 0)
            optimal = math.max(optimal, tonumber(v(record, 5, 0)) or 0)
        end
    end
    local futureWorkforce = optimal + addedWorkforce
    local workforceFacts = menu.plannerWorkforceFacts(stationName, profileIndex, queue)
    people = math.max(people, workforceFacts.people)
    capacity = math.max(capacity, workforceFacts.capacity)
    optimal = math.max(optimal, workforceFacts.optimal)
    futureWorkforce = optimal + addedWorkforce
    local habitatGap = math.max(futureWorkforce - capacity - workforceFacts.plannedCapacity, 0)
    local habitatRecommended = workforceFacts.habitatCapacity > 0 and math.ceil(habitatGap / workforceFacts.habitatCapacity) or nil
    local habitatPlayer = intended("__habitat__")
    if habitatGap > 0 then
        rows[#rows + 1] = { depth=91, kind="HABITAT", wareId="__habitat__", ware="Workforce habitat", module=workforceFacts.habitatName, planned=workforceFacts.plannedCount, recommended=habitatRecommended, player=habitatPlayer, editable=habitatRecommended ~= nil, requiredRate=habitatGap, capacityPerModule=workforceFacts.habitatCapacity, baselineCapacity=capacity, species=workforceFacts.species, provisions=workforceFacts.provisions, provisionScope=workforceFacts.provisionScope, provisionPlan=workforceFacts.provisionPlan, storageCheck=workforceFacts.storageCheck }
    end
    if habitatGap > 0 and habitatRecommended == nil then
        cascadePassed = false
        cascadeReason = "The plan requires more workforce, but no owned compatible habitat blueprint was returned."
        local warning = "HABITAT: need about " .. formatNumber(habitatGap) .. " more workforce capacity, but X4 did not return an owned compatible habitat blueprint. Acquire one; EOC will not guess the module type."
        warnings[#warnings + 1] = warning
        globalWarnings[#globalWarnings + 1] = warning
    elseif habitatGap > 0 and habitatPlayer ~= (habitatRecommended or 0) then
        local warning = workforceFacts.habitatName .. ": your plan must add about " .. tostring(habitatRecommended or 0) .. " habitat module(s) after counting " .. tostring(workforceFacts.plannedCount) .. " already queued; you entered " .. tostring(habitatPlayer) .. "."
        warnings[#warnings + 1] = warning
        moduleIssues = moduleIssues + 1
    end
    local workforceNote = habitatGap > 0 and habitatRecommended ~= nil and ("WORKFORCE PATH: " .. workforceFacts.habitatName .. " provides about " .. formatNumber(workforceFacts.habitatCapacity) .. " capacity each. WORKFORCE SUPPLIES - INFORMATION ONLY, NOT MODULE COUNTS: " .. workforceFacts.provisionScope .. " Future hourly use remains unknown until workers arrive; refresh after habitation fills.") or ""

    local transports = {}
    for ware in pairs(moduleCounts) do local _, transport = wareFacts(ware); transports[transport] = true end
    for transport in pairs(transports) do
        if transport ~= "SOLID" and transport ~= "LIQUID" and transport ~= "UNKNOWN" then
            local storageCapacity, storageFree = 0, 0
            for _, record in ipairs(menu.storageRecords or {}) do
                if text(v(record, 1, "")) == stationName and string.upper(text(v(record, 2, ""))) == transport then storageCapacity = tonumber(v(record, 4, 0)) or 0; storageFree = tonumber(v(record, 5, 0)) or 0; break end
            end
            if storageCapacity <= 0 or storageFree <= 0 then
                local warning = "STORAGE: the plan needs " .. transport .. " storage, but current evidence does not prove usable free capacity."
                warnings[#warnings + 1] = warning
                globalWarnings[#globalWarnings + 1] = warning
            end
        end
    end
    local summary = #warnings == 0 and (projectScenario and "PLAYER SCENARIO IS INTERNALLY BALANCED - PROJECT DEMAND REMAINS UNKNOWN - NOT CLEARED TO BUILD" or "PLAN LOOKS BALANCED FOR CURRENT EVIDENCE - NOT CLEARED TO BUILD") or ("CHECK THIS PLAN: " .. tostring(#warnings) .. " issue(s) need attention before building.")
    DebugError("[JKEOC][B354][PLAYER_MODULE_CALCULATOR] station=" .. stationName .. " ware=" .. nativePlan.ware .. " project_scenario=" .. tostring(projectScenario) .. " root_player=" .. tostring(rootPlayer) .. " rows=" .. tostring(#rows) .. " warnings=" .. tostring(#warnings) .. " cascade=" .. tostring(cascadePassed) .. " added_workforce=" .. tostring(addedWorkforce) .. " habitat_recommended=" .. tostring(habitatRecommended) .. " construction_authority=0")
    return { rows = rows, warnings = warnings, globalWarnings = globalWarnings, moduleIssues = moduleIssues, summary = summary, cascadePassed = cascadePassed, cascadeReason = cascadeReason, projectScenario = projectScenario, rootPlayer = rootPlayer, addedWorkforce = addedWorkforce, people = people, capacity = capacity, futureWorkforce = futureWorkforce, habitatRecommended = habitatRecommended, workforceNote = workforceNote }
end

function menu.makeAgreedBuildPlan(nativePlan, caseData, result, evidenceKey)
    if type(result) ~= "table" or type(result.rows) ~= "table" then return nil, nil end
    local stationName = text(v(caseData, 1, "Selected station"))
    local profileIndex = 0
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then profileIndex = tonumber(v(profile, 16, 0)) or 0; break end
    end
    local rows, payloadRows = {}, {}
    for _, row in ipairs(result.rows or {}) do
        local kind = row.kind or (row.editable == false and "SOURCE" or "MODULE")
        local saved = {
            kind=kind, wareId=menu.supplyWareId(row.wareId), ware=text(row.ware), module=text(row.module),
            agreed=(kind == "MODULE" or kind == "HABITAT") and (tonumber(row.player) or 0) or 0,
            baselinePlanned=tonumber(row.planned) or 0, baselineProduction=tonumber(row.production) or 0,
            outputPerHour=tonumber(row.outputPerHour) or 0, requiredRate=tonumber(row.requiredRate) or 0,
            transport=text(row.transport ~= nil and row.transport or "UNKNOWN"), baselineCapacity=tonumber(row.baselineCapacity) or 0,
            capacityPerModule=tonumber(row.capacityPerModule) or 0, provisions=text(row.provisions or ""), species=text(row.species or "")
        }
        rows[#rows + 1] = saved
        payloadRows[#payloadRows + 1] = { saved.kind, saved.wareId, saved.ware, saved.module, saved.agreed, saved.baselinePlanned, saved.baselineProduction, saved.outputPerHour, saved.requiredRate, saved.transport, saved.baselineCapacity, saved.capacityPerModule, saved.provisions, saved.species }
    end
    local conditions = {}
    for _, warning in ipairs(result.globalWarnings or {}) do conditions[#conditions + 1] = text(warning) end
    local status = result.projectScenario and (#conditions == 0 and "PLAYER SCENARIO COUNTS SAVED - PROJECT DEMAND REMAINS UNKNOWN" or ("PLAYER SCENARIO COUNTS SAVED - " .. tostring(#conditions) .. " SAFETY CONDITION(S) REMAIN")) or (#conditions == 0 and "AGREED COUNTS - CURRENT SAFETY CHECKS PASS" or ("AGREED COUNTS - " .. tostring(#conditions) .. " SAFETY CONDITION(S) REMAIN"))
    local wareId = menu.supplyWareId(nativePlan.ware)
    local plan = { station=stationName, wareId=wareId, ware=text(v(caseData, 4, nativePlan.ware)), status=status, saved=getElapsedTime(), evidence=text(evidenceKey), rows=rows, warnings=conditions }
    local payload = { station=stationName, profile=profileIndex, ware=wareId, name=plan.ware, status=status, evidence=text(evidenceKey), rows=payloadRows, warnings=conditions }
    return plan, payload
end

function menu.agreedPlanAssessment(plan, currentSimplePlan)
    local currentByWare = {}
    for _, row in ipairs(currentSimplePlan or {}) do currentByWare[menu.supplyWareId(row.wareId)] = row end
    local displayRows, stale = {}, false
    local projectScenario = string.find(string.upper(text(plan.status)), "PLAYER SCENARIO", 1, true) ~= nil
    local evidenceLoaded = #(currentSimplePlan or {}) > 0
    for _, saved in ipairs(plan.rows or {}) do
        local current = currentByWare[menu.supplyWareId(saved.wareId)]
        local row = { kind=saved.kind, wareId=saved.wareId, ware=saved.ware, module=saved.module, agreed=saved.agreed, requiredRate=saved.requiredRate, transport=saved.transport, progress=0, remaining=saved.agreed, progressKnown=evidenceLoaded, provisions=saved.provisions, species=saved.species }
        if saved.kind == "MODULE" then
            if current then
                local currentPlanned = tonumber(current.planned) or 0
                local baselinePlanned = tonumber(saved.baselinePlanned) or 0
                local newlyPlanned = math.max(currentPlanned - baselinePlanned, 0)
                local completed = 0
                if (tonumber(saved.outputPerHour) or 0) > 0 then
                    local grossCompleted = math.max(math.floor((((tonumber(current.production) or 0) - (tonumber(saved.baselineProduction) or 0)) / saved.outputPerHour) + 0.01), 0)
                    completed = math.max(grossCompleted - math.max(baselinePlanned - currentPlanned, 0), 0)
                end
                row.progress = math.min(row.agreed, newlyPlanned + completed)
                row.remaining = math.max(row.agreed - row.progress, 0)
            end
            -- An optional zero-count duplicate guard is intentionally broader than
            -- the short current estimate. Its absence still means zero modules are
            -- required. If the ware later appears with a nonzero requirement, the
            -- normal additional-versus-remaining comparison marks the plan stale.
            if not projectScenario and evidenceLoaded and current then
                if not current.liveProgressOnly and (current.additional == nil or (tonumber(current.additional) or 0) ~= row.remaining) then stale = true end
            elseif not projectScenario and evidenceLoaded and row.agreed > 0 then
                stale = true
            end
        elseif saved.kind == "HABITAT" then
            if current then
                local currentPlanned = tonumber(current.planned) or 0
                local baselinePlanned = tonumber(saved.baselinePlanned) or 0
                local newlyPlanned = math.max(currentPlanned - baselinePlanned, 0)
                local completed = 0
                if (tonumber(saved.capacityPerModule) or 0) > 0 then
                    local grossCompleted = math.max(math.floor((((tonumber(current.baselineCapacity) or 0) - (tonumber(saved.baselineCapacity) or 0)) / saved.capacityPerModule) + 0.01), 0)
                    completed = math.max(grossCompleted - math.max(baselinePlanned - currentPlanned, 0), 0)
                end
                row.progress = math.min(row.agreed, newlyPlanned + completed)
                row.remaining = math.max(row.agreed - row.progress, 0)
                if not projectScenario and not current.liveProgressOnly and (current.additional == nil or (tonumber(current.additional) or 0) ~= row.remaining) then stale = true end
            elseif not projectScenario and evidenceLoaded and row.agreed > 0 then
                stale = true
            end
        elseif evidenceLoaded then
            if not current and not projectScenario then stale = true elseif current then row.requiredRate = tonumber(current.requiredRate) or row.requiredRate end
        end
        displayRows[#displayRows + 1] = row
    end
    return displayRows, stale, evidenceLoaded
end

function menu.savedPlanLiveRows(plan)
    local profileIndex, station64 = 0, nil
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == plan.station then profileIndex = tonumber(v(profile, 16, 0)) or 0; station64 = menu.supplyStationId(profile); break end
    end
    local queue = {}
    for _, record in ipairs(menu.constructionRecords or {}) do
        if text(v(record, 1, "")) == plan.station or (profileIndex > 0 and (tonumber(v(record, 2, 0)) or 0) == profileIndex) then queue = v(record, 8, {}); break end
    end
    local workforceFacts = menu.plannerWorkforceFacts(plan.station, profileIndex, queue)
    local rows = {}
    for _, saved in ipairs(plan.rows or {}) do
        if saved.kind == "MODULE" then
            local planned = 0
            for _, item in ipairs(queue or {}) do
                local status = string.upper(text(v(item, 3, "PLANNED")))
                if string.lower(text(v(item, 1, ""))) == string.lower(saved.module or "") and status ~= "COMPLETE" and status ~= "COMPLETED" then planned = planned + 1 end
            end
            rows[#rows + 1] = { kind="MODULE", wareId=saved.wareId, ware=saved.ware, module=saved.module, planned=planned, production=station64 and menu.supplySafeRate(station64, saved.wareId, true, true) or saved.baselineProduction, additional=saved.agreed, liveProgressOnly=true }
        elseif saved.kind == "HABITAT" then
            rows[#rows + 1] = { kind="HABITAT", wareId="__habitat__", ware="Workforce habitat", module=saved.module, planned=workforceFacts.plannedCount, baselineCapacity=workforceFacts.capacity, additional=saved.agreed, liveProgressOnly=true, species=workforceFacts.species, provisions=workforceFacts.provisions }
        else
            rows[#rows + 1] = { kind="SOURCE", wareId=saved.wareId, ware=saved.ware, requiredRate=saved.requiredRate, liveProgressOnly=true }
        end
    end
    return rows
end

function menu.savedPlanRefreshTarget(plan)
    if not plan or text(plan.station) == "" then return nil end
    local stationName = text(plan.station)
    for _, record in ipairs(menu.constructionRecords or {}) do
        if text(v(record, 1, "")) == stationName then return { station=stationName, index=tonumber(v(record, 2, 0)) or 0 } end
    end
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then return { station=stationName, index=tonumber(v(profile, 16, 0)) or 0 } end
    end
    return nil
end

function menu.renderAgreedBuildList(tableWidget, plan, currentSimplePlan, commandKey, caseData, nativePlan)
    local rows, stale, evidenceLoaded = menu.agreedPlanAssessment(plan, currentSimplePlan)
    local projectScenario = string.find(string.upper(text(plan.status)), "PLAYER SCENARIO", 1, true) ~= nil
    section(tableWidget, projectScenario and "SAVED PLAYER SCENARIO BUILD LIST" or "SAVED AGREED BUILD LIST")
    local statusRow = tableWidget:addRow(false)
    local conditionCount = #(plan.warnings or {})
    local statusText = projectScenario and (conditionCount > 0 and ("PLAYER SCENARIO SAVED: Project demand remains unknown and " .. tostring(conditionCount) .. " safety condition(s) still block construction. The chosen final count is not an EOC demand recommendation.") or "PLAYER SCENARIO SAVED: The selected counts are internally balanced, but project demand remains unknown. The chosen final count is not an EOC demand recommendation.") or (not evidenceLoaded and "SAVED LIST RESTORED: Current Planner evidence is not loaded yet. The agreed counts remain available; return to the case and run the readiness check to refresh progress." or (stale and "PLAN NEEDS REVIEW: Current evidence no longer matches every saved count. The saved list was not overwritten." or (conditionCount > 0 and ("COUNTS SAVED: EOC and player agree on the production-module counts, but " .. tostring(conditionCount) .. " safety condition(s) still block construction.") or "CURRENT AGREEMENT: EOC and player module counts still match the latest evidence.")))
    statusRow[1]:setColSpan(4):createText(statusText, { wordwrap = true, color = not evidenceLoaded and investigationUnknownColor or ((stale or conditionCount > 0) and investigationFailColor or investigationPassColor), font = Helper.headerFont })
    local guideRow = tableWidget:addRow(false)
    guideRow[1]:setColSpan(4):createText("RETURN HERE AS YOU BUILD: EOC keeps this list in the save game. Use the normal X4 Station Build Plan; EOC never places modules. Only while this exact saved-list screen is visible, EOC refreshes the station about once per minute. Every other Solution Planner screen remains in DRAFT MODE with automatic refresh disabled.", { wordwrap = true, color = navigationStoryColor })
    local refreshRow = tableWidget:addRow(true)
    refreshRow[1]:setColSpan(4)
    menu.addPrimaryButton(refreshRow, 1, menu.constructionRefreshing and "REFRESHING SAVED-LIST PROGRESS..." or "REFRESH PROGRESS NOW", function()
        local target = menu.savedPlanRefreshTarget(plan)
        if not target or target.index <= 0 then
            menu.plannerRefreshStatus = "REFRESH BLOCKED: EOC could not resolve this saved list to the exact current station. No progress was changed."
            menu.refresh()
            return
        end
        menu.constructionRefreshing = true
        menu.plannerManualRefreshPending = target.station
        menu.plannerNextRefreshAt = getElapsedTime() + 60
        menu.plannerRefreshStatus = "REFRESHING SAVED-LIST PROGRESS: Reading the exact station plan, installed production, workforce, and habitat evidence."
        raise("construction.refresh", { index = target.index, station = target.station })
        menu.refresh()
    end, not menu.constructionRefreshing)
    if menu.plannerRefreshStatus then
        local refreshStatusRow = tableWidget:addRow(false)
        refreshStatusRow[1]:setColSpan(4):createText(menu.plannerRefreshStatus, { wordwrap = true, color = navigationStoryColor })
    end
    local pageSize = 6
    local pageCount = math.max(1, math.ceil(#rows / pageSize))
    menu.agreedBuildPage = math.max(1, math.min(tonumber(menu.agreedBuildPage) or 1, pageCount))
    local first = (menu.agreedBuildPage - 1) * pageSize + 1
    local last = math.min(#rows, first + pageSize - 1)
    for index = first, last do
        local row = rows[index]
        local display = ""
        if row.kind == "MODULE" then
            display = row.progressKnown and ((row.module ~= "" and row.module or row.ware) .. " | AGREED ADD " .. tostring(row.agreed) .. " | EOC SEES ADDED/PLANNED ABOUT " .. tostring(row.progress) .. " | STILL NEED ABOUT " .. tostring(row.remaining)) or ((row.module ~= "" and row.module or row.ware) .. " | AGREED ADD " .. tostring(row.agreed) .. " | CURRENT PROGRESS NOT REFRESHED")
            if row.agreed == 0 then display = (row.module ~= "" and row.module or row.ware) .. " | AGREED ADD 0 | DO NOT ADD DUPLICATE CAPACITY" end
        elseif row.kind == "HABITAT" then
            display = row.progressKnown and ((row.module ~= "" and row.module or "Compatible habitat") .. " | AGREED ADD " .. tostring(row.agreed) .. " | EOC SEES ADDED/PLANNED ABOUT " .. tostring(row.progress) .. " | STILL NEED ABOUT " .. tostring(row.remaining)) or ((row.module ~= "" and row.module or "Compatible habitat") .. " | AGREED ADD " .. tostring(row.agreed) .. " | CURRENT PROGRESS NOT REFRESHED")
        else
            display = row.ware .. " [" .. row.transport .. "] | NO PRODUCTION MODULE | PROVIDE ABOUT " .. formatNumber(row.requiredRate) .. "/h THROUGH THE RAW-SOURCE ROUTE"
        end
        local listRow = tableWidget:addRow(false)
        listRow[1]:setColSpan(4):createText(display, { wordwrap = true, color = ((row.kind == "MODULE" or row.kind == "HABITAT") and row.remaining == 0) and investigationPassColor or investigationUnknownColor, font = Helper.headerFont })
        if row.kind == "HABITAT" then
            local supplyRow = tableWidget:addRow(false)
            local supplyEvidence = (row.provisions or "") ~= "" and ("Current " .. ((row.species or "") ~= "" and row.species or "workforce") .. " supplies: " .. row.provisions .. ".") or "Exact provision wares for this habitat are not proven by the current station-wide evidence."
            supplyRow[1]:setColSpan(4):createText("WORKFORCE SUPPLIES - INFORMATION ONLY, NOT MODULE COUNTS: " .. supplyEvidence, { wordwrap = true, color = navigationStoryColor })
        end
    end
    if pageCount > 1 then
        local pager = tableWidget:addRow(true)
        pager[1]:setColSpan(2); addButton(pager, 1, "PREVIOUS SAVED-LIST PAGE", function() menu.agreedBuildPage = math.max(1, menu.agreedBuildPage - 1); menu.refresh() end, menu.agreedBuildPage > 1)
        pager[3]:setColSpan(2); addButton(pager, 3, "NEXT SAVED-LIST PAGE", function() menu.agreedBuildPage = math.min(pageCount, menu.agreedBuildPage + 1); menu.refresh() end, menu.agreedBuildPage < pageCount)
    end
    if conditionCount > 0 then
        local conditionRow = tableWidget:addRow(false)
        conditionRow[1]:setColSpan(4):createText("DO NOT BUILD YET: " .. text(plan.warnings[1]), { wordwrap = true, color = investigationFailColor })
        if conditionCount > 1 then
            local moreRow = tableWidget:addRow(false)
            moreRow[1]:setColSpan(4):createText(tostring(conditionCount - 1) .. " additional saved safety condition(s) remain. Return to the calculator or open Advanced Evidence and Math.", { wordwrap = true, color = investigationUnknownColor })
        end
    end
    local actionRow = tableWidget:addRow(true)
    local returnLabel = not caseData and "RETURN TO SAVED LISTS" or (stale and "RETURN TO CALCULATOR - REVIEW PLAN" or "RETURN TO MODULE CALCULATOR")
    actionRow[1]:setColSpan(2); menu.addPrimaryButton(actionRow, 1, returnLabel, function() menu.solutionAgreedKey = nil; menu.solutionAgreedStandaloneKey = nil; menu.plannerRefreshStatus = nil; menu.refresh() end, true)
    actionRow[3]:setColSpan(2)
    local confirmKey = menu.agreedPlanKey(plan.station, plan.wareId)
    addButton(actionRow, 3, menu.agreedClearConfirm == confirmKey and "CONFIRM CLEAR SAVED LIST" or "CLEAR SAVED LIST", function()
        if menu.agreedClearConfirm ~= confirmKey then menu.agreedClearConfirm = confirmKey; menu.refresh(); return end
        local profileIndex = 0
        for _, profile in ipairs(menu.stations or {}) do if text(v(profile, 1, "")) == plan.station then profileIndex = tonumber(v(profile, 16, 0)) or 0; break end end
        menu.pendingAgreedClearKey = confirmKey
        raise("planner.agreed.clear", { station=plan.station, profile=profileIndex, ware=plan.wareId })
    end, true)
end

function menu.runExpansionReadiness(caseData, preservePlannerPages)
    local rows = {}
    local function add(label, state, evidence) rows[#rows + 1] = { label = label, state = state, evidence = evidence } end
    local action = managedActionForCase(caseData)
    local actionStateText = action and string.upper(text(v(action, 6, ""))) or ""
    local stationName = text(v(caseData, 1, "Selected station"))
    local ware = text(v(caseData, 4, "affected ware"))
    local supplyWare = text(v(caseData, 17, ware))
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local planned = tonumber(v(caseData, 34, 0)) or 0
    local recoveryExhausted = actionStateText == "RECOVERY EXHAUSTED - PLANNER AVAILABLE"
        or actionStateText == "INPUT DELIVERY TEST EXHAUSTED - LOCAL PRODUCTION CHECKS REMAIN"
    local plannedProductionReview = planned > 0
    local capacity = tonumber(v(caseData, 13, 0)) or 0
    local free = tonumber(v(caseData, 14, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local ownedSuppliers = tonumber(v(caseData, 19, 0)) or 0
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    local missingInputs = tonumber(v(caseData, 27, 0)) or 0
    local missingNames = text(v(caseData, 28, "No input name returned"))
    local nativePlan = menu.nativePlannerEvidence(caseData)
    local blueprintState = nativePlan.state
    local blueprintModule = nativePlan.selected and nativePlan.selected.name or ""
    local trueHQ = v(caseData, 39, false) == true
    local role = ""
    for _, profile in ipairs(menu.stations or {}) do
        if text(v(profile, 1, "")) == stationName then role = string.upper(text(v(profile, 2, ""))); break end
    end
    local mixedStation = string.find(role, "MIXED", 1, true) ~= nil or string.find(role, "EVERYTHING", 1, true) ~= nil
    local complexStation = trueHQ or mixedStation

    if recoveryExhausted then
        add("IMMEDIATE RECOVERY TEST", "PASS", "The bounded BUY offer completed the full 30-minute test with reachable supply and compatible traders, but stock did not rise.")
    elseif plannedProductionReview then
        add("IMMEDIATE RECOVERY TEST", "WARNING", "Matching production is already committed in the X4 Station Build Plan. Planner access is limited to reviewing that existing plan and its supporting recipe; this does not prove the earlier recovery test passed or justify duplicate capacity.")
    else
        add("IMMEDIATE RECOVERY TEST", "NOT READY", "Immediate recovery has not reached the evidence-supported exhaustion state.")
    end
    add("EXISTING / PLANNED OUTPUT", (produces > 0 or planned > 0) and "WARNING" or "PASS", produces > 0 and (tostring(produces) .. " installed " .. ware .. " production module(s) already exist; restore and measure them before adding capacity.") or (planned > 0 and (tostring(planned) .. " matching module(s) are already planned; do not add a duplicate.") or "No installed or planned matching production module was reported."))
    add("CURRENT CARGO STORAGE", capacity > 0 and "PASS" or "NOT READY", capacity > 0 and (formatNumber(capacity) .. " compatible capacity is installed; " .. formatNumber(free) .. " is currently free. This proves current storage only, not the future recipe's required allocation.") or "No compatible storage capacity was reported for the affected ware.")
    add("CURRENT RECOVERY-WARE SUPPLY", suppliers > 0 and "PASS" or "WARNING", tostring(suppliers) .. " reachable offer(s), including " .. tostring(ownedSuppliers) .. " owned offer(s), for " .. supplyWare .. ". This is the ware EOC tested for immediate recovery; it is not proof of every future production input.")
    add("CURRENT DELIVERY CAPACITY", compatible > 0 and "PASS" or "NOT READY", tostring(compatible) .. " compatible station trader(s) were reported for the current shortage. EOC has not proven compatibility or live orders for every future recipe input.")
    if blueprintState == "OWNED" then
        local recipeNames = {}
        for _, resource in ipairs(nativePlan.selected.resources or {}) do recipeNames[#recipeNames + 1] = resource.name end
        add("COMPLETE PRODUCTION RECIPE", "PASS", #recipeNames > 0 and ("X4's native module library returned every primary input: " .. table.concat(recipeNames, ", ") .. ".") or "X4's native module library returned a production recipe with no primary inputs.")
    else
        add("COMPLETE PRODUCTION RECIPE", "CANNOT PROVE", nativePlan.reason or "No owned compatible module recipe was returned.")
    end
    if blueprintState == "OWNED" then
        add("PRODUCTION MODULE / BLUEPRINT", "PASS", "X4's native blueprint list returned " .. blueprintModule .. " (" .. nativePlan.selected.blueprintName .. "), production method " .. nativePlan.selected.method .. ".")
    elseif blueprintState == "NOT OWNED" then
        add("PRODUCTION MODULE / BLUEPRINT", "NOT READY", "X4 returned " .. (blueprintModule ~= "" and blueprintModule or "a compatible production module") .. ", but its blueprint is not owned. Acquire the blueprint before planning this module.")
    else
        add("PRODUCTION MODULE / BLUEPRINT", "CANNOT PROVE", nativePlan.reason or "X4 did not return an owned compatible production-module blueprint.")
    end
    add("PRODUCTION METHOD / COMPLETE RECIPE", blueprintState == "OWNED" and "PASS" or "CANNOT PROVE", blueprintState == "OWNED" and ("Native blueprint method " .. nativePlan.selected.method .. "; output " .. formatNumber(nativePlan.selected.outputPerHour) .. " " .. ware .. "/h; workforce " .. formatNumber(nativePlan.selected.maxworkforce) .. ".") or "X4 did not return an owned module/method/recipe chain for this ware.")
    add("CONSTRUCTION COMMITMENT", "CANNOT PROVE", "Plot space, module compatibility, builder, build-storage wares, construction budget, and final cost remain authoritative in the vanilla Station Build Plan.")
    local complexEvidence
    if trueHQ then
        complexEvidence = "X4 identifies this exact station object as the player headquarters. Review the existing plan for duplicate capacity, competing inputs, and shared-storage pressure before adding anything."
    elseif mixedStation then
        complexEvidence = "The EOC station profile identifies this as mixed-purpose or build-everything. Its display name is not being used as headquarters evidence. Review the existing plan before adding anything."
    else
        complexEvidence = "X4 does not identify this exact station as player headquarters, and its EOC profile is not mixed/build-everything. Normal plan review is still required."
    end
    add("COMPLEX-STATION RISK", complexStation and "WARNING" or "PASS", complexEvidence)

    local notReady, unknown, warnings = 0, 0, 0
    for _, item in ipairs(rows) do
        if item.state == "NOT READY" then notReady = notReady + 1 elseif item.state == "CANNOT PROVE" then unknown = unknown + 1 elseif item.state == "WARNING" then warnings = warnings + 1 end
    end
    local summary = notReady > 0 and "NOT READY - CORRECT THE FAILED CONDITION BEFORE PLANNING" or ((unknown > 0 or warnings > 0) and "READY FOR CAUTIOUS PLANNING - NOT CLEARED TO BUILD" or "READY FOR PLANNING")
    if not preservePlannerPages then
        menu.plannerChecklistPage = 1
        menu.plannerSimplePage = 1
    end
    menu.expansionReadiness = { key = checklistCaseKey(caseData), evidenceKey = expansionEvidenceKey(caseData), station = stationName, ware = ware, rows = rows, summary = summary, notReady = notReady, unknown = unknown, warnings = warnings, checkedAt = getElapsedTime(), nativePlan = nativePlan }
    DebugError("[JKEOC][B289][EXPANSION_READINESS] station=" .. stationName .. " ware=" .. ware .. " blueprint=" .. blueprintState .. " module=" .. blueprintModule .. " true_hq=" .. tostring(trueHQ) .. " summary=" .. summary .. " not_ready=" .. tostring(notReady) .. " cannot_prove=" .. tostring(unknown) .. " warnings=" .. tostring(warnings) .. " construction_authority=0")
    return menu.expansionReadiness
end

local function eocChecklistState(caseData, plan, step)
    local action = managedActionForCase(caseData)
    local actionType = action and string.upper(text(v(action, 2, ""))) or ""
    local actionStateText = action and string.upper(text(v(action, 6, ""))) or ""
    local movementVerified = action and v(action, 13, false) == true
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local ownedSuppliers = tonumber(v(caseData, 19, 0)) or 0
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local plannedProduction = tonumber(v(caseData, 34, 0)) or 0
    local missingInputs = tonumber(v(caseData, 27, 0)) or 0
    local paused = v(caseData, 29, false) == true
    local capacity = tonumber(v(caseData, 13, 0)) or 0

    local function tradeCycle(expectedType, verifyMovement)
        if not action or actionType ~= expectedType then return "EOC WAITING", "EOC has not yet established the required bounded " .. expectedType .. " action.", true end
        if actionStateText == "RECOVERY EXHAUSTED - PLANNER AVAILABLE"
            or actionStateText == "INPUT DELIVERY TEST EXHAUSTED - LOCAL PRODUCTION CHECKS REMAIN" then
            if verifyMovement then return "EOC CHECKED", "Stock did not rise during the full delivery-test window; EOC has proven this recovery path failed and opened expansion readiness review.", true end
            return "EOC VERIFIED", "The bounded offer remained active for the full 30-minute delivery-test window and reached the recovery-exhaustion gate.", true
        end
        if verifyMovement then
            if movementVerified then return "EOC VERIFIED", "Live stock moved from the action baseline after EOC created the bounded offer.", true end
            return "EOC WAITING", "The offer is active, but EOC has not yet observed the required stock movement.", true
        end
        if string.find(actionStateText, "VERIFIED", 1, true) or actionStateText == "ACTION IN PROGRESS" then
            return "EOC VERIFIED", "The bounded offer remained active across a later reconciliation cycle.", true
        end
        if actionStateText == "ACTION STARTED" then return "EOC STARTED", "EOC created the bounded offer and is waiting for the next reconciliation cycle.", true end
        return "EOC WAITING", text(v(action, 7, "EOC is waiting for the managed action boundary.")), true
    end

    if plan == "IMPORT_READY" then
        if step == 1 then return tradeCycle("BUY", false) end
        if step == 2 then
            if suppliers > 0 then return "EOC VERIFIED", "EOC observes " .. tostring(suppliers) .. " reachable offer(s). X4 does not expose enough evidence here to certify every ware rule, price, blacklist, or manager-range setting.", true end
            return "EOC BLOCKED", "No reachable supplier is present in current evidence.", true
        end
        if step == 3 then
            if compatible > 0 then return "EOC VERIFIED", "EOC observes " .. tostring(compatible) .. " cargo-compatible assigned trader(s). Their live order acceptance remains an X4/player inspection boundary.", true end
            return "EOC BLOCKED", "No compatible assigned station trader is present in current evidence.", true
        end
        if step == 4 then
            return "EOC CHECKED", ownedSuppliers > 0 and ("EOC observes " .. tostring(ownedSuppliers) .. " owned supplier offer(s). A dedicated route is not required for immediate verification; recommend one only if later evidence proves recurring delivery failure.") or "EOC observes no owned supplier offer. Continue testing the current import path before making a long-term production decision.", true
        end
        if step == 6 then return tradeCycle("BUY", true) end
    elseif plan == "STORAGE_OVERAGE" then
        if step == 1 then return "EOC VERIFIED", "EOC checked current station evidence for the overstocked ware and its managed action.", true end
        if step == 2 then return "EOC CHECKED", "EOC is using its bounded SELL action first. Storage-allocation mutation is outside EOC authority and is not a required player checkbox.", true end
        if step == 3 then return tradeCycle("SELL", false) end
        if step == 4 then return "EOC CHECKED", ownedSuppliers > 0 and ("EOC observes " .. tostring(ownedSuppliers) .. " owned supplier/consumer-network offer(s) in current evidence.") or "EOC does not currently observe an owned outlet; its bounded NPC export remains the supported recovery action.", true end
        if step == 5 then return tradeCycle("SELL", true) end
    elseif plan == "ALLOGRAPHYNE_PROJECT" then
        if step == 1 and string.upper(text(v(menu.missionContext, 2, ""))) == "ALLOGRAPHYNE" then return "EOC VERIFIED", "EOC's mission context identifies active Allographyne demand.", true end
        if step == 2 then
            if suppliers > 0 and compatible > 0 then return "EOC VERIFIED", "EOC observes reachable supply and compatible assigned traders for the import path.", true end
            return "EOC BLOCKED", "Current evidence does not show both reachable supply and compatible assigned delivery capacity.", true
        end
        if step == 5 and action and actionType == "BUY" then return tradeCycle("BUY", true) end
    elseif plan == "PLANNED_PRODUCTION" then
        if step == 1 then
            if produces > 0 and plannedProduction <= 0 then return "EOC VERIFIED", "EOC now observes installed production capacity.", true end
            return "EOC WAITING", "EOC still observes " .. tostring(plannedProduction) .. " planned matching production module(s). Finish construction in X4, then run fresh verification.", true
        end
        if step == 2 then
            if missingInputs <= 0 and capacity > 0 then return "EOC CHECKED", "Current evidence reports compatible storage and no empty production input. EOC will re-evaluate the completed chain after construction.", true end
            return "EOC WAITING", "EOC still observes an input or compatible-storage condition. Use the retained Solution Planner recipe for any required modules; EOC will manage supported input offers.", true
        end
        if step == 3 then return tradeCycle("BUY", false) end
        if step == 4 then return tradeCycle("BUY", true) end
        if step == 5 then return "EOC WAITING", "EOC will remove only its own emergency offer after a fresh verification proves stable local recovery.", true end
    elseif plan == "PAUSED_PRODUCTION" or plan == "MISSING_INPUTS" or plan == "INSTALLED_PRODUCTION" then
        if step == 1 then
            if produces > 0 and not paused then return "EOC CHECKED", "EOC observes installed production and no reported manual pause. It has not proven that the module is enabled or undamaged; confirm those conditions in the vanilla station view.", true end
            return "EOC WAITING", "EOC still observes the production line as paused or unavailable.", true
        end
        if step == 2 then
            if missingInputs <= 0 then return "EOC VERIFIED", "EOC currently reports no missing production input.", true end
            return "EOC WAITING", "EOC still reports " .. tostring(missingInputs) .. " missing production input(s).", true
        end
        if step == 3 then return "EOC CHECKED", "EOC reported the evidence it can prove. Module damage/enabled state, workforce policy, and manual allocation controls remain visible X4 boundaries, not generic player checklist answers.", true end
        if step == 4 then
            if action and actionType == "BUY" then return tradeCycle("BUY", true) end
            return "EOC CHECKING", "EOC will evaluate the next completed production evidence automatically and return the result.", true
        end
        if step == 5 then return "EOC CHECKED", "Capacity escalation remains advisory. Reopen Solution Planner whenever retained escalation evidence is available.", true end
    elseif plan == "SUPPLY_UNAVAILABLE" then
        if step == 1 then return "EOC CHECKED", "EOC currently observes no reachable supplier. Ware-rule and blacklist mutation remains outside EOC authority and is reported only as an X4 boundary.", true end
        if step == 2 then
            return "EOC VERIFIED", ownedSuppliers > 0 and ("EOC found " .. tostring(ownedSuppliers) .. " owned supplier(s).") or "EOC searched its current evidence and found no owned supplier.", true
        end
        if step == 4 then
            if capacity > 0 and compatible > 0 then return "EOC VERIFIED", "EOC observes compatible storage and assigned delivery capacity.", true end
            return "EOC WAITING", "Current evidence still lacks compatible storage or delivery capacity. Build only Planner-identified storage/production modules; registered-ship automation follows its separate authorization mode.", true
        end
        if step == 5 then
            if suppliers > 0 or produces > 0 then return "EOC VERIFIED", "EOC now observes a real supplier or installed production source.", true end
            return "EOC WAITING", "EOC still observes no proven supplier or local production source.", true
        end
    elseif plan == "LOGISTICS_MISSING" then
        if step == 1 then
            if compatible > 0 then return "EOC VERIFIED", "EOC observes compatible assigned delivery capacity.", true end
            return "EOC WAITING", "EOC still observes no compatible assigned delivery ship.", true
        end
        if step == 3 then return tradeCycle("BUY", false) end
        if step == 4 then return tradeCycle("BUY", true) end
        if step == 2 then
            if compatible > 0 then return "EOC VERIFIED", "EOC observes compatible assigned delivery capacity and will continue bounded verification.", true end
            return "EOC WAITING", "EOC still observes no compatible assigned trader. Auto-assignment is limited to eligible registered ships when that separate authority is enabled.", true
        end
        if step == 5 then return "EOC CHECKED", "Production escalation is not required until EOC exhausts the supported delivery path. Retained Planner access remains available for reference after escalation.", true end
    end
    return nil, nil, false
end

local function checklistPlayerClassification(plan, step)
    if plan == "STORAGE_OVERAGE" then
        if step == 2 then return "ACTION", true end
        if step == 4 then return "OPTIONAL STRATEGY", false end
    elseif plan == "ALLOGRAPHYNE_PROJECT" then
        if step == 3 or step == 6 then return "ACTION", true end
        if step == 4 then return "ADVISORY", false end
        return "CHECK", true
    elseif plan == "PLANNED_PRODUCTION" then
        if step == 2 or step == 3 then return "ACTION", true end
        if step == 5 then return "OPTIONAL STRATEGY", false end
        return "CHECK", true
    elseif plan == "PAUSED_PRODUCTION" or plan == "MISSING_INPUTS" or plan == "INSTALLED_PRODUCTION" then
        if step == 5 then return "OPTIONAL STRATEGY", false end
        return "CHECK", true
    elseif plan == "IMPORT_READY" then
        if step == 5 then return "OPTIONAL STRATEGY", false end
    elseif plan == "SUPPLY_UNAVAILABLE" then
        if step == 1 then return "CHECK", true end
        if step == 3 then return "OPTIONAL STRATEGY", false end
        if step == 4 then return "ACTION", true end
    elseif plan == "LOGISTICS_MISSING" then
        if step == 2 then return "CHECK / ACTION", true end
        if step == 5 then return "OPTIONAL STRATEGY", false end
    end
    return "ACTION", true
end

local function renderInteractiveChecklist(tableWidget, caseData, items)
    menu.checklistProgress = menu.checklistProgress or {}
    local key = checklistCaseKey(caseData)
    local plan = checklistPlanId(caseData)
    local playerComplete, playerNo, playerPending, optionalPending, eocVerified, eocWaiting = 0, 0, 0, 0, 0, 0
    local nextPlayerStep, nextWaitingStep
    local function toggleHandler(boundCase, boundKey, boundProgressKey, boundStep, boundState, boundText)
        return function()
            local nextState = boundState == "COMPLETE" and "NO" or (boundState == "NO" and "PENDING" or "COMPLETE")
            menu.checklistProgress[boundProgressKey] = nextState
            raise("checklist.set", { key = boundKey, station = text(v(boundCase, 1, "")), subject = text(v(boundCase, 4, "")), casetype = text(v(boundCase, 3, "")), plan = checklistPlanId(boundCase), step = boundStep, state = nextState, text = boundText, schema = EOC_CHECKLIST_SCHEMA })
            menu.refresh()
        end
    end
    local function askEOCHandler(boundCase, boundKey, boundProgressKey, boundStep, boundText)
        return function()
            if actionState("analysis.run").running then return end
            if menu.checklistProgress[boundProgressKey] == "CHECKING" or menu.checklistProgress[boundProgressKey] == "WAITING" then return end
            menu.checklistProgress[boundProgressKey] = "CHECKING"
            menu.pendingChecklistRequest = { progressKey = boundProgressKey, key = boundKey, station = text(v(boundCase, 1, "")), subject = text(v(boundCase, 4, "")), casetype = text(v(boundCase, 3, "")), plan = checklistPlanId(boundCase), step = boundStep, text = boundText }
            raise("checklist.set", { key = boundKey, station = text(v(boundCase, 1, "")), subject = text(v(boundCase, 4, "")), casetype = text(v(boundCase, 3, "")), plan = checklistPlanId(boundCase), step = boundStep, state = "CHECKING", text = boundText, schema = EOC_CHECKLIST_SCHEMA })
            if startAction("analysis.run") then menu.analysisRunning = true; raise("analysis.run", { checklist = true, station = text(v(boundCase, 1, "")), subject = text(v(boundCase, 4, "")), step = boundStep }) end
            menu.refresh()
        end
    end
    for index, item in ipairs(items or {}) do
        local stepIndex = index
        local stepText = tostring(item)
        local progressKey = key .. "|" .. tostring(stepIndex)
        local eocState, eocDetail, locked = eocChecklistState(caseData, plan, stepIndex)
        local savedState = menu.checklistProgress[progressKey]
        local state = (savedState == "COMPLETE" or savedState == "PLAYER CONFIRMED") and "COMPLETE" or (savedState == "NO" and "NO" or "PENDING")
        local marker, background, handler, active
        if locked then
            local eocComplete = eocState == "EOC VERIFIED" or eocState == "EOC CHECKED"
            if eocComplete then eocVerified = eocVerified + 1 else eocWaiting = eocWaiting + 1; nextWaitingStep = nextWaitingStep or stepIndex end
            local requestMarker = savedState == "CHECKING" and "EOC CHECKING" or ((savedState == "REQUESTED" or savedState == "WAITING") and "WAITING FOR TRADE CYCLE" or eocState)
            marker = "[" .. requestMarker .. "] "
            background = eocComplete and inactiveModeBackground or pendingChoiceBackground
            handler = askEOCHandler(caseData, key, progressKey, stepIndex, stepText)
            active = not eocComplete and not actionState("analysis.run").running and savedState ~= "CHECKING" and savedState ~= "WAITING"
        else
            if menu.mode == "MANAGED" then
                marker = "[EOC / X4 BOUNDARY] "
                background = inactiveModeBackground
                handler = function() end
                active = false
            else
            local classification, required = checklistPlayerClassification(plan, stepIndex)
            if required then
                if state == "COMPLETE" then playerComplete = playerComplete + 1 elseif state == "NO" then playerNo = playerNo + 1 else playerPending = playerPending + 1; nextPlayerStep = nextPlayerStep or stepIndex end
            elseif state == "PENDING" then
                optionalPending = optionalPending + 1
            end
            marker = state == "COMPLETE" and "[PLAYER: YES / DONE] " or (state == "NO" and "[PLAYER: NO / NOT DONE] " or "[PLAYER " .. classification .. "] ")
            background = state ~= "PENDING" and inactiveModeBackground or availableModeBackground
            handler = toggleHandler(caseData, key, progressKey, stepIndex, state, stepText)
            active = true
            end
            if plan == "IMPORT_READY" and stepIndex == 5 then
                local plannerReady = menu.plannerAccessForCase(caseData)
                marker = plannerReady and "[RUN READINESS CHECK AND OPEN PLANNER] " or "[LOCKED - EOC STILL TESTING] "
                active = plannerReady
                handler = plannerReady and function()
                        menu.runExpansionReadiness(caseData)
                        menu.solutionCase = caseData
                        menu.focusCaseStation(caseData)
                        captureNavigation("DIAGNOSTICS - " .. text(v(caseData, 4, "SELECTED CASE")))
                        menu.page = "solution"
                        menu.activeTab = "solution"
                        menu.refresh()
                    end or function() end
                if not plannerReady then
                    stepText = "Permanent station-plan escalation unlocks only after EOC keeps its bounded BUY offer active for a full 30-minute delivery-test window, confirms reachable supply and compatible station traders, and still observes no stock increase. Run fresh verification after the window; do not expand this station yet."
                else
                    stepText = "Run EOC's expansion-readiness check for this exact station and ware, then open the Solution Planner with the resulting PASS, WARNING, NOT READY, and CANNOT PROVE evidence. This check does not alter the station."
                end
            end
        end
        local row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        local label = marker .. tostring(stepIndex) .. ". " .. stepText
        if locked and eocDetail then label = label .. "  —  " .. eocDetail end
        addButton(row, 1, label, handler, active, background, Helper.standardButtonHeight * 3, nil, nil, true)
    end
    local plannerReady, plannerReason = menu.plannerAccessForCase(caseData)
    if plan ~= "IMPORT_READY" and plannerReady then
        local plannerRow = tableWidget:addRow(true)
        plannerRow[1]:setColSpan(4)
        local plannerLabel = plannerReason == "PLANNED_PRODUCTION_REVIEW" and "OPEN SOLUTION PLANNER - REVIEW EXISTING PRODUCTION PLAN" or "REOPEN SOLUTION PLANNER - FRESH READINESS MAY BE REQUIRED"
        addButton(plannerRow, 1, plannerLabel, function()
            if plannerReason == "PLANNED_PRODUCTION_REVIEW" then
                DebugError("[JKEOC][B291][PLANNED_PRODUCTION_PLANNER_ROUTE] station=" .. text(v(caseData, 1, "")) .. " ware=" .. text(v(caseData, 4, "")) .. " planned=" .. tostring(tonumber(v(caseData, 34, 0)) or 0) .. " action=RUN_READINESS_AND_OPEN")
                menu.runExpansionReadiness(caseData)
            end
            menu.solutionCase = caseData
            menu.focusCaseStation(caseData)
            captureNavigation("DIAGNOSTICS - " .. text(v(caseData, 4, "SELECTED CASE")))
            menu.page = "solution"
            menu.activeTab = "solution"
            menu.refresh()
        end, true, currentChoiceBackground)
    end
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("TWO-WAY PROGRESS: " .. tostring(eocVerified) .. " EOC verified | " .. tostring(eocWaiting) .. " ask/wait EOC | " .. tostring(playerComplete) .. " required player steps done | " .. tostring(playerNo) .. " required steps not done | " .. tostring(playerPending) .. " required checks/actions pending | " .. tostring(optionalPending) .. " optional strategy choices (never blocking).", { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(false)
    local acknowledgement
    if nextPlayerStep then
        acknowledgement = (playerComplete + playerNo > 0 and "EOC ACKNOWLEDGEMENT: I recorded your answers. " or "EOC STATUS: A required player check or action remains. ") .. "NEXT REQUIRED PLAYER STEP: " .. tostring(nextPlayerStep) .. ". " .. tostring(items[nextPlayerStep]) .. " Click once for YES/DONE, again for NO/NOT DONE, and again to clear the answer. Optional strategy rows never block verification."
    elseif nextWaitingStep then
        acknowledgement = "EOC ACKNOWLEDGEMENT: Your required player steps are complete. I am waiting on live evidence for step " .. tostring(nextWaitingStep) .. ". Allow the relevant operating cycle, then run a fresh verification check."
    else
        acknowledgement = "EOC ACKNOWLEDGEMENT: Every checklist step is complete or EOC-verified. Run a fresh verification check so I can resolve, improve, or escalate the case from current evidence."
    end
    if playerNo > 0 then
        acknowledgement = acknowledgement .. " BRANCH ACTIVE: A NO / NOT DONE answer prevents EOC from treating that prerequisite as satisfied. EOC will keep the case open, avoid claiming success, and direct the next verification toward the unresolved branch. It will not cancel or mutate an existing managed action from the answer alone."
    end
    row[1]:setColSpan(4):createText(acknowledgement, { wordwrap = true, color = navigationStoryColor })
    -- Verification is offered once, on Verify Result. The checklist explains
    -- readiness but must not create a second competing verification control.
end

pair = function(tableWidget, leftLabel, leftValue, rightLabel, rightValue)
    local row = tableWidget:addRow(false)
    row[1]:createText(leftLabel)
    row[2]:createText(text(leftValue), { halign = "right" })
    row[3]:createText(rightLabel)
    row[4]:createText(text(rightValue), { halign = "right" })
end

local function selectedStation()
    if type(menu.stations) ~= "table" then return nil end
    return menu.stations[menu.selected]
end

local function addWorkingStationBanner(tableWidget)
    local station = selectedStation()
    if not station then return end
    local stationName = text(v(station, 1, "SELECTED STATION"))
    local caseSubject = menu.diagnosticCase and text(v(menu.diagnosticCase, 1, "")) == stationName and text(v(menu.diagnosticCase, 4, "")) or nil
    local label = "WORKING STATION - " .. stationName
    if caseSubject and caseSubject ~= "-" then label = label .. "  |  CASE - " .. caseSubject end
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4)
    row[1]:createText(label, { wordwrap = true, color = navigationStoryColor })
end

local function stationCases(station)
    local matches = {}
    local stationName = text(v(station, 1, ""))

    for _, case in ipairs(menu.cases or {}) do
        if text(v(case, 1, "")) == stationName then
            table.insert(matches, case)
        end
    end

    return matches
end

local function casePlaybook(case)
    local rootCause = string.lower(text(v(case, 6, "")))
    local searchable = string.lower(
        text(v(case, 3, "")) .. " " .. text(v(case, 4, "")) .. " " ..
        text(v(case, 6, "")) .. " " .. text(v(case, 7, ""))
    )
    local playbook = {
        family = "GENERAL OPERATIONS",
        impact = "The station has persistent evidence that requires a focused review before corrective action is chosen.",
        investigate = "Compare the current evidence, station configuration, assigned ships, and recent operating state. Change only the first verified blocker.",
        player = "Use the station workspace and the relevant vanilla station screen to correct the verified blocker. EOC will not guess or make an unsupported change.",
        authority = "EOC can analyze, monitor, report, and perform only explicitly enabled bounded actions. Configuration, funding, construction, and ordinary ship orders remain player decisions.",
        verify = "Ask EOC once. EOC will compare later retained evidence automatically and return the supported result.",
    }

    local function has(word) return string.find(searchable, word, 1, true) ~= nil end
    local function rootHas(word) return string.find(rootCause, word, 1, true) ~= nil end
    if rootHas("import remediation") or rootHas("known sell offer") or ((has("ware") or has("shortage") or has("supply") or has("import") or has("allographyne")) and not (has("workforce") or has("food") or has("habitat") or has("storage") or has("capacity") or has("fund") or has("credit") or has("budget") or has("money") or has("production") or has("paused") or has("miner") or has("mining") or has("resource") or has("ore") or has("silicon") or has("hydrogen") or has("methane") or has("helium") or has("ice") or has("construction") or has("build") or has("builder") or has("defen") or has("attack") or has("threat"))) then
        playbook.family = "WARE SUPPLY AND DELIVERY"
        playbook.impact = "Required stock is below its operational target and may stop production, workforce support, construction, or terraforming delivery."
        playbook.investigate = "Check, in order: buy offer and requested amount; correct free storage; trade rule; manager range; compatible available trader; reachable supplier stock and price."
        playbook.player = "Correct the first failed check in Logical Station Overview or ship orders. If all checks pass, do not add production until EOC returns its delivery-test result."
        playbook.verify = "EOC will compare later delivery evidence automatically and report whether stock, an incoming order, or the shortage trend improved."
    elseif rootHas("local production exists") or rootHas("empty production input") or rootHas("production module") or rootHas("paused") then
        playbook.family = "PRODUCTION CHAIN"
        playbook.impact = "A paused module or missing upstream input is reducing or stopping station output."
        playbook.investigate = "Check module status, the first empty required input, storage allocation, production method, and whether planned construction already addresses the gap."
        playbook.player = "Restore the deepest missing input first or resume the affected module. Add production only after imports and existing capacity are proven insufficient."
        playbook.verify = "EOC will compare later production evidence automatically and report whether output and the input-shortage trend improved."
    elseif has("workforce") or has("food") or has("habitat") then
        playbook.family = "WORKFORCE SUPPORT"
        playbook.impact = "Workforce supply or habitat support is limiting the station's sustainable production bonus."
        playbook.investigate = "Check habitat demand, Food Rations and Medical Supplies targets, current stock, compatible storage, reachable supply, and assigned container traders."
        playbook.player = "Restore the missing workforce ware through imports or local production. Do not add habitat capacity until current demand is supplied."
        playbook.verify = "EOC will compare later workforce-supply evidence automatically and report whether stock and trend improved."
    elseif has("storage") or has("capacity") or has("full") then
        playbook.family = "STORAGE CAPACITY OR ALLOCATION"
        playbook.impact = "Missing, full, or incorrectly allocated storage can block buying, mining deliveries, production, and sales."
        playbook.investigate = "Confirm the ware's cargo type, allocated amount, free capacity, automatic storage target, and whether another ware is consuming the same storage pool."
        playbook.player = "Adjust ware allocation in Logical Station Overview. Add the correct storage module only when the existing storage pool is genuinely insufficient."
        playbook.verify = "EOC will compare later allocation and transfer evidence automatically and report whether usable capacity and flow recovered."
    elseif has("fund") or has("credit") or has("budget") or has("money") then
        playbook.family = "STATION FUNDING"
        playbook.impact = "The station may be unable to place required purchases even when offers, ships, and suppliers exist."
        playbook.investigate = "Compare station account balance with the manager's operating-budget estimate and the cost of the immediate shortage."
        playbook.player = "Transfer an appropriate operating reserve through the station Information account. EOC does not transfer player funds."
        playbook.verify = "EOC will compare later funding evidence automatically and report whether buy orders or required stock increased."
    elseif has("production") or has("input") or has("module") or has("paused") then
        playbook.family = "PRODUCTION CHAIN"
        playbook.impact = "A paused module or missing upstream input is reducing or stopping station output."
        playbook.investigate = "Check module status, the first empty required input, storage allocation, production method, and whether planned construction already addresses the gap."
        playbook.player = "Restore the deepest missing input first or resume the affected module. Add production only after imports and existing capacity are proven insufficient."
        playbook.verify = "EOC will compare later production evidence automatically and report whether output and the input-shortage trend improved."
    elseif has("miner") or has("mining") or has("resource") or has("ore") or has("silicon") or has("hydrogen") or has("methane") or has("helium") or has("ice") then
        playbook.family = "MINING AND RAW RESOURCES"
        playbook.impact = "The station is not receiving enough raw resource throughput for its demand."
        playbook.investigate = "Check resource demand, correct miner cargo type, subordinate assignment, resource probes, sector reach, blacklists, and whether miners are operational or stalled."
        playbook.player = "Reassign or add a suitable mineral or gas miner only after confirming demand and access. EOC can use only eligible registered ships within granted assignment authority."
        playbook.verify = "EOC will compare later mining-delivery evidence automatically and report whether raw stock and throughput rose."
    elseif has("construction") or has("build") or has("builder") then
        playbook.family = "CONSTRUCTION"
        playbook.impact = "An incomplete build plan or missing construction supply is delaying new station capability."
        playbook.investigate = "Check builder assignment, build storage funds, missing build wares, reachable sell offers, docking access, and whether the planned module is still required."
        playbook.player = "Fund build storage, supply the missing build ware, assign a builder, or revise the plan through the vanilla Build Plan interface. EOC does not alter construction plans."
        playbook.verify = "EOC will compare later construction evidence automatically and report whether the missing-ware or builder condition cleared."
    elseif has("defen") or has("attack") or has("threat") or has("shield") or has("turret") then
        playbook.family = "DEFENSE READINESS"
        playbook.impact = "The station's assigned defense or fitted capability may not match its operational risk."
        playbook.investigate = "Review local threats, defense subordinates, operational state, station module loadout, ammunition supply, and replacement readiness."
        playbook.player = "Assign or repair defensive assets and correct station loadout through normal X4 controls. EOC will not purchase ships or redesign the station."
        playbook.verify = "EOC will compare later defense evidence automatically and report whether readiness or case severity improved."
    elseif has("ship") or has("trader") or has("logistic") or has("assignment") then
        playbook.family = "SHIP ASSIGNMENT AND LOGISTICS"
        playbook.impact = "A needed logistics role lacks a suitable, available, correctly assigned ship."
        playbook.investigate = "Check ship purpose, cargo class, commander, current orders, operational state, station assignment, range, and EOC registration or pending approval."
        playbook.player = "Use Fleet and Logistics to inspect registered and pending ships. Build, free, or manually assign a suitable ship if no eligible ship exists."
        playbook.verify = "EOC will compare later assignment and station evidence automatically and report whether the ship is working and the need improved."
    end
    return playbook
end

captureNavigation = function(label, keepSelection)
    menu.navigationStack = menu.navigationStack or {}
    menu.narrativeSessionStart = menu.narrativeSessionStart or 0
    local origin = {
        page = menu.page,
        activeTab = menu.activeTab,
        label = label,
        keepSelection = keepSelection and true or false,
        selected = menu.selected,
        selectedCase = menu.selectedCase,
        caseScope = menu.caseScope,
        caseSeverity = menu.caseSeverity,
        casePage = menu.casePage,
        fleetScope = menu.fleetScope,
        fleetView = menu.fleetView,
        fleetPage = menu.fleetPage,
        fleetRecommendationCargo = menu.fleetRecommendationCargo,
        diagnosticView = menu.diagnosticView,
        kpiView = menu.kpiView,
        kpiResultPage = menu.kpiResultPage,
        predictiveStationId = menu.predictiveStationId,
        predictiveFilter = menu.predictiveFilter,
        supplyView = menu.supplyView,
        supplyOverviewDetailWare = menu.supplyOverviewDetailWare and { balance = menu.supplyOverviewDetailWare.balance, bottlenecks = menu.supplyOverviewDetailWare.bottlenecks },
    }
    table.insert(menu.navigationStack, origin)
    menu.navigationOrigin = origin
end

local function restoreNavigation()
    local origin = menu.navigationOrigin
    if not origin then
        return
    end
    if not origin.keepSelection then
        menu.selected = origin.selected or menu.selected
    end
    menu.selectedCase = origin.selectedCase or menu.selectedCase
    menu.caseScope = origin.caseScope or menu.caseScope
    menu.caseSeverity = origin.caseSeverity or menu.caseSeverity
    menu.casePage = origin.casePage or menu.casePage
    menu.fleetScope = origin.fleetScope or menu.fleetScope
    menu.fleetView = origin.fleetView or menu.fleetView
    menu.fleetPage = origin.fleetPage or menu.fleetPage
    menu.fleetRecommendationCargo = origin.fleetRecommendationCargo
    menu.diagnosticView = origin.diagnosticView or menu.diagnosticView
    menu.kpiView = origin.kpiView or menu.kpiView
    menu.kpiResultPage = origin.kpiResultPage or menu.kpiResultPage
    menu.predictiveStationId = origin.predictiveStationId
    menu.predictiveFilter = origin.predictiveFilter or menu.predictiveFilter
    menu.supplyView = origin.supplyView or menu.supplyView
    menu.supplyOverviewDetailWare = origin.supplyOverviewDetailWare or menu.supplyOverviewDetailWare
    menu.page = origin.page
    menu.activeTab = origin.activeTab or origin.page
    table.remove(menu.navigationStack)
    menu.navigationOrigin = menu.navigationStack[#menu.navigationStack]
    menu.refresh()
end

local function openCasesCenter()
    if menu.page ~= "cases" then
        captureNavigation(menu.page == "dashboard" and "OVERVIEW" or string.upper(menu.page or "PREVIOUS SCREEN"))
    end
    menu.caseScope = selectedStation() and "station" or "global"
    menu.caseSeverity = "all"
    menu.selectedCase = 1
    menu.casePage = 1
    menu.diagnosticCase = nil
    menu.page = "cases"
    menu.activeTab = "cases"
    menu.refresh()
end

local function captureReportOrigin(page, label)
    menu.reportRunning = true
    menu.reportStatus = "GENERATING REPORT..."
    menu.reportOrigin = {
        page = page,
        label = label,
        selected = menu.selected,
        selectedCase = menu.selectedCase,
        caseScope = menu.caseScope,
        caseSeverity = menu.caseSeverity,
        casePage = menu.casePage,
        fleetScope = menu.fleetScope,
        fleetView = menu.fleetView,
        fleetPage = menu.fleetPage,
    }
    menu.refresh()
end

-- Build 260 Supply Model is deliberately isolated from every recurring EOC
-- scheduler. These helpers are called only from the Supply Model page after a
-- deliberate player click. Snapshots are advisory and never become case/SPOS
-- evidence or managed-trade authority.
function menu.supplyModelStore()
    if type(menu.supplyModelCache) == "table" then return menu.supplyModelCache end
    local store
    pcall(function()
        store = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), menu.supplyBlackboardKey)
    end)
    if type(store) ~= "table" then store = { views = {}, audit = {} } end
    if type(store.views) ~= "table" then store.views = {} end
    if type(store.audit) ~= "table" then store.audit = {} end
    menu.supplyModelCache = store
    return store
end

function menu.saveSupplyModelStore(store)
    menu.supplyModelCache = store
    pcall(function()
        SetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), menu.supplyBlackboardKey, store)
    end)
end

function menu.supplyStationId(profile)
    local raw = v(profile, 24, nil)
    if raw == nil or tostring(raw) == "" then return nil end
    local ok, result = pcall(ConvertStringTo64Bit, tostring(raw))
    if not ok or result == 0 then return nil end
    return result
end

function menu.supplyWareId(value)
    local result = tostring(value or "")
    result = result:gsub("^ware%.", "")
    return result
end

function menu.supplyIsExcludedWare(ware)
    return menu.supplyWareId(ware):lower() == "rawscrap"
end

function menu.supplyList(source)
    local result, seen = {}, {}
    if type(source) ~= "table" then return result end
    for _, value in pairs(source) do
        local ware = menu.supplyWareId(value)
        if ware ~= "" and not seen[ware] and not menu.supplyIsExcludedWare(ware) then
            seen[ware] = true
            result[#result + 1] = ware
        end
    end
    table.sort(result)
    return result
end

function menu.supplySafeRate(station, ware, production, ignorestate)
    local ok, value = pcall(function()
        if production then return C.GetContainerWareProduction(station, ware, ignorestate) end
        return C.GetContainerWareConsumption(station, ware, ignorestate)
    end)
    if not ok then return 0 end
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    return value
end

function menu.supplyWareMetadata(ware)
    local name, minprice, maxprice, averageprice, volume, transport
    local ok = pcall(function()
        name, minprice, maxprice, averageprice, volume, transport = GetWareData(ware, "name", "minprice", "maxprice", "avgprice", "volume", "transport")
    end)
    if not ok then name = ware end
    minprice = tonumber(minprice) or 0
    maxprice = tonumber(maxprice) or minprice
    averageprice = tonumber(averageprice) or ((minprice + maxprice) / 2)
    return {
        id = ware,
        name = tostring(name or ware),
        minprice = minprice,
        maxprice = math.max(minprice, maxprice),
        averageprice = math.max(minprice, math.min(math.max(minprice, maxprice), averageprice)),
        volume = math.max(1, tonumber(volume) or 1),
        transport = tostring(transport or "UNKNOWN"),
    }
end

function menu.supplyStationSnapshot(profile, includeSettings)
    local station = menu.supplyStationId(profile)
    if not station then return nil end
    local isplayerowned, stationname, products, resources, tradewares, cargo
    local ok = pcall(function()
        isplayerowned, stationname, products, resources, tradewares, cargo = GetComponentData(station, "isplayerowned", "name", "products", "allresources", "tradewares", "cargo")
    end)
    if not ok or not isplayerowned then return nil end
    products, resources, tradewares = menu.supplyList(products), menu.supplyList(resources), menu.supplyList(tradewares)
    cargo = type(cargo) == "table" and cargo or {}
    local wares, seen = {}, {}
    local function include(list)
        for _, ware in ipairs(list) do
            if not seen[ware] then seen[ware] = true; wares[#wares + 1] = ware end
        end
    end
    include(products); include(resources); include(tradewares)
    table.sort(wares)
    local productSet, resourceSet = {}, {}
    for _, ware in ipairs(products) do productSet[ware] = true end
    for _, ware in ipairs(resources) do resourceSet[ware] = true end
    local records = {}
    for _, ware in ipairs(wares) do
        local metadata = menu.supplyWareMetadata(ware)
        local record = {
            ware = ware,
            name = metadata.name,
            product = productSet[ware] == true,
            resource = resourceSet[ware] == true,
            installedProduction = menu.supplySafeRate(station, ware, true, true),
            effectiveProduction = menu.supplySafeRate(station, ware, true, false),
            installedConsumption = menu.supplySafeRate(station, ware, false, true),
            effectiveConsumption = menu.supplySafeRate(station, ware, false, false),
            stock = math.max(0, tonumber(cargo[ware]) or 0),
            minprice = metadata.minprice,
            maxprice = metadata.maxprice,
            averageprice = metadata.averageprice,
            volume = metadata.volume,
            transport = metadata.transport,
        }
        if includeSettings then
            pcall(function()
                record.storage = math.max(0, tonumber(GetWareProductionLimit(station, ware)) or 0)
                record.storageOverride = HasContainerStockLimitOverride(station, ware) and true or false
                record.buyprice = tonumber(GetContainerWarePrice(station, ware, true)) or metadata.averageprice
                record.sellprice = tonumber(GetContainerWarePrice(station, ware, false)) or metadata.averageprice
                record.buypriceOverride = HasContainerWarePriceOverride(station, ware, true) and true or false
                record.sellpriceOverride = HasContainerWarePriceOverride(station, ware, false) and true or false
            end)
        end
        records[#records + 1] = record
    end
    return {
        id = tostring(v(profile, 24, "")),
        profileIndex = tonumber(v(profile, 16, 0)) or 0,
        name = tostring(stationname or v(profile, 1, "Unknown station")),
        role = text(v(profile, 2, "UNDEFINED")),
        storageCapacity = math.max(0, tonumber(v(profile, 15, 0)) or 0),
        products = products,
        resources = resources,
        wares = records,
    }
end

function menu.supplyCollect(view)
    local snapshot = { view = view, captured = getElapsedTime(), rows = {}, stations = {}, excluded = "Raw Scrap" }
    local stationOnly = view == "station" or view == "settings"
    if stationOnly then
        local profile = menu.stations and menu.stations[menu.selected]
        local record = profile and menu.supplyStationSnapshot(profile, view == "settings") or nil
        if record then snapshot.stations[1] = record end
    else
        for _, profile in ipairs(menu.stations or {}) do
            local record = menu.supplyStationSnapshot(profile, false)
            if record then snapshot.stations[#snapshot.stations + 1] = record end
        end
    end

    local wareMap = {}
    for _, station in ipairs(snapshot.stations) do
        for _, record in ipairs(station.wares) do
            local aggregate = wareMap[record.ware]
            if not aggregate then
                aggregate = {
                    ware = record.ware, name = record.name, installed = 0, effective = 0,
                    demand = 0, currentDemand = 0, supported = 0, producers = 0,
                    consumers = 0, producerStations = {}, consumerStations = {},
                }
                wareMap[record.ware] = aggregate
            end
            aggregate.installed = aggregate.installed + record.installedProduction
            aggregate.effective = aggregate.effective + record.effectiveProduction
            aggregate.demand = aggregate.demand + record.installedConsumption
            aggregate.currentDemand = aggregate.currentDemand + record.effectiveConsumption
            if record.installedProduction > 0 then
                aggregate.producers = aggregate.producers + 1
                aggregate.producerStations[#aggregate.producerStations + 1] = { name = station.name, installed = record.installedProduction, effective = record.effectiveProduction }
            end
            if record.installedConsumption > 0 then
                aggregate.consumers = aggregate.consumers + 1
                aggregate.consumerStations[#aggregate.consumerStations + 1] = { id = station.id, profileIndex = station.profileIndex, name = station.name, demand = record.installedConsumption, current = record.effectiveConsumption }
            end
        end
    end

    for _, station in ipairs(snapshot.stations) do
        local supportFactor = 1
        local hasMeasuredInput = false
        for _, ware in ipairs(station.resources or {}) do
            local input = wareMap[ware]
            if input and input.demand > 0 then
                hasMeasuredInput = true
                supportFactor = math.min(supportFactor, math.max(0, math.min(1, input.installed / input.demand)))
            end
        end
        station.supportFactor = hasMeasuredInput and supportFactor or 1
        for _, record in ipairs(station.wares) do
            if record.installedProduction > 0 and wareMap[record.ware] then
                wareMap[record.ware].supported = wareMap[record.ware].supported + record.installedProduction * station.supportFactor
            end
        end
    end

    for _, aggregate in pairs(wareMap) do
        aggregate.coverage = aggregate.demand > 0 and (aggregate.installed * 100 / aggregate.demand) or (aggregate.installed > 0 and 100 or 0)
        aggregate.deficit = math.max(0, aggregate.demand - aggregate.installed)
        aggregate.surplus = math.max(0, aggregate.installed - aggregate.demand)
        table.sort(aggregate.producerStations, function(a, b) return a.installed > b.installed end)
        table.sort(aggregate.consumerStations, function(a, b) return a.demand > b.demand end)
        snapshot.rows[#snapshot.rows + 1] = aggregate
    end
    table.sort(snapshot.rows, function(a, b)
        if view == "bottlenecks" or view == "expansion" then
            if a.deficit == b.deficit then return a.name < b.name end
            return a.deficit > b.deficit
        elseif view == "capacity" then
            if a.installed == b.installed then return a.name < b.name end
            return a.installed > b.installed
        end
        if a.coverage == b.coverage then return a.name < b.name end
        return a.coverage < b.coverage
    end)
    return snapshot
end

function menu.supplyRun(view)
    DebugError("[JKEOC][B279][SUPPLY_RUN] stage=START view=" .. tostring(view) .. " trigger=PLAYER_EXPLICIT recurring_supply_scan=0")
    local store = menu.supplyModelStore()
    local current = menu.supplyCollect(view)
    local prior = store.views[view] and store.views[view].current or nil
    store.views[view] = { previous = prior, current = current }
    menu.saveSupplyModelStore(store)
    menu.supplyStatus = "ON-DEMAND ANALYSIS COMPLETE: " .. string.upper(view)
    menu.supplySelectedCapacityWare = nil
    menu.supplySelectedExpansionWare = nil
    DebugError("[JKEOC][B279][SUPPLY_RUN] stage=COMPLETE view=" .. tostring(view) .. " stations=" .. tostring(#(current.stations or {})) .. " wares=" .. tostring(#(current.rows or {})) .. " recurring_supply_scan=0")
end

function menu.supplyViewSnapshots(view)
    local state = menu.supplyModelStore().views[view]
    if type(state) ~= "table" then return nil, nil end
    return state.current, state.previous
end

function menu.supplyPreviousRow(previous, ware)
    if not previous then return nil end
    for _, row in ipairs(previous.rows or {}) do if row.ware == ware then return row end end
    return nil
end

function menu.supplyMatchingCase(stationName, wareName)
    for _, caseData in ipairs(menu.cases or {}) do
        if text(v(caseData, 1, "")) == tostring(stationName or "") and (text(v(caseData, 4, "")) == tostring(wareName or "") or text(v(caseData, 17, "")) == tostring(wareName or "")) then return caseData end
    end
    return nil
end

function menu.supplyOpenExistingCase(caseData)
    menu.diagnosticCase = caseData
    menu.focusCaseStation(caseData)
    captureNavigation("SUPPLY MODEL - EXISTING CASE")
    menu.page = "diagnostics"
    menu.activeTab = "diagnostics"
    menu.diagnosticView = "recovery"
    menu.refresh()
end

function menu.supplyCaseBridge(tableWidget, detailRecord, prior)
    if (tonumber(detailRecord.coverage) or 100) >= 50 then return end
    section(tableWidget, "CASE SYSTEM BRIDGE")
    local persistentSevere = prior and (tonumber(prior.coverage) or 100) < 50
    local bridge = tableWidget:addRow(false)
    bridge[1]:setColSpan(4):createText(persistentSevere and
        "PERSISTENCE PROVEN: This ware remained severe across two player-requested snapshots. Open an existing station/ware case or request one new case below. EOC checks the exact station and ware before creating anything." or
        "CASE CREATION LOCKED — CORROBORATION REQUIRED. Existing matching cases can still be opened now; EOC must independently retain later severe evidence before creating a new case.",
        { wordwrap = true, color = persistentSevere and investigationUnknownColor or investigationNeutralColor })
    local consumers = detailRecord.consumerStations or {}
    local firstConsumer, lastConsumer = menu.adaptiveListNavigation(tableWidget, "supply.casebridge." .. tostring(detailRecord.ware), #consumers, { fixedRows = 24, rowUnits = 1, maximum = 5 })
    for consumerIndex = firstConsumer, lastConsumer do
        local consumer = consumers[consumerIndex]
        local boundConsumer, boundWare = consumer, detailRecord.name
        local existingCase = menu.supplyMatchingCase(boundConsumer.name, boundWare)
        local caseRow = tableWidget:addRow(true)
        caseRow[1]:setColSpan(4)
        if existingCase then
            local boundCase = existingCase
            addButton(caseRow, 1, "CASE ACTIVE — OPEN " .. boundConsumer.name .. " / " .. boundWare, function() menu.supplyOpenExistingCase(boundCase) end, true, inactiveModeBackground)
        elseif persistentSevere and (tonumber(boundConsumer.profileIndex) or 0) > 0 then
            addButton(caseRow, 1, "ADD CASE — " .. boundConsumer.name .. " / " .. boundWare, function()
                if startAction("case.create") then
                    raise("case.create", { index = boundConsumer.profileIndex, subject = boundWare, issues = 1, rootcause = "Persistent severe Supply Model deficit across two explicit snapshots; station-specific cause is not yet proven.", corrective = "Open Diagnostics and run the smallest supported station/ware verification before changing logistics, prices, storage, or construction." })
                end
                menu.refresh()
            end, not actionState("case.create").running, availableModeBackground)
        else
            addButton(caseRow, 1, "NEW CASE LOCKED — " .. boundConsumer.name .. " / " .. boundWare, function() end, false, inactiveModeBackground)
        end
    end
    actionResult(tableWidget, "case.create", "Creates at most one station/ware case after persistence is proven. Existing matching cases are opened instead of duplicated.")
end

function menu.supplySelectedStationRecord(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local profile = menu.stations and menu.stations[menu.selected]
    local selectedId = profile and tostring(v(profile, 24, "")) or ""
    if selectedId ~= "" then
        for _, station in ipairs(snapshot.stations or {}) do
            if tostring(station.id or "") == selectedId then return station end
        end
    end
    return nil
end

function menu.supplySelectedStationWareSet(snapshot, productsOnly)
    local station = menu.supplySelectedStationRecord(snapshot)
    local result = {}
    if not station then return result, nil end
    if productsOnly then
        for _, ware in ipairs(station.products or {}) do result[ware] = true end
    else
        for _, record in ipairs(station.wares or {}) do result[record.ware] = true end
    end
    return result, station
end

function menu.supplyDelta(value, previous)
    if previous == nil then return "NO PREVIOUS SNAPSHOT" end
    local delta = (tonumber(value) or 0) - (tonumber(previous) or 0)
    if math.abs(delta) < 0.005 then return "NO CHANGE" end
    return (delta > 0 and "+" or "") .. formatNumber(delta)
end

function menu.supplyElapsedLabel(value)
    local seconds = math.max(0, math.floor(tonumber(value) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d game time", hours, minutes, remainder)
end

function menu.supplyBar(tableWidget, label, value, maximum, suffix, color)
    local row = tableWidget:addRow(false)
    row[1]:createText(label, { wordwrap = true })
    local safeMaximum = math.max(1, tonumber(maximum) or 1)
    local safeValue = math.max(0, math.min(safeMaximum, tonumber(value) or 0))
    row[2]:setColSpan(2):createStatusBar({
        current = safeValue, start = 0, max = safeMaximum,
        valueColor = color or navigationStoryColor,
        markerColor = inactiveModeBackground,
        height = Helper.standardTextHeight,
    })
    row[4]:createText(formatNumber(value) .. (suffix or ""), { halign = "right" })
end

function menu.supplyCoverageState(record)
    local demand = tonumber(record and record.demand) or 0
    local coverage = tonumber(record and record.coverage) or 0
    if demand <= 0 then return "NO DEMAND", investigationNeutralColor end
    if coverage < 50 then return "SEVERE", investigationFailColor end
    if coverage < 100 then return "SHORTAGE", investigationUnknownColor end
    if coverage <= 125 then return "BALANCED", investigationPassColor end
    return "SURPLUS", navigationStoryColor
end

function menu.supplySuggestedPrices(record, coverage)
    local range = math.max(0, (tonumber(record.maxprice) or 0) - (tonumber(record.minprice) or 0))
    local suggestedBuy = math.floor(math.max(record.minprice, math.min(record.maxprice, coverage < 75 and record.maxprice or coverage < 100 and (record.averageprice + range * 0.25) or record.averageprice)) + 0.5)
    local suggestedSell = math.floor(math.max(record.minprice, math.min(record.maxprice, coverage > 125 and record.minprice or coverage > 100 and (record.averageprice - range * 0.25) or record.averageprice)) + 0.5)
    local minimumSpread = range >= 1 and 1 or 0
    if suggestedSell - suggestedBuy < minimumSpread then
        if coverage < 100 then suggestedBuy = math.min(suggestedBuy, record.maxprice - minimumSpread); suggestedSell = math.max(suggestedSell, suggestedBuy + minimumSpread)
        else suggestedSell = math.max(suggestedSell, record.minprice + minimumSpread); suggestedBuy = math.min(suggestedBuy, suggestedSell - minimumSpread) end
    end
    suggestedBuy = math.floor(math.max(record.minprice, math.min(record.maxprice, suggestedBuy)) + 0.5)
    suggestedSell = math.floor(math.max(record.minprice, math.min(record.maxprice, suggestedSell)) + 0.5)
    return suggestedBuy, suggestedSell, minimumSpread
end

function menu.supplyLegend(tableWidget)
    local explanation = tableWidget:addRow(false)
    explanation[1]:setColSpan(4):createText("HOW TO READ COVERAGE: 100% means installed supply exactly matches measured demand. Below 100% is a shortage; above 100% is surplus. For example, 350% means supply is 3.5 times measured demand — not a score of 350 out of 100.", { wordwrap = true, color = navigationStoryColor })
    local row = tableWidget:addRow(false)
    row[1]:createText("RED  SEVERE <50%", { color = investigationFailColor })
    row[2]:createText("AMBER  SHORTAGE <100%", { color = investigationUnknownColor })
    row[3]:createText("GREEN  BALANCED 100-125%", { color = investigationPassColor })
    row[4]:createText("CYAN  SURPLUS >125%", { color = navigationStoryColor, halign = "right" })
end

function menu.supplyPlainLanguage(tableWidget, record)
    local supply = tonumber(record and record.installed) or 0
    local demand = tonumber(record and record.demand) or 0
    local gap = supply - demand
    local coverage = tonumber(record and record.coverage) or 0
    local verdict
    if demand <= 0 then
        verdict = "NO INTERNAL NEED MEASURED: Your stations did not report using this ware in this snapshot. EOC cannot judge whether outside customers will buy it."
    elseif supply <= 0 then
        verdict = "NOT MAKING ENOUGH: Your stations use " .. formatNumber(demand) .. " units each game hour, but EOC found no installed player-owned production."
    elseif gap < 0 then
        verdict = "NOT MAKING ENOUGH: Your stations can make " .. formatNumber(supply) .. " units each game hour but use " .. formatNumber(demand) .. ". The measured shortfall is " .. formatNumber(math.abs(gap)) .. " units each game hour."
    elseif coverage <= 125 then
        verdict = "SUPPLY ROUGHLY MATCHES NEED: Your stations can make " .. formatNumber(supply) .. " units each game hour and use " .. formatNumber(demand) .. "."
    else
        verdict = "MAKING MORE THAN YOUR STATIONS USE: Your stations can make " .. formatNumber(supply) .. " units each game hour but use " .. formatNumber(demand) .. ". The measured surplus is " .. formatNumber(gap) .. " units each game hour."
    end
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("PLAIN-LANGUAGE RESULT: " .. verdict, { wordwrap = true, color = gap < 0 and investigationFailColor or (coverage > 125 and navigationStoryColor or investigationPassColor), font = Helper.headerFont })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHAT THE NUMBERS MEAN: '/h' means units per game hour; it is a production or use rate, not stored inventory. Coverage compares installed player-owned production with measured use by your own stations. 100% means equal rates; " .. string.format("%.1f%%", coverage) .. " means production is " .. string.format("%.1f", demand > 0 and supply / demand or 0) .. " times measured internal use.", { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHAT THIS SNAPSHOT DOES NOT PROVE: It does not track individual ships currently in flight, guarantee an NPC buyer, or prove that price, trade rules, travel time, cargo space, or station-manager range can move the ware. Use Fleet & Logistics for ship coverage and the station's trade settings for buyers and permissions.", { wordwrap = true, color = investigationNeutralColor })
end

function menu.supplyGrid(tableWidget, view, records, previous, detailHandler)
    menu.supplyLegend(tableWidget)
    local summary = tableWidget:addRow(false)
    summary[1]:setColSpan(4):createText(tostring(#records) .. " MEASURED-DEMAND RESOURCES | ADAPTIVE SCREEN BOUNDARY", { halign = "center", color = investigationNeutralColor })
    local cardUnits = math.max(1, math.ceil(menu.supplyCardHeight() / math.max(1, Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize)))
    local first, last = menu.adaptiveListNavigation(tableWidget, "supply." .. tostring(view), #records, { fixedRows = 12, rowUnits = cardUnits, columns = 2 })
    for index = first, last, 2 do
        local row = tableWidget:addRow(true)
        for slot = 0, 1 do
            local record = records[index + slot]
            if record then
                local column = slot == 0 and 1 or 3
                local state, color = menu.supplyCoverageState(record)
                local prior = menu.supplyPreviousRow(previous, record.ware)
                local label
                local gap = (tonumber(record.installed) or 0) - (tonumber(record.demand) or 0)
                local gapText = gap < 0 and ("SHORT " .. formatNumber(math.abs(gap)) .. " UNITS PER GAME HOUR") or ("EXTRA " .. formatNumber(gap) .. " UNITS PER GAME HOUR")
                local trend = prior and ("CHANGE " .. menu.supplyDelta(record.coverage, prior.coverage) .. " POINTS") or "FIRST SNAPSHOT"
                label = record.name .. "\n" .. state .. " | COVERAGE " .. string.format("%.0f%%", tonumber(record.coverage) or 0) .. "\n" .. gapText .. " | " .. trend
                row[column]:setColSpan(2)
                addButton(row, column, label, function() detailHandler(record); menu.refresh() end, true, inactiveModeBackground, menu.supplyCardHeight(), color, true, true)
            end
        end
    end
end

function menu.supplyNavigation(tableWidget)
    section(tableWidget, "ON-DEMAND SUPPLY MODEL")
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "EMPIRE SUPPLY BALANCE", function() menu.supplyView = "balance"; menu.supplyPages.balance = menu.supplyPages.balance or 1; menu.refresh() end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "INSTALLED / SUPPORTED / EFFECTIVE", function() menu.supplyView = "capacity"; menu.supplyPages.capacity = menu.supplyPages.capacity or 1; menu.refresh() end, true)
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "TOP SUPPLY BOTTLENECKS", function() menu.supplyView = "bottlenecks"; menu.supplyPages.bottlenecks = menu.supplyPages.bottlenecks or 1; menu.refresh() end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "WARES BY PRODUCING STATION", function() menu.supplyView = "producers"; menu.supplyPages.producers = menu.supplyPages.producers or 1; menu.refresh() end, true)
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "SELECTED STATION SUPPLY PROFILE", function() menu.supplyView = "station"; menu.supplyPages.station = menu.supplyPages.station or 1; menu.refresh() end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "STATION PRICE & STORAGE PLAN", function() menu.supplyView = "settings"; menu.refresh() end, true)
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "ADVISORY EXPANSION PLANNER", function() menu.supplyView = "expansion"; menu.refresh() end, true)
    local explanation = tableWidget:addRow(false)
    explanation[1]:setColSpan(4):createText("This tab performs no analysis while idle. Enter a view and explicitly run it. Each view retains only its previous and current snapshots so EOC can show the change since that view's last refresh.", { wordwrap = true })
end

function menu.supplyRefreshControls(tableWidget, view, current)
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "BACK TO SUPPLY MODEL CHOICES", function() menu.supplyView = "home"; menu.supplyPreview = nil; menu.refresh() end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, current and "REFRESH THIS ANALYSIS" or "RUN THIS ANALYSIS", function() menu.supplyRun(view); menu.refresh() end, true)
    local status = tableWidget:addRow(false)
    status[1]:setColSpan(4):createText(current and ("LAST ON-DEMAND REFRESH: " .. menu.supplyElapsedLabel(current.captured) .. " | " .. #(current.stations or {}) .. " station(s) measured | Raw Scrap excluded") or "NOT ANALYZED: No station or ware data has been read for this view.", { wordwrap = true, color = current and investigationNeutralColor or investigationUnknownColor })
end

function menu.supplyExpansionView(tableWidget, current, previous)
    local wareSet, station = menu.supplySelectedStationWareSet(current, false)
    if not station then
        local empty = tableWidget:addRow(false)
        empty[1]:setColSpan(4):createText("The selected station is not present in this snapshot. Return to Stations, select a valid player station, then run the Expansion Planner again.", { wordwrap = true, color = investigationUnknownColor })
        return
    end
    local candidates = {}
    for index, record in ipairs(current.rows or {}) do
        if wareSet[record.ware] and (tonumber(record.demand) or 0) > 0 then
            local state, priority, reason
            if record.deficit > 0 and record.installed <= 0 then
                state, priority = "NEW OWNED CAPACITY CANDIDATE", 1
                reason = "Empire demand exceeds installed owned production and this snapshot measured no owned production capacity."
            elseif record.deficit > 0 and record.installed > 0 and record.supported < record.installed * 0.9 then
                state, priority = "RECOVER INPUT SUPPORT FIRST", 2
                reason = "Installed capacity exists, but the advisory supported ceiling is materially lower. Adding output capacity before restoring inputs is not supported."
            elseif record.deficit > 0 and record.effective < math.min(record.installed, record.supported) * 0.9 then
                state, priority = "RESTORE EXISTING CAPACITY FIRST", 3
                reason = "Existing capacity is not currently effective. Recover the present line before considering another module."
            elseif record.deficit > 0 then
                state, priority = "EXPANSION CANDIDATE", 4
                reason = "Measured empire demand exceeds installed owned production after the current capacity and support checks."
            else
                state, priority = "NO EXPANSION SUPPORTED", 5
                reason = "This on-demand snapshot does not show an owned production deficit for the selected resource."
            end
            candidates[#candidates + 1] = { index = index, record = record, state = state, priority = priority, reason = reason }
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority == b.priority then
            if a.record.deficit == b.record.deficit then return a.record.name < b.record.name end
            return a.record.deficit > b.record.deficit
        end
        return a.priority < b.priority
    end)
    if #candidates == 0 then
        local empty = tableWidget:addRow(false)
        empty[1]:setColSpan(4):createText("No station-relevant resource with measured internal demand was returned for " .. station.name .. ".", { wordwrap = true })
        return
    end
    local options = {}
    for index, candidate in ipairs(candidates) do
        options[#options + 1] = { id = index, text = candidate.state .. " | " .. candidate.record.name, icon = "", displayremoveoption = false }
    end
    local selected = clamp(tonumber(menu.supplySelectedExpansionWare) or 1, 1, #candidates)
    menu.supplySelectedExpansionWare = selected
    local selectRow = tableWidget:addRow(true)
    local dropdown = selectRow[1]:setColSpan(4):createDropDown(options, { active = true, startOption = selected, height = Helper.standardButtonHeight })
    dropdown:setTextProperties({ fontsize = Helper.standardFontSize })
    selectRow[1].handlers.onDropDownConfirmed = function(_, value)
        menu.supplySelectedExpansionWare = clamp(tonumber(value) or selected, 1, #candidates)
        menu.refresh()
    end
    local candidate = candidates[selected]
    local record = candidate.record
    local prior = menu.supplyPreviousRow(previous, record.ware)
    section(tableWidget, station.name .. " | " .. record.name)
    local maximum = math.max(1, record.installed, record.supported, record.effective, record.demand)
    menu.supplyBar(tableWidget, "INSTALLED OWNED CAPACITY", record.installed, maximum, "/h", navigationStoryColor)
    menu.supplyBar(tableWidget, "SUPPORTED CEILING", record.supported, maximum, "/h", investigationUnknownColor)
    menu.supplyBar(tableWidget, "EFFECTIVE NOW", record.effective, maximum, "/h", investigationPassColor)
    menu.supplyBar(tableWidget, "EMPIRE DEMAND", record.demand, maximum, "/h", investigationFailColor)
    local decision = tableWidget:addRow(false)
    decision[1]:setColSpan(4):createText("PLANNER RESULT: " .. candidate.state .. "\n" .. candidate.reason, { wordwrap = true, color = candidate.priority <= 4 and investigationUnknownColor or investigationPassColor })
    local evidence = tableWidget:addRow(false)
    evidence[1]:setColSpan(4):createText("DEFICIT " .. formatNumber(record.deficit) .. "/h | " .. (record.demand > 0 and ("COVERAGE " .. string.format("%.1f%%", record.coverage)) or "NO MEASURED INTERNAL DEMAND") .. " | " .. record.producers .. " producing station(s) | " .. record.consumers .. " consuming station(s) | deficit delta " .. menu.supplyDelta(record.deficit, prior and prior.deficit or nil), { wordwrap = true })
    local boundary = tableWidget:addRow(false)
    boundary[1]:setColSpan(4):createText("ADVISORY BOUNDARY: EOC has not proven an exact module macro, module count, plot location, construction cost, or complete upstream recipe for this recommendation. Review the named ware in the vanilla Station Build Plan before committing construction. EOC will not place or build anything.", { wordwrap = true, color = investigationNeutralColor })
end

function menu.supplyOverviewView(tableWidget, view, current, previous)
    local titles = {
        balance = "EMPIRE SUPPLY BALANCE",
        capacity = "INSTALLED / SUPPORTED / EFFECTIVE CAPACITY",
        bottlenecks = "TOP SUPPLY BOTTLENECKS",
        producers = "WARES BY PRODUCING STATION",
        expansion = "ADVISORY EXPANSION PLANNER",
    }
    section(tableWidget, titles[view] or "SUPPLY MODEL")
    menu.supplyRefreshControls(tableWidget, view, current)
    if not current then return end
    local rows = current.rows or {}
    if #rows == 0 then
        local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("The selected on-demand pass returned no supported production or consumption records.", { wordwrap = true }); return
    end
    if view == "expansion" then
        menu.supplyExpansionView(tableWidget, current, previous)
        return
    end
    if view == "producers" then
        local productSet, selectedStation = menu.supplySelectedStationWareSet(current, true)
        if not selectedStation then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("The selected station is not present in this snapshot. Select a valid player station and refresh this analysis.", { wordwrap = true }); return end
        local products = {}
        for _, record in ipairs(rows) do if record.installed > 0 and productSet[record.ware] and (tonumber(record.demand) or 0) > 0 then products[#products + 1] = record end end
        if #products == 0 then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("No product at " .. selectedStation.name .. " has measured internal demand in this snapshot."); return end
        local chosen
        if menu.supplyProducerDetailWare then for _, record in ipairs(products) do if record.ware == menu.supplyProducerDetailWare then chosen = record; break end end end
        if not chosen then
            local note = tableWidget:addRow(false); note[1]:setColSpan(4):createText("SELECTED-STATION PRODUCTS: " .. #products .. " | Select a resource to see every owned station producing it.", { wordwrap = true, color = investigationNeutralColor })
            menu.supplyGrid(tableWidget, "producers", products, previous, function(record) menu.supplyProducerDetailWare = record.ware end)
            return
        end
        local back = tableWidget:addRow(true); back[1]:setColSpan(4)
        addButton(back, 1, "BACK TO SELECTED-STATION PRODUCT GRID", function() menu.supplyProducerDetailWare = nil; menu.refresh() end, true)
        section(tableWidget, selectedStation.name .. " RESOURCE | " .. chosen.name .. " - PRODUCING STATIONS")
        local maximum = chosen.producerStations[1] and chosen.producerStations[1].installed or 1
        local summary = tableWidget:addRow(false)
        summary[1]:setColSpan(4):createText(tostring(#chosen.producerStations) .. " PRODUCING STATIONS | ADAPTIVE SCREEN BOUNDARY", { halign = "center", color = investigationNeutralColor })
        local first, last = menu.adaptiveListNavigation(tableWidget, "supply.producers.detail", #chosen.producerStations, { fixedRows = 14, rowUnits = 2 })
        for index = first, last do
            local producer = chosen.producerStations[index]
            menu.supplyBar(tableWidget, producer.name, producer.installed, maximum, "/h", navigationStoryColor)
            local prior = menu.supplyPreviousRow(previous, chosen.ware)
            local priorStation
            if prior then for _, entry in ipairs(prior.producerStations or {}) do if entry.name == producer.name then priorStation = entry; break end end end
            local delta = tableWidget:addRow(false); delta[1]:setColSpan(4):createText("Effective " .. formatNumber(producer.effective) .. "/h | installed delta " .. menu.supplyDelta(producer.installed, priorStation and priorStation.installed or nil), { wordwrap = true })
        end
        return
    end

    local displayRows = {}
    local maximumDeficit = 1
    for _, record in ipairs(rows) do maximumDeficit = math.max(maximumDeficit, record.deficit) end
    for _, record in ipairs(rows) do
        local show = (tonumber(record.demand) or 0) > 0 and (view ~= "bottlenecks" or record.deficit > 0)
        if show then displayRows[#displayRows + 1] = record end
    end
    if #displayRows == 0 then
        local empty = tableWidget:addRow(false)
        empty[1]:setColSpan(4):createText(view == "bottlenecks" and "No measured supply deficit appears in this snapshot." or "No resource with measured internal demand appears in this snapshot.", { wordwrap = true })
        return
    end
    if view == "capacity" then
        local wareSet, selectedStation = menu.supplySelectedStationWareSet(current, false)
        if not selectedStation then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("The selected station is not present in this snapshot. Select a valid player station and refresh this analysis.", { wordwrap = true }); return end
        local relevant = {}
        for _, record in ipairs(displayRows) do if wareSet[record.ware] then relevant[#relevant + 1] = record end end
        if #relevant == 0 then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("No resource present at " .. selectedStation.name .. " has measured internal demand in this snapshot."); return end
        local record
        if menu.supplyCapacityDetailWare then
            for _, candidate in ipairs(relevant) do if candidate.ware == menu.supplyCapacityDetailWare then record = candidate; break end end
        end
        if not record then
            local note = tableWidget:addRow(false)
            note[1]:setColSpan(4):createText("SELECTED STATION RESOURCES: " .. #relevant .. " | Select any card for installed, supported and effective detail. Values are empire-wide for that resource.", { wordwrap = true, color = investigationNeutralColor })
            menu.supplyGrid(tableWidget, "capacity", relevant, previous, function(chosen) menu.supplyCapacityDetailWare = chosen.ware end)
            return
        end
        local back = tableWidget:addRow(true); back[1]:setColSpan(4)
        addButton(back, 1, "BACK TO SELECTED-STATION RESOURCE GRID", function() menu.supplyCapacityDetailWare = nil; menu.refresh() end, true)
        local prior = menu.supplyPreviousRow(previous, record.ware)
        section(tableWidget, selectedStation.name .. " RESOURCE | " .. record.name)
        local maximum = math.max(1, record.installed, record.supported, record.effective, record.demand)
        menu.supplyBar(tableWidget, "INSTALLED", record.installed, maximum, "/h", navigationStoryColor)
        menu.supplyBar(tableWidget, "SUPPORTED CEILING", record.supported, maximum, "/h", investigationUnknownColor)
        menu.supplyBar(tableWidget, "EFFECTIVE NOW", record.effective, maximum, "/h", investigationPassColor)
        local detail = tableWidget:addRow(false)
        detail[1]:setColSpan(4):createText((record.demand > 0 and ("Demand " .. formatNumber(record.demand) .. "/h | coverage " .. string.format("%.1f%%", record.coverage)) or "NO MEASURED INTERNAL DEMAND") .. " | " .. record.consumers .. " consuming station(s)", { wordwrap = true })
        local delta = tableWidget:addRow(false)
        delta[1]:setColSpan(4):createText("Installed delta " .. menu.supplyDelta(record.installed, prior and prior.installed or nil) .. " | effective delta " .. menu.supplyDelta(record.effective, prior and prior.effective or nil), { wordwrap = true })
        local position = tableWidget:addRow(false)
        position[1]:setColSpan(4):createText("SELECTED-STATION RESOURCE GRID: " .. #relevant .. " resource(s) | Values retain the empire-wide Capacity scope for the chosen ware.", { wordwrap = true, color = investigationNeutralColor })
        return
    end
    local detailWare = menu.supplyOverviewDetailWare and menu.supplyOverviewDetailWare[view]
    local detailRecord
    if detailWare then for _, candidate in ipairs(displayRows) do if candidate.ware == detailWare then detailRecord = candidate; break end end end
    if not detailRecord then
        local note = tableWidget:addRow(false)
        note[1]:setColSpan(4):createText(view == "bottlenecks" and "WORST SHORTAGES FIRST | Select a card for evidence and snapshot change." or "EMPIRE RESOURCE MATRIX | Supply minus demand is shown on each card. Select a card for evidence and snapshot change.", { wordwrap = true, color = investigationNeutralColor })
        menu.supplyOverviewDetailWare = menu.supplyOverviewDetailWare or {}
        menu.supplyGrid(tableWidget, view, displayRows, previous, function(chosen) menu.supplyOverviewDetailWare[view] = chosen.ware end)
    else
        local back = tableWidget:addRow(true); back[1]:setColSpan(4)
        addButton(back, 1, "BACK TO RESOURCE GRID", function() menu.supplyOverviewDetailWare[view] = nil; menu.refresh() end, true)
        local prior = menu.supplyPreviousRow(previous, detailRecord.ware)
        local state, color = menu.supplyCoverageState(detailRecord)
        section(tableWidget, detailRecord.name .. " | " .. state)
        menu.supplyPlainLanguage(tableWidget, detailRecord)
        if view == "bottlenecks" then
            menu.supplyBar(tableWidget, "MEASURED DEFICIT", detailRecord.deficit, maximumDeficit, "/h", color)
        else
            menu.supplyBar(tableWidget, "INSTALLED SUPPLY", detailRecord.installed, math.max(1, detailRecord.installed, detailRecord.demand), "/h", navigationStoryColor)
            menu.supplyBar(tableWidget, "INTERNAL DEMAND", detailRecord.demand, math.max(1, detailRecord.installed, detailRecord.demand), "/h", investigationFailColor)
        end
        local evidence = tableWidget:addRow(false)
        evidence[1]:setColSpan(4):createText((detailRecord.demand > 0 and ("Coverage " .. string.format("%.1f%%", detailRecord.coverage)) or "NO MEASURED INTERNAL DEMAND") .. " | installed production " .. formatNumber(detailRecord.installed) .. " units per game hour | internal use " .. formatNumber(detailRecord.demand) .. " units per game hour | " .. detailRecord.producers .. " producing station(s) | " .. detailRecord.consumers .. " consuming station(s)", { wordwrap = true })
        local delta = tableWidget:addRow(false)
        delta[1]:setColSpan(4):createText("CHANGE SINCE THE PREVIOUS PLAYER-RUN SNAPSHOT: coverage changed " .. menu.supplyDelta(detailRecord.coverage, prior and prior.coverage or nil) .. " percentage points; the shortage changed " .. menu.supplyDelta(detailRecord.deficit, prior and prior.deficit or nil) .. " units per game hour. NO PREVIOUS SNAPSHOT means EOC has nothing earlier to compare yet.", { wordwrap = true })
        menu.supplyCaseBridge(tableWidget, detailRecord, prior)
    end
end

function menu.supplyBuildPriceBatch(station, wares, current)
    local rows, skipped, unchanged = {}, 0, 0
    menu.supplyDrafts = menu.supplyDrafts or {}
    for _, wareRecord in ipairs(wares or {}) do
        local coverage = 100
        for _, aggregate in ipairs(current.rows or {}) do if aggregate.ware == wareRecord.ware then coverage = tonumber(aggregate.coverage) or 100; break end end
        local suggestedBuy, suggestedSell, minimumSpread = menu.supplySuggestedPrices(wareRecord, coverage)
        local key = station.id .. "|" .. wareRecord.ware
        local draft = menu.supplyDrafts[key]
        local buy = math.floor((tonumber(draft and draft.buy) or suggestedBuy) + 0.5)
        local sell = math.floor((tonumber(draft and draft.sell) or suggestedSell) + 0.5)
        local valid = buy >= wareRecord.minprice and buy <= wareRecord.maxprice and sell >= wareRecord.minprice and sell <= wareRecord.maxprice and sell - buy >= minimumSpread
        if valid and (math.floor((tonumber(wareRecord.buyprice) or -1) + 0.5) ~= buy or math.floor((tonumber(wareRecord.sellprice) or -1) + 0.5) ~= sell) then
            rows[#rows + 1] = { ware = wareRecord.ware, name = wareRecord.name, beforeBuy = wareRecord.buyprice, beforeSell = wareRecord.sellprice, buy = buy, sell = sell }
        elseif not valid then skipped = skipped + 1 else unchanged = unchanged + 1 end
    end
    return { station = station.name, stationid = station.id, rows = rows, skipped = skipped, unchanged = unchanged }
end

function menu.supplyApplyPriceBatch(station, batch)
    local station64 = ConvertStringTo64Bit(station.id)
    local applied, failed = 0, 0
    local store = menu.supplyModelStore()
    for _, proposal in ipairs(batch.rows or {}) do
        local applyOk, applyError = pcall(function()
            SetContainerWarePriceOverride(station64, proposal.ware, true, proposal.buy)
            SetContainerWarePriceOverride(station64, proposal.ware, false, proposal.sell)
        end)
        local afterBuy, afterSell, buyOverride, sellOverride = -1, -1, false, false
        local readOk = false
        if applyOk then
            readOk = pcall(function()
                afterBuy = tonumber(GetContainerWarePrice(station64, proposal.ware, true)) or -1
                afterSell = tonumber(GetContainerWarePrice(station64, proposal.ware, false)) or -1
                buyOverride = HasContainerWarePriceOverride(station64, proposal.ware, true) and true or false
                sellOverride = HasContainerWarePriceOverride(station64, proposal.ware, false) and true or false
            end)
        end
        local verified = readOk and buyOverride and sellOverride and math.floor(afterBuy + 0.5) == proposal.buy and math.floor(afterSell + 0.5) == proposal.sell
        if verified then applied = applied + 1 else failed = failed + 1 end
        table.insert(store.audit, 1, { transaction = "BATCH PRICE", station = station.name, stationid = station.id, ware = proposal.ware, warename = proposal.name, time = getElapsedTime(), before = { buy = proposal.beforeBuy, sell = proposal.beforeSell }, requested = { buy = proposal.buy, sell = proposal.sell }, after = { buy = afterBuy, sell = afterSell, buyoverride = buyOverride, selloverride = sellOverride }, verified = verified, error = applyOk and "" or tostring(applyError) })
        DebugError("[JKEOC][B279][BATCH_PRICE_APPLY] station=" .. station.name .. " stationid=" .. station.id .. " ware=" .. proposal.ware .. " requested_buy=" .. tostring(proposal.buy) .. " requested_sell=" .. tostring(proposal.sell) .. " readback_buy=" .. tostring(afterBuy) .. " readback_sell=" .. tostring(afterSell) .. " verified=" .. tostring(verified) .. " apply_ok=" .. tostring(applyOk))
    end
    while #store.audit > 64 do table.remove(store.audit) end
    menu.saveSupplyModelStore(store)
    menu.supplyApplyResult = "BATCH PRICE RESULT: " .. tostring(applied) .. " verified applied | " .. tostring(failed) .. " failed | " .. tostring(batch.skipped or 0) .. " invalid skipped | " .. tostring(batch.unchanged or 0) .. " unchanged | storage unchanged."
    DebugError("[JKEOC][B279][BATCH_PRICE_COMPLETE] station=" .. station.name .. " proposed=" .. tostring(#(batch.rows or {})) .. " applied=" .. tostring(applied) .. " failed=" .. tostring(failed) .. " invalid_skipped=" .. tostring(batch.skipped or 0) .. " unchanged=" .. tostring(batch.unchanged or 0) .. " storage_changes=0")
    menu.supplyBatchPreview = nil
    menu.supplyRun("settings")
end

function menu.supplyStationSelector(tableWidget)
    local options = {}
    local activeProfile = menu.stations and menu.stations[menu.selected]
    local activeId = activeProfile and tostring(v(activeProfile, 24, "")) or ""
    for _, profile in ipairs(menu.stations or {}) do
        local stationId = tostring(v(profile, 24, ""))
        if stationId ~= "" then
            options[#options + 1] = { id = stationId, text = text(v(profile, 1, "Station")), icon = "", displayremoveoption = false }
        end
    end
    local row = tableWidget:addRow(true)
    row[1]:createText("SELECT STATION")
    local dropdown = row[2]:setColSpan(3):createDropDown(options, { active = #options > 0, startOption = activeId, height = Helper.standardButtonHeight })
    dropdown:setTextProperties({ fontsize = Helper.standardFontSize })
    row[2].handlers.onDropDownConfirmed = function(_, value)
        local confirmedId = tostring(value or "")
        if confirmedId == "" or confirmedId == activeId then return end
        for index, profile in ipairs(menu.stations or {}) do
            if tostring(v(profile, 24, "")) == confirmedId then
                menu.selected = index
                menu.supplyDraft = nil
                menu.supplyDrafts = {}
                menu.supplyPreview = nil
                menu.supplyBatchPreview = nil
                menu.supplyApplyResult = nil
                menu.supplySelectedWare = nil
                menu.supplyStationDetailWare = nil
                menu.supplyProducerDetailWare = nil
                menu.supplyCapacityDetailWare = nil
                menu.supplyStatus = "STATION CHANGED: Select REFRESH THIS ANALYSIS to collect current Supply evidence for the newly selected station. No analysis ran automatically."
                DebugError("[JKEOC][B280][SUPPLY_STATION_SELECT] stationid=" .. confirmedId .. " collection=not_run explicit_refresh_required=true")
                menu.refresh()
                return
            end
        end
    end
end

function menu.supplySelectedStationView(tableWidget, view, current, previous)
    section(tableWidget, view == "settings" and "STATION PRICE & STORAGE PLAN" or "SELECTED STATION SUPPLY PROFILE")
    menu.supplyStationSelector(tableWidget)
    menu.supplyRefreshControls(tableWidget, view, current)
    if not current then return end
    local station = current.stations and current.stations[1]
    if not station then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("The selected station is unavailable. Select a valid player station on the Stations tab and run this view again.", { wordwrap = true }); return end
    local selectedProfile = menu.stations and menu.stations[menu.selected]
    local selectedStationId = selectedProfile and tostring(v(selectedProfile, 24, "")) or ""
    if selectedStationId == "" or tostring(station.id or "") ~= selectedStationId then
        local stale = tableWidget:addRow(false)
        stale[1]:setColSpan(4):createText("STATION CHANGED: The displayed cache belongs to " .. tostring(station.name or "the previously selected station") .. ". Select REFRESH THIS ANALYSIS to collect the newly selected station. Until then, EOC will not show, preview, or apply stale station values.", { wordwrap = true, color = investigationUnknownColor })
        return
    end
    section(tableWidget, station.name .. " | " .. station.role)
    if view == "station" then
        local priorStation = previous and previous.stations and previous.stations[1]
        local previousMap = {}
        if priorStation then for _, record in ipairs(priorStation.wares or {}) do previousMap[record.ware] = record end end
        local displayWares = {}
        for _, record in ipairs(station.wares or {}) do
            if record.installedProduction > 0 or record.installedConsumption > 0 then displayWares[#displayWares + 1] = record end
        end
        local chosen
        if menu.supplyStationDetailWare then for _, record in ipairs(displayWares) do if record.ware == menu.supplyStationDetailWare then chosen = record; break end end end
        if not chosen then
            local note = tableWidget:addRow(false); note[1]:setColSpan(4):createText("STATION RESOURCE GRID | Every card is a resource actually present at this station. Select one for output, input, stock and snapshot-change detail.", { wordwrap = true, color = investigationNeutralColor })
            local summary = tableWidget:addRow(false)
            summary[1]:setColSpan(4):createText(tostring(#displayWares) .. " STATION RESOURCES | ADAPTIVE SCREEN BOUNDARY", { halign = "center", color = investigationNeutralColor })
            local cardUnits = math.max(1, math.ceil(menu.supplyCardHeight() / math.max(1, Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize)))
            local first, last = menu.adaptiveListNavigation(tableWidget, "supply.station.resources", #displayWares, { fixedRows = 14, rowUnits = cardUnits, columns = 2 })
            for index = first, last, 2 do
                local row = tableWidget:addRow(true)
                for slot = 0, 1 do
                    local record = displayWares[index + slot]
                    if record then
                        local column = slot == 0 and 1 or 3
                        local label = record.name .. "\nMAKING NOW " .. formatNumber(record.effectiveProduction) .. " / GAME HOUR | USING " .. formatNumber(record.installedConsumption) .. " / GAME HOUR\nSTORED NOW " .. formatNumber(record.stock)
                        row[column]:setColSpan(2)
                        addButton(row, column, label, function() menu.supplyStationDetailWare = record.ware; menu.refresh() end, true, inactiveModeBackground, menu.supplyCardHeight(), record.installedProduction > 0 and navigationStoryColor or investigationNeutralColor, true, true)
                    end
                end
            end
        else
            local back = tableWidget:addRow(true); back[1]:setColSpan(4)
            addButton(back, 1, "BACK TO STATION RESOURCE GRID", function() menu.supplyStationDetailWare = nil; menu.refresh() end, true)
            section(tableWidget, chosen.name)
            local explanation = tableWidget:addRow(false)
            explanation[1]:setColSpan(4):createText("READ THIS FIRST: Installed output is what this station could make if supplied and operating. Effective output is what its current inputs and operating conditions support. Installed input is what its modules could use. Each rate is units per game hour; STOCK is the number of units currently stored.", { wordwrap = true, color = navigationStoryColor })
            local maximum = math.max(1, chosen.installedProduction, chosen.installedConsumption)
            menu.supplyBar(tableWidget, "INSTALLED OUTPUT", chosen.installedProduction, maximum, "/h", navigationStoryColor)
            menu.supplyBar(tableWidget, "INSTALLED INPUT", chosen.installedConsumption, maximum, "/h", investigationUnknownColor)
            menu.supplyBar(tableWidget, "EFFECTIVE OUTPUT", chosen.effectiveProduction, maximum, "/h", investigationPassColor)
            local prior = previousMap[chosen.ware]
            local delta = tableWidget:addRow(false); delta[1]:setColSpan(4):createText("Stock " .. formatNumber(chosen.stock) .. " | effective-output delta " .. menu.supplyDelta(chosen.effectiveProduction, prior and prior.effectiveProduction or nil), { wordwrap = true })
        end
        if #displayWares == 0 then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("No measurable production or consumption rate was returned for this station.") end
        return
    end

    local wares = station.wares or {}
    if #wares == 0 then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("No configurable production, resource, or trade ware was returned for this station."); return end
    local options = {}
    local selectedWare = tostring(menu.supplySelectedWare or "")
    local selectedIndex = 1
    for index, wareRecord in ipairs(wares) do
        options[#options + 1] = { id = wareRecord.ware, text = wareRecord.name, icon = "", displayremoveoption = false }
        if wareRecord.ware == selectedWare then selectedIndex = index end
    end
    menu.supplySelectedWare = wares[selectedIndex].ware
    local selectRow = tableWidget:addRow(true)
    local dropdown = selectRow[1]:setColSpan(4):createDropDown(options, { active = true, startOption = menu.supplySelectedWare, height = Helper.standardButtonHeight })
    dropdown:setTextProperties({ fontsize = Helper.standardFontSize })
    selectRow[1].handlers.onDropDownConfirmed = function(_, value)
        local confirmedWare = tostring(value or "")
        local found = false
        for _, wareRecord in ipairs(wares) do if wareRecord.ware == confirmedWare then found = true; break end end
        if found then
            if menu.supplySelectedWare ~= confirmedWare then menu.supplyDraft = nil end
            menu.supplySelectedWare = confirmedWare
        end
        menu.supplyPreview = nil
        menu.supplyApplyResult = nil
        menu.refresh()
    end
    local record = wares[selectedIndex]
    local coverageRow
    for _, aggregate in ipairs(current.rows or {}) do if aggregate.ware == record.ware then coverageRow = aggregate; break end end
    local coverage = coverageRow and coverageRow.coverage or 100
    local suggestedBuy, suggestedSell, minimumSpread = menu.supplySuggestedPrices(record, coverage)
    local throughput = math.max(record.installedProduction, record.installedConsumption)
    local suggestedStorage = math.max(1, math.floor(math.max(record.stock, throughput * 2) + 0.5))
    if record.storage and record.storage > 0 then suggestedStorage = math.min(math.max(record.storage * 2, 1), suggestedStorage) end
    local physicalWareLimit = station.storageCapacity > 0 and math.max(1, math.floor(station.storageCapacity / math.max(1, record.volume))) or nil
    if physicalWareLimit then suggestedStorage = math.min(suggestedStorage, physicalWareLimit) end
    local draftKey = station.id .. "|" .. record.ware
    menu.supplyDrafts = menu.supplyDrafts or {}
    if not menu.supplyDrafts[draftKey] then menu.supplyDrafts[draftKey] = { key = draftKey, buy = suggestedBuy, sell = suggestedSell, storage = suggestedStorage } end
    if not menu.supplyDraft or menu.supplyDraft.key ~= draftKey then
        menu.supplyDraft = menu.supplyDrafts[draftKey]
        menu.supplyPreview = nil
    end
    local draft = menu.supplyDraft
    local priceReason = tableWidget:addRow(false)
    local priceVerdict = coverage < 100 and "SHORTAGE: EOC leans toward a higher valid buy price to attract supply. It is not recommending more selling while your own stations are short." or (coverage > 125 and "SURPLUS: EOC leans toward a lower valid sell price to help excess stock leave the station. It is not recommending that you buy more of this ware." or "BALANCED: Current owned production is close to measured internal use, so EOC avoids a large price change.")
    priceReason[1]:setColSpan(4):createText("WHY EOC SUGGESTED THIS: " .. priceVerdict .. " Buy price is what this station offers suppliers. Sell price is what customers pay. Storage allocation is the share of station storage reserved for this ware; increasing it can take space away from other wares.", { wordwrap = true, color = coverage < 100 and investigationUnknownColor or navigationStoryColor, font = Helper.headerFont })
    priceReason = tableWidget:addRow(false)
    priceReason[1]:setColSpan(4):createText("EVIDENCE USED: Empire coverage is " .. string.format("%.1f%%", coverage) .. ". 100% means installed production equals measured use by your own stations. Current stock is " .. formatNumber(record.stock) .. " units; installed production is " .. formatNumber(record.installedProduction) .. " units per game hour; installed use is " .. formatNumber(record.installedConsumption) .. " units per game hour. This advice cannot prove outside market demand or that a ship can reach a buyer.", { wordwrap = true })
    pair(tableWidget, "CURRENT BUY PRICE", formatNumber(record.buyprice) .. " Cr", "EOC SUGGESTED", formatNumber(suggestedBuy) .. " Cr")
    pair(tableWidget, "CURRENT SELL PRICE", formatNumber(record.sellprice) .. " Cr", "EOC SUGGESTED", formatNumber(suggestedSell) .. " Cr")
    pair(tableWidget, "CURRENT STORAGE ALLOCATION", formatNumber(record.storage), "EOC SUGGESTED", formatNumber(suggestedStorage))
    local function editRow(label, field)
        local row = tableWidget:addRow(true)
        row[1]:createText(label)
        row[2]:setColSpan(3):createEditBox({ height = Helper.standardButtonHeight }):setText(tostring(draft[field] or 0))
        row[2].handlers.onEditBoxDeactivated = function(_, entered)
            draft[field] = tostring(entered or "")
            menu.supplyPreview = nil
            menu.supplyBatchPreview = nil
            menu.supplyApplyResult = nil
        end
    end
    editRow("PROPOSED BUY PRICE", "buy")
    editRow("PROPOSED SELL PRICE", "sell")
    editRow("PROPOSED STORAGE", "storage")
    local guidance = tableWidget:addRow(false)
    guidance[1]:setColSpan(4):createText("HOW TO CHANGE THESE SETTINGS: 1. Read the current values on the left. 2. Read EOC's suggestions on the right. Suggestions do not change the station. 3. Type each value you want into Proposed. 4. Press TAB after each value. 5. Select PREVIEW. Preview changes nothing. 6. Check the preview, then select CONFIRM to apply it.", { wordwrap = true, color = investigationNeutralColor })
    local buy, sell, storage = tonumber(draft.buy), tonumber(draft.sell), tonumber(draft.storage)
    local valid = buy and sell and storage and buy >= record.minprice and buy <= record.maxprice and sell >= record.minprice and sell <= record.maxprice and sell - buy >= minimumSpread and storage >= 1 and (not physicalWareLimit or storage <= physicalWareLimit)
    local bounds = tableWidget:addRow(false)
    bounds[1]:setColSpan(4):createText("VALID PRICE RANGE: " .. formatNumber(record.minprice) .. "-" .. formatNumber(record.maxprice) .. " Cr. Sell price must be at least " .. formatNumber(minimumSpread) .. " Cr above buy price. Current proposed spread: " .. (buy and sell and formatNumber(sell - buy) or "INVALID") .. " Cr. Storage is whole ware units" .. (physicalWareLimit and (" and is capped at " .. formatNumber(physicalWareLimit) .. " by measured station capacity") or "") .. ". Changing allocation can reduce shared storage available to other wares.", { wordwrap = true, color = valid and investigationNeutralColor or investigationFailColor })
    local action = tableWidget:addRow(true); action[1]:setColSpan(4)
    if not menu.supplyPreview then
        addButton(action, 1, "PREVIEW EXACT STATION CHANGES", function()
            local liveBuy, liveSell, liveStorage = tonumber(draft.buy), tonumber(draft.sell), tonumber(draft.storage)
            local liveValid = liveBuy and liveSell and liveStorage and liveBuy >= record.minprice and liveBuy <= record.maxprice and liveSell >= record.minprice and liveSell <= record.maxprice and liveSell - liveBuy >= minimumSpread and liveStorage >= 1 and (not physicalWareLimit or liveStorage <= physicalWareLimit)
            menu.supplyPreview = liveValid and draftKey or nil
            menu.supplyApplyResult = liveValid and nil or "NOT READY - PRESS TAB AFTER EACH FIELD, THEN CORRECT THE RED VALIDATION MESSAGE"
            menu.refresh()
        end, true)
    else
        addButton(action, 1, "CONFIRM: APPLY PRICE & STORAGE OVERRIDES", function()
            local station64 = ConvertStringTo64Bit(station.id)
            local before = { buy = record.buyprice, sell = record.sellprice, storage = record.storage, buyoverride = record.buypriceOverride, selloverride = record.sellpriceOverride, storageoverride = record.storageOverride }
            local applyOk, applyError = pcall(function()
                SetContainerWarePriceOverride(station64, record.ware, true, math.floor(buy + 0.5))
                SetContainerWarePriceOverride(station64, record.ware, false, math.floor(sell + 0.5))
                SetContainerStockLimitOverride(station64, record.ware, math.floor(storage + 0.5))
            end)
            local verified, after = false, {}
            if applyOk then
                local readOk = pcall(function()
                    after.buy = tonumber(GetContainerWarePrice(station64, record.ware, true)) or -1
                    after.sell = tonumber(GetContainerWarePrice(station64, record.ware, false)) or -1
                    after.storage = tonumber(GetWareProductionLimit(station64, record.ware)) or -1
                    after.buyoverride = HasContainerWarePriceOverride(station64, record.ware, true) and true or false
                    after.selloverride = HasContainerWarePriceOverride(station64, record.ware, false) and true or false
                    after.storageoverride = HasContainerStockLimitOverride(station64, record.ware) and true or false
                end)
                verified = readOk and after.buyoverride and after.selloverride and after.storageoverride and math.floor(after.buy + 0.5) == math.floor(buy + 0.5) and math.floor(after.sell + 0.5) == math.floor(sell + 0.5) and math.floor(after.storage + 0.5) == math.floor(storage + 0.5)
            end
            DebugError("[JKEOC][B279][PRICE_STORAGE_APPLY] station=" .. station.name .. " stationid=" .. station.id .. " ware=" .. record.ware .. " requested_buy=" .. tostring(math.floor(buy + 0.5)) .. " requested_sell=" .. tostring(math.floor(sell + 0.5)) .. " requested_storage=" .. tostring(math.floor(storage + 0.5)) .. " readback_buy=" .. tostring(after.buy or -1) .. " readback_sell=" .. tostring(after.sell or -1) .. " readback_storage=" .. tostring(after.storage or -1) .. " verified=" .. tostring(verified) .. " apply_ok=" .. tostring(applyOk))
            local store = menu.supplyModelStore()
            table.insert(store.audit, 1, { station = station.name, stationid = station.id, ware = record.ware, warename = record.name, time = getElapsedTime(), before = before, requested = { buy = math.floor(buy + 0.5), sell = math.floor(sell + 0.5), storage = math.floor(storage + 0.5) }, after = after, verified = verified, error = applyOk and "" or tostring(applyError) })
            while #store.audit > 64 do table.remove(store.audit) end
            menu.saveSupplyModelStore(store)
            menu.supplyApplyResult = verified and "APPLIED - EOC VERIFIED BY IMMEDIATE READ-BACK" or "NOT VERIFIED - X4 DID NOT REPORT THE COMPLETE REQUESTED STATE"
            menu.supplyPreview = nil
            menu.supplyRun("settings")
            menu.refresh()
        end, valid, pendingChoiceBackground)
        local preview = tableWidget:addRow(false)
        preview[1]:setColSpan(4):createText("PENDING CONFIRMATION: " .. record.name .. " at " .. station.name .. ". Buy " .. formatNumber(record.buyprice) .. " -> " .. formatNumber(buy) .. " Cr; sell " .. formatNumber(record.sellprice) .. " -> " .. formatNumber(sell) .. " Cr; storage " .. formatNumber(record.storage) .. " -> " .. formatNumber(storage) .. ". This explicitly enables manual price and storage overrides for this ware. No credits or cargo are moved by this click.", { wordwrap = true, color = investigationUnknownColor })
    end
    section(tableWidget, "OPTIONAL: REVIEW ALL PRICE CHANGES FOR THIS STATION")
    local batchNote = tableWidget:addRow(false)
        batchNote[1]:setColSpan(4):createText("WHAT THIS DOES: Shows only wares whose suggested buy or sell price differs from the station's current price. It never changes storage. Preview changes nothing; Confirm applies the listed prices and immediately asks X4 to report them back. If there are no meaningful changes, EOC will say NO PRICE CHANGES NEEDED.", { wordwrap = true, color = investigationNeutralColor })
    if not menu.supplyBatchPreview or menu.supplyBatchPreview.stationid ~= station.id then
        local batchRow = tableWidget:addRow(true); batchRow[1]:setColSpan(4)
        addButton(batchRow, 1, "PREVIEW ONLY THE PRICES EOC WOULD CHANGE", function()
            menu.supplyBatchPreview = menu.supplyBuildPriceBatch(station, wares, current)
            menu.supplyApplyResult = nil
            menu.refresh()
        end, true)
    else
        local batch = menu.supplyBatchPreview
        local summary = tableWidget:addRow(false)
        summary[1]:setColSpan(4):createText(#(batch.rows or {}) == 0 and ("NO PRICE CHANGES NEEDED: " .. tostring(batch.unchanged or 0) .. " ware(s) already match EOC's suggestion. Storage will not change.") or ("PENDING CONFIRMATION: EOC would change prices for " .. tostring(#(batch.rows or {})) .. " ware(s). " .. tostring(batch.unchanged or 0) .. " already need no change; " .. tostring(batch.skipped or 0) .. " invalid proposal(s) were safely skipped. Storage will not change."), { wordwrap = true, color = #(batch.rows or {}) == 0 and investigationPassColor or investigationUnknownColor })
        local proposals = batch.rows or {}
        local first, last = menu.adaptiveListNavigation(tableWidget, "supply.price.batch", #proposals, { fixedRows = 26, rowUnits = 1, maximum = 6 })
        for index = first, last do
            local proposal = proposals[index]
            local proposalRow = tableWidget:addRow(false)
            proposalRow[1]:setColSpan(4):createText(proposal.name .. ": BUY " .. formatNumber(proposal.beforeBuy) .. " -> " .. formatNumber(proposal.buy) .. " Cr | SELL " .. formatNumber(proposal.beforeSell) .. " -> " .. formatNumber(proposal.sell) .. " Cr", { wordwrap = true })
        end
        local confirmBatch = tableWidget:addRow(true)
        confirmBatch[1]:setColSpan(2); addButton(confirmBatch, 1, "CONFIRM ALL " .. tostring(#(batch.rows or {})) .. " PRICE CHANGES", function() menu.supplyApplyPriceBatch(station, batch); menu.refresh() end, #(batch.rows or {}) > 0, pendingChoiceBackground)
        confirmBatch[3]:setColSpan(2); addButton(confirmBatch, 3, "CANCEL BATCH", function() menu.supplyBatchPreview = nil; menu.refresh() end, true)
    end
    if menu.supplyApplyResult then local result = tableWidget:addRow(false); result[1]:setColSpan(4):createText(menu.supplyApplyResult, { wordwrap = true, color = (menu.supplyApplyResult:find("APPLIED", 1, true) == 1 or menu.supplyApplyResult:find(" 0 failed", 1, true)) and investigationPassColor or investigationFailColor }) end
end

function menu.supplyModelCenter(tableWidget)
    menu.supplyView = menu.supplyView or "home"
    if menu.supplyView == "home" then menu.supplyNavigation(tableWidget); return end
    local current, previous = menu.supplyViewSnapshots(menu.supplyView)
    if menu.supplyView == "station" or menu.supplyView == "settings" then
        menu.supplySelectedStationView(tableWidget, menu.supplyView, current, previous)
    else
        menu.supplyOverviewView(tableWidget, menu.supplyView, current, previous)
    end
end

local function createHeader(frame, parentWidth)
    local titleHeight = Helper.scaleY(42)
    local tabHeight = Helper.scaleY(38)
    local headerHeight = titleHeight + tabHeight
    local usableWidth = parentWidth - 2 * Helper.borderSize
    local tableWidget = frame:addTable(11, {
        tabOrder = 1,
        x = Helper.borderSize,
        y = Helper.borderSize,
        width = usableWidth,
        borderEnabled = true,
    })
    local columnWidth = math.floor(usableWidth / 11)

    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setColWidth(4, columnWidth, false)
    tableWidget:setColWidth(5, columnWidth, false)
    tableWidget:setColWidth(6, columnWidth, false)
    tableWidget:setColWidth(7, columnWidth, false)
    tableWidget:setColWidth(8, columnWidth, false)
    tableWidget:setColWidth(9, columnWidth, false)
    tableWidget:setColWidth(10, columnWidth, false)

    local row = tableWidget:addRow(false, { fixed = true })
    row[1]:setColSpan(11):createText(menu.title, {
        halign = "center",
        font = Helper.titleFont,
        fontsize = Helper.standardFontSize + 4,
    })

    row = tableWidget:addRow(true, { fixed = true })
    addTabButton(row, 1, "STATIONS", "stations")
    addTabButton(row, 2, "OVERVIEW", "dashboard")
    addTabButton(row, 3, "KPI CENTER", "kpi")
    addTabButton(row, 4, "SUPPLY MODEL", "supply")
    addTabButton(row, 5, "FLEET & LOGISTICS", "fleet")
    addTabButton(row, 6, "DIAGNOSTICS", "diagnostics")
    addTabButton(row, 7, "SOLUTION PLANNER", "solution")
    addTabButton(row, 8, "CONSTRUCTION", "construction")
    addTabButton(row, 9, "CASES", "cases")
    addTabButton(row, 10, "REPORTS", "reports")
    addTabButton(row, 11, "GLOBAL SETTINGS", "settings")

    local activeColumns = {
        stations = 1,
        dashboard = 2,
        kpi = 3,
        supply = 4,
        fleet = 5,
        diagnostics = 6,
        solution = 7,
        construction = 8,
        cases = 9,
        reports = 10,
        settings = 11,
    }
    tableWidget:setSelectedRow(2)
    tableWidget:setSelectedCol(activeColumns[menu.activeTab or menu.page] or 2)

    tableWidget.properties.maxVisibleHeight = headerHeight
    return headerHeight
end

local function solutionPlannerCenter(tableWidget)
    local caseData = menu.solutionCase or menu.diagnosticCase
    if menu.diagnosticCase and (not caseData or (
        text(v(caseData, 1, "")) == text(v(menu.diagnosticCase, 1, ""))
        and text(v(caseData, 3, "")) == text(v(menu.diagnosticCase, 3, ""))
        and text(v(caseData, 4, "")) == text(v(menu.diagnosticCase, 4, ""))
    )) then
        if caseData ~= menu.diagnosticCase then
            DebugError("[JKEOC][B289][PLANNER_CONTEXT_REFRESH] station=" .. text(v(menu.diagnosticCase, 1, "")) .. " ware=" .. text(v(menu.diagnosticCase, 4, "")) .. " source=fresh_diagnostic_case")
        end
        caseData = menu.diagnosticCase
        menu.solutionCase = caseData
    end
    if not caseData then
        local standalonePlan = menu.solutionAgreedStandaloneKey and menu.agreedBuildPlans and menu.agreedBuildPlans[menu.solutionAgreedStandaloneKey] or nil
        if standalonePlan then
            menu.renderAgreedBuildList(tableWidget, standalonePlan, menu.savedPlanLiveRows(standalonePlan), "", nil, nil)
            return
        end
        section(tableWidget, "SOLUTION PLANNER — COMMAND FIRST")
        local emptyCommand = tableWidget:addRow(false)
        emptyCommand[1]:setColSpan(4):createText("EOC CONCLUSION: No station case is loaded.", { wordwrap = true, color = investigationUnknownColor, font = Helper.headerFont })
        local emptyNext = tableWidget:addRow(false)
        emptyNext[1]:setColSpan(4):createText("DO THIS NEXT: Open Diagnostics and select the case that needs a permanent-solution review.", { wordwrap = true })
        local savedPlans = {}
        for key, plan in pairs(menu.agreedBuildPlans or {}) do savedPlans[#savedPlans + 1] = { key=key, plan=plan } end
        table.sort(savedPlans, function(a, b) return (a.plan.station .. "|" .. a.plan.ware) < (b.plan.station .. "|" .. b.plan.ware) end)
        if #savedPlans > 0 then
            local savedPageCount = math.max(1, math.ceil(#savedPlans / 6))
            menu.agreedIndexPage = math.max(1, math.min(tonumber(menu.agreedIndexPage) or 1, savedPageCount))
            section(tableWidget, "SAVED AGREED BUILD LISTS" .. (savedPageCount > 1 and (" - PAGE " .. tostring(menu.agreedIndexPage) .. " OF " .. tostring(savedPageCount)) or ""))
            local savedFirst = (menu.agreedIndexPage - 1) * 6 + 1
            local savedLast = math.min(#savedPlans, savedFirst + 5)
            for index = savedFirst, savedLast do
                local saved = savedPlans[index]
                local savedAction = tableWidget:addRow(true)
                savedAction[1]:setColSpan(4)
                menu.addPrimaryButton(savedAction, 1, "OPEN SAVED LIST - " .. saved.plan.station .. " -> " .. saved.plan.ware, function()
                    menu.solutionAgreedStandaloneKey = saved.key
                    menu.agreedBuildPage = 1
                    menu.refresh()
                end, true)
            end
            if savedPageCount > 1 then
                local savedPager = tableWidget:addRow(true)
                savedPager[1]:setColSpan(2); addButton(savedPager, 1, "PREVIOUS SAVED LISTS", function() menu.agreedIndexPage = math.max(1, menu.agreedIndexPage - 1); menu.refresh() end, menu.agreedIndexPage > 1)
                savedPager[3]:setColSpan(2); addButton(savedPager, 3, "NEXT SAVED LISTS", function() menu.agreedIndexPage = math.min(savedPageCount, menu.agreedIndexPage + 1); menu.refresh() end, menu.agreedIndexPage < savedPageCount)
            end
        end
        local emptyAction = tableWidget:addRow(true)
        emptyAction[1]:setColSpan(4)
        menu.addPrimaryButton(emptyAction, 1, "OPEN DIAGNOSTICS", function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end, true)
        return
    end

    local commandPlannerReady, commandPlannerReason = menu.plannerAccessForCase(caseData)
    local commandReadiness = menu.expansionReadiness
    local commandReadinessMatches = commandReadiness and commandReadiness.key == checklistCaseKey(caseData) and commandReadiness.evidenceKey == expansionEvidenceKey(caseData)
    local commandNativePlan = commandReadinessMatches and commandReadiness.nativePlan or nil
    local commandProjectDemandUnknown = commandNativePlan and commandNativePlan.projectDemandUnmeasured
    local commandScenarioMode = commandProjectDemandUnknown == true
    local commandSimplePlan = commandNativePlan and commandNativePlan.checklist and commandNativePlan.checklist.simplePlan or {}
    local commandCascadePassed = not commandNativePlan or not commandNativePlan.checklist or commandNativePlan.checklist.cascadePassed ~= false
    local commandCascadeReason = commandNativePlan and commandNativePlan.checklist and commandNativePlan.checklist.cascadeReason or "No cascade evidence is loaded."
    local commandSupportRequirement = nil
    if commandNativePlan and commandNativePlan.checklist and (tonumber(v(caseData, 15, 0)) or 0) > 0 then
        for _, item in ipairs(commandNativePlan.checklist.items or {}) do
            if (tonumber(item.depth) or 0) > 0 and (item.state == "REQUIRED" or item.state == "SOURCE REQUIRED") then
                commandSupportRequirement = item
                break
            end
        end
    end
    local commandKey = checklistCaseKey(caseData)
    local calculatorKey = commandKey .. "|" .. expansionEvidenceKey(caseData)
    menu.plannerModuleDrafts = menu.plannerModuleDrafts or {}
    menu.plannerModuleDrafts[calculatorKey] = menu.plannerModuleDrafts[calculatorKey] or { counts = {}, result = nil, dirty = false }
    local calculatorState = menu.plannerModuleDrafts[calculatorKey]
    for _, item in ipairs(commandSimplePlan) do
        if item.wareId and calculatorState.counts[menu.supplyWareId(item.wareId)] == nil then calculatorState.counts[menu.supplyWareId(item.wareId)] = "0" end
    end
    local showingDeepDive = menu.solutionDeepDiveKey == commandKey
    local agreedWareId = commandNativePlan and commandNativePlan.ware or v(caseData, 40, "")
    local agreedKey = agreedWareId ~= "" and menu.agreedPlanKey(text(v(caseData, 1, "")), agreedWareId) or ""
    local savedAgreedPlan = agreedKey ~= "" and menu.agreedBuildPlans and menu.agreedBuildPlans[agreedKey] or nil
    local showingAgreedPlan = savedAgreedPlan and menu.solutionAgreedKey == commandKey
    local deepDivePage = math.max(1, math.min(2, tonumber(menu.solutionDeepDivePage) or 1))
    local commandConclusion, commandNext, commandActionLabel, commandAction
    if not commandPlannerReady then
        commandConclusion = "EOC CONCLUSION: Immediate recovery testing is not finished. Permanent construction is locked."
        commandNext = "DO THIS NEXT: Return to Diagnostics and complete the bounded recovery and verification cycle."
        commandActionLabel = "RETURN TO DIAGNOSTICS — CONTINUE RECOVERY"
        commandAction = function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end
    elseif not commandReadinessMatches then
        commandConclusion = "EOC CONCLUSION: Temporary recovery is exhausted or an existing plan needs review, but EOC has not checked permanent-solution prerequisites yet."
        commandNext = "DO THIS NEXT: Run the read-only readiness check. It changes nothing."
        commandActionLabel = "RUN READ-ONLY READINESS CHECK"
        commandAction = function() menu.runExpansionReadiness(caseData); menu.refresh() end
    elseif (commandReadiness.notReady or 0) > 0 then
        commandConclusion = "EOC CONCLUSION: Permanent construction is NOT READY because a required condition failed."
        commandNext = "DO THIS NEXT: Return to Diagnostics, correct the failed condition, and run fresh verification."
        commandActionLabel = "RETURN TO DIAGNOSTICS — CORRECT FAILED CONDITION"
        commandAction = function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end
    elseif commandProjectDemandUnknown then
        commandConclusion = "EOC CONCLUSION: Project demand exists, but EOC cannot convert it into a safe hourly production requirement. A calculated zero is not a zero-module recommendation."
        commandNext = "DO THIS NEXT: X4 has not supplied a measurable demand rate, so EOC cannot recommend a count. Use the PLAYER SCENARIO calculator below to choose a final-output module count and check its complete support chain, or return to Diagnostics to review the active project."
        commandActionLabel = "RETURN TO DIAGNOSTICS — REVIEW ACTIVE PROJECT"
        commandAction = function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end
    elseif commandPlannerReason == "PLANNED_PRODUCTION_REVIEW" or (tonumber(v(caseData, 34, 0)) or 0) > 0 then
        commandConclusion = "EOC CONCLUSION: Matching production is already planned. Do not add duplicate capacity."
        commandNext = "DO THIS NEXT: Review and finish the existing X4 Station Build Plan, then verify the result."
        commandActionLabel = "OPEN EOC CONSTRUCTION STATUS"
        commandAction = function() menu.page = "construction"; menu.activeTab = "construction"; menu.refresh() end
    elseif commandSupportRequirement then
        commandConclusion = "EOC CONCLUSION: Existing " .. text(v(caseData, 4, "final-output")) .. " production is installed, but its supporting production chain is incomplete. Do not add duplicate final-output capacity."
        commandNext = "DO THIS NEXT: Use the simple build list below. It gives the best current estimate of how many production modules to add. Open Deep Dive only when you want the evidence and calculations."
        commandActionLabel = "ADVANCED - BUILD DETAILS"
        commandAction = function() menu.solutionDeepDiveKey = checklistCaseKey(caseData); menu.solutionDeepDivePage = 1; menu.refresh() end
    elseif commandNativePlan and commandNativePlan.moduleCount > 0 then
        commandConclusion = "EOC CONCLUSION: Current measured station demand supports a cautious review of " .. tostring(commandNativePlan.moduleCount) .. " additional production module(s)."
        commandNext = "DO THIS NEXT: Review the native recipe and prerequisites in Deep Dive before committing anything in X4."
        commandActionLabel = "DEEP DIVE — EVIDENCE AND ANALYSIS"
        commandAction = function() menu.solutionDeepDiveKey = checklistCaseKey(caseData); menu.solutionDeepDivePage = 1; menu.refresh() end
    else
        commandConclusion = "EOC CONCLUSION: Measured station consumption does not currently prove a need for another production module."
        commandNext = "DO THIS NEXT: Do not add capacity from this snapshot. Ask EOC to test the case; EOC will return when later demand evidence supports an answer."
        commandActionLabel = "RETURN TO DIAGNOSTICS — VERIFY LATER"
        commandAction = function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end
    end
    if showingAgreedPlan then
        local savedScenarioMode = string.find(string.upper(text(savedAgreedPlan.status)), "PLAYER SCENARIO", 1, true) ~= nil
        local savedCurrentPlan = savedScenarioMode and menu.savedPlanLiveRows(savedAgreedPlan) or commandSimplePlan
        menu.renderAgreedBuildList(tableWidget, savedAgreedPlan, savedCurrentPlan, commandKey, caseData, commandNativePlan)
        return
    end
    if not showingDeepDive then
        section(tableWidget, "SOLUTION PLANNER — COMMAND FIRST")
        if commandReadinessMatches then
            local refreshRow = tableWidget:addRow(false)
            refreshRow[1]:setColSpan(4):createText("DRAFT MODE: Automatic evidence refresh is paused while you calculate or review details. Save and open the build list when you want EOC to watch construction and workforce progress.", { wordwrap = true, color = navigationStoryColor })
        end
        local conclusionRow = tableWidget:addRow(false)
        conclusionRow[1]:setColSpan(4):createText(commandConclusion, { wordwrap = true, color = commandProjectDemandUnknown and investigationUnknownColor or navigationStoryColor, font = Helper.headerFont })
        local nextRow = tableWidget:addRow(false)
        nextRow[1]:setColSpan(4):createText(commandNext, { wordwrap = true })
        if savedAgreedPlan then
            local savedRow = tableWidget:addRow(true)
            savedRow[1]:setColSpan(4)
            menu.addPrimaryButton(savedRow, 1, "OPEN SAVED AGREED BUILD LIST", function()
                menu.solutionAgreedKey = commandKey
                menu.agreedBuildPage = 1
                menu.refresh()
            end, true)
        end
        if commandReadinessMatches and #commandSimplePlan > 0 then
            local displayedPlan = calculatorState.result and calculatorState.result.rows or commandSimplePlan
            for _, item in ipairs(displayedPlan) do
                if item.wareId and calculatorState.counts[menu.supplyWareId(item.wareId)] == nil then calculatorState.counts[menu.supplyWareId(item.wareId)] = "0" end
            end
            local simplePageSize = 6
            local simplePageCount = math.max(1, math.ceil(#displayedPlan / simplePageSize))
            menu.plannerSimplePage = math.max(1, math.min(tonumber(menu.plannerSimplePage) or 1, simplePageCount))
            section(tableWidget, (commandScenarioMode and "PLAYER SCENARIO - CHOOSE FINAL MODULE COUNT" or "WHAT TO ADD - BEST CURRENT ESTIMATE") .. (simplePageCount > 1 and (" - PAGE " .. tostring(menu.plannerSimplePage) .. " OF " .. tostring(simplePageCount)) or ""))
            local activeCascadePassed = calculatorState.result and calculatorState.result.cascadePassed or commandCascadePassed
            local activeCascadeReason = calculatorState.result and calculatorState.result.cascadeReason or commandCascadeReason
            local cascadeRow = tableWidget:addRow(false)
            local cascadeText = commandScenarioMode and not calculatorState.result and "PLAYER SCENARIO READY: Choose at least one final-output module and check the plan. EOC will calculate the bounded native support cascade without claiming that X4 demand proves your chosen count." or ((activeCascadePassed and "CASCADE CHECK COMPLETE: " or "CASCADE GATE STOPPED - ESTIMATE INCOMPLETE: ") .. activeCascadeReason)
            cascadeRow[1]:setColSpan(4):createText(cascadeText, { wordwrap = true, color = activeCascadePassed and investigationPassColor or investigationFailColor })
            local calculatorGuide = tableWidget:addRow(false)
            calculatorGuide[1]:setColSpan(4):createText(calculatorState.dirty and "YOUR PLAN CHANGED: Press TAB after the number, then select CHECK MY MODULE PLAN again. The prior result is stale." or (commandScenarioMode and "PROJECT DEMAND IS UNKNOWN: Enter how many final-output modules you are considering, press TAB, then select CHECK MY MODULE PLAN. EOC will calculate the supporting modules and safety gates; it does not claim your chosen final count is required." or "TRY YOUR OWN PLAN: Type how many modules you intend to add, press TAB after each number, then select CHECK MY MODULE PLAN. EOC changes no station or build plan."), { wordwrap = true, color = calculatorState.dirty and investigationFailColor or navigationStoryColor })
            local simpleFirst = (menu.plannerSimplePage - 1) * simplePageSize + 1
            local simpleLast = math.min(#displayedPlan, simpleFirst + simplePageSize - 1)
            for simpleIndex = simpleFirst, simpleLast do
                local item = displayedPlan[simpleIndex]
                local recommended = item.recommended ~= nil and item.recommended or item.additional
                local wareId = menu.supplyWareId(item.wareId or "")
                local playerCount = math.max(0, math.floor((tonumber(calculatorState.counts[wareId]) or 0) + 0.5))
                local simpleRow = tableWidget:addRow(false)
                if recommended ~= nil and item.editable ~= false then
                    local comparison = commandScenarioMode and item.finalOutput and (calculatorState.result and ("PLAYER SCENARIO COUNT " .. tostring(playerCount) .. " - NOT AN EOC DEMAND ESTIMATE") or "CHOOSE YOUR COUNT - EOC DEMAND ESTIMATE UNKNOWN") or (calculatorState.result and (playerCount > recommended and ("TOO MANY BY ABOUT " .. tostring(playerCount - recommended)) or (playerCount < recommended and ("ADD ABOUT " .. tostring(recommended - playerCount) .. " MORE") or "MATCHES CURRENT ESTIMATE")) or ("EOC ESTIMATE: ADD ABOUT " .. tostring(recommended)))
                    local simpleText = (item.module ~= "" and item.module or item.ware) .. " | " .. comparison
                    if item.finalOutput then simpleText = simpleText .. " | INSTALLED " .. tostring(item.installed or 0) .. " | ALREADY PLANNED " .. tostring(item.planned or 0) end
                    if item.kind == "HABITAT" then simpleText = simpleText .. " | " .. formatNumber(item.capacityPerModule or 0) .. " WORKFORCE EACH | ALREADY PLANNED " .. tostring(item.planned or 0) end
                    simpleRow[1]:setColSpan(2):createText(simpleText, { wordwrap = true, color = calculatorState.result and playerCount ~= recommended and investigationFailColor or investigationPassColor, font = Helper.headerFont })
                    simpleRow[3]:createText("YOU PLAN TO ADD", { color = navigationStoryColor })
                    simpleRow[4]:createEditBox({ height = Helper.standardButtonHeight }):setText(tostring(calculatorState.counts[wareId] or "0"))
                    simpleRow[4].handlers.onEditBoxDeactivated = function(_, entered)
                        calculatorState.counts[wareId] = tostring(math.max(0, math.min(999, math.floor((tonumber(entered) or 0) + 0.5))))
                        calculatorState.dirty = true
                        menu.plannerSaveStatus = nil
                    end
                    if item.kind == "HABITAT" then
                        local supplyRow = tableWidget:addRow(false)
                        supplyRow[1]:setColSpan(4):createText("WORKFORCE SUPPLIES - INFORMATION ONLY, NOT MODULE COUNTS: " .. (item.provisionScope and item.provisionScope ~= "" and item.provisionScope or "Exact future provision wares remain unknown until workers arrive."), { wordwrap = true, color = navigationStoryColor })
                    end
                else
                    simpleRow[1]:setColSpan(4):createText(item.ware .. ": NO PRODUCTION-MODULE COUNT AVAILABLE | PROVIDE ABOUT " .. formatNumber(item.requiredRate or 0) .. "/h BY THE SOURCE ROUTE SHOWN IN ADVANCED DETAILS", { wordwrap = true, color = investigationUnknownColor, font = Helper.headerFont })
                end
            end
            if simplePageCount > 1 then
                local simplePager = tableWidget:addRow(true)
                simplePager[1]:setColSpan(2)
                addButton(simplePager, 1, "PREVIOUS BUILD-LIST PAGE", function() menu.plannerSimplePage = math.max(1, menu.plannerSimplePage - 1); menu.refresh() end, menu.plannerSimplePage > 1)
                simplePager[3]:setColSpan(2)
                addButton(simplePager, 3, "NEXT BUILD-LIST PAGE", function() menu.plannerSimplePage = math.min(simplePageCount, menu.plannerSimplePage + 1); menu.refresh() end, menu.plannerSimplePage < simplePageCount)
            end
            if calculatorState.result then
                local resultRow = tableWidget:addRow(false)
                resultRow[1]:setColSpan(4):createText(calculatorState.result.summary, { wordwrap = true, color = #(calculatorState.result.warnings or {}) == 0 and investigationPassColor or investigationFailColor, font = Helper.headerFont })
                for warningIndex = 1, math.min(3, #(calculatorState.result.globalWarnings or {})) do
                    local warningRow = tableWidget:addRow(false)
                    warningRow[1]:setColSpan(4):createText(calculatorState.result.globalWarnings[warningIndex], { wordwrap = true, color = investigationFailColor })
                end
                if #(calculatorState.result.globalWarnings or {}) > 3 then
                    local moreWarnings = tableWidget:addRow(false)
                    moreWarnings[1]:setColSpan(4):createText(tostring(#calculatorState.result.globalWarnings - 3) .. " more non-module warning(s) remain; open Advanced Evidence and Math.", { wordwrap = true, color = investigationUnknownColor })
                end
                if calculatorState.result.workforceNote and calculatorState.result.workforceNote ~= "" then
                    local workforceNoteRow = tableWidget:addRow(false)
                    workforceNoteRow[1]:setColSpan(4):createText(calculatorState.result.workforceNote, { wordwrap = true, color = navigationStoryColor })
                end
            end
            local calculatorRow = tableWidget:addRow(true)
            calculatorRow[1]:setColSpan(2)
            menu.addPrimaryButton(calculatorRow, 1, "CHECK MY MODULE PLAN", function()
                calculatorState.result = menu.evaluateModulePlan(commandNativePlan, caseData, calculatorState.counts)
                calculatorState.dirty = false
                menu.plannerSaveStatus = nil
                menu.plannerSimplePage = 1
                menu.refresh()
            end, true)
            calculatorRow[3]:setColSpan(2)
            addButton(calculatorRow, 3, "CLEAR MY PLAN", function()
                calculatorState.counts = {}
                for _, item in ipairs(commandSimplePlan) do if item.wareId then calculatorState.counts[menu.supplyWareId(item.wareId)] = "0" end end
                calculatorState.result = nil
                calculatorState.dirty = false
                menu.plannerSaveStatus = nil
                menu.plannerSimplePage = 1
                menu.refresh()
            end, true)
            local canSaveAgreement = calculatorState.result and not calculatorState.dirty and calculatorState.result.cascadePassed and (tonumber(calculatorState.result.moduleIssues) or 0) == 0
            local saveRow = tableWidget:addRow(true)
            saveRow[1]:setColSpan(4)
            local saveLabel = commandScenarioMode and (savedAgreedPlan and "REPLACE SAVED PLAYER SCENARIO" or "SAVE PLAYER SCENARIO BUILD LIST") or (savedAgreedPlan and "REPLACE SAVED AGREED BUILD LIST" or "SAVE AGREED BUILD LIST")
            menu.addPrimaryButton(saveRow, 1, saveLabel, function()
                local saveResult = calculatorState.result
                if calculatorState.dirty or type(saveResult) ~= "table" or type(saveResult.rows) ~= "table" or not saveResult.cascadePassed or (tonumber(saveResult.moduleIssues) or 0) ~= 0 then
                    menu.plannerSaveStatus = "SAVE NOT RECORDED: Press TAB after every changed number, then select CHECK MY MODULE PLAN again before saving. Your previous checked counts were not saved."
                    DebugError("[JKEOC][B356][AGREED_SAVE_BLOCKED_STALE_RESULT] station=" .. text(v(caseData, 1, "Selected station")) .. " dirty=" .. tostring(calculatorState.dirty) .. " result=" .. tostring(type(saveResult)) .. " construction_authority=0")
                    menu.refresh()
                    return
                end
                local plan, payload = menu.makeAgreedBuildPlan(commandNativePlan, caseData, saveResult, expansionEvidenceKey(caseData))
                if not plan or not payload then
                    menu.plannerSaveStatus = "SAVE NOT RECORDED: The checked plan is no longer available. Select CHECK MY MODULE PLAN again; EOC did not save old counts."
                    DebugError("[JKEOC][B356][AGREED_SAVE_BLOCKED_MISSING_RESULT] station=" .. text(v(caseData, 1, "Selected station")) .. " construction_authority=0")
                    menu.refresh()
                    return
                end
                menu.plannerSaveStatus = nil
                menu.pendingAgreedPlan = { key=agreedKey, plan=plan, commandKey=commandKey }
                raise("planner.agreed.save", payload)
            end, canSaveAgreement)
            if menu.plannerSaveStatus then
                local saveStatusRow = tableWidget:addRow(false)
                saveStatusRow[1]:setColSpan(4):createText(menu.plannerSaveStatus, { wordwrap = true, color = investigationFailColor, font = Helper.headerFont })
            end
            if calculatorState.result and not canSaveAgreement then
                local saveGuide = tableWidget:addRow(false)
                saveGuide[1]:setColSpan(4):createText(calculatorState.dirty and "SAVE LOCKED: Press TAB after the changed number and check the module plan again." or (commandScenarioMode and "SAVE LOCKED: Choose at least one final-output module, match every calculated support count, and complete the cascade before saving this player scenario." or "SAVE LOCKED: EOC and player module counts must match and the cascade must complete before this becomes the remembered build list."), { wordwrap = true, color = investigationFailColor })
            end
        end
        local commandRow = tableWidget:addRow(true)
        commandRow[1]:setColSpan(2)
        menu.addPrimaryButton(commandRow, 1, commandActionLabel, commandAction, true)
        commandRow[3]:setColSpan(2)
        addButton(commandRow, 3, "ADVANCED - EVIDENCE AND MATH", function()
            menu.solutionDeepDiveKey = commandKey
            menu.solutionDeepDivePage = 1
            menu.refresh()
        end, true)
        return
    end

    local deepDiveReadiness = menu.expansionReadiness
    local deepDiveNativePlan = deepDiveReadiness and deepDiveReadiness.nativePlan
    local deepDiveResourceCount = deepDiveNativePlan and deepDiveNativePlan.selected and #(deepDiveNativePlan.selected.resources or {}) or 0
    local deepDiveChecklistCount = deepDiveNativePlan and deepDiveNativePlan.checklist and #(deepDiveNativePlan.checklist.items or {}) or 2
    local deepDiveReadinessCount = deepDiveReadiness and #(deepDiveReadiness.rows or {}) or 0
    local deepDiveRowPitch = math.max(1, Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize)
    -- Word-wrapped safety, evidence, and recipe rows commonly consume more than
    -- one standard row. Budget them before creating the table so X4 never has
    -- to reject an already-overheight table.
    local deepDiveRequiredUnits = 30 + (2 * deepDiveReadinessCount) + (2 * deepDiveResourceCount) + (2 * math.min(5, deepDiveChecklistCount))
    local deepDiveRequiredPixels = deepDiveRequiredUnits * deepDiveRowPitch
    local deepDiveAvailablePixels = tonumber(menu.listContentHeight) or Helper.scaleY(config.maxHeight)
    local deepDiveNeedsPaging = deepDiveRequiredPixels > deepDiveAvailablePixels
    if not deepDiveNeedsPaging then deepDivePage = 1 end
    menu.solutionDeepDivePage = deepDivePage
    DebugError("[JKEOC][B349][PLANNER_PIXEL_BUDGET] required=" .. tostring(deepDiveRequiredPixels) .. " available=" .. tostring(deepDiveAvailablePixels) .. " readiness=" .. tostring(deepDiveReadinessCount) .. " resources=" .. tostring(deepDiveResourceCount) .. " checklist=" .. tostring(deepDiveChecklistCount) .. " pages=" .. tostring(deepDiveNeedsPaging and 2 or 1) .. " active=" .. tostring(deepDivePage))

    if deepDivePage == 1 then
        section(tableWidget, "STATION SOLUTION PLANNER")
        local safetyBanner = tableWidget:addRow(false)
        safetyBanner[1]:setColSpan(4):createText("TEST ESCALATION SAFETY: Do not use permanent construction as a shortcut around an active station problem. EOC unlocks new-capacity recommendations only after immediate recovery evidence is exhausted. When matching production is already planned, EOC permits review of that existing plan and its supporting recipe without authorizing duplicate capacity. HQ, mixed-purpose, and build-everything stations require special caution because added modules can duplicate capacity, compete for inputs, and worsen shared-storage pressure.", { wordwrap = true, color = investigationFailColor })
    end
    if not caseData then
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("No case is loaded. Open Diagnostics, exhaust the immediate recovery checks, then select OPEN PLANNER on the permanent-solution step.", { wordwrap = true, color = investigationUnknownColor })
        return
    end
    local plannerReady, plannerReason = menu.plannerAccessForCase(caseData)
    local warning = deepDivePage == 1 and tableWidget:addRow(false) or nil
    local plannerWarning = plannerReason == "PLANNED_PRODUCTION_REVIEW"
        and "PLANNED-PRODUCTION REVIEW: X4 already reports matching production in this station's build plan. EOC may show the exact native recipe and supporting requirements so you can review the committed plan. This does not prove the earlier recovery test passed and does not authorize duplicate modules; finish and verify the existing plan first."
        or (plannerReady and "ESCALATION WARNING: EOC has exhausted the immediate recovery evidence it can test: a bounded BUY offer remained active for the full 30-minute delivery-test window, reachable supply and compatible station traders were present, and stock did not rise. This planner is advisory. Review the station's existing build plan before adding anything; complex mixed-purpose stations and HQ-style build-everything stations can be made worse by duplicate modules, input competition, or shared-storage pressure." or "PLANNER LOCKED: EOC has not exhausted immediate recovery testing for this case. Return to Diagnostics and let the bounded BUY action complete its 30-minute delivery-test window. EOC must confirm reachable supply, compatible station traders, a later reconciliation, and no stock increase before permanent construction advice is shown. Do not expand this station yet.")
    if warning then warning[1]:setColSpan(4):createText(plannerWarning, { wordwrap = true, color = plannerReady and investigationUnknownColor or investigationFailColor }) end
    if not plannerReady then
        local lockedRow = tableWidget:addRow(true)
        lockedRow[1]:setColSpan(4)
        addButton(lockedRow, 1, "RETURN TO DIAGNOSTICS - CONTINUE EOC TESTING", function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end, true)
        return
    end
    local readiness = menu.expansionReadiness
    local readinessMatches = readiness and readiness.key == checklistCaseKey(caseData) and readiness.evidenceKey == expansionEvidenceKey(caseData)
    if not readinessMatches then
        local required = tableWidget:addRow(false)
        required[1]:setColSpan(4):createText("EXPANSION READINESS CHECK REQUIRED: Before EOC shows any permanent recommendation, it will review the evidence it can prove for this exact station and ware and identify every condition X4 still requires you to inspect. The check is read-only and changes nothing.", { wordwrap = true, color = investigationUnknownColor })
        local checkRow = tableWidget:addRow(true)
        checkRow[1]:setColSpan(4)
        addButton(checkRow, 1, "RUN EXPANSION READINESS CHECK", function() menu.runExpansionReadiness(caseData); menu.refresh() end, true, currentChoiceBackground)
        return
    end
    if deepDivePage == 1 then
        section(tableWidget, "EXPANSION READINESS CHECK - " .. readiness.summary)
        local readinessSummary = tableWidget:addRow(false)
        readinessSummary[1]:setColSpan(4):createText("EOC checked the current case evidence before showing a plan: " .. tostring(readiness.notReady or 0) .. " not ready | " .. tostring(readiness.warnings or 0) .. " warning(s) | " .. tostring(readiness.unknown or 0) .. " condition(s) EOC cannot prove. CANNOT PROVE is not a pass; follow the stated vanilla-editor check before building.", { wordwrap = true, color = (readiness.notReady or 0) > 0 and investigationFailColor or investigationUnknownColor })
        for _, item in ipairs(readiness.rows or {}) do
            local itemRow = tableWidget:addRow(false)
            local itemColor = item.state == "PASS" and investigationPassColor or (item.state == "NOT READY" and investigationFailColor or investigationUnknownColor)
            itemRow[1]:setColSpan(4):createText(item.state .. " - " .. item.label .. ": " .. item.evidence, { wordwrap = true, color = itemColor })
        end
    end
    if (readiness.notReady or 0) > 0 then
        local blocked = tableWidget:addRow(false)
        blocked[1]:setColSpan(4):createText("PLAN NOT READY: 1. Read the failed check above. 2. Fix that exact problem. 3. Open Diagnostics and run Fresh Empire Analysis once. 4. Return here only after the check passes. EOC will not suggest construction while a required check is failing.", { wordwrap = true, color = investigationFailColor })
        local returnRow = tableWidget:addRow(true)
        returnRow[1]:setColSpan(4)
        addButton(returnRow, 1, "RETURN TO DIAGNOSTICS", function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end, true)
        return
    end
    if deepDiveNeedsPaging and deepDivePage == 1 then
        local nextPage = tableWidget:addRow(true)
        nextPage[1]:setColSpan(4)
        menu.addPrimaryButton(nextPage, 1, "NEXT - MODULE, RECIPE, AND SUPPORT CHAIN", function() menu.solutionDeepDivePage = 2; menu.refresh() end, true)
        return
    end
    if deepDiveNeedsPaging then
        section(tableWidget, "SOLUTION PLANNER - PAGE 2 OF 2")
        local previousPage = tableWidget:addRow(true)
        previousPage[1]:setColSpan(4)
        addButton(previousPage, 1, "PREVIOUS - READINESS AND SAFETY", function() menu.solutionDeepDivePage = 1; menu.refresh() end, true)
    end
    local stationName = text(v(caseData, 1, "Selected station"))
    local ware = text(v(caseData, 4, "affected ware"))
    local produces = tonumber(v(caseData, 15, 0)) or 0
    local suppliers = tonumber(v(caseData, 18, 0)) or 0
    local ownedSuppliers = tonumber(v(caseData, 19, 0)) or 0
    local compatible = tonumber(v(caseData, 24, 0)) or 0
    local missingInputs = tonumber(v(caseData, 27, 0)) or 0
    local missingNames = text(v(caseData, 28, "No proven missing input name"))
    local planned = tonumber(v(caseData, 34, 0)) or 0
    section(tableWidget, stationName .. " -> " .. ware)
    pair(tableWidget, "LOCAL PRODUCTION", tostring(produces) .. " installed", "ALREADY PLANNED", tostring(planned) .. " matching module(s)")
    pair(tableWidget, "REACHABLE SUPPLY", tostring(suppliers) .. " offer(s), " .. tostring(ownedSuppliers) .. " owned", "DELIVERY CAPACITY", tostring(compatible) .. " compatible station trader(s)")
    pair(tableWidget, "KNOWN INPUT GAP", missingInputs > 0 and missingNames or "None proven in current evidence", "PLANNER MODE", "ADVISORY - NO BUILD AUTHORITY")
    local nativePlan = readiness.nativePlan
    if nativePlan and nativePlan.state == "OWNED" and nativePlan.selected then
        section(tableWidget, "NATIVE X4 MODULE, BLUEPRINT, METHOD, AND CAPACITY")
        pair(tableWidget, "MODULE", nativePlan.selected.name, "OWNED BLUEPRINT", nativePlan.selected.blueprintName)
        pair(tableWidget, "PRODUCTION METHOD", nativePlan.selected.method, "WORKFORCE PER MODULE", formatNumber(nativePlan.selected.maxworkforce))
        pair(tableWidget, "ONE-MODULE OUTPUT", formatNumber(nativePlan.selected.outputPerHour) .. " " .. ware .. "/h", "NET STATION DEFICIT", formatNumber(nativePlan.deficitPerHour) .. " " .. ware .. "/h")
        pair(tableWidget, "LIVE CONSUMPTION", formatNumber(nativePlan.consumptionPerHour) .. "/h", "CURRENT INSTALLED OUTPUT", formatNumber(nativePlan.productionPerHour) .. "/h")
        local countRow = tableWidget:addRow(false)
        local capacityText = nativePlan.projectDemandUnmeasured
            and "RECOMMENDED CAPACITY: UNKNOWN. Project-driven demand was not exposed as an hourly station-consumption rate, so the calculated zero cannot justify a zero-module conclusion. Confirm the active project demand before planning capacity."
            or (nativePlan.moduleCount > 0 and ("RECOMMENDED CAPACITY: Plan " .. tostring(nativePlan.moduleCount) .. " " .. nativePlan.selected.name .. " module(s). X4 output math: ceil(" .. formatNumber(nativePlan.deficitPerHour) .. " / " .. formatNumber(nativePlan.selected.outputPerHour) .. ") = " .. tostring(nativePlan.moduleCount) .. ".") or ("RECOMMENDED CAPACITY: 0 additional modules. Current native hourly output already meets or exceeds measured hourly consumption; construction is not justified by this snapshot."))
        countRow[1]:setColSpan(4):createText(capacityText, { wordwrap = true, color = (nativePlan.projectDemandUnmeasured or nativePlan.moduleCount > 0) and investigationUnknownColor or investigationPassColor })
        section(tableWidget, "FULL PER-MODULE PRODUCTION DEPENDENCIES")
        if #(nativePlan.selected.resources or {}) == 0 then
            local resourceRow = tableWidget:addRow(false)
            resourceRow[1]:setColSpan(4):createText("No primary production inputs were returned by X4 for this module/method.", { wordwrap = true })
        else
            for _, resource in ipairs(nativePlan.selected.resources) do
                local resourceRow = tableWidget:addRow(false)
                local totalRequirement = nativePlan.projectDemandUnmeasured and "UNKNOWN until project demand is measured" or (formatNumber(resource.amountPerHour * nativePlan.moduleCount) .. "/h for the recommended count")
                resourceRow[1]:setColSpan(4):createText(resource.name .. ": " .. formatNumber(resource.amountPerHour) .. "/h per module | " .. totalRequirement .. " | requires " .. resource.transport .. " storage and a proven supply route.", { wordwrap = true })
            end
        end
    end
    section(tableWidget, "LIVE PRODUCTION-CHAIN CHECKLIST")
    local checklist = nativePlan and nativePlan.checklist
    local checklistItems = checklist and checklist.items or {
        { state = "CANNOT PROVE", label = "NATIVE PRODUCTION CHAIN", evidence = "X4 did not return a complete owned module/recipe chain. No exact dependency or module count will be inferred." },
        { state = "REQUIRED", label = "VANILLA BUILD-PLAN REVIEW", evidence = "Confirm the production method, recipe, storage, workforce, plot, builder, build wares, and module compatibility in X4 before committing." },
    }
    local pageSize = 5
    local pageCount = math.max(1, math.ceil(#checklistItems / pageSize))
    menu.plannerChecklistPage = math.max(1, math.min(tonumber(menu.plannerChecklistPage) or 1, pageCount))
    local firstItem = (menu.plannerChecklistPage - 1) * pageSize + 1
    local lastItem = math.min(#checklistItems, firstItem + pageSize - 1)
    local statePrefix = { COMPLETE = "[X]", INFORMATION = "[i]", PLANNED = "[/]", ASSIGNED = "[/]", ASSIGNING = "[/]", ["APPROVAL REQUIRED"] = "[ ]", REQUIRED = "[ ]", ["SURPLUS PLAN"] = "[!]", ["SOURCE REQUIRED"] = "[!]", ["CANNOT PROVE"] = "[?]" }
    for itemIndex = firstItem, lastItem do
        local item = checklistItems[itemIndex]
        local itemColor = item.state == "COMPLETE" and investigationPassColor or ((item.state == "REQUIRED" or item.state == "SURPLUS PLAN" or item.state == "SOURCE REQUIRED") and investigationFailColor or (item.state == "INFORMATION" and navigationStoryColor or investigationUnknownColor))
        local checklistRow = tableWidget:addRow(false)
        checklistRow[1]:setColSpan(4):createText((statePrefix[item.state] or "[?]") .. " " .. item.state .. " - " .. item.label .. ": " .. item.evidence, { wordwrap = true, color = itemColor })
    end
    local checklistNav = tableWidget:addRow(true)
    addButton(checklistNav, 1, "PREVIOUS", function() menu.plannerChecklistPage = math.max(1, menu.plannerChecklistPage - 1); menu.refresh() end, menu.plannerChecklistPage > 1)
    checklistNav[2]:createText("PAGE " .. tostring(menu.plannerChecklistPage) .. " / " .. tostring(pageCount), { halign = "center" })
    local rawAction
    for _, item in ipairs(checklistItems) do if item.action then rawAction = item.action; break end end
    if rawAction then
        local bound = rawAction
        local rawStation = text(v(caseData, 1, ""))
        local rawWare = menu.supplyWareId(bound.ware)
        local rawKey = rawStation .. "|" .. rawWare
        menu.rawSourceAcknowledgements = menu.rawSourceAcknowledgements or {}
        local confirmationRefreshes = tonumber(menu.rawSourceAcknowledgements[rawKey]) or 0
        local acknowledgementActive = confirmationRefreshes > 0
        local record = menu.rawSourceRecords and menu.rawSourceRecords[rawKey]
        local label = acknowledgementActive and ((record and record.ship ~= "" and "RAW SOURCE SHIP ASSIGNED") or "RAW SOURCE REQUEST RECEIVED") or (bound.disabledLabel or (menu.shipmode == "AUTO-ASSIGN REGISTERED" and "ASSIGN NEXT RAW SOURCE" or (menu.shipmode == "APPROVAL REQUIRED" and "PROPOSE NEXT RAW SOURCE" or "CHECK RAW SOURCE")))
        addButton(checklistNav, 3, label, function()
            if (tonumber(menu.rawSourceAcknowledgements[rawKey]) or 0) > 0 then return end
            menu.rawSourceRecords = menu.rawSourceRecords or {}
            menu.rawSourceRecords[rawKey] = { status = "REQUESTED", ship = "", detail = "EOC submitted the exact raw-source assignment check." }
            menu.rawSourceAcknowledgements[rawKey] = 2
            raise("planner.rawsource", { station = rawStation, profile = nativePlan.stationProfileIndex or 0, ware = bound.ware, name = bound.name, transport = bound.transport, rate = bound.rate })
            menu.refresh()
        end, not bound.disabled and not acknowledgementActive, currentChoiceBackground)
        if acknowledgementActive then menu.rawSourceAcknowledgements[rawKey] = confirmationRefreshes - 1 end
    else
        addButton(checklistNav, 3, "REFRESH CHECKLIST", function() menu.runExpansionReadiness(caseData, true); menu.refresh() end, true, currentChoiceBackground)
    end
    addButton(checklistNav, 4, "NEXT", function() menu.plannerChecklistPage = math.min(pageCount, menu.plannerChecklistPage + 1); menu.refresh() end, menu.plannerChecklistPage < pageCount)
    local boundary = tableWidget:addRow(false)
    boundary[1]:setColSpan(4):createText(nativePlan and nativePlan.state == "OWNED" and "WHAT EOC KNOWS: X4 confirmed that you own this module and returned its recipe, output, workers and capacity. WHAT EOC DOES NOT KNOW: plot position, module connections, builder, build-storage supplies, final cost and future storage space. Check those items in the normal Station Build Plan. EOC will not change the plan." or "WHAT EOC KNOWS: X4 did not return a complete owned module and recipe. WHAT TO DO: Open the normal Station Build Plan and choose the module there. EOC will not guess or change the plan.", { wordwrap = true, color = investigationUnknownColor })
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2); addButton(row, 1, "RETURN TO COMMAND SUMMARY", function() menu.solutionDeepDiveKey = nil; menu.solutionDeepDivePage = 1; menu.refresh() end, true)
    row[3]:setColSpan(2); addButton(row, 3, "RETURN TO DIAGNOSTICS", function() menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh() end, true)
end

local function constructionRecordForSelected()
    local station = selectedStation()
    local profileIndex = tonumber(v(station, 16, menu.selected)) or menu.selected
    local stationName = text(v(station, 1, ""))
    local active = menu.activeConstructionSnapshot
    if active then
        local activeIndex = tonumber(v(active, 2, 0)) or 0
        local activeName = text(v(active, 1, ""))
        if (profileIndex > 0 and activeIndex == profileIndex) or (stationName ~= "" and activeName == stationName) then return active end
    end
    for _, record in ipairs(menu.constructionRecords or {}) do
        if (tonumber(v(record, 2, 0)) or 0) == profileIndex or text(v(record, 1, "")) == stationName then return record end
    end
    return { stationName, profileIndex, 0, 0, 0, 0, 0, {} }
end

local function constructionCenter(tableWidget)
    local record = constructionRecordForSelected()
    local stationName = text(v(record, 1, "SELECTED STATION"))
    local index = tonumber(v(record, 2, menu.selected)) or menu.selected
    local total = tonumber(v(record, 3, 0)) or 0
    local planned = tonumber(v(record, 4, 0)) or 0
    local building = tonumber(v(record, 5, 0)) or 0
    local builders = tonumber(v(record, 6, 0)) or 0
    local buildStorage = tonumber(v(record, 7, 0)) or 0
    local queue = v(record, 8, {})
    local budget = tonumber(v(record, 9, 0)) or 0
    local wantedBudget = tonumber(v(record, 10, 0)) or 0
    local missingWares = v(record, 11, {})
    local lastFunding = tonumber(v(record, 12, 0)) or 0
    local lastFundingTime = tonumber(v(record, 13, 0)) or 0
    local row
    section(tableWidget, "STATION CONSTRUCTION - " .. stationName)
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(total > 0 and "ONGOING CONSTRUCTION DETECTED" or "NO ONGOING CONSTRUCTION DETECTED", { color = total > 0 and investigationPassColor or investigationNeutralColor })
    row = tableWidget:addRow(false)
    row[1]:createText("QUEUE") row[2]:createText(tostring(total)) row[3]:createText("UNDERWAY / PLANNED") row[4]:createText(tostring(building) .. " / " .. tostring(planned))
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, menu.constructionRefreshing and "REFRESHING CONSTRUCTION..." or "REFRESH CONSTRUCTION STATUS", function()
        menu.constructionRefreshing = true; menu.constructionStatus = "REFRESHING: Reading the latest station plan and assignments..."; raise("construction.refresh", { index = index, station = stationName }); menu.refresh()
    end, not menu.constructionRefreshing)
    if menu.constructionStatus then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(menu.constructionStatus, { wordwrap = true, color = resultColor("IMPROVING") }) end

    section(tableWidget, "CONSTRUCTION READINESS CHECKLIST")
    local function check(label, state, detail, stateColor)
        local r = tableWidget:addRow(false); r[1]:createText(state, { color = stateColor }); r[2]:createText(label); r[3]:setColSpan(2):createText(detail, { wordwrap = true })
    end
    check("BUILD PLAN / QUEUE", total > 0 and "MET" or "NOT MET", total > 0 and (tostring(total) .. " planned or active module(s) detected.") or "No planned or active modules were found.", total > 0 and investigationPassColor or resultColor("UNKNOWN"))
    check("BUILDER ASSIGNED", builders > 0 and "MET" or (total > 0 and "STALLED - CHECK BUILDER" or "NOT REQUIRED"), builders > 0 and "X4 reports a construction vessel assigned to this station build." or (total > 0 and "No construction vessel is currently assigned. Assign a builder, then refresh Construction Status." or "No construction plan requires a builder."), builders > 0 and investigationPassColor or (total > 0 and resultColor("FAILED") or resultColor("UNKNOWN")))
    check("BUILD-STORAGE SHIP", buildStorage > 0 and "MET" or "OPTIONAL", buildStorage > 0 and (tostring(buildStorage) .. " assigned build-storage trader(s) detected.") or "No player build-storage trader is assigned. NPC deliveries may still satisfy construction, so this is not treated as a failure.", buildStorage > 0 and investigationPassColor or resultColor("UNKNOWN"))
    check("CONSTRUCTION PROGRESS", building > 0 and "MET" or "WAITING", building > 0 and (tostring(building) .. " module(s) currently under construction.") or (planned > 0 and "Modules are queued but none is currently building." or "No construction progress to measure."), building > 0 and investigationPassColor or resultColor("UNKNOWN"))
    local budgetMet = wantedBudget <= 0 or budget >= wantedBudget
    local shortfall = math.max(0, wantedBudget - budget)
    row = tableWidget:addRow(shortfall > 0)
    row[1]:createText(budgetMet and "MET" or "NOT FUNDED", { color = budgetMet and investigationPassColor or resultColor("FAILED") })
    row[2]:createText("CONSTRUCTION BUDGET")
    row[3]:createText(string.format("Available now: %d Cr | X4 currently requests: %d Cr%s", budget, wantedBudget, budgetMet and "." or (" | add " .. tostring(shortfall) .. " Cr now.")), { wordwrap = true })
    if lastFunding > 0 then
        local historyRow = tableWidget:addRow(false)
        historyRow[1]:createText("CONFIRMED")
        historyRow[2]:createText("LAST EOC TRANSFER")
        historyRow[3]:setColSpan(2):createText(tostring(lastFunding) .. " Cr transferred successfully" .. (lastFundingTime > 0 and (" at " .. formatGameTime(lastFundingTime)) or "") .. ". Construction may immediately reserve or spend these credits; the live balance above can return to zero.", { wordwrap = true, color = investigationPassColor })
    end
    if shortfall > 0 and total > 0 then
        local confirming = menu.constructionFundingPending and menu.constructionFundingPending.station == stationName and menu.constructionFundingPending.amount == shortfall
        addButton(row, 4, confirming and ("CONFIRM TRANSFER " .. tostring(shortfall) .. " Cr") or ("APPROVE FUNDS " .. tostring(shortfall) .. " Cr"), function()
            if confirming then
                menu.constructionStatus = "TRANSFERRING: X4 is rechecking the exact construction shortfall..."
                raise("construction.fund", { index = index, station = stationName, amount = shortfall })
                menu.constructionFundingPending = nil
            else
                menu.constructionFundingPending = { station = stationName, amount = shortfall }
                menu.constructionStatus = "CONFIRMATION REQUIRED: Approve the exact " .. tostring(shortfall) .. " Cr construction shortfall for " .. stationName .. "."
            end
            menu.refresh()
        end, true)
    end
    if shortfall > 0 and total <= 0 then
        row[4]:createText("BLOCKED - NO BUILD QUEUE", { color = resultColor("FAILED") })
    end
    if total > 0 and builders == 0 then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, menu.constructionBuilderPending and "CONFIRM BUILDER REASSIGNMENT" or "FIND AND ASSIGN ELIGIBLE BUILDER", function()
            menu.constructionStatus = menu.constructionBuilderPending and "REASSIGNING: Replacing the confirmed builder's current station role..." or "SEARCHING: Looking for player-owned construction-capable ships in this station sector..."
            raise("construction.builder", { index = index, station = stationName })
            menu.refresh()
        end, true)
    end
    check("BUILD WARES", #missingWares == 0 and "MET" or "MISSING", #missingWares == 0 and "No remaining construction-ware deficit is reported." or (tostring(#missingWares) .. " construction ware type(s) are still required; see the list below."), #missingWares == 0 and investigationPassColor or resultColor("FAILED"))
    if #missingWares > 0 then
        section(tableWidget, "MISSING CONSTRUCTION WARES")
        local firstWare, lastWare = menu.adaptiveListNavigation(tableWidget, "construction.missingwares", #missingWares, { fixedRows = 24, rowUnits = 1, maximum = 5 })
        for wareIndex = firstWare, lastWare do
            local ware = missingWares[wareIndex]
            row = tableWidget:addRow(false); row[1]:setColSpan(2):createText(text(v(ware, 1, "Unknown ware"))); row[3]:createText("REMAINING"); row[4]:createText(tostring(v(ware, 2, 0)))
        end
    end

    section(tableWidget, "ORDERED BUILD QUEUE AND PROGRESS")
    if #queue == 0 then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("No construction modules are currently in the detected queue.") end
    local firstQueue, lastQueue = menu.adaptiveListNavigation(tableWidget, "construction.queue", #queue, { fixedRows = 30, rowUnits = 1, maximum = 8 })
    for queueIndex = firstQueue, lastQueue do
        local item = queue[queueIndex]
        local progress = tonumber(v(item, 4, 0)) or 0
        row = tableWidget:addRow(false)
        row[1]:createText("#" .. tostring(v(item, 8, queueIndex)))
        row[2]:createText(text(v(item, 1, "Unknown module")), { wordwrap = true })
        row[3]:createText(text(v(item, 3, "PLANNED")), { color = progress > 0 and investigationPassColor or resultColor("UNKNOWN") })
        row[4]:createText(string.format("%.1f%%", progress))
    end
end
local function filteredCases()
    local filtered = {}
    local station = selectedStation()
    local stationName = text(v(station, 1, ""))

    for _, case in ipairs(menu.cases or {}) do
        local severityMatches = menu.caseSeverity == "all" or
            string.lower(text(v(case, 2, ""))) == menu.caseSeverity
        local scopeMatches = menu.caseScope == "global" or
            text(v(case, 1, "")) == stationName
        if severityMatches and scopeMatches then
            table.insert(filtered, case)
        end
    end

    return filtered
end

local function stationObservations(station)
    local matches = {}
    local stationName = text(v(station, 1, ""))
    for _, observation in ipairs(menu.observations or {}) do
        if text(v(observation, 1, "")) == stationName then table.insert(matches, observation) end
    end
    return matches
end

local function observationHasPlayerCase(stationName, subject)
    for _, case in ipairs(menu.cases or {}) do
        if text(v(case, 1, "")) == stationName and v(case, 11, "") == "PLAYER" and text(v(case, 4, "")) == subject then return true end
    end
    return false
end

-- Close one exact player-requested investigation through the established
-- case.close transaction. EOC-confirmed cases and retained evidence are not
-- removed by this presentation-side update.
function menu.closePlayerRequestedCase(caseData, returnToCases)
    if not caseData or v(caseData, 11, "") ~= "PLAYER" then return false end
    menu.focusCaseStation(caseData)
    local stationName = text(v(caseData, 1, ""))
    local subject = text(v(caseData, 4, ""))
    for index = #menu.cases, 1, -1 do
        if text(v(menu.cases[index], 1, "")) == stationName and text(v(menu.cases[index], 4, "")) == subject and v(menu.cases[index], 11, "") == "PLAYER" then
            table.remove(menu.cases, index)
        end
    end
    if menu.diagnosticCase and text(v(menu.diagnosticCase, 1, "")) == stationName and text(v(menu.diagnosticCase, 4, "")) == subject and v(menu.diagnosticCase, 11, "") == "PLAYER" then
        menu.diagnosticCase = nil
    end
    menu.selectedCase = 1
    menu.casePage = 1
    if returnToCases then
        menu.caseScope = "station"
        menu.caseSeverity = "all"
        menu.page = "cases"
        menu.activeTab = "cases"
    end
    raise("case.close", { index = v(selectedStation(), 16, menu.selected), subject = subject })
    menu.refresh()
    return true
end

local function casesCenter(tableWidget)
    local scopeLabel = menu.caseScope == "global" and "ALL STATIONS" or
        ("SELECTED STATION - " .. text(v(selectedStation(), 1, "NONE")))
    local severityLabel = menu.caseSeverity == "all" and "ALL" or string.upper(menu.caseSeverity)
    section(tableWidget, "EOC CASE CENTER")
    local selectedProfile = selectedStation()
    local selectedProfileIssues = tonumber(v(selectedProfile, 8, 0)) or 0
    local selectedEOCCases = 0
    local selectedPlayerCases = 0
    if selectedProfile then
        for _, profileCase in ipairs(stationCases(selectedProfile)) do
            if v(profileCase, 11, "") == "PLAYER" then
                selectedPlayerCases = selectedPlayerCases + 1
            else
                selectedEOCCases = selectedEOCCases + 1
            end
        end
    end
    local selectedObservations = selectedProfile and stationObservations(selectedProfile) or {}
    local selectedDifference = math.max(0, #selectedObservations - selectedEOCCases)
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText(menu.caseScope == "station" and "READ THIS FIRST: A CASE is one problem EOC is actively following for this station. Start with PLAYER COMMAND SUMMARY below: it says whether EOC is handling the case, waiting for normal game activity, or needs one action from you. The longer incident and evidence history is supporting detail, not a second to-do list." or "READ THIS FIRST: Each row is one station problem EOC is following. Open a case to see one plain-language next action. Use the filters only when you need to narrow the list.", { wordwrap = true, color = navigationStoryColor, font = Helper.headerFont })
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    if menu.clearCasesConfirm then
        addButton(row, 1, "CONFIRM: DELETE ALL EOC CASES AND REBUILD FROM LIVE DATA", function()
            if startAction("case.clearall") then
                menu.clearCasesConfirm = false
                menu.cases = {}
                menu.observations = {}
                menu.monitoredCases = {}
                menu.diagnosticCase = nil
                menu.selectedCase = 1
                menu.casePage = 1
                raise("case.clearall", {})
                menu.refresh()
            end
        end, not actionState("case.clearall").running)
        local cancelrow = tableWidget:addRow(true)
        cancelrow[1]:setColSpan(4)
        addButton(cancelrow, 1, "CANCEL - KEEP ALL CASES", function()
            menu.clearCasesConfirm = false
            menu.refresh()
        end, true)
    else
        addButton(row, 1, "ADVANCED: CLEAR ALL EOC CASE HISTORY", function()
            menu.clearCasesConfirm = true
            menu.refresh()
        end, not actionState("case.clearall").running)
    end
    actionResult(tableWidget, "case.clearall", "Deletes EOC case and retained evidence records only, then runs one fresh Empire Analysis. It does not change stations, ships, orders, funds, or settings.")
    pair(
        tableWidget,
        "SCOPE",
        menu.caseScope == "global" and "ALL PLAYER STATIONS" or text(v(selectedStation(), 1, "SELECTED STATION")),
        "DISPLAYED",
        #filteredCases()
    )
    local statusRow = tableWidget:addRow(false)
    statusRow[1]:setColSpan(4):createText(
        "ACTIVE FILTERS: SCOPE - " .. scopeLabel .. " | SEVERITY - " .. severityLabel
    )

    local row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.caseScope == "global" and "ACTIVE: " or "") .. "ALL STATIONS", menu.caseScope == "global", true, function()
        menu.caseScope = "global"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end)
    addModeButton(row, 2, (menu.caseScope == "station" and "ACTIVE: " or "") .. "SELECTED STATION", menu.caseScope == "station", selectedStation() ~= nil, function()
        menu.caseScope = "station"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end)
    addModeButton(row, 3, (menu.caseSeverity == "all" and "ACTIVE: " or "") .. "ALL SEVERITIES", menu.caseSeverity == "all", true, function()
        menu.caseSeverity = "all"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end)
    addModeButton(row, 4, (menu.caseSeverity == "critical" and "ACTIVE: " or "") .. "CRITICAL", menu.caseSeverity == "critical", true, function()
        menu.caseSeverity = "critical"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, (menu.caseSeverity == "warning" and "ACTIVE: " or "") .. "WARNING", menu.caseSeverity == "warning", true, function()
        menu.caseSeverity = "warning"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addButton(row, 3, "CLEAR FILTERS", function()
        menu.caseScope = "global"
        menu.caseSeverity = "all"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.refresh()
    end, menu.caseScope ~= "global" or menu.caseSeverity ~= "all")

    section(tableWidget, "STATION SUMMARY — CONTEXT, NOT EXTRA TASKS")
    pair(tableWidget, "SELECTED STATION", text(v(selectedProfile, 1, "NONE")), "HEALTH / TREND", text(v(selectedProfile, 3, "UNKNOWN")) .. " / " .. text(v(selectedProfile, 4, "UNKNOWN")))
    pair(tableWidget, "CURRENT ISSUES", selectedProfileIssues, "RETAINED OBSERVATIONS", #selectedObservations)
    pair(tableWidget, "EOC-CONFIRMED CASES", selectedEOCCases, "PLAYER-REQUESTED CASES", selectedPlayerCases)
    pair(tableWidget, "CHRONIC / RECURRING", text(v(selectedProfile, 18, 0)) .. " / " .. text(v(selectedProfile, 17, 0)), "HISTORY HITS", v(selectedProfile, 22, 0))
    local health = string.upper(text(v(selectedProfile, 3, "MONITORING")))
    row = tableWidget:addRow(false)
    local explanation = health == "CHRONIC" and "WHY THIS STATION IS CHRONIC: One or more retained observations reached SYSTEMIC status after repeated evidence. Review every contributor below. CHRONIC clears only after later healthy samples move those observations through recovery and resolution." or "STATUS EXPLANATION: The issue inventory below shows the retained evidence behind this station's health and trend."
    row[1]:setColSpan(4):createText(explanation, { wordwrap = true, color = health == "CHRONIC" and investigationUnknownColor or navigationStoryColor })

    local incidents, incidentOrder = {}, {}
    for _, observation in ipairs(selectedObservations) do
        local subject = text(v(observation, 3, "General operations"))
        if not incidents[subject] then incidents[subject] = { subject = subject, observations = {}, leading = observation }; incidentOrder[#incidentOrder + 1] = subject end
        local incident = incidents[subject]; incident.observations[#incident.observations + 1] = observation
        local priority = { RELAPSED=5, SYSTEMIC=4, RECURRING=3, CANDIDATE=2, RECOVERING=1, RESOLVED=0 }
        if (priority[string.upper(text(v(observation,4,"BASELINE")))] or 0) > (priority[string.upper(text(v(incident.leading,4,"BASELINE")))] or 0) then incident.leading=observation end
    end
    section(tableWidget, "SUPPORTING ISSUE HISTORY  |  " .. #incidentOrder .. " SUBJECT(S) / " .. #selectedObservations .. " RETAINED EVIDENCE RECORD(S)")
    if #incidentOrder == 0 then
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("EOC has no saved problem for this station. Run Fresh Empire Analysis once to update its information.", { wordwrap = true })
    else
        local firstIncident, lastIncident = menu.adaptiveListNavigation(tableWidget, "cases.incidents", #incidentOrder, { fixedRows = 24, rowUnits = 7, maximum = 1 })
        for incidentIndex = firstIncident, lastIncident do
            local subject = incidentOrder[incidentIndex]
            local incident, leading = incidents[subject], incidents[subject].leading
            local existing = observationHasPlayerCase(text(v(selectedProfile, 1, "")), subject)
            local existingPlayerCase
            if existing then
                for _, caseData in ipairs(menu.cases or {}) do
                    if text(v(caseData, 1, "")) == text(v(selectedProfile, 1, "")) and text(v(caseData, 4, "")) == subject and v(caseData, 11, "") == "PLAYER" then
                        existingPlayerCase = caseData
                        break
                    end
                end
            end
            section(tableWidget, subject .. " | " .. #incident.observations .. " SUPPORTING EVIDENCE RECORD(S)")
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("STORY: EOC grouped these records because they concern the same station and subject. They may represent one operating chain rather than separate failures.",{wordwrap=true,color=investigationUnknownColor})
            local missionStation, missionWare, missionText = text(v(menu.missionContext,1,"")), text(v(menu.missionContext,2,"")), text(v(menu.missionContext,3,""))
            if missionStation == text(v(selectedProfile,1,"")) and missionWare == subject then
                row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("MISSION CONTEXT CONFIRMED: "..missionText.." EOC recognizes this as project demand; only proven operational effects contribute to station health.",{wordwrap=true,color=navigationStoryColor})
            end
            local firstObservation, lastObservation = menu.adaptiveListNavigation(tableWidget, "cases.incident.observations." .. subject, #incident.observations, { fixedRows = 30, rowUnits = 1, maximum = 3 })
            for observationIndex = firstObservation, lastObservation do
                local observation = incident.observations[observationIndex]
                local state=string.upper(text(v(observation,4,"BASELINE")))
                row=tableWidget:addRow(false); row[1]:setColSpan(4):createText(state.." - "..text(v(observation,2,"OBSERVATION"))..": "..text(v(observation,5,"No evidence summary available")),{wordwrap=true,color=resultColor(state)})
            end
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("LEADING EXPLANATION: "..text(v(leading,6,"Cause not yet confirmed")).." DO THIS NEXT: "..text(v(leading,7,"Continue monitoring")),{wordwrap=true})
            row=tableWidget:addRow(true); row[1]:setColSpan(4)
            if existingPlayerCase then
                local boundCase = existingPlayerCase
                addButton(row,1,"OPEN EXISTING INVESTIGATION: "..subject,function()
                    menu.caseDuplicateNotice = nil
                    menu.focusCaseStation(boundCase)
                    menu.diagnosticCase = boundCase
                    captureNavigation("CASE - " .. subject)
                    menu.diagnosticView = "recovery"
                    menu.page = "diagnostics"
                    menu.activeTab = "diagnostics"
                    menu.refresh()
                end,true)
            else
                addButton(row,1,"ASK EOC TO INVESTIGATE: "..subject,function()
                if selectedProfile and startAction("case.create") then
                    table.insert(menu.cases,{text(v(selectedProfile,1,"Selected station")),"PLAYER","PLAYER-REPORTED",subject,"OPEN - PLAYER REQUESTED",text(v(leading,6,"Grouped retained evidence requires focused investigation.")),text(v(leading,7,"Review grouped evidence and run focused diagnostics.")),#incident.observations,0,0,"PLAYER"})
                    raise("case.create",{index=v(selectedProfile,16,menu.selected),subject=subject,issues=#incident.observations,rootcause=text(v(leading,6,"Grouped retained evidence requires focused investigation.")),corrective=text(v(leading,7,"Review grouped evidence and run focused diagnostics.")),observationindex=v(leading,14,0),observationcount=#incident.observations})
                    menu.refresh()
                end
                end,not actionState("case.create").running)
            end
        end
    end
    local cases = filteredCases()
    if #cases == 0 then
        section(tableWidget, "NO MATCHING ACTIVE CASES")
        pair(tableWidget, "STATUS", "No confirmed recovery case matches the current filters.", "ACTION", (#selectedObservations > 0 and "Review retained issues above or open a player investigation." or "Run a fresh Empire Analysis."))
        return
    end

    menu.selectedCase = clamp(menu.selectedCase, 1, #cases)
    section(tableWidget, "ACTIVE CASES — CHOOSE ONE PROBLEM TO FOLLOW  |  " .. #cases .. " SHOWN")
    local header = tableWidget:addRow(false)
    header[1]:setColSpan(2):createText("STATION")
    header[3]:createText("SEVERITY")
    header[4]:createText("SUBJECT")
    local firstCase, lastCase = menu.adaptiveListNavigation(tableWidget, "cases.active", #cases, { fixedRows = 34, rowUnits = 1, maximum = 4 })
    for index = firstCase, lastCase do
        local case = cases[index]
        local caseIndex = index
        local caseData = case
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addModeButton(row, 1, "OPEN CASE: " .. text(v(caseData, 1, "Unknown station")) .. " -> " .. text(v(caseData, 4, "GENERAL OPERATIONS")), caseIndex == menu.selectedCase, true, function()
            menu.selectedCase = caseIndex
            menu.caseDuplicateNotice = nil
            for _, actionNameToClear in ipairs({ "case.create", "case.monitor", "case.close" }) do
                local transientState = actionState(actionNameToClear)
                transientState.result = nil
                transientState.lastRun = nil
            end
            menu.focusCaseStation(caseData)
            menu.diagnosticCase = caseData
            captureNavigation("CASE - " .. text(v(caseData, 4, "SELECTED CASE")))
            menu.diagnosticView = "recovery"
            menu.page = "diagnostics"
            menu.activeTab = "diagnostics"
            menu.refresh()
        end, true)
        row[3]:createText(text(v(caseData, 2, "ISSUE")))
        row[4]:createText(text(v(caseData, 4, "GENERAL OPERATIONS")))
    end

    local selected = cases[menu.selectedCase]
    section(tableWidget, "SELECTED CASE: " .. text(v(selected, 1, "Unknown station")) .. " -> " .. text(v(selected, 4, "GENERAL OPERATIONS")))
    pair(tableWidget, "SEVERITY", v(selected, 2, "ISSUE"), "WORKFLOW", "GUIDED RECOVERY")
    local selectedChecks = prerequisiteRows(selected)
    local selectedAction, selectedActionColor = managedActionText(selected)
    local selectedBlocked = string.find(string.upper(selectedAction), "BLOCKED", 1, true) ~= nil
    local selectedPlannerReady, selectedPlannerReason = menu.plannerAccessForCase(selected)
    local selectedRecoveryExhausted = selectedPlannerReady and (selectedPlannerReason == "RECOVERY_EXHAUSTED" or selectedPlannerReason == "RETAINED_READINESS")
    local selectedPlayerDecision = selectedBlocked or selectedRecoveryExhausted
    section(tableWidget, "PLAYER COMMAND SUMMARY — START HERE")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(selectedPlayerDecision and "PLAYER ACTION REQUIRED" or "NO PLAYER ACTION RIGHT NOW — EOC IS HANDLING THIS CASE", { wordwrap = true, color = selectedPlayerDecision and investigationFailColor or investigationPassColor, font = Helper.headerFont })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(selectedRecoveryExhausted and "DO THIS NEXT: Reopen Solution Planner. Temporary recovery is exhausted and EOC needs your project-demand or permanent-solution decision." or (selectedBlocked and ("DO THIS NEXT: " .. manualNextAction(selected, selectedChecks)) or ("EOC STATUS: " .. selectedAction)), { wordwrap = true, color = selectedActionColor })
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    menu.addPrimaryButton(row, 1, "OPEN GUIDED NEXT ACTION — RETURN PATH PRESERVED", function()
        menu.focusCaseStation(selected)
        menu.diagnosticCase = selected
        captureNavigation("CASE - " .. text(v(selected, 4, "SELECTED CASE")))
        menu.diagnosticView = "recovery"
        menu.page = "diagnostics"
        menu.activeTab = "diagnostics"
        menu.refresh()
    end, true)
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHY THIS CASE IS OPEN: " .. text(v(selected, 6, "Evidence requires review")), { wordwrap = true })

    local checks = selectedChecks
    local firstProblem = nil
    local passCount, notApplicableCount = 0, 0
    for _, check in ipairs(checks) do
        if check.state == "PASS" then passCount = passCount + 1
        elseif check.state == "NOT APPLICABLE" then notApplicableCount = notApplicableCount + 1
        elseif not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN" or check.state == "NOT YET TESTED") then firstProblem = check end
    end

    local selectedDeepDiveKey = checklistCaseKey(selected)
    local showingCaseDeepDive = menu.caseDeepDiveKey == selectedDeepDiveKey
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, showingCaseDeepDive and "CLOSE DEEP DIVE — COMMAND ONLY" or "DEEP DIVE — EVIDENCE AND ANALYSIS", function()
        if showingCaseDeepDive then
            menu.caseDeepDiveKey = nil
        else
            menu.caseDeepDiveKey = selectedDeepDiveKey
        end
        menu.refresh()
    end, true)
    if showingCaseDeepDive then
        section(tableWidget, firstProblem and (firstProblem.state == "FAIL" and "WHAT EOC FOUND" or "WHAT EOC STILL NEEDS TO LEARN") or "WHAT EOC FOUND")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " - " .. firstProblem.label .. ": " .. firstProblem.evidence) or "PASS - NO VERIFIED BLOCKER: all reported prerequisites pass or do not apply.", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })
        section(tableWidget, "WHAT EOC IS DOING")
        row = tableWidget:addRow(false)
        local actionText, actionColor = managedActionText(selected)
        row[1]:setColSpan(4):createText(actionText, { wordwrap = true, color = actionColor })
        if string.find(string.upper(actionText), "BLOCKED", 1, true) then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("PLAYER ACTION REQUIRED: " .. manualNextAction(selected, checks), { wordwrap = true, color = investigationFailColor })
        end
        local scoutRecommendation, scoutChecklist = scoutRecoveryPlan(selected, checks)
        section(tableWidget, "SCOUT'S BEST LONG-TERM RECOMMENDATION")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(scoutRecommendation, { wordwrap = true, color = navigationStoryColor })
        section(tableWidget, "EOC / PLAYER COMMAND CHECKLIST - SELECT EACH STEP TO ANSWER OR ASK EOC")
        renderInteractiveChecklist(tableWidget, selected, scoutChecklist)
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("EOC CHECKED " .. tostring(#checks) .. " CONDITION(S): " .. passCount .. " passed | " .. notApplicableCount .. " did not apply. Guided Recovery explains the result in order.", { wordwrap = true })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("EVIDENCE SNAPSHOT: Values came from " .. (menu.lastUpdated and ("the EOC analysis at " .. menu.lastUpdated) or "the last EOC analysis") .. ". They may differ from the current vanilla station screen until verification runs.", { wordwrap = true })
    end
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, firstProblem and firstProblem.state ~= "FAIL" and "CONTINUE - COLLECT THE MISSING EVIDENCE" or ("SHOW ME WHAT TO DO: " .. text(v(selected, 4, "SELECTED CASE"))), function()
        menu.focusCaseStation(selected)
        menu.diagnosticCase = selected
        captureNavigation("CASE - " .. text(v(selected, 4, "SELECTED CASE")))
        menu.diagnosticView = "recovery"
        menu.page = "diagnostics"
        menu.activeTab = "diagnostics"
        menu.refresh()
    end, true)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "OPEN STATION: " .. text(v(selected, 1, "Unknown station")), function()
        menu.focusCaseStation(selected)
        captureNavigation("CASES")
        menu.page = "stations"
        menu.activeTab = "stations"
        menu.refresh()
    end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "GENERATE REPORT: SELECTED STATION", function()
        menu.focusCaseStation(selected)
        captureReportOrigin("cases", "CASES - " .. text(v(selected, 1, "SELECTED STATION")))
        menu.pendingReport = "SELECTED STATION"
        raise("report.station", { index = v(selectedStation(), 16, menu.selected) })
    end, true)

    if v(selected, 11, "") == "PLAYER" then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, actionLabel("case.close", "CLOSE PLAYER-REQUESTED CASE", "CLOSING PLAYER CASE"), function()
            if startAction("case.close") then
                menu.closePlayerRequestedCase(selected, false)
            end
        end, not actionState("case.close").running)
        actionResult(tableWidget, "case.close", "Closes only the player-requested investigation; EOC-confirmed cases and evidence remain intact.")
    end
end


local function fleetBuildManager(tableWidget)
    menu.fleetManager=menu.fleetManager or {mode="list",size="ALL",catalogPage=1,catalogSearch="",distribute=false}
    local state=menu.fleetManager
    local row
    section(tableWidget,"FLEET BUILD MANAGER - EOC 2.2 GA")
    row=tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("Create named fleet-production templates entirely inside EOC. Orders use owned blueprints, X4-generated compatible loadouts, normal resources, and separate Preview and Confirm actions.",{wordwrap=true})
    if state.mode=="list" then
        local templates=fleetTemplateStore()
        row=tableWidget:addRow(true);row[1]:setColSpan(4)
        addButton(row,1,"CREATE NEW FLEET TEMPLATE",function()
            state.mode="edit";state.originalName=nil;state.draft={name="New Fleet "..tostring(#templates+1),entries={}};state.result=nil;state.plan=nil;menu.refresh()
        end,true)
        section(tableWidget,"SAVED FLEET TEMPLATES  |  "..#templates)
        if #templates==0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("No EOC fleet templates are saved in this game.")
        else
            local first, last = menu.adaptiveListNavigation(tableWidget, "fleetbuild.templates", #templates, { fixedRows = 10, rowUnits = 1 })
            for index = first, last do
                local template = templates[index]
                row=tableWidget:addRow(true);row[1]:setColSpan(2):createText(template.name,{wordwrap=true});row[3]:createText(fleetShipCount(template).." SHIP(S)")
                addButton(row,4,"OPEN",function()state.selected=template.name;state.mode="detail";state.plan=nil;state.result=nil;state.deleteConfirm=false;menu.refresh()end,true)
            end
        end
        return
    end
    if state.mode=="edit" then
        local draft=state.draft or {name="New Fleet",entries={}};state.draft=draft
        section(tableWidget,state.originalName and "EDIT FLEET TEMPLATE" or "NEW FLEET TEMPLATE")
        row=tableWidget:addRow(true);row[1]:createText("NAME")
        row[2]:setColSpan(3):createEditBox({height=Helper.standardButtonHeight}):setText(draft.name or "")
        row[2].handlers.onEditBoxDeactivated=function(_,entered)draft.name=tostring(entered or "")end
        section(tableWidget,"FLEET CONTENTS  |  "..fleetShipCount(draft).." OF "..FLEET_MAX_SHIPS.." SHIPS")
        if #(draft.entries or {})==0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("No ships added. Use the owned-blueprint catalog below.")
        else
            local firstDraft, lastDraft = menu.adaptiveListNavigation(tableWidget, "fleetbuild.draft.entries", #draft.entries, { fixedRows = 20, rowUnits = 1, maximum = 6 })
            for index = firstDraft, lastDraft do
                local entry = draft.entries[index]
                row=tableWidget:addRow(true);row[1]:setColSpan(2):createText(entry.name.." ("..entry.size..")")
                addButton(row,3,"ADD 1 - NOW "..entry.amount,function()entry.amount=math.min(FLEET_MAX_PER_ENTRY,(entry.amount or 1)+1);state.result=nil;menu.refresh()end,fleetShipCount(draft)<FLEET_MAX_SHIPS)
                addButton(row,4,"REMOVE 1",function()entry.amount=math.max(0,(entry.amount or 1)-1);if entry.amount==0 then table.remove(draft.entries,index) end;state.result=nil;menu.refresh()end,true)
            end
        end
        section(tableWidget,"ADD OWNED BLUEPRINT")
        row=tableWidget:addRow(true);row[1]:createText("SEARCH SHIP NAME")
        row[2]:setColSpan(2):createEditBox({height=Helper.standardButtonHeight}):setText(state.catalogSearch or "")
        row[2].handlers.onEditBoxDeactivated=function(_,entered)state.catalogSearch=tostring(entered or "");state.catalogPage=1;menu.refresh()end
        addButton(row,4,"CLEAR SEARCH",function()state.catalogSearch="";state.catalogPage=1;menu.refresh()end,(state.catalogSearch or "")~="")
        row=tableWidget:addRow(true)
        for column,size in ipairs({"ALL","S","M","L"}) do addModeButton(row,column,(state.size==size and "ACTIVE: " or "")..size,state.size==size,true,function()state.size=size;state.catalogPage=1;menu.refresh()end) end
        local catalog={}
        local search=string.lower(tostring(state.catalogSearch or ""))
        for _,blueprint in ipairs(menu.shipBlueprints or {}) do
            local size=text(v(blueprint,2,"UNKNOWN")):upper()
            local display=string.lower(text(v(blueprint,1,"")))
            local macro=string.lower(text(v(blueprint,3,"")))
            if (state.size=="ALL" or state.size==size) and (search=="" or string.find(display,search,1,true) or string.find(macro,search,1,true)) then catalog[#catalog+1]=blueprint end
        end
        table.sort(catalog,function(a,b)return text(v(a,1,""))<text(v(b,1,""))end)
        if #catalog==0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("NO OWNED SHIP BLUEPRINTS MATCH: "..tostring(state.catalogSearch or ""),{wordwrap=true}) end
        if #catalog > 0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText(#catalog.." MATCHING OWNED BLUEPRINTS | ADAPTIVE SCREEN BOUNDARY",{halign="center",color=investigationNeutralColor}) end
        local first, last = menu.adaptiveListNavigation(tableWidget, "fleetbuild.catalog", #catalog, { fixedRows = 18 + #(draft.entries or {}), rowUnits = 1 })
        for index=first,last do
            local blueprint=catalog[index];row=tableWidget:addRow(true);row[1]:setColSpan(3):createText(text(v(blueprint,1,"Owned ship")).." ("..text(v(blueprint,2,"?"))..")",{wordwrap=true})
            addButton(row,4,"ADD ONE",function()
                local macro=text(v(blueprint,3,""));local found
                for _,existing in ipairs(draft.entries) do if existing.macro==macro then found=existing break end end
                if found then found.amount=math.min(FLEET_MAX_PER_ENTRY,found.amount+1) else draft.entries[#draft.entries+1]={name=text(v(blueprint,1,"Owned ship")),size=text(v(blueprint,2,"?")),macro=macro,amount=1} end
                state.result=nil;menu.refresh()
            end,fleetShipCount(draft)<FLEET_MAX_SHIPS)
        end
        row=tableWidget:addRow(true);row[1]:setColSpan(2)
        addButton(row,1,"SAVE FLEET TEMPLATE",function()local success,result=storeFleetTemplate(draft,state.originalName);state.result=result;if success then state.selected=result;state.mode="detail";state.draft=nil;state.originalName=nil end;menu.refresh()end,fleetShipCount(draft)>0)
        row[3]:setColSpan(2);addButton(row,3,"CANCEL - RETURN TO TEMPLATES",function()state.mode="list";state.draft=nil;state.originalName=nil;state.result=nil;menu.refresh()end,true)
        if state.result then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("STATUS: "..state.result,{wordwrap=true}) end
        return
    end
    local template=findFleetTemplate(state.selected)
    if not template then state.mode="list";state.selected=nil;state.plan=nil;menu.refresh();return end
    section(tableWidget,"FLEET TEMPLATE - "..template.name)
    local templateEntries = template.entries or {}
    local firstEntry, lastEntry = menu.adaptiveListNavigation(tableWidget, "fleetbuild.template.detail", #templateEntries, { fixedRows = 16, rowUnits = 1 })
    for index = firstEntry, lastEntry do local entry = templateEntries[index]; pair(tableWidget,entry.name,entry.size,"QUANTITY",entry.amount) end
    row=tableWidget:addRow(true);row[1]:setColSpan(2);addButton(row,1,"EDIT TEMPLATE",function()state.mode="edit";state.originalName=template.name;state.draft=copySerializable(template);state.plan=nil;state.result=nil;menu.refresh()end,true)
    row[3]:setColSpan(2);addButton(row,3,state.deleteConfirm and "CONFIRM DELETE TEMPLATE" or "DELETE TEMPLATE",function()if state.deleteConfirm then deleteFleetTemplate(template.name);state.mode="list";state.selected=nil;state.deleteConfirm=false;state.plan=nil;state.result=nil else state.deleteConfirm=true end;menu.refresh()end,true,state.deleteConfirm and pendingChoiceBackground or nil)
    section(tableWidget,"BUILD CONTROL")
    row=tableWidget:addRow(true);row[1]:setColSpan(2);addModeButton(row,1,(state.distribute and "" or "ACTIVE: ").."ONE COMPATIBLE SHIPYARD",not state.distribute,true,function()state.distribute=false;state.plan=nil;state.result=nil;menu.refresh()end)
    row[3]:setColSpan(2);addModeButton(row,3,(state.distribute and "ACTIVE: " or "").."SPREAD ACROSS COMPATIBLE SHIPYARDS",state.distribute,true,function()state.distribute=true;state.plan=nil;state.result=nil;menu.refresh()end)
    row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,"PREVIEW FLEET BUILD - "..fleetShipCount(template).." SHIPS",function()state.plan=computeFleetBuildPlan(template,state.distribute==true);state.result=state.plan.error;menu.refresh()end,true)
    local plan=state.plan
    if plan then
        section(tableWidget,"FLEET BUILD PREVIEW")
        row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("PLAN: "..plan.total.." ship(s) across "..plan.yards.." player shipyard(s). Preview does not place orders.",{wordwrap=true})
        local jobs = plan.jobs or {}
        local firstJob, lastJob = menu.adaptiveListNavigation(tableWidget, "fleetbuild.plan.jobs", #jobs, { fixedRows = 22 + #templateEntries, rowUnits = 1 })
        for index = firstJob, lastJob do local job = jobs[index]; pair(tableWidget,job.yard.name,job.yard.sector,job.entry.name,job.amount) end
        if #(plan.skipped or {})>0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("SKIPPED - NO COMPATIBLE PLAYER YARD: "..table.concat(plan.skipped,", "),{wordwrap=true}) end
        row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,plan.submitted and "FLEET ORDER SUBMITTED - LOCKED" or "CONFIRM: BUILD THIS FLEET",function()
            local success,result=executeFleetBuildPlan(plan);state.result=result;raise(success and "fleetbuild.queued" or "fleetbuild.partial",{name=template.name,accepted=plan.accepted or 0,requested=plan.total or 0});menu.refresh()
        end,not plan.error and plan.total>0 and not plan.submitted,not plan.error and plan.total>0 and not plan.submitted and pendingChoiceBackground or nil)
    end
    if state.result then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("STATUS: "..state.result,{wordwrap=true}) end
    row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,"RETURN TO SAVED FLEET TEMPLATES",function()state.mode="list";state.plan=nil;state.result=nil;state.deleteConfirm=false;menu.refresh()end,true)
end
function menu.reconciledLogisticsCoverage()
    local merged, order = {}, {}
    for _, sourceRecord in ipairs(menu.logisticsCoverage or {}) do
        local key = text(v(sourceRecord, 1, "")) .. "|" .. menu.supplyWareId(v(sourceRecord, 2, ""))
        local record = merged[key]
        if not record then
            record = {}
            for index = 1, 16 do record[index] = v(sourceRecord, index, index == 11 and "" or 0) end
            merged[key] = record
            order[#order + 1] = record
        else
            record[5] = math.max(tonumber(record[5]) or 0, tonumber(v(sourceRecord, 5, 0)) or 0)
            record[6] = math.max(tonumber(record[6]) or 0, tonumber(v(sourceRecord, 6, 0)) or 0)
            for index = 7, 10 do record[index] = math.max(tonumber(record[index]) or 0, tonumber(v(sourceRecord, index, 0)) or 0) end
            if #text(v(sourceRecord, 11, "")) > #text(record[11]) then record[11] = v(sourceRecord, 11, "") end
            local currentSource, candidateSource = text(record[12]), text(v(sourceRecord, 12, "UNKNOWN"))
            local currentWeak = currentSource == "" or currentSource == "UNKNOWN" or currentSource == "UNKNOWN - NO CURRENT SOURCE PROOF" or currentSource == "SOURCE TEMPORARILY UNAVAILABLE"
            local candidateStrong = candidateSource ~= "" and candidateSource ~= "UNKNOWN" and candidateSource ~= "UNKNOWN - NO CURRENT SOURCE PROOF" and candidateSource ~= "SOURCE TEMPORARILY UNAVAILABLE"
            if currentWeak and candidateStrong then record[12] = candidateSource end
            record[13] = math.max(tonumber(record[13]) or 0, tonumber(v(sourceRecord, 13, 0)) or 0)
            record[14] = math.max(tonumber(record[14]) or 0, tonumber(v(sourceRecord, 14, 0)) or 0)
            if text(record[15]) == "" then record[15] = v(sourceRecord, 15, "SHARED POOL") end
            record[16] = math.max(tonumber(record[16]) or 0, tonumber(v(sourceRecord, 16, 0)) or 0)
            local currentRole, candidateRole = text(record[4]), text(v(sourceRecord, 4, "LOGISTICS"))
            if string.find(currentRole, "EMERGENCY", 1, true) and not string.find(candidateRole, "EMERGENCY", 1, true) then record[4] = candidateRole end
        end
    end
    return order
end

local function fleetCenter(tableWidget)
    local station = selectedStation()
    local stationName = text(v(station, 1, "SELECTED STATION"))
    local entries = {}

    local function selectFleetView(view)
        menu.fleetView = view
        menu.fleetPage = 1
        menu.coverageShipListKey = nil
        menu.refresh()
    end

    local function addEntry(entry)
        table.insert(entries, entry)
    end

    section(tableWidget, "FLEET & LOGISTICS CENTER")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("PURPOSE: EOC reports whether logistics needs player approval, a registered ship, or no change. Choose a view only when you want supporting details.", { wordwrap = true })
    section(tableWidget, "EOC CONCLUSION")
    local fleetConclusion = #menu.pendingAssignments > 0 and
        (#menu.pendingAssignments .. " assignment(s) await " .. (menu.shipmode == "APPROVAL REQUIRED" and "your approval." or "EOC processing.")) or
        (#menu.registeredShips == 0 and "No eligible logistics ships are registered." or "No assignment currently awaits player approval.")
    local fleetNext = #menu.pendingAssignments > 0 and "Open PENDING and review the first assignment." or
        (#menu.registeredShips == 0 and "Register suitable unassigned ships." or "Scan shipping needs only after station demand changes.")
    local fleetRow = tableWidget:addRow(false)
    fleetRow[1]:setColSpan(4):createText(fleetConclusion .. " DO THIS NEXT: " .. fleetNext, { wordwrap = true })
    pair(tableWidget, "ASSIGNMENT AUTHORITY", menu.shipmode, "TRADE AUTHORITY", menu.mode)
    local fleetScopeLabel = menu.fleetScope == "global" and "EMPIRE - ALL STATIONS" or
        ("SELECTED STATION - " .. stationName)
    local fleetViewLabels = {
        coverage = "LOGISTICS COVERAGE",
        stations = "STATIONS",
        ships = "REGISTERED AVAILABLE SHIPS",
        offers = "TRADE ACTIVITY",
        pending = "PENDING ASSIGNMENTS",
        staffing = "FLEET STAFFING",
        recommendations = "SHIP RECOMMENDATIONS",
        fleetbuild = "FLEET MANAGEMENT",
    }
    local fleetStatus = tableWidget:addRow(false)
    fleetStatus[1]:setColSpan(4):createText(
        "ACTIVE SCOPE: " .. fleetScopeLabel .. " | ACTIVE VIEW: " .. fleetViewLabels[menu.fleetView]
    )

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, (menu.fleetScope == "global" and "ACTIVE: " or "") .. "EMPIRE - ALL STATIONS", menu.fleetScope == "global", true, function()
        menu.fleetScope = "global"
        menu.coverageReturnContext = nil
        menu.fleetPage = 1
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, (menu.fleetScope == "station" and "ACTIVE: " or "") .. "SELECTED STATION", menu.fleetScope == "station", station ~= nil, function()
        menu.fleetScope = "station"
        menu.fleetPage = 1
        menu.refresh()
    end)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addModeButton(row, 1, (menu.fleetView == "staffing" and "ACTIVE: " or "") .. "DO MY STATIONS HAVE ENOUGH ASSIGNED SHIPS?", menu.fleetView == "staffing", true, function()
        selectFleetView("staffing")
    end)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addModeButton(row, 1, (menu.fleetView == "coverage" and "ACTIVE: " or "") .. "UNIFIED LOGISTICS COVERAGE", menu.fleetView == "coverage", true, function()
        selectFleetView("coverage")
    end)

    row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.fleetView == "stations" and "ACTIVE: " or "") .. "STATIONS", menu.fleetView == "stations", true, function()
        selectFleetView("stations")
    end)
    addModeButton(row, 2, (menu.fleetView == "ships" and "ACTIVE: " or "") .. "REGISTERED SHIPS", menu.fleetView == "ships", true, function()
        selectFleetView("ships")
    end)
    addModeButton(row, 3, (menu.fleetView == "offers" and "ACTIVE: " or "") .. "TRADE ACTIVITY", menu.fleetView == "offers", true, function()
        selectFleetView("offers")
    end)
    addModeButton(row, 4, (menu.fleetView == "pending" and "ACTIVE: " or "") .. "PENDING", menu.fleetView == "pending", true, function()
        selectFleetView("pending")
    end)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, (menu.fleetView == "recommendations" and "ACTIVE: " or "") .. "DOES A STATION NEED A SHIP?", menu.fleetView == "recommendations", true, function()
        selectFleetView("recommendations")
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, (menu.fleetView == "fleetbuild" and "ACTIVE: " or "") .. "FLEET MANAGEMENT", menu.fleetView == "fleetbuild", true, function()
        selectFleetView("fleetbuild")
    end)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "CLEAR FILTERS", function()
        menu.fleetScope = "global"
        menu.coverageReturnContext = nil
        menu.coverageSelected = nil
        menu.coverageShipListKey = nil
        menu.fleetPage = 1
        menu.refresh()
    end, menu.fleetScope ~= "global")

    if menu.fleetView == "fleetbuild" then
        fleetBuildManager(tableWidget)
        return
    end

    if menu.fleetView == "offers" then
        local tradeChoice = tableWidget:addRow(true)
        tradeChoice[1]:setColSpan(2)
        addModeButton(tradeChoice, 1, (menu.tradeActivityView == "empire" and "ACTIVE: " or "") .. "OBSERVED EMPIRE TRADE WORK", menu.tradeActivityView == "empire", true, function() menu.tradeActivityView = "empire"; menu.refresh() end)
        tradeChoice[3]:setColSpan(2)
        addModeButton(tradeChoice, 3, (menu.tradeActivityView == "eoc" and "ACTIVE: " or "") .. "EOC-MANAGED OFFERS", menu.tradeActivityView == "eoc", true, function() menu.tradeActivityView = "eoc"; menu.refresh() end)
        local tradeHelp = tableWidget:addRow(false)
        tradeHelp[1]:setColSpan(4):createText(menu.tradeActivityView == "empire" and
            "EMPIRE VIEW: Station-level activity observed by EOC's capacity sampler. OPEN REQUESTS are station demand calls; ACTIVE SHIPS are assigned ships currently working; QUEUED DEALS are ship trade deals. This is not an individual ware/order manifest and does not claim completed deliveries." or
            "EOC VIEW: Only offers created or tracked by EOC. VERIFIED means the offer still exists; it does not mean delivery completed.", { wordwrap = true, color = navigationStoryColor })
    end

    if menu.fleetView == "staffing" then
        section(tableWidget, "STATION FLEET REQUIREMENTS - PLAYER FLOOR + EOC LEARNED MINIMUM")
        local covered, missing, learning, learnedGaps, affectedStations = 0, 0, 0, 0, {}
        for _, record in ipairs(menu.minimumStaffing) do
            local gap = tonumber(v(record, 5, 0)) or 0
            if gap > 0 then missing = missing + 1; affectedStations[text(v(record, 1, "Unknown station"))] = true else covered = covered + 1 end
            local capacity = menu.capacityByRole[text(v(record, 1, "")) .. "|" .. text(v(record, 2, ""))]
            if not capacity or capacity.status == "LEARNING" then learning = learning + 1 elseif (tonumber(v(record, 3, 0)) or 0) < capacity.recommended then learnedGaps = learnedGaps + 1 end
        end
        local affectedCount = 0
        for _ in pairs(affectedStations) do affectedCount = affectedCount + 1 end
        local conclusion = tableWidget:addRow(false)
        conclusion[1]:setColSpan(4):createText(missing == 0 and
            ((missing == 0 and ("ALL " .. covered .. " PLAYER-CONFIGURED SHIP FLOORS ARE COVERED.") or (missing .. " SHIP ROLE(S) AT " .. affectedCount .. " STATION(S) ARE BELOW THE PLAYER FLOOR; " .. covered .. " meet it.")) .. " EOC CAPACITY: " .. learning .. " role(s) learning, " .. learnedGaps .. " mature role(s) below the learned operational minimum."),
            { wordwrap = true, color = missing == 0 and investigationPassColor or investigationUnknownColor, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
        local meaning = tableWidget:addRow(false)
        meaning[1]:setColSpan(4):createText("THIS PAGE COUNTS ASSIGNED SHIPS, NOT STATION EMPLOYEES. Example: '11 assigned | player floor 2 | EOC minimum 8' means you required at least 2, while current observed logistics evidence supports keeping 8.", { wordwrap = true })
        local authority = tableWidget:addRow(false)
        authority[1]:setColSpan(4):createText("AUTHORITY: OBSERVATION ONLY FOR LEARNED CAPACITY. The player floor remains the saved policy minimum. EOC's learned minimum changes with actual orders and repeated samples but cannot move, remove, build, or reassign a ship in this TEST build. Escorts remain under SSE control.", { wordwrap = true, color = navigationStoryColor })
        local learnedHelp = tableWidget:addRow(false)
        learnedHelp[1]:setColSpan(4):createText("EOC FOR DUMMIES: PLAYER FLOOR is the minimum you saved. EOC MINIMUM is the number currently supported by observed open station orders, active ship deals, cargo volume, and assigned capacity. LEARNING means EOC needs six five-minute samples. Recommendations can rise quickly, but fall only one ship after six lower-pressure samples.", { wordwrap = true })
        if #menu.minimumStaffing == 0 then
            local empty = tableWidget:addRow(false)
            empty[1]:setColSpan(4):createText("NO ACTIVE MINIMUMS: Every saved minimum is zero, or no applicable station currently exists. Zero means disabled. Open Global Settings to choose a target; saving a target does not create a free ship or bypass normal construction.", { wordwrap = true })
        else
            local filters = tableWidget:addRow(true)
            addModeButton(filters, 1, (menu.staffingFilter == "attention" and "ACTIVE: " or "") .. "BELOW PLAYER FLOOR (" .. missing .. ")", menu.staffingFilter == "attention", true, function() menu.staffingFilter = "attention"; menu.fleetPage = 1; menu.refresh() end)
            addModeButton(filters, 2, (menu.staffingFilter == "covered" and "ACTIVE: " or "") .. "PLAYER FLOOR COVERED (" .. covered .. ")", menu.staffingFilter == "covered", true, function() menu.staffingFilter = "covered"; menu.fleetPage = 1; menu.refresh() end)
            filters[3]:setColSpan(2)
            addModeButton(filters, 3, (menu.staffingFilter == "all" and "ACTIVE: " or "") .. "ALL FLEET REQUIREMENTS (" .. #menu.minimumStaffing .. ")", menu.staffingFilter == "all", true, function() menu.staffingFilter = "all"; menu.fleetPage = 1; menu.refresh() end)
            local records = {}
            for _, record in ipairs(menu.minimumStaffing) do
                local gap = tonumber(v(record, 5, 0)) or 0
                if menu.staffingFilter == "all" or (menu.staffingFilter == "attention" and gap > 0) or (menu.staffingFilter == "covered" and gap <= 0) then records[#records + 1] = record end
            end
            table.sort(records, function(a, b)
                local ag, bg = tonumber(v(a, 5, 0)) or 0, tonumber(v(b, 5, 0)) or 0
                if (ag > 0) ~= (bg > 0) then return ag > 0 end
                local as, bs = text(v(a, 1, "")), text(v(b, 1, ""))
                if as == bs then return text(v(a, 2, "")) < text(v(b, 2, "")) end
                return as < bs
            end)
            if #records == 0 then
                local none = tableWidget:addRow(false)
                none[1]:setColSpan(4):createText(menu.staffingFilter == "attention" and "NO ROLE IS BELOW THE PLAYER FLOOR. Choose PLAYER FLOOR COVERED or ALL FLEET REQUIREMENTS to inspect EOC's learned operational minimums." or "No ship roles match this filter.", { wordwrap = true, color = investigationPassColor })
            end
            local first, last = menu.adaptiveListNavigation(tableWidget, "fleet.staffing." .. tostring(menu.staffingFilter), #records, { fixedRows = 24, rowUnits = 2 })
            for index = first, last do
                local record = records[index]
                local current, target, gap = tonumber(v(record, 3, 0)) or 0, tonumber(v(record, 4, 0)) or 0, tonumber(v(record, 5, 0)) or 0
                local capacity = menu.capacityByRole[text(v(record, 1, "")) .. "|" .. text(v(record, 2, ""))]
                local result = gap > 0 and ("BELOW PLAYER FLOOR BY " .. gap) or "PLAYER FLOOR COVERED"
                local roleLine = tableWidget:addRow(false)
                roleLine[1]:setColSpan(4):createText(text(v(record, 1, "Unknown station")) .. " | " .. text(v(record, 2, "UNKNOWN ROLE")) .. ": " .. current .. " ASSIGNED | PLAYER FLOOR " .. target .. " | " .. (capacity and ("EOC MINIMUM " .. capacity.recommended .. " — " .. capacity.status .. " / " .. capacity.confidence .. " CONFIDENCE / " .. capacity.trend) or "EOC MINIMUM LEARNING — NO SAMPLE YET") .. " | " .. result, { wordwrap = true, color = gap > 0 and investigationUnknownColor or investigationPassColor })
                local evidenceLine = tableWidget:addRow(false)
                evidenceLine[1]:setColSpan(4):createText(capacity and ("EVIDENCE: " .. capacity.openorders .. " open order(s), " .. capacity.active .. " active ship(s), " .. capacity.deals .. " queued deal(s), " .. capacity.openvolume .. " cargo-volume requested, " .. capacity.capacity .. " assigned cargo capacity, sample " .. capacity.samples .. ". " .. capacity.reason) or "EVIDENCE: Waiting for the first five-minute capacity sample. No fleet action is authorized.", { wordwrap = true, color = navigationStoryColor })
            end
        end
        local settingsRoute = tableWidget:addRow(true)
        settingsRoute[1]:setColSpan(4)
        addButton(settingsRoute, 1, "OPEN GLOBAL SETTINGS - CHANGE SHIP MINIMUMS OR AUTHORITY", function() menu.page = "settings"; menu.activeTab = "settings"; menu.refresh() end, true)
        return
    end

    if menu.fleetView == "coverage" then
        do
        section(tableWidget, "EOC 3.6 LOGISTICS EXCEPTION DASHBOARD")
        local intro = tableWidget:addRow(false)
        intro[1]:setColSpan(4):createText("Healthy evidence is summarized. Actionable exceptions are shown first. Select a station, then select one resource card for complete ship and source evidence.", { wordwrap = true })

        local reconciledCoverage = menu.reconciledLogisticsCoverage()

        local function coverageState(record)
            local stock, target = tonumber(v(record, 5, 0)) or 0, tonumber(v(record, 6, 0)) or 0
            local assigned, working = tonumber(v(record, 7, 0)) or 0, tonumber(v(record, 8, 0)) or 0
            local blocked, lastMovement = tonumber(v(record, 10, 0)) or 0, tonumber(v(record, 13, 0)) or 0
            local samples, eligible = tonumber(v(record, 14, 1)) or 1, tonumber(v(record, 16, 0)) or 0
            local role, source = text(v(record, 4, "LOGISTICS")), text(v(record, 12, "UNKNOWN"))
            local sufficientlyStocked = target > 0 and stock >= target * 0.95
            if sufficientlyStocked then return working > 0 and ("COVERED — " .. tostring(working) .. " SHIPS WORKING") or "COVERED — STOCK SUFFICIENT", 3 end
            if lastMovement > 0 and working > 0 then return "COVERED — " .. tostring(working) .. " SHIPS WORKING", 3 end
            if blocked > 0 and working <= 0 then return "BLOCKED", 1 end
            if source == "SOURCE TEMPORARILY UNAVAILABLE" and stock < target then return "SOURCE UNAVAILABLE", 1 end
            if assigned <= 0 and stock < target then return eligible > 0 and "ADD 1 SHIP" or "NO ELIGIBLE SHIP", 1 end
            if string.find(role, "EMERGENCY", 1, true) then return lastMovement > 0 and "COVERED" or "AWAITING DELIVERY", lastMovement > 0 and 3 or 2 end
            if target > 0 and stock >= target then return "COVERED", 3 end
            if assigned > 0 or samples <= 1 then return "AWAITING DELIVERY", 2 end
            return "EVIDENCE UNKNOWN", 2
        end

        local function coverageKey(record)
            return text(v(record, 1, "")) .. "|" .. text(v(record, 2, "")) .. "|" .. text(v(record, 4, ""))
        end

        if menu.fleetScope == "global" then
            local summaries, order = {}, {}
            for _, record in ipairs(reconciledCoverage) do
                local stationValue = text(v(record, 1, "Unknown station"))
                local summary = summaries[stationValue]
                if not summary then summary = { name = stationValue, covered = 0, waiting = 0, action = 0, total = 0 }; summaries[stationValue] = summary; order[#order + 1] = summary end
                local _, severity = coverageState(record)
                summary.total = summary.total + 1
                if severity == 1 then summary.action = summary.action + 1 elseif severity == 2 then summary.waiting = summary.waiting + 1 else summary.covered = summary.covered + 1 end
            end
            table.sort(order, function(a, b) if a.action == b.action then return a.name < b.name end return a.action > b.action end)
            local totals = tableWidget:addRow(false)
            local actionTotal, waitingTotal, coveredTotal = 0, 0, 0
            for _, summary in ipairs(order) do actionTotal = actionTotal + summary.action; waitingTotal = waitingTotal + summary.waiting; coveredTotal = coveredTotal + summary.covered end
            totals[1]:setColSpan(4):createText("EMPIRE SUMMARY — " .. actionTotal .. " ACTIONABLE | " .. waitingTotal .. " AWAITING EVIDENCE | " .. coveredTotal .. " COVERED | " .. #order .. " STATIONS", { halign = "center", color = actionTotal > 0 and investigationUnknownColor or investigationPassColor })
            local cardUnits = math.max(1, math.ceil(menu.supplyCardHeight() / math.max(1, Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize)))
            local first, last = menu.adaptiveListNavigation(tableWidget, "fleet.coverage.empire", #order, { fixedRows = 11, rowUnits = cardUnits, columns = 2 })
            for index = first, last, 2 do
                local cardRow = tableWidget:addRow(true)
                for slot = 0, 1 do
                    local summary = order[index + slot]
                    if summary then
                        local column = slot == 0 and 1 or 3
                        cardRow[column]:setColSpan(2)
                        local label = summary.name .. "\n" .. summary.action .. " ACTIONABLE | " .. summary.waiting .. " WAITING | " .. summary.covered .. " COVERED"
                        addButton(cardRow, column, label, function()
                            menu.coverageReturnContext = { scope = "global", filter = menu.coverageFilter or "action", page = menu.fleetPage or 1 }
                            for profileIndex, profile in ipairs(menu.stations or {}) do if text(v(profile, 1, "")) == summary.name then menu.selected = profileIndex break end end
                            menu.fleetScope = "station"; menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.coverageFilter = "action"; menu.fleetPage = 1; menu.refresh()
                        end, true, inactiveModeBackground, menu.supplyCardHeight(), summary.action > 0 and investigationUnknownColor or investigationPassColor, true, true)
                    end
                end
            end
            return
        end

        if menu.coverageReturnContext then
            local backRow = tableWidget:addRow(true)
            backRow[1]:setColSpan(4)
            addButton(backRow, 1, "BACK TO EMPIRE SUMMARY", function()
                local origin = menu.coverageReturnContext
                menu.fleetScope = origin.scope or "global"
                menu.coverageFilter = origin.filter or "action"
                menu.fleetPage = origin.page or 1
                menu.coverageSelected = nil
                menu.coverageShipListKey = nil
                menu.coverageReturnContext = nil
                menu.refresh()
            end, true)
        end

        local filterRow = tableWidget:addRow(true)
        menu.coverageFilter = menu.coverageFilter or "action"
        addModeButton(filterRow, 1, (menu.coverageFilter == "action" and "ACTIVE: " or "") .. "ACTIONABLE", menu.coverageFilter == "action", true, function() menu.coverageFilter = "action"; menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.fleetPage = 1; menu.refresh() end)
        addModeButton(filterRow, 2, (menu.coverageFilter == "waiting" and "ACTIVE: " or "") .. "WAITING", menu.coverageFilter == "waiting", true, function() menu.coverageFilter = "waiting"; menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.fleetPage = 1; menu.refresh() end)
        addModeButton(filterRow, 3, (menu.coverageFilter == "covered" and "ACTIVE: " or "") .. "COVERED", menu.coverageFilter == "covered", true, function() menu.coverageFilter = "covered"; menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.fleetPage = 1; menu.refresh() end)
        addModeButton(filterRow, 4, (menu.coverageFilter == "all" and "ACTIVE: " or "") .. "ALL EVIDENCE", menu.coverageFilter == "all", true, function() menu.coverageFilter = "all"; menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.fleetPage = 1; menu.refresh() end)

        local selectedName = text(v(selectedStation(), 1, ""))
        local records = {}
        for _, record in ipairs(reconciledCoverage) do
            if text(v(record, 1, "")) == selectedName then
                local state, severity = coverageState(record)
                if menu.coverageFilter == "all" or (menu.coverageFilter == "action" and severity == 1) or (menu.coverageFilter == "waiting" and severity == 2) or (menu.coverageFilter == "covered" and severity == 3) then records[#records + 1] = { raw = record, state = state, severity = severity } end
            end
        end
        table.sort(records, function(a, b) if a.severity == b.severity then return text(v(a.raw, 3, "")) < text(v(b.raw, 3, "")) end return a.severity < b.severity end)

        local selected
        if menu.coverageSelected then for _, item in ipairs(records) do if coverageKey(item.raw) == menu.coverageSelected then selected = item break end end end
        if selected then
            local record = selected.raw
            local selectedKey = coverageKey(record)
            if menu.coverageShipListKey == selectedKey then
                local backToEvidence = tableWidget:addRow(true)
                backToEvidence[1]:setColSpan(4)
                addButton(backToEvidence, 1, "BACK TO " .. string.upper(text(v(record, 3, "WARE"))) .. " EVIDENCE", function() menu.coverageShipListKey = nil; menu.refresh() end, true)
                section(tableWidget, selectedName .. " — SHARED ASSIGNMENT POOL")
                local boundary = tableWidget:addRow(false)
                boundary[1]:setColSpan(4):createText("EVIDENCE BOUNDARY: These are station subordinates reported in the shared assignment pool. This list does not prove that each ship serves " .. text(v(record, 3, "this ware")) .. ".", { wordwrap = true, color = navigationStoryColor })
                local shipNames = {}
                for name in string.gmatch(text(v(record, 11, "")), "([^,]+)") do
                    local clean = string.gsub(name, "^%s+", "")
                    clean = string.gsub(clean, "%s+$", "")
                    if clean ~= "" then shipNames[#shipNames + 1] = clean end
                end
                local header = tableWidget:addRow(false)
                header[1]:createText("SHIP", { color = navigationStoryColor, font = Helper.headerFont })
                header[2]:createText("PURPOSE", { color = navigationStoryColor, font = Helper.headerFont })
                header[3]:createText("STATION", { color = navigationStoryColor, font = Helper.headerFont })
                header[4]:createText("WARE PROOF", { color = navigationStoryColor, font = Helper.headerFont })
                local firstShip, lastShip = menu.adaptiveListNavigation(tableWidget, "fleet.coverage.ships." .. selectedKey, #shipNames, { fixedRows = 24, rowUnits = 1, maximum = 8 })
                for shipIndex = firstShip, lastShip do
                    local shipRow = tableWidget:addRow(false)
                    shipRow[1]:createText(shipNames[shipIndex], { wordwrap = true })
                    shipRow[2]:createText(string.find(string.upper(text(v(record, 4, "LOGISTICS"))), "RAW RESOURCE", 1, true) and "MINING" or "LOGISTICS")
                    shipRow[3]:createText(selectedName, { wordwrap = true })
                    shipRow[4]:createText("SHARED POOL — UNPROVEN", { wordwrap = true, color = investigationUnknownColor })
                end
                if #shipNames == 0 then
                    local noShips = tableWidget:addRow(false)
                    noShips[1]:setColSpan(4):createText("No individual ship names were transported for this shared-pool record.", { wordwrap = true, color = investigationUnknownColor })
                end
                local readOnly = tableWidget:addRow(false)
                readOnly[1]:setColSpan(4):createText("READ-ONLY SUPPORTING EVIDENCE: Do not change assignments from this view.", { wordwrap = true, color = navigationStoryColor })
                return
            end
            local back = tableWidget:addRow(true); back[1]:setColSpan(4); addButton(back, 1, "BACK TO " .. string.upper(menu.coverageFilter) .. " CARDS", function() menu.coverageSelected = nil; menu.coverageShipListKey = nil; menu.refresh() end, true)
            section(tableWidget, selectedName .. " — " .. text(v(record, 3, "Unknown ware")))
            pair(tableWidget, "ROLE", text(v(record, 4, "LOGISTICS")), "STATUS", selected.state)
            pair(tableWidget, "STOCK / TARGET", formatNumber(v(record, 5, 0)) .. " / " .. formatNumber(v(record, 6, 0)), "SHARED ASSIGNMENT POOL", tostring(v(record, 7, 0)) .. " SHIP(S)")
            pair(tableWidget, "WORK / WAIT / BLOCK", tostring(v(record, 8, 0)) .. " / " .. tostring(v(record, 9, 0)) .. " / " .. tostring(v(record, 10, 0)), "ELIGIBLE AVAILABLE", v(record, 16, 0))
            local assignmentEvidence = tableWidget:addRow(false)
            assignmentEvidence[1]:setColSpan(4):createText("ASSIGNMENT EVIDENCE: " .. tostring(v(record, 7, 0)) .. " station subordinate(s) | " .. text(v(record, 15, "SHARED POOL")) .. ". Assignment count alone does not prove ware-specific delivery.", { wordwrap = true })
            local sourceEvidence = tableWidget:addRow(false)
            sourceEvidence[1]:setColSpan(4):createText("SOURCE EVIDENCE: " .. text(v(record, 12, "UNKNOWN")) .. " | LAST CONFIRMED MOVEMENT: " .. ((tonumber(v(record, 13, 0)) or 0) > 0 and menu.supplyElapsedLabel(v(record, 13, 0)) or "NOT YET OBSERVED"), { wordwrap = true, color = text(v(record, 12, "UNKNOWN")) == "SOURCE TEMPORARILY UNAVAILABLE" and investigationFailColor or navigationStoryColor })
            if text(v(record, 11, "")) ~= "" then
                local shipList = tableWidget:addRow(true)
                shipList[1]:setColSpan(4)
                addButton(shipList, 1, "VIEW " .. tostring(v(record, 7, 0)) .. " ASSIGNED SHIPS", function()
                    menu.coverageShipListKey = selectedKey
                    menu.listPages = menu.listPages or {}
                    menu.listPages["fleet.coverage.ships." .. selectedKey] = 1
                    menu.refresh()
                end, true)
            end
            local nextText
            if text(v(record, 12, "UNKNOWN")) == "SOURCE TEMPORARILY UNAVAILABLE" then
                nextText = "DO THIS NEXT: Do not assign another ship yet. Confirm a reachable source or wait for new stock-movement evidence, then refresh this card."
            elseif selected.state == "NO ELIGIBLE SHIP" or selected.state == "ADD 1 SHIP" then
                nextText = "DO THIS NEXT: Open Registered Ships and verify one compatible unassigned ship before changing assignment authority."
            elseif selected.severity == 3 then
                nextText = "DO THIS NEXT: No assignment change is required."
            else
                nextText = "DO THIS NEXT: Keep the current assignment unchanged until EOC records delivery or stronger source evidence."
            end
            local nextRow = tableWidget:addRow(false)
            nextRow[1]:setColSpan(4):createText(nextText, { wordwrap = true, color = navigationStoryColor })
            return
        end

        local summary = tableWidget:addRow(false); summary[1]:setColSpan(4):createText(selectedName .. " — " .. #records .. " " .. string.upper(menu.coverageFilter) .. " RECORD(S) | SELECT ONE FOR FULL EVIDENCE", { halign = "center" })
        if #records == 0 then local empty = tableWidget:addRow(false); empty[1]:setColSpan(4):createText("No records match this station and filter. Choose ALL EVIDENCE to inspect this station, or BACK TO EMPIRE SUMMARY to return to the station boxes.", { wordwrap = true }); return end
        local cardUnits = math.max(1, math.ceil(menu.supplyCardHeight() / math.max(1, Helper.scaleY(Helper.standardTextHeight) + Helper.borderSize)))
        local first, last = menu.adaptiveListNavigation(tableWidget, "fleet.coverage.station." .. tostring(menu.coverageFilter), #records, { fixedRows = 20, rowUnits = cardUnits, columns = 2 })
        for index = first, last, 2 do
            local cardRow = tableWidget:addRow(true)
            for slot = 0, 1 do
                local item = records[index + slot]
                if item then
                    local record, column = item.raw, slot == 0 and 1 or 3; cardRow[column]:setColSpan(2)
                    local label = text(v(record, 3, "Unknown ware")) .. " — " .. item.state .. "\n" .. formatNumber(v(record, 5, 0)) .. " / " .. formatNumber(v(record, 6, 0)) .. " STOCK | " .. tostring(v(record, 8, 0)) .. "/" .. tostring(v(record, 9, 0)) .. "/" .. tostring(v(record, 10, 0)) .. " WORK/WAIT/BLOCK"
                    addButton(cardRow, column, label, function() menu.coverageShipListKey = nil; menu.coverageSelected = coverageKey(record); menu.refresh() end, true, inactiveModeBackground, menu.supplyCardHeight(), item.severity == 1 and investigationFailColor or item.severity == 2 and investigationUnknownColor or investigationPassColor, true, true)
                end
            end
        end
        return
        end

        -- Retained below only as unreachable Build 307 comparison code during
        -- static regression review; Build 308 exits through the dashboard above.
        section(tableWidget, "EOC 3.6 UNIFIED LOGISTICS COVERAGE")
        local explanation = tableWidget:addRow(false)
        explanation[1]:setColSpan(4):createText("This view joins current station stock and production rates with exact station assignments, working/waiting/blocked evidence, EOC-managed actions, source proof, and confirmed stock movement. Ordinary X4 station traders are a shared pool; EOC will not invent a ware-specific route.", { wordwrap = true })
        local refreshRow = tableWidget:addRow(true)
        refreshRow[1]:setColSpan(4)
        addButton(refreshRow, 1, "REFRESH STOCK & RATE EVIDENCE", function()
            menu.supplyRun("overview")
        end, true)

        local supplyByStationWare = {}
        local store = menu.supplyModelStore()
        local currentSupply = store.views and store.views.overview and store.views.overview.current or nil
        for _, supplyStation in ipairs((currentSupply and currentSupply.stations) or {}) do
            for _, ware in ipairs(supplyStation.wares or {}) do
                supplyByStationWare[text(supplyStation.name) .. "|" .. menu.supplyWareId(ware.ware)] = ware
            end
        end

        local function constructionRequired(stationNameValue, wareNameValue)
            for _, caseData in ipairs(menu.cases or {}) do
                if text(v(caseData, 1, "")) == stationNameValue and text(v(caseData, 4, "")) == wareNameValue then
                    local evidence = string.upper(text(v(caseData, 3, "")) .. " " .. text(v(caseData, 6, "")))
                    if string.find(evidence, "NO STORAGE", 1, true) or string.find(evidence, "CONSTRUCTION REQUIRED", 1, true) then return true end
                end
            end
            return false
        end

        local coverageRows = {}
        for _, record in ipairs(menu.logisticsCoverage or {}) do
            local stationNameValue = text(v(record, 1, "Unknown station"))
            if menu.fleetScope == "global" or stationNameValue == stationName then coverageRows[#coverageRows + 1] = record end
        end
        -- Ships Trade Analyzer proved that X4 exposes a shared pool of 170 table
        -- rows. Keep five for other windows and the first-draw limbo row, then
        -- constrain the retained coverage slice by both the remaining 164-row
        -- pool and the live pixel height. A coverage record owns six fixed rows.
        local rowPitch = Helper.scaleY(Helper.standardTextHeight)
        local measured, measuredHeight = pcall(function()
            local fontsize = Helper.scaleFont(Helper.standardFont, Helper.standardFontSize)
            return math.ceil(C.GetTextHeight("Ag", Helper.standardFont, math.floor(fontsize), 0))
        end)
        if measured and type(measuredHeight) == "number" then
            rowPitch = math.max(rowPitch, Helper.scaleY(Helper.standardTextOffsety) + measuredHeight)
        end
        rowPitch = rowPitch + Helper.borderSize
        local fixedRows = 22
        if menu.clickStatus and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then fixedRows = fixedRows + 1 end
        if menu.navigationOrigin and menu.page ~= menu.navigationOrigin.page then fixedRows = fixedRows + 1 end
        local contentPixels = tonumber(menu.coverageContentHeight) or Helper.scaleY(config.maxHeight)
        local pixelRows = math.max(1, math.floor(contentPixels / rowPitch) - fixedRows)
        local poolRows = math.max(1, (170 - 5 - 1) - fixedRows)
        local recordsPerPage = math.max(1, math.floor(math.min(pixelRows, poolRows) / 6))
        local pageCount = math.max(1, math.ceil(#coverageRows / recordsPerPage))
        menu.fleetPage = math.max(1, math.min(pageCount, tonumber(menu.fleetPage) or 1))
        local firstRecord = (menu.fleetPage - 1) * recordsPerPage + 1
        local lastRecord = math.min(#coverageRows, firstRecord + recordsPerPage - 1)
        local nav = tableWidget:addRow(true)
        addButton(nav, 1, "PREVIOUS", function() menu.fleetPage = math.max(1, menu.fleetPage - 1); menu.refresh() end, menu.fleetPage > 1)
        nav[2]:createText("PAGE " .. tostring(menu.fleetPage) .. " / " .. tostring(pageCount) .. " — " .. tostring(#coverageRows) .. " RECORDS", { halign = "center" })
        addButton(nav, 3, "NEXT", function() menu.fleetPage = math.min(pageCount, menu.fleetPage + 1); menu.refresh() end, menu.fleetPage < pageCount)
        nav[4]:createText(tostring(recordsPerPage) .. " RECORDS PER PAGE", { halign = "center" })

        for recordIndex = firstRecord, lastRecord do
            local record = coverageRows[recordIndex]
            if record then
                local stationNameValue = text(v(record, 1, "Unknown station"))
                local wareId = menu.supplyWareId(v(record, 2, ""))
                local wareNameValue = text(v(record, 3, "Unknown ware"))
                local role = text(v(record, 4, "LOGISTICS"))
                local stock = tonumber(v(record, 5, 0)) or 0
                local target = tonumber(v(record, 6, 0)) or 0
                local assigned = tonumber(v(record, 7, 0)) or 0
                local working = tonumber(v(record, 8, 0)) or 0
                local waiting = tonumber(v(record, 9, 0)) or 0
                local blocked = tonumber(v(record, 10, 0)) or 0
                local shipNames = text(v(record, 11, ""))
                local source = text(v(record, 12, "UNKNOWN - NO CURRENT SOURCE PROOF"))
                local lastMovement = tonumber(v(record, 13, 0)) or 0
                local samples = tonumber(v(record, 14, 1)) or 1
                local assignmentScope = text(v(record, 15, "SHARED POOL"))
                local eligible = tonumber(v(record, 16, 0)) or 0
                local supply = supplyByStationWare[stationNameValue .. "|" .. wareId]
                local production = supply and (tonumber(supply.effectiveProduction) or 0) or 0
                local consumption = supply and (tonumber(supply.effectiveConsumption) or 0) or 0
                if supply then stock = tonumber(supply.stock) or stock end

                local state
                if constructionRequired(stationNameValue, wareNameValue) then
                    state = "PLAYER CONSTRUCTION REQUIRED"
                elseif string.find(role, "EMERGENCY", 1, true) then
                    state = lastMovement > 0 and "COVERED — STOCK MOVEMENT CONFIRMED" or "AWAITING FIRST DELIVERY"
                elseif source == "SOURCE TEMPORARILY UNAVAILABLE" and stock < target then
                    state = "SOURCE TEMPORARILY UNAVAILABLE"
                elseif assigned <= 0 and stock < target then
                    state = eligible > 0 and "MORE CAPACITY NEEDED — ADD 1 SHIP" or "NO ELIGIBLE SHIP AVAILABLE"
                elseif blocked > 0 and working <= 0 then
                    state = "BLOCKED — " .. tostring(blocked) .. " SHIP(S) NOT OPERATIONAL"
                elseif target > 0 and stock >= target then
                    state = working > 0 and ("COVERED — " .. tostring(working) .. " SHIPS WORKING") or "COVERED — STOCK AT TARGET"
                elseif lastMovement > 0 then
                    state = "COVERED — " .. tostring(working) .. " SHIPS WORKING"
                elseif assigned > 0 and samples <= 1 then
                    state = "AWAITING FIRST DELIVERY"
                elseif assigned > 0 then
                    state = "AWAITING FIRST DELIVERY"
                else
                    state = "COVERAGE UNKNOWN — REFRESH EVIDENCE"
                end

                section(tableWidget, stationNameValue .. " — " .. wareNameValue)
                pair(tableWidget, "ROLE", role, "STATUS", state)
                pair(tableWidget, "STOCK / TARGET", formatNumber(stock) .. " / " .. formatNumber(target), "RATE PROD / USE", formatNumber(production) .. "/h / " .. formatNumber(consumption) .. "/h")
                pair(tableWidget, "SHIPS ASSIGNED", tostring(assigned), "WORK / WAIT / BLOCK", tostring(working) .. " / " .. tostring(waiting) .. " / " .. tostring(blocked))
                local shipsRow = tableWidget:addRow(false)
                shipsRow[1]:setColSpan(4):createText("ASSIGNED SHIPS: " .. (shipNames ~= "" and shipNames or "NONE") .. " | " .. assignmentScope, { wordwrap = false })
                local evidenceRow = tableWidget:addRow(false)
                evidenceRow[1]:setColSpan(4):createText("SOURCE: " .. source .. " | LAST CONFIRMED MOVEMENT: " .. (lastMovement > 0 and menu.supplyElapsedLabel(lastMovement) or "NOT YET OBSERVED"), { wordwrap = false })
            end
        end
        if #coverageRows == 0 then
            local empty = tableWidget:addRow(false)
            empty[1]:setColSpan(4):createText("No logistics coverage records match the active scope. EOC will rebuild this evidence during its established empire-analysis cycle; no player refresh is required.", { wordwrap = true })
        end
        return
    end

    if menu.fleetView == "stations" then
        for _, profile in ipairs(menu.stations) do
            if menu.fleetScope == "global" or text(v(profile, 1, "")) == stationName then
                addEntry({
                    text(v(profile, 1, "Station")),
                    "Assigned: " .. text(v(profile, 9, 0)),
                    "MINERS / TRADERS",
                    text(v(profile, 10, 0)) .. " / " .. text(v(profile, 11, 0)),
                })
            end
        end
    elseif menu.fleetView == "ships" then
        for _, ship in ipairs(menu.registeredShips) do
            addEntry({
                v(ship, 1, "Ship"),
                v(ship, 2, "UNKNOWN PURPOSE"),
                "STATE / COMMANDER",
                (v(ship, 4, false) and "OPERATIONAL" or "NOT OPERATIONAL") .. " / " .. text(v(ship, 5, "AVAILABLE")),
            })
        end
    elseif menu.fleetView == "offers" then
        if menu.tradeActivityView == "eoc" then
            for _, offer in ipairs(menu.tradeOffers) do
                if menu.fleetScope == "global" or text(v(offer, 1, "")) == stationName then
                    addEntry({ v(offer, 1, "Station"), text(v(offer, 2, "OFFER")) .. " " .. text(v(offer, 3, "Ware")), "AMOUNT / OFFER STATUS", formatNumber(v(offer, 4, 0)) .. " / " .. (v(offer, 5, false) and "VERIFIED" or "UNVERIFIED") })
                end
            end
        else
            for _, activity in ipairs(menu.capacityRecords or {}) do
                if string.find(activity.role or "", "TRADE", 1, true) and (menu.fleetScope == "global" or activity.station == stationName) then
                    addEntry({ activity.station, activity.role, "OPEN REQUESTS / ACTIVE SHIPS / QUEUED DEALS", tostring(activity.openorders) .. " / " .. tostring(activity.active) .. " / " .. tostring(activity.deals) })
                end
            end
        end
    elseif menu.fleetView == "recommendations" then
        local function blueprintMatchesCargo(blueprint, cargo, size)
            local blueprintSize = text(v(blueprint, 2, "")):upper()
            local macroId = text(v(blueprint, 3, "")):lower()
            local roleMatch = (cargo == "CONTAINER" and macroId:find("_trans_", 1, true)) or
                (cargo == "SOLID" and macroId:find("_miner_solid_", 1, true)) or
                (cargo == "LIQUID" and macroId:find("_miner_liquid_", 1, true))
            return roleMatch and blueprintSize == size
        end
        local function findBestWharf(caseStation, macroId)
            local best, bestScore
            for _, route in ipairs(menu.shipWharfRoutes) do
                if text(v(route, 4, "")) == caseStation and text(v(route, 9, "")) == macroId then
                    local distance = tonumber(v(route, 5, -1)) or -1
                    local queued = tonumber(v(route, 6, 0)) or 0
                    local inprogress = tonumber(v(route, 7, 0)) or 0
                    local distanceScore = distance >= 0 and distance or 9999
                    local score = distanceScore * 10000 + queued + inprogress
                    if not bestScore or score < bestScore then best, bestScore = route, score end
                end
            end
            return best, bestScore
        end
        local function findBestLogisticsOption(caseStation, cargo, size)
            local firstOwned, bestBlueprint, bestWharf, bestScore
            for _, blueprint in ipairs(menu.shipBlueprints) do
                if blueprintMatchesCargo(blueprint, cargo, size) then
                    firstOwned = firstOwned or blueprint
                    local wharf, score = findBestWharf(caseStation, text(v(blueprint, 3, "")))
                    if wharf and (not bestScore or score < bestScore) then
                        bestBlueprint, bestWharf, bestScore = blueprint, wharf, score
                    end
                end
            end
            return bestBlueprint or firstOwned, bestWharf
        end
        local seen = {}
        for _, case in ipairs(menu.cases) do
            local caseStation = text(v(case, 1, "Unknown station"))
            local cargo = text(v(case, 12, "UNKNOWN")):upper()
            local compatible = tonumber(v(case, 24, 0)) or 0
            local current = tonumber(v(case, 8, 0)) or 0
            local target = tonumber(v(case, 9, 0)) or 0
            local supportedCargo = cargo == "CONTAINER" or cargo == "SOLID" or cargo == "LIQUID"
            local key = caseStation .. "|" .. cargo
            if not seen[key] and supportedCargo and compatible == 0 and target > current and
                (not menu.fleetRecommendationCargo or cargo == menu.fleetRecommendationCargo) and
                (menu.fleetScope == "global" or caseStation == stationName) then
                seen[key] = true
                local mediumBlueprint, mediumWharf = findBestLogisticsOption(caseStation, cargo, "M")
                local largeBlueprint, largeWharf = findBestLogisticsOption(caseStation, cargo, "L")
                addEntry({
                    caseStation,
                    text(v(case, 4, "Logistics shortage")),
                    cargo,
                    mediumBlueprint or false,
                    mediumWharf or false,
                    largeBlueprint or false,
                    largeWharf or false,
                })
            end
        end
    else
        for _, pending in ipairs(menu.pendingAssignments) do
            if menu.fleetScope == "global" or text(v(pending, 2, "")) == stationName then
                addEntry({
                    v(pending, 1, "Ship"),
                    v(pending, 2, "Unknown station"),
                    v(pending, 3, "LOGISTICS"),
                    v(pending, 4, "AWAITING APPROVAL"),
                })
            end
        end
    end

    local viewTitles = {
        stations = "STATION LOGISTICS",
        ships = "REGISTERED AVAILABLE SHIPS",
        offers = menu.tradeActivityView == "eoc" and "EOC-MANAGED OFFERS" or "OBSERVED EMPIRE TRADE WORK",
        pending = "PENDING ASSIGNMENTS",
        staffing = "FLEET STAFFING",
        recommendations = "SHIP RECOMMENDATIONS",
        fleetbuild = "FLEET MANAGEMENT",
    }
    section(tableWidget, viewTitles[menu.fleetView] .. "  |  " .. #entries .. " RECORD(S)  |  ADAPTIVE SCREEN BOUNDARY")

    if menu.fleetView == "recommendations" and menu.fleetRecommendationCargo then
        local routed = tableWidget:addRow(false)
        routed[1]:setColSpan(4):createText("PREDICTIVE ROUTE: Showing the exact " .. menu.fleetRecommendationCargo .. " ship-construction need for " .. stationName .. ". Review the evidence, choose a size when required, preview, then confirm exactly one ship. Use the return button above to continue the Predictive issue list.", { wordwrap = true, color = navigationStoryColor })
        local showAll = tableWidget:addRow(true)
        showAll[1]:setColSpan(4)
        addButton(showAll, 1, "SHOW ALL SHIP RECOMMENDATIONS", function() menu.fleetRecommendationCargo = nil; menu.refresh() end, true)
    end

    if #entries == 0 then
        local emptyMessages = {
            stations = "No station logistics records match the selected scope.",
            ships = "No eligible ships are registered. Use Register Suitable Unassigned Ships below. EOC accepts operational M/L/XL trade or mining ships with supported cargo, plus tug-class salvage ships, with no commander or subordinates.",
            offers = menu.tradeActivityView == "eoc" and "No EOC-created or EOC-tracked offers match this scope." or "UNKNOWN — no dynamic capacity snapshot is available for this scope. EOC will populate it through the established sampler without player babysitting.",
            pending = menu.shipmode == "APPROVAL REQUIRED" and
                "No assignments await approval. Entries appear when EOC finds a supported need and a compatible registered ship." or
                "No assignments await approval. Pending normally remains empty unless Ship Assignment Authority is Approval Required.",
            recommendations = "No verified case currently shows both a real logistics shortfall and zero compatible ships. EOC will not recommend purchasing a ship without that evidence.",
        }
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:createText("STATUS")
        statusRow[2]:setColSpan(3):createText(emptyMessages[menu.fleetView], { wordwrap = true })
    else
        local first, last = menu.adaptiveListNavigation(tableWidget, "fleet." .. tostring(menu.fleetView), #entries, { fixedRows = menu.fleetView == "recommendations" and 28 or 18, rowUnits = menu.fleetView == "recommendations" and 12 or 1 })
        for index = first, last do
            local entry = entries[index]
            if menu.fleetView == "recommendations" then
                local caseStation = text(entry[1])
                local cargo = text(entry[3])
                local mediumBlueprint = type(entry[4]) == "table" and entry[4] or nil
                local mediumWharf = type(entry[5]) == "table" and entry[5] or nil
                local largeBlueprint = type(entry[6]) == "table" and entry[6] or nil
                local largeWharf = type(entry[7]) == "table" and entry[7] or nil
                local mediumAvailable = mediumBlueprint ~= nil and mediumWharf ~= nil
                local largeAvailable = largeBlueprint ~= nil and largeWharf ~= nil
                local orderKey = caseStation .. "|" .. cargo
                local persisted = existingShipOrder(caseStation, cargo)
                local orderState = menu.shipOrderState[orderKey] or {}
                menu.shipOrderState[orderKey] = orderState

                if persisted and not orderState.selectedSize then
                    local persistedMacro = text(v(persisted, 3, ""))
                    if mediumBlueprint and text(v(mediumBlueprint, 3, "")) == persistedMacro then
                        orderState.selectedSize = "M"
                    elseif largeBlueprint and text(v(largeBlueprint, 3, "")) == persistedMacro then
                        orderState.selectedSize = "L"
                    end
                elseif not orderState.selectedSize and mediumAvailable ~= largeAvailable then
                    orderState.selectedSize = mediumAvailable and "M" or "L"
                end

                local selectedSize = orderState.selectedSize
                local selectedBlueprint = selectedSize == "M" and mediumBlueprint or selectedSize == "L" and largeBlueprint or nil
                local selectedWharf = selectedSize == "M" and mediumWharf or selectedSize == "L" and largeWharf or nil
                local selectedAvailable = selectedBlueprint ~= nil and selectedWharf ~= nil
                local selectedShip = selectedBlueprint and text(v(selectedBlueprint, 1, "Owned logistics hull")) or ""
                local selectedMacro = selectedBlueprint and text(v(selectedBlueprint, 3, "")) or ""

                local headline = tableWidget:addRow(false)
                if persisted or orderState.task then
                    headline[1]:setColSpan(4):createText("EOC ORDER COMPLETE - EXACTLY 1 SHIP WAS SUBMITTED", { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
                elseif mediumAvailable and largeAvailable and not selectedSize then
                    headline[1]:setColSpan(4):createText("EOC FOUND BOTH MEDIUM AND LARGE OPTIONS", { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
                elseif selectedAvailable then
                    headline[1]:setColSpan(4):createText("EOC RECOMMENDS BUYING EXACTLY 1 " .. (selectedSize == "M" and "MEDIUM" or "LARGE") .. " SHIP: " .. selectedShip, { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
                elseif mediumBlueprint or largeBlueprint then
                    headline[1]:setColSpan(4):createText("EOC CANNOT OFFER A BUILDABLE MEDIUM OR LARGE SHIP", { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
                else
                    headline[1]:setColSpan(4):createText("EOC CANNOT RECOMMEND A SHIP: NO MATCHING OWNED MEDIUM OR LARGE BLUEPRINT", { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
                end

                local status = tableWidget:addRow(false)
                status[1]:setColSpan(4):createText("RECOMMENDATION TARGET: Station: " .. caseStation .. "; need: " .. text(entry[2]) .. "; required cargo: " .. cargo .. ". Current order state is shown below.", { wordwrap = true })

                if mediumAvailable and largeAvailable and not persisted and not orderState.task then
                    local question = tableWidget:addRow(false)
                    question[1]:setColSpan(4):createText("SHIP SIZE: Do you want a Medium or Large ship to support this task?", { wordwrap = true })
                    local choices = tableWidget:addRow(true)
                    choices[1]:setColSpan(2)
                    addButton(choices, 1, (selectedSize == "M" and "SELECTED: " or "CHOOSE: ") .. "MEDIUM - " .. text(v(mediumBlueprint, 1, "Medium ship")), function()
                        orderState.selectedSize = "M"
                        orderState.preview = false
                        orderState.error = nil
                        menu.refresh()
                    end, true)
                    choices[3]:setColSpan(2)
                    addButton(choices, 3, (selectedSize == "L" and "SELECTED: " or "CHOOSE: ") .. "LARGE - " .. text(v(largeBlueprint, 1, "Large ship")), function()
                        orderState.selectedSize = "L"
                        orderState.preview = false
                        orderState.error = nil
                        menu.refresh()
                    end, true)
                    selectedSize = orderState.selectedSize
                    selectedBlueprint = selectedSize == "M" and mediumBlueprint or selectedSize == "L" and largeBlueprint or nil
                    selectedWharf = selectedSize == "M" and mediumWharf or selectedSize == "L" and largeWharf or nil
                    selectedAvailable = selectedBlueprint ~= nil and selectedWharf ~= nil
                    selectedShip = selectedBlueprint and text(v(selectedBlueprint, 1, "Owned logistics hull")) or ""
                    selectedMacro = selectedBlueprint and text(v(selectedBlueprint, 3, "")) or ""
                elseif selectedAvailable and not persisted and not orderState.task then
                    local onlyOption = tableWidget:addRow(false)
                    onlyOption[1]:setColSpan(4):createText("SHIP SIZE: Only " .. (selectedSize == "M" and "Medium" or "Large") .. " is currently available from a matching owned blueprint and compatible player shipyard, so EOC is offering that size.", { wordwrap = true })
                end

                if persisted and not selectedAvailable then
                    local submitted = tableWidget:addRow(true)
                    submitted[1]:setColSpan(4)
                    addButton(submitted, 1, "ORDER SUBMITTED - EXACTLY 1 SHIP", function() end, false)
                    local persistedStatus = tableWidget:addRow(false)
                    persistedStatus[1]:setColSpan(4):createText("ORDER STATUS: SUBMITTED - X4 ACCEPTED TASK " .. text(v(persisted, 6, "recorded")) .. ". EOC has locked this station-and-cargo need against every hull size. No further EOC action is required.", { wordwrap = true })
                elseif selectedAvailable then
                    local blueprintStatus = tableWidget:addRow(false)
                    blueprintStatus[1]:setColSpan(4):createText("BLUEPRINT: FOUND - " .. selectedShip .. " (" .. selectedSize .. ").", { wordwrap = true })
                    local distance = tonumber(v(selectedWharf, 5, -1)) or -1
                    local distanceText = distance >= 0 and (formatNumber(distance) .. " gate(s)") or "route unavailable"
                    local wharfStatus = tableWidget:addRow(false)
                    wharfStatus[1]:setColSpan(4):createText("EOC BUILD LOCATION: " .. text(v(selectedWharf, 2, "Unknown wharf")) .. " - " .. text(v(selectedWharf, 3, "Unknown sector")) .. ". DISTANCE: " .. distanceText .. ". CURRENT LOAD: " .. formatNumber(v(selectedWharf, 6, 0)) .. " queued, " .. formatNumber(v(selectedWharf, 7, 0)) .. " building; " .. formatNumber(v(selectedWharf, 8, 0)) .. " build module(s).", { wordwrap = true })

                    local review = tableWidget:addRow(true)
                    review[1]:setColSpan(4)
                    if persisted or orderState.task then
                        addButton(review, 1, "ORDER SUBMITTED - EXACTLY 1 SHIP", function() end, false)
                    elseif orderState.preview then
                        addButton(review, 1, "CONFIRM: QUEUE EXACTLY 1 " .. selectedShip, function()
                            local success, result = queueEOCShipOrder(v(selectedWharf, 10, ""), selectedMacro, "")
                            if success then
                                orderState.task = result
                                orderState.preview = false
                                orderState.queueStatus = "SUBMITTED"
                                local now = getElapsedTime()
                                table.insert(menu.shipOrderRecords, { caseStation, cargo, selectedMacro, text(v(selectedWharf, 2, "Unknown wharf")), selectedShip, result, now })
                                raise("shipping.purchase.queued", { station = caseStation, cargo = cargo, macro = selectedMacro, wharf = text(v(selectedWharf, 2, "Unknown wharf")), ship = selectedShip, size = selectedSize, task = result })
                            else
                                orderState.preview = false
                                orderState.error = result
                                raise("shipping.purchase.failed", { reason = result })
                            end
                            menu.refresh()
                        end, true, pendingChoiceBackground)
                    else
                        addButton(review, 1, "PREVIEW EOC ORDER: EXACTLY 1 " .. selectedShip, function()
                            orderState.preview = true
                            orderState.error = nil
                            menu.refresh()
                        end, true)
                    end

                    local explanation = tableWidget:addRow(false)
                    local orderMessage
                    if orderState.task and orderState.queueStatus == "SUBMITTED" then
                        orderMessage = "ORDER STATUS: SUBMITTED - X4 ACCEPTED TASK " .. text(orderState.task) .. ". EOC has finished this one-shot order and locked this station-and-cargo need against every hull size. The player-owned shipyard now handles normal resource delivery and construction scheduling; no further EOC action is required."
                    elseif persisted or orderState.task then
                        orderMessage = "ORDER STATUS: SUBMITTED. EOC will not submit another Medium or Large order for this station and cargo need. The player-owned shipyard consumes normal hull and equipment resources; missing resources delay construction."
                    elseif orderState.error then
                        orderMessage = "ORDER STATUS: NOT SUBMITTED. " .. text(orderState.error) .. " WHAT THIS MEANS: no ship was ordered. DO THIS NEXT: correct the named blueprint, shipyard, ownership, loadout, resource, or native rejection condition, then preview and confirm exactly one ship once. Do not repeat against the unchanged condition."
                    elseif orderState.preview then
                        orderMessage = "CONFIRMATION REQUIRED: The next click queues exactly one " .. (selectedSize == "M" and "Medium" or "Large") .. " ship with an X4-generated, owned-blueprint loadout. No shipyard screen opens. This does not enable automatic or repeat production."
                    else
                        orderMessage = "EOC ORDER CONTROL: Size selected. Preview first, then confirm. EOC queues exactly one ship internally. No shipyard screen opens, no resources are bypassed, and no repeat production is enabled."
                    end
                    explanation[1]:setColSpan(4):createText(orderMessage, { wordwrap = true })
                elseif not mediumAvailable and not largeAvailable and not persisted and not orderState.task then
                    local unavailable = tableWidget:addRow(false)
                    local availability
                    if mediumBlueprint or largeBlueprint then
                        availability = "EOC found " .. (mediumBlueprint and largeBlueprint and "Medium and Large blueprints" or mediumBlueprint and "a Medium blueprint" or "a Large blueprint") .. ", but no matching player-owned shipyard currently reports that it can build an available hull."
                    else
                        availability = "EOC found no owned Medium or Large blueprint matching " .. cargo .. " logistics."
                    end
                    unavailable[1]:setColSpan(4):createText("SHIP SIZE: " .. availability .. " EOC cannot show or send this order. Nothing changed. WHAT TO DO: 1. Buy or research one matching Medium or Large ship blueprint. 2. Make sure you own a shipyard that can build it. 3. Return to this recommendation. 4. Preview the order once. Do not repeat this job until one of those missing items is fixed.", { wordwrap = true })
                end

                local reason = tableWidget:addRow(false)
                reason[1]:setColSpan(4):createText("WHY ONE: The active EOC case reports a real shortfall and zero compatible logistics ships. Queue no more than one, register and assign it after construction, then rescan before considering another.", { wordwrap = true })
                local safety = tableWidget:addRow(false)
                safety[1]:setColSpan(4):createText("PLAYER AUTHORITY: Size choice, preview, and confirmation are separate deliberate actions when both sizes are available. EOC uses X4's valid-loadout generator, never bypasses shipyard resources, and never repeats the order automatically.", { wordwrap = true })
            else
                pair(tableWidget, entry[1], entry[2], entry[3], entry[4])
            end
        end
    end

    if menu.fleetView == "pending" and #entries > 0 and menu.shipmode == "APPROVAL REQUIRED" then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(
            row,
            1,
            actionLabel("shipping.approve", "AUTHORIZE PENDING ASSIGNMENT", "AUTHORIZING ASSIGNMENT"),
            function()
                if startAction("shipping.approve") then
                    raise("shipping.approve", {})
                end
            end,
            not actionState("shipping.approve").running
        )
    end

    if menu.fleetView == "pending" then
        actionResult(tableWidget, "shipping.approve", "Explicitly authorizes only the displayed, MD-verified pending assignment.")
    end

    section(tableWidget, "LOGISTICS ACTIONS")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, actionLabel("shipping.register", "ACTION: REGISTER SUITABLE UNASSIGNED SHIPS", "REGISTERING SUITABLE SHIPS"), function()
        if startAction("shipping.register") then
            raise("shipping.register", {})
        end
    end, not actionState("shipping.register").running)
    actionResult(tableWidget, "shipping.register", "Registers eligible unassigned trade and mining ships plus tug-class salvage ships. Open EOC from the Docked-menu access button.")

    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, actionLabel("shipping.scan", "ACTION: SCAN SHIPPING NEEDS", "SCANNING SHIPPING NEEDS"), function()
        if startAction("shipping.scan") then
            raise("shipping.scan", {})
        end
    end, not actionState("shipping.scan").running)
    row[3]:setColSpan(2)
    addButton(row, 3, actionLabel("trade.review", "ACTION: REVIEW EOC TRADE ORDERS", "REVIEWING ORDERS"), function()
        if startAction("trade.review") then
            raise("trade.review", {})
        end
    end, not actionState("trade.review").running)
    actionResult(tableWidget, "shipping.scan", "Checks supported station logistics needs and eligible registered ships.")
    actionResult(tableWidget, "trade.review", "Checks only EOC-owned trade offers and reports any changes.")
end

local function captureForcedVerificationScroll()
    local tableId = menu.mainTable and menu.mainTable.id or nil
    local ok, topRow = false, nil
    if tableId ~= nil then ok, topRow = pcall(GetTopRow, tableId) end
    if ok and topRow ~= nil then
        menu.forcedVerificationTopRow = topRow
        menu.forcedVerificationPage = menu.page
        menu.forcedVerificationScrollLocked = true
    DebugError("[JKEOC][B277][FORCED_VERIFY_SCROLL_CAPTURE] page=" .. tostring(menu.page) .. " top=" .. tostring(topRow))
    else
        menu.forcedVerificationTopRow = nil
        menu.forcedVerificationPage = nil
        menu.forcedVerificationScrollLocked = nil
        DebugError("[JKEOC][B277][FORCED_VERIFY_SCROLL_CAPTURE_FAILED] page=" .. tostring(menu.page) .. " tableid=" .. tostring(tableId))
    end
end

local function diagnosticsCenter(tableWidget)
    local station = selectedStation()
    local stationName = text(v(station, 1, "NO STATION SELECTED"))
    local cases = station and stationCases(station) or {}
    local diagnosticCase = menu.diagnosticCase
    if diagnosticCase and text(v(diagnosticCase, 1, "")) ~= text(v(station, 1, "")) then diagnosticCase = nil end
    if not diagnosticCase then diagnosticCase = cases[1] end
    -- Persist the exact fallback case displayed by Diagnostics so a direct
    -- Solution Planner tab click keeps the same station and ware context.
    if diagnosticCase and menu.diagnosticCase ~= diagnosticCase then
        menu.diagnosticCase = diagnosticCase
        DebugError("[JKEOC][B290][DIAGNOSTIC_CONTEXT_RETAINED] station=" .. text(v(diagnosticCase, 1, "")) .. " ware=" .. text(v(diagnosticCase, 4, "")) .. " source=displayed_station_case")
    end
    -- Player-requested cases are 11-field investigation requests, not completed
    -- 36-field diagnostic evidence records. Never render absent evidence as zero.
    local diagnosticReady = diagnosticCase and string.upper(text(v(diagnosticCase, 2, ""))) ~= "PLAYER" and #diagnosticCase >= 32
    if diagnosticCase and not diagnosticReady and menu.diagnosticView ~= "recovery" then menu.diagnosticView = "recovery" end
    local diagnosticPlaybook = diagnosticCase and casePlaybook(diagnosticCase) or nil
    local diagnosticSubject = diagnosticCase and text(v(diagnosticCase, 4, "SELECTED CASE")) or "NO CASE"
    local verificationKey = stationName .. "|" .. diagnosticSubject
    local workingCaseEvidenceMissing = menu.caseEvidenceMissing and menu.caseEvidenceKey == verificationKey
    local noMatchComplete = diagnosticCase and not diagnosticReady and (workingCaseEvidenceMissing or string.upper(text(v(diagnosticCase, 5, ""))) == "NO CURRENT PROBLEM CONFIRMED")
    local workingChecks = diagnosticCase and prerequisiteRows(diagnosticCase) or {}
    local workingEvidenceMissing = false
    for _, check in ipairs(workingChecks) do if check.state == "UNKNOWN" or check.state == "NOT YET TESTED" then workingEvidenceMissing = true; break end end

    section(tableWidget, "EOC GUIDED RECOVERY")
    local rootRow = tableWidget:addRow(true)
    rootRow[1]:setColSpan(4)
    addButton(rootRow, 1, "OPEN CASES ROOT — REVIEW / CLEAR CASES", function()
        menu.resetTabToRoot("cases")
        menu.page = "cases"
        menu.activeTab = "cases"
        menu.refresh()
    end, true)
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("THIS CASE HAS ONE STORY: what EOC noticed, what the evidence proves, what you need to do, and how EOC will verify the result.", { wordwrap = true })
    pair(tableWidget, "WORKING STATION", stationName, "ACTIVE CASES", #cases)
    if diagnosticCase then
        section(tableWidget, "WORKING CASE: " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
    end

    local row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.diagnosticView == "recovery" and "ACTIVE: " or "") .. (noMatchComplete and "RESULT" or "NEXT ACTION"), menu.diagnosticView == "recovery", not noMatchComplete, function()
        menu.diagnosticView = "recovery"
        menu.refresh()
    end)
    addModeButton(row, 2, (menu.diagnosticView == "supplier" and "ACTIVE: " or "") .. (diagnosticReady and "EVIDENCE DETAILS" or (noMatchComplete and "NO EVIDENCE REQUIRED" or "EVIDENCE AFTER ANALYSIS")), menu.diagnosticView == "supplier", diagnosticReady, function()
        menu.diagnosticView = "supplier"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, (menu.diagnosticView == "stabilization" and "ACTIVE: " or "") .. (diagnosticReady and "VERIFY RESULT" or (noMatchComplete and "NO ACTION TO VERIFY" or "VERIFY AFTER ANALYSIS")), menu.diagnosticView == "stabilization", diagnosticReady, function()
        menu.diagnosticView = "stabilization"
        menu.refresh()
    end)

    if menu.diagnosticView == "investigation" then
        if not diagnosticCase then section(tableWidget, "NO CASE AVAILABLE"); row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("Select an active case before starting a root-cause investigation.", { wordwrap = true }); return end
        local investigationChecks = prerequisiteRows(diagnosticCase)
        local confidence, cause, recommendation, facts, unknowns = rootCauseAssessment(diagnosticCase, investigationChecks)
        section(tableWidget, "EOC'S CONCLUSION - " .. confidence)
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("WHAT EOC CAN SAY: " .. cause, { wordwrap = true })
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("WHAT YOU NEED TO DO: " .. recommendation, { wordwrap = true })
        section(tableWidget, "WHAT EOC CHECKED")
        for _, check in ipairs(investigationChecks) do
            local checkColor = resultColor(check.state)
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(check.state .. " - " .. check.label .. ": " .. check.evidence, { wordwrap = true, color = checkColor })
        end
        if #unknowns > 0 then section(tableWidget, "WHAT EOC STILL NEEDS TO LEARN"); for _, item in ipairs(unknowns) do row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("UNKNOWN - " .. item, { wordwrap = true, color = investigationUnknownColor }) end end
        if confidence == "CAUSE NOT YET KNOWN" then
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, actionLabel("analysis.run", "RUN FRESH ANALYSIS - IDENTIFY THE CAUSE", "COLLECTING FRESH EVIDENCE"), function()
                if startAction("analysis.run") then menu.analysisRunning = true; menu.pendingCaseEvidenceKey = verificationKey; raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject }) end
            end, not actionState("analysis.run").running)
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("Do not change this station yet. EOC will return with a supported action or clearly state which evidence is still unavailable.", { wordwrap = true, color = investigationUnknownColor })
        elseif confidence == "MORE OBSERVATION REQUIRED" then
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, actionLabel("case.monitor", "SAVE THIS CASE - " .. intelligenceName() .. " WILL KEEP WATCHING", "SAVING MONITORED CASE"), function()
                if startAction("case.monitor") then raise("case.monitor", { station = stationName, subject = diagnosticSubject, confidence = confidence, cause = cause, amount = tonumber(v(diagnosticCase, 8, 0)) or 0, target = tonumber(v(diagnosticCase, 9, 0)) or 0 }) end
            end, not actionState("case.monitor").running)
            actionResult(tableWidget, "case.monitor", "Monitoring begins only after X4 confirms this saved case. It changes no station orders or configuration.")
            local monitorResult = tostring(actionState("case.monitor").result or "")
            local monitoringActive = monitorResult ~= ""
            section(tableWidget, monitoringActive and "MONITORING ACTIVE" or "MONITORING AVAILABLE - NOT YET ACTIVE")
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(monitoringActive and (intelligenceName() .. " is watching this station and will compare later observations for you, " .. playerDisplayName() .. ".") or ("I need more evidence, " .. playerDisplayName() .. ". Save this case if you want me to keep watching while you continue playing."), { wordwrap = true, color = navigationStoryColor })
        else
            section(tableWidget, "ROOT CAUSE CONFIRMED - MONITORING NOT REQUIRED")
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("I found the immediate blocker, " .. playerDisplayName() .. ". Restore the missing input; EOC will verify the station through its established background analysis and return the answer.", { wordwrap = true, color = navigationStoryColor })
        end
    elseif menu.diagnosticView == "recovery" then
        if not station then
            section(tableWidget, "NO STATION SELECTED")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("NEXT ACTION: Select a player station, then return to Guided Recovery.", { wordwrap = true })
            row = tableWidget:addRow(true)
            row[1]:setColSpan(4)
            addButton(row, 1, "SELECT A STATION - RETURN TO GUIDED RECOVERY", function()
                captureNavigation("GUIDED RECOVERY")
                menu.page = "stations"
                menu.activeTab = "stations"
                menu.refresh()
            end, true)
            return
        elseif not diagnosticCase then
            section(tableWidget, "NO ACTIVE CASE")
            row = tableWidget:addRow(false)
            local observations = stationObservations(station)
            local health = string.upper(text(v(station, 3, "MONITORING")))
            row[1]:setColSpan(4):createText((health == "CHRONIC" and "This station has had the same serious problem for several checks, but no recovery case is open. Open Cases, choose the exact problem you want to solve, and create one player investigation for it." or "No recovery case is open for this station. Open Cases to review its " .. #observations .. " saved observation(s) or start one investigation."), { wordwrap = true, color = health == "CHRONIC" and investigationUnknownColor or nil })
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, "OPEN THIS STATION'S CASE REVIEW", function() menu.caseScope = "station"; menu.caseSeverity = "all"; menu.selectedCase = 1; menu.casePage = 1; menu.diagnosticCase = nil; menu.page = "cases"; menu.activeTab = "cases"; menu.refresh() end, true)
            return
        end

        if noMatchComplete then
            section(tableWidget, "ANALYSIS COMPLETE - NO CURRENT PROBLEM CONFIRMED")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("EOC completed a fresh Empire Analysis and found no current " .. diagnosticSubject .. " problem at " .. stationName .. ". The request did not match any active EOC case, so EOC recommends no station change.", { wordwrap = true, color = investigationPassColor })
            section(tableWidget, "WHAT THIS MEANS FOR YOU")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("Do not transfer funds, change storage, alter trade settings, add production, or reassign ships for this investigation. There is no diagnosed action and therefore nothing to verify.", { wordwrap = true })
            section(tableWidget, "WHERE TO GO NEXT")
            row = tableWidget:addRow(true)
            if v(diagnosticCase, 11, "") == "PLAYER" then
                row[1]:setColSpan(2)
                addButton(row, 1, actionLabel("case.close", "CLOSE THIS INVESTIGATION - NO CURRENT PROBLEM", "CLOSING THIS INVESTIGATION"), function()
                    if startAction("case.close") then
                        DebugError("[JKEOC][B352][TERMINAL_NO_MATCH_CLOSE] station=" .. stationName .. " subject=" .. diagnosticSubject .. " player_case=1")
                        menu.closePlayerRequestedCase(diagnosticCase, true)
                    end
                end, not actionState("case.close").running)
                row[3]:setColSpan(2)
                addButton(row, 3, "KEEP THIS INVESTIGATION OPEN - RETURN TO CASES", function()
                    DebugError("[JKEOC][B352][TERMINAL_NO_MATCH_KEEP] station=" .. stationName .. " subject=" .. diagnosticSubject .. " player_case=1")
                    menu.caseScope = "station"; menu.caseSeverity = "all"; menu.selectedCase = 1; menu.casePage = 1; menu.diagnosticCase = nil; menu.page = "cases"; menu.activeTab = "cases"; menu.refresh()
                end, true)
            else
                row[1]:setColSpan(4)
                addButton(row, 1, "RETURN TO CASES - REVIEW THIS RESULT", function()
                    menu.caseScope = "station"; menu.caseSeverity = "all"; menu.selectedCase = 1; menu.casePage = 1; menu.diagnosticCase = nil; menu.page = "cases"; menu.activeTab = "cases"; menu.refresh()
                end, true)
            end
            return
        elseif not diagnosticReady then
            section(tableWidget, "INVESTIGATION REQUEST RECEIVED")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("EOC has recorded your concern about " .. diagnosticSubject .. " at " .. stationName .. ". This is not a diagnosis yet, so EOC will not display or infer station funds, storage, supply, production, or logistics evidence from this request.", { wordwrap = true, color = navigationStoryColor })
            section(tableWidget, "WHAT YOU NEED TO DO")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("Select RUN EMPIRE ANALYSIS below. EOC will inspect the station, build the complete evidence record, and then return you to this case with Evidence Details available.", { wordwrap = true })
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, actionLabel("analysis.run", "RUN EMPIRE ANALYSIS - DIAGNOSE THIS CASE", "ANALYZING THIS STATION"), function()
                if startAction("analysis.run") then menu.analysisRunning = true; menu.pendingCaseEvidenceKey = verificationKey; raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject }) end
            end, not actionState("analysis.run").running)
            section(tableWidget, "WHAT HAPPENS NEXT")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("After analysis, EOC will show what it observed, the station's actual operating-account balance from X4, the supported cause, and the next player action. Verification remains locked until there is a diagnosed action to verify.", { wordwrap = true })
            return
        end

        row = tableWidget:addRow(true); row[1]:setColSpan(4)
        addButton(row, 1, "READ EOC'S CONCLUSION AND EVIDENCE", function() menu.diagnosticView = "investigation"; menu.refresh() end, true)

        local diagnosticChecks = prerequisiteRows(diagnosticCase)
        local commandAction, commandColor = managedActionText(diagnosticCase)
        local commandBlocked = string.find(string.upper(commandAction), "BLOCKED", 1, true) ~= nil
        local priorUnchanged = menu.verificationKey == verificationKey and string.upper(text(menu.verificationClass, "")) == "UNCHANGED"
        local recoveryPlannerReady, recoveryPlannerReason = menu.plannerAccessForCase(diagnosticCase)
        local recoveryExhausted = recoveryPlannerReady and (recoveryPlannerReason == "RECOVERY_EXHAUSTED" or recoveryPlannerReason == "RETAINED_READINESS")
        local playerOwnsNext = commandBlocked or priorUnchanged or recoveryExhausted
        section(tableWidget, "PLAYER COMMAND — READ THIS FIRST")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(playerOwnsNext and "PLAYER ACTION REQUIRED" or "NO PLAYER ACTION RIGHT NOW — EOC IS HANDLING THIS CASE", { wordwrap = true, color = playerOwnsNext and investigationUnknownColor or investigationPassColor, font = Helper.headerFont })
        row = tableWidget:addRow(false)
        local commandNext = recoveryExhausted and "DO THIS NEXT: Reopen Solution Planner. Temporary delivery recovery is exhausted, so EOC needs your project-demand or permanent-solution decision." or (commandBlocked and ("DO THIS NEXT: " .. manualNextAction(diagnosticCase, diagnosticChecks)) or (priorUnchanged and ("PLAYER CHECK REQUIRED: The completed wait-and-verify cycle was unchanged. " .. manualNextAction(diagnosticCase, diagnosticChecks)) or ("EOC STATUS: " .. commandAction)))
        row[1]:setColSpan(4):createText(commandNext, { wordwrap = true, color = priorUnchanged and investigationUnknownColor or commandColor })
        local firstProblem = nil
        for _, check in ipairs(diagnosticChecks) do
            if not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN" or check.state == "NOT YET TESTED") then firstProblem = check end
        end
        local nextAction = manualNextAction(diagnosticCase, diagnosticChecks)
        local evidenceMissing = firstProblem and (firstProblem.state == "UNKNOWN" or firstProblem.state == "NOT YET TESTED")
        local marketEligible = firstProblem and (firstProblem.label == "DELIVERY PATH" or firstProblem.label == "REACHABLE SUPPLY" or firstProblem.label == "STORAGE FREE SPACE")
        local recoveryCommand = tableWidget:addRow(true)
        recoveryCommand[1]:setColSpan(4)
        if recoveryExhausted then
            menu.addPrimaryButton(recoveryCommand, 1, "REOPEN SOLUTION PLANNER — PLAYER DECISION REQUIRED", function()
                menu.runExpansionReadiness(diagnosticCase)
                menu.solutionCase = diagnosticCase
                menu.focusCaseStation(diagnosticCase)
                captureNavigation("DIAGNOSTICS - " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
                menu.page = "solution"
                menu.activeTab = "solution"
                menu.refresh()
            end, true)
        elseif evidenceMissing then
            menu.addPrimaryButton(recoveryCommand, 1, actionLabel("analysis.run", "RUN FRESH ANALYSIS — IDENTIFY THE CAUSE", "COLLECTING FRESH EVIDENCE"), function()
                if startAction("analysis.run") then menu.analysisRunning = true; menu.pendingCaseEvidenceKey = verificationKey; raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject }) end
            end, not actionState("analysis.run").running)
        elseif marketEligible then
            menu.addPrimaryButton(recoveryCommand, 1, "OPEN RECOVERY OPTIONS — REVIEW BEFORE CHANGING ANYTHING", function()
                menu.diagnosticView = "options"; menu.marketChoiceNote = nil; menu.marketTestPreview = nil; menu.marketRemovePreview = nil; menu.refresh()
            end, true)
        else
            menu.addPrimaryButton(recoveryCommand, 1, priorUnchanged and "OPEN EOC TEST RESULT — UNCHANGED" or "ASK EOC TO VERIFY — BACKGROUND TEST", function() menu.diagnosticView = "stabilization"; menu.refresh() end, true)
        end
        local recoveryDeepDiveKey = checklistCaseKey(diagnosticCase)
        local showingRecoveryDeepDive = menu.diagnosticDeepDiveKey == recoveryDeepDiveKey
        local deepDiveRow = tableWidget:addRow(true)
        deepDiveRow[1]:setColSpan(4)
        addButton(deepDiveRow, 1, showingRecoveryDeepDive and "CLOSE DEEP DIVE — COMMAND ONLY" or "DEEP DIVE — EVIDENCE AND ANALYSIS", function()
            if showingRecoveryDeepDive then
                menu.diagnosticDeepDiveKey = nil
            else
                menu.diagnosticDeepDiveKey = recoveryDeepDiveKey
            end
            menu.refresh()
        end, true)
        if not showingRecoveryDeepDive then return end

        section(tableWidget, evidenceMissing and "STEP 1 OF 3 - WHAT EOC DOES NOT KNOW YET" or "STEP 1 OF 3 - WHAT EOC FOUND")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " - " .. firstProblem.label) or "PASS - ALL REPORTED PREREQUISITES", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and ("EVIDENCE: " .. firstProblem.evidence) or "EVIDENCE: No failed or unknown prerequisite was returned.", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })

        section(tableWidget, "STEP 2 OF 3 - WHAT EOC IS DOING")
        row = tableWidget:addRow(false)
        local actionText, actionColor = managedActionText(diagnosticCase)
        row[1]:setColSpan(4):createText(evidenceMissing and "EOC is collecting fresh evidence and has not started a station action." or actionText, { wordwrap = true, color = evidenceMissing and investigationUnknownColor or actionColor })
        if not evidenceMissing and string.find(string.upper(actionText), "BLOCKED", 1, true) then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("PLAYER ACTION REQUIRED: " .. nextAction, { wordwrap = true, color = investigationFailColor })
        end
        if not evidenceMissing then
            local scoutRecommendation, scoutChecklist = scoutRecoveryPlan(diagnosticCase, diagnosticChecks)
            section(tableWidget, "STEP 3 OF 3 - SCOUT'S BEST LONG-TERM PLAN")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(scoutRecommendation, { wordwrap = true, color = navigationStoryColor })
            renderInteractiveChecklist(tableWidget, diagnosticCase, scoutChecklist)
        end

        if evidenceMissing then
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, actionLabel("analysis.run", "RUN FRESH ANALYSIS - IDENTIFY THE CAUSE", "COLLECTING FRESH EVIDENCE"), function()
                if startAction("analysis.run") then menu.analysisRunning = true; menu.pendingCaseEvidenceKey = verificationKey; raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject }) end
            end, not actionState("analysis.run").running)
        end

        if marketEligible then
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, "OPEN RECOVERY OPTIONS - REVIEW BEFORE CHANGING ANYTHING", function()
                menu.diagnosticView = "options"; menu.marketChoiceNote = nil; menu.marketTestPreview = nil; menu.marketRemovePreview = nil; menu.refresh()
            end, true)
        end
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "VIEW SUPPORTING EVIDENCE", function() menu.diagnosticView = "supplier"; menu.refresh() end, true)
        row[3]:setColSpan(2)
        menu.addPrimaryButton(row, 3, evidenceMissing and "VERIFICATION WAITS FOR A SUPPORTED ACTION" or (priorUnchanged and "OPEN EOC TEST RESULT — UNCHANGED" or "ASK EOC TO VERIFY — BACKGROUND TEST"), function() menu.diagnosticView = "stabilization"; menu.refresh() end, not evidenceMissing)

        section(tableWidget, "STEP 3 OF 3 - VERIFY AFTER THE ACTION")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(evidenceMissing and "EOC must identify a supported action before there is anything to verify." or "Ask EOC once. EOC will retain the baseline, use the next completed established analysis cycle, and return RESOLVED, IMPROVING, UNCHANGED, WORSENING, or BLOCKED without another player prompt.", { wordwrap = true })
    elseif menu.diagnosticView == "options" then
        if not diagnosticCase then section(tableWidget, "NO ACTIVE CASE"); row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("Return to Guided Recovery and select an active case.", { wordwrap = true }); return end
        local optionChecks = prerequisiteRows(diagnosticCase)
        local optionProblem = nil
        for _, check in ipairs(optionChecks) do if not optionProblem and (check.state == "FAIL" or check.state == "UNKNOWN") then optionProblem = check end end
        local marketEligible = optionProblem and (optionProblem.label == "DELIVERY PATH" or optionProblem.label == "REACHABLE SUPPLY" or optionProblem.label == "STORAGE FREE SPACE")
        local marketType = (optionProblem and optionProblem.label == "STORAGE FREE SPACE") and "SELL" or "BUY"
        local marketKey = stationName .. "|" .. diagnosticSubject .. "|" .. marketType
        section(tableWidget, "RECOVERY OPTIONS - " .. diagnosticSubject)
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("SELECTED STATION: " .. stationName .. " | BLOCKER: " .. (optionProblem and (optionProblem.state .. " - " .. optionProblem.label) or "NO FAILED CHECK"), { wordwrap = true, color = optionProblem and resultColor(optionProblem.state) or investigationPassColor })
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(optionProblem and ("EVIDENCE: " .. optionProblem.evidence) or "No supported recovery test is currently required.", { wordwrap = true })
        if marketEligible then
            section(tableWidget, "OPTION 1 - TEST OUTSIDE TRADE WITHOUT CHANGING YOUR POLICY")
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(marketType == "BUY" and "Creates one limited EOC buy offer that allows NPC traders. Your Empire-only rule and normal offers will not change." or "Creates one limited EOC sell offer for the proven extra stock. Your ware rule and normal offers will not change.", { wordwrap = true, color = navigationStoryColor })
            row = tableWidget:addRow(true); row[1]:setColSpan(2); row[3]:setColSpan(2)
            local marketState = actionState("market.test")
            if menu.marketActionKey == marketKey and marketState.running then
                addButton(row, 1, "CREATING ONE EOC " .. marketType .. " TEST - PLEASE WAIT", function() end, false)
                addButton(row, 3, "ACTION LOCKED - WAIT FOR RESULT", function() end, false)
            elseif menu.marketActionKey == marketKey and marketState.result and marketState.result ~= "WORKING" then
                addButton(row, 1, "TEST ATTEMPT COMPLETE - READ RESULT BELOW", function() end, false)
                addButton(row, 3, "NO REPEAT SUBMISSION", function() end, false)
            elseif menu.marketTestPreview == marketKey then
                addButton(row, 1, "CONFIRM ONE EOC " .. marketType .. " TEST", function() if startAction("market.test") then menu.marketActionKey = marketKey; raise("market.test.confirm", { station = stationName, subject = diagnosticSubject, type = marketType, amount = math.max(1, tonumber(v(diagnosticCase, 30, 0)) or tonumber(v(diagnosticCase, 31, 0)) or 1), current = tonumber(v(diagnosticCase, 8, 0)) or 0, target = tonumber(v(diagnosticCase, 9, 0)) or 0, caseclass = tostring(v(diagnosticCase, 35, "")), caseindex = tonumber(v(diagnosticCase, 36, 0)) or 0 }); menu.marketTestPreview = nil end end, true, pendingChoiceBackground)
                addButton(row, 3, "CANCEL PREVIEW - CHANGE NOTHING", function() menu.marketTestPreview = nil; menu.refresh() end, true)
            else
                addButton(row, 1, "PREVIEW EOC NPC " .. marketType .. " TEST", function() menu.marketTestPreview = marketKey; menu.marketRemovePreview = nil; menu.refresh() end, true)
                addButton(row, 3, "KEEP EMPIRE-ONLY", function() menu.marketChoiceNote = "Empire-only retained. Your own stations and cargo-compatible ships must satisfy this ware. EOC will not recommend more storage as the first fix while that delivery path remains restricted."; menu.refresh() end, true)
            end
            actionResult(tableWidget, "market.test", "Creates one bounded, reversible EOC-owned offer only after confirmation.")
            section(tableWidget, "OPTION 2 - REVIEW PHYSICAL STORAGE SEPARATELY")
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("Storage construction is a separate decision. Review installed capacity and ware allocation only after deciding whether trade and logistics can restore flow.", { wordwrap = true })
            row = tableWidget:addRow(true); row[1]:setColSpan(2); row[3]:setColSpan(2)
            addButton(row, 1, "VIEW STORAGE EVIDENCE", function() menu.diagnosticView = "supplier"; menu.refresh() end, true)
            local removeState = actionState("market.test.remove")
            if menu.marketRemoveActionKey == marketKey and removeState.running then
                addButton(row, 3, "REMOVING EOC TEST OFFER - PLEASE WAIT", function() end, false)
            elseif menu.marketRemoveActionKey == marketKey and removeState.result and removeState.result ~= "WORKING" then
                addButton(row, 3, "REMOVAL ATTEMPT COMPLETE - NO REPEAT", function() end, false)
            else
                addButton(row, 3, menu.marketRemovePreview == marketKey and "CONFIRM REMOVE EOC TEST OFFER" or "REMOVE EOC TEST / DO NOTHING", function() if menu.marketRemovePreview == marketKey then if startAction("market.test.remove") then menu.marketRemoveActionKey = marketKey; raise("market.test.remove", { station = stationName, subject = diagnosticSubject, type = marketType }); menu.marketRemovePreview = nil end else menu.marketRemovePreview = marketKey; menu.marketTestPreview = nil; menu.marketChoiceNote = "AWAITING CONFIRMATION: No ordinary offer or station rule will be touched. Select the amber CONFIRM REMOVE EOC TEST OFFER button only to remove EOC's matching test offer."; menu.refresh() end end, true, menu.marketRemovePreview == marketKey and pendingChoiceBackground or nil)
            end
            actionResult(tableWidget, "market.test.remove", "Removes only EOC's matching test offer; otherwise changes nothing.")
            if menu.marketChoiceNote then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(menu.marketChoiceNote, { wordwrap = true, color = investigationUnknownColor }) end
        end
        row = tableWidget:addRow(true); row[1]:setColSpan(2); row[3]:setColSpan(2)
        addButton(row, 1, "RETURN TO GUIDED RECOVERY", function() menu.diagnosticView = "recovery"; menu.refresh() end, true)
        addButton(row, 3, "GO TO VERIFY RESULT", function() menu.diagnosticView = "stabilization"; menu.refresh() end, true)
    elseif menu.diagnosticView == "supplier" then
        section(tableWidget, "SUPPORTING EVIDENCE: " .. (diagnosticCase and text(v(diagnosticCase, 4, "SELECTED CASE")) or "NO CASE SELECTED"))
        if diagnosticCase then
            local detailChecks = prerequisiteRows(diagnosticCase)
            local detailConfidence, detailCause, detailRecommendation = rootCauseAssessment(diagnosticCase, detailChecks)
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(menu.lastUpdated and ("LAST COMPLETED CHECK: " .. menu.lastUpdated .. ". These numbers will not change until another analysis finishes.") or "LAST COMPLETED CHECK: time unavailable. The numbers below were saved with this case. They are not a live reading.", { wordwrap = true, color = menu.lastUpdated and nil or investigationUnknownColor })
            if menu.caseEvidenceHandoffMessage and menu.caseEvidenceKey == verificationKey then
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText(menu.caseEvidenceHandoffMessage, { wordwrap = true, color = workingCaseEvidenceMissing and investigationUnknownColor or investigationPassColor })
            end
            local awaitingEvidence = false
            for _, check in ipairs(detailChecks) do
                local state = string.upper(text(check.state))
                if state == "UNKNOWN" or state == "NOT YET TESTED" then awaitingEvidence = true; break end
            end
            local caseType = string.upper(text(v(diagnosticCase, 3, "")))
            local storagePressure = caseType == "STORAGE PRESSURE"
            section(tableWidget, "WHAT EOC CAN SAY")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(workingCaseEvidenceMissing and "NO CONFIRMED MATCH: The fresh analysis found no evidence-confirmed EOC case for this station and subject." or (storagePressure and ("WARE ALLOCATION PRESSURE — PHYSICAL STORAGE CHECKED SEPARATELY. " .. detailCause) or (detailConfidence .. ": " .. detailCause)), { wordwrap = true, color = awaitingEvidence and investigationUnknownColor or navigationStoryColor })
            local currentStock = tonumber(v(diagnosticCase, 8, 0)) or 0
            local targetStock = tonumber(v(diagnosticCase, 9, 0)) or 0
            local maximumStock = tonumber(v(diagnosticCase, 10, 0)) or 0
            section(tableWidget, "WHAT EOC KNOWS")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CURRENT " .. text(v(diagnosticCase, 4, "WARE")) .. " STOCK: " .. formatNumber(currentStock), { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("WARE TARGET: " .. (targetStock > 0 and formatNumber(targetStock) or "UNAVAILABLE OR NOT SET") .. " | WARE ALLOCATION LIMIT: " .. (maximumStock > 0 and formatNumber(maximumStock) or "UNAVAILABLE IN THE LAST SCAN") .. ". Physical cargo storage is shown separately in Evidence Checks.", { wordwrap = true, color = (targetStock <= 0 or maximumStock <= 0) and investigationUnknownColor or nil })
            local accountBalance = tonumber(v(diagnosticCase, 32, -1)) or -1
            row = tableWidget:addRow(false)
            if accountBalance < 0 then
                row[1]:setColSpan(4):createText("STATION OPERATING ACCOUNT BALANCE: NOT CAPTURED IN THIS CASE SNAPSHOT. Run a fresh analysis before making a funding decision.", { wordwrap = true, color = investigationUnknownColor })
            else
                row[1]:setColSpan(4):createText("STATION OPERATING ACCOUNT BALANCE: " .. formatNumber(accountBalance) .. " Cr" .. (accountBalance == 0 and " - X4 explicitly reported zero available operating funds at the last analysis." or " - available to this station at the last analysis."), { wordwrap = true, color = accountBalance == 0 and investigationFailColor or investigationPassColor })
            end
            section(tableWidget, "WHAT EOC IS DOING")
            row = tableWidget:addRow(false)
            if workingCaseEvidenceMissing then
                row[1]:setColSpan(4):createText("EOC completed the requested analysis and found no matching confirmed case. That does not prove the station is healthy, but repeating the same analysis will not create evidence. Continue normal play and let EOC watch for a supported change.", { wordwrap = true, color = investigationUnknownColor })
            elseif awaitingEvidence then
                row[1]:setColSpan(4):createText("EOC does not have enough evidence to recommend a safe station change. " .. detailRecommendation, { wordwrap = true, color = investigationUnknownColor })
            else
                local actionText, actionColor = managedActionText(diagnosticCase)
                row[1]:setColSpan(4):createText(actionText, { wordwrap = true, color = actionColor })
            end
            if not workingCaseEvidenceMissing and not awaitingEvidence then
                local scoutRecommendation, scoutChecklist = scoutRecoveryPlan(diagnosticCase, detailChecks)
                section(tableWidget, "SCOUT'S BEST LONG-TERM RECOMMENDATION")
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText(scoutRecommendation, { wordwrap = true, color = navigationStoryColor })
                section(tableWidget, "PLAYER CHECKLIST - COMPLETE ONLY THE STEPS THAT APPLY")
                renderInteractiveChecklist(tableWidget, diagnosticCase, scoutChecklist)
            end
            section(tableWidget, "EVIDENCE CHECKS - GREEN CONFIRMED | RED FAILED | AMBER NOT YET KNOWN")
            for _, check in ipairs(detailChecks) do
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText(check.state .. " - " .. check.label .. ": " .. check.evidence, { wordwrap = true, color = resultColor(check.state) })
            end
            section(tableWidget, "WHY THIS CASE MATTERS")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(diagnosticPlaybook.impact, { wordwrap = true })
            if awaitingEvidence then
                row = tableWidget:addRow(true); row[1]:setColSpan(4)
                if workingCaseEvidenceMissing then
                    addButton(row, 1, actionLabel("case.monitor", "START MONITORING - WAIT FOR NEW EVIDENCE", "STARTING MONITORING"), function()
                        if startAction("case.monitor") then raise("case.monitor", { station = stationName, subject = diagnosticSubject, confidence = "NO CONFIRMED MATCH", cause = "Fresh analysis found no matching confirmed case.", amount = tonumber(v(diagnosticCase, 8, 0)) or 0, target = tonumber(v(diagnosticCase, 9, 0)) or 0 }) end
                    end, not actionState("case.monitor").running)
                else
                    addButton(row, 1, actionLabel("analysis.run", "RUN FRESH ANALYSIS - IDENTIFY THE CAUSE", "COLLECTING FRESH EVIDENCE"), function()
                        if startAction("analysis.run") then menu.analysisRunning = true; menu.pendingCaseEvidenceKey = verificationKey; raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject }) end
                    end, not actionState("analysis.run").running)
                end
            end
        else
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("No working case is selected.", { wordwrap = true })
        end
    elseif menu.diagnosticView == "stabilization" then
        section(tableWidget, "VERIFY RECOVERY")
        row = tableWidget:addRow(false)
        local unchangedHere = menu.verificationKey == verificationKey and string.upper(text(menu.verificationClass, "")) == "UNCHANGED"
        row[1]:setColSpan(4):createText(workingEvidenceMissing and "THERE IS NOTHING TO VERIFY YET. EOC has not identified a supported player action. Return to Next Action and run the requested fresh analysis first." or (unchangedHere and ("PLAYER CHECK REQUIRED AFTER UNCHANGED RESULT: " .. manualNextAction(diagnosticCase, workingChecks)) or ("ACTION BEING VERIFIED: " .. manualNextAction(diagnosticCase, workingChecks))), { wordwrap = true, color = workingEvidenceMissing and investigationUnknownColor or (unchangedHere and investigationUnknownColor or navigationStoryColor) })
        if string.upper(text(v(diagnosticCase, 2, ""))) == "PLAYER" then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("VERIFICATION LOCKED: This player-requested incident is NOT YET TESTED. Collect supported focused evidence before claiming recovery.", { wordwrap = true, color = investigationUnknownColor }) end
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        local backgroundTest = menu.backgroundTests and menu.backgroundTests[verificationKey] or nil
        menu.backgroundTestAcknowledged = menu.backgroundTestAcknowledged or {}
        local backgroundState = string.upper(text(backgroundTest and backgroundTest.status, ""))
        local backgroundPending = backgroundTest and (backgroundState == "REQUESTED" or backgroundState == "CHECKING" or backgroundState == "WAITING")
        local backgroundFinished = backgroundTest and not backgroundPending
        local backgroundSuccess = backgroundState == "RESOLVED" or backgroundState == "SUCCESS"
        local testPlannerReady, testPlannerReason = menu.plannerAccessForCase(diagnosticCase)
        local testRecoveryExhausted = testPlannerReady and testPlannerReason == "RECOVERY_EXHAUSTED"
        local backgroundCanRetest = backgroundFinished and menu.backgroundTestAcknowledged[verificationKey] and not backgroundSuccess and not testRecoveryExhausted
        local backgroundFinishedLabel = backgroundSuccess and "RETURN TO GUIDED RECOVERY - TEST COMPLETE"
            or (backgroundState == "IMPROVING" or backgroundState == "PARTIAL") and "RETURN TO NEXT ACTION - WAIT ONE CYCLE"
            or (backgroundState == "UNCHANGED" or backgroundState == "WORSENING" or backgroundState == "FAILED") and "OPEN NEXT ACTION - FIX THE PROBLEM"
            or (backgroundState == "BLOCKED" or backgroundState == "ABORTED" or string.find(backgroundState, "INSUFFICIENT", 1, true)) and "OPEN NEXT ACTION - RUN FRESH ANALYSIS"
            or "OPEN NEXT ACTION - REFRESH THE INFORMATION"
        local backgroundButtonLabel = testRecoveryExhausted and "OPEN SOLUTION PLANNER - RECOVERY EXHAUSTED"
            or (workingEvidenceMissing and "OPEN NEXT ACTION - EOC NEEDS MORE INFORMATION"
            or (backgroundPending and "TEST RUNNING - WAIT FOR EOC"
            or (backgroundCanRetest and "RUN ONE NEW TEST - ONLY AFTER YOU HAVE FINISHED THE STEPS"
            or (backgroundFinished and backgroundFinishedLabel
            or "ASK EOC TO RUN THIS TEST ONCE"))))
        addButton(row, 1, backgroundButtonLabel, function()
            if testRecoveryExhausted then
                menu.solutionCase = diagnosticCase
                menu.page = "solution"
                menu.activeTab = "solution"
                menu.refresh()
                return
            end
            if workingEvidenceMissing then menu.diagnosticView = "recovery"; menu.refresh(); return end
            if backgroundFinished and not backgroundCanRetest then
                menu.backgroundTestAcknowledged[verificationKey] = true
                menu.diagnosticView = "recovery"
                menu.refresh()
                return
            end
            raise("verification.request", { station = stationName, subject = diagnosticSubject, severity = text(v(diagnosticCase, 2, "UNKNOWN")), amount = tonumber(v(diagnosticCase, 8, 0)) or 0 })
            menu.backgroundTests = menu.backgroundTests or {}
            menu.backgroundTestAcknowledged[verificationKey] = nil
            menu.backgroundTests[verificationKey] = { station=stationName, subject=diagnosticSubject, status="REQUESTED", result="EOC started the test. Keep playing normally. Do not press the test button again and do not open Station Build mode. Wait for TEST COMPLETE.", baseline=tonumber(v(diagnosticCase, 8, 0)) or 0, severity=text(v(diagnosticCase, 2, "UNKNOWN")), samples=0 }
            menu.refresh()
        end, not backgroundPending and (workingEvidenceMissing or string.upper(text(v(diagnosticCase, 2, ""))) ~= "PLAYER"))
        row[3]:setColSpan(2)
        addButton(row, 3, "RETURN TO GUIDED RECOVERY", function() menu.diagnosticView = "recovery"; menu.refresh() end, true)
        if backgroundTest then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(menu.playerDisplayText("EOC BACKGROUND TEST: " .. text(backgroundTest.status, "UNKNOWN") .. "\n" .. menu.backgroundTestInstruction(backgroundTest, diagnosticCase, workingChecks)), { wordwrap = true, color = resultColor(string.upper(text(backgroundTest.status, "UNKNOWN"))) })
        elseif menu.verificationKey == verificationKey then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(menu.playerDisplayText("CASE VERIFICATION: " .. text(menu.verificationClass, "UNKNOWN") .. "\n" .. text(menu.verificationResult) .. "\nWORKING CASE: " .. stationName .. " -> " .. diagnosticSubject), { wordwrap = true, color = resultColor(string.upper(text(menu.verificationClass, "UNKNOWN"))) })
        elseif menu.pendingVerificationKey == verificationKey then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(menu.playerDisplayText("CASE VERIFICATION: RUNNING\n" .. text(menu.verificationResult)), { wordwrap = true })
        else
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(menu.playerDisplayText(workingEvidenceMissing and "VERIFICATION STATUS: WAITING FOR EOC TO IDENTIFY A SUPPORTED ACTION" or "VERIFICATION STATUS: READY — ASK EOC ONCE; EOC OWNS THE TEST AND RESULT"), { wordwrap = true })
        end
    else
        section(tableWidget, "GUIDED RECOVERY")
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("The requested diagnostics view is unavailable. Select Next Action, Evidence Details, or Verify Result.", { wordwrap = true })
    end

    if diagnosticCase and menu.diagnosticView ~= "recovery" and menu.diagnosticView ~= "options" and menu.diagnosticView ~= "stabilization" then
        section(tableWidget, "WHERE TO GO NEXT")
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, menu.diagnosticView == "supplier" and "RETURN TO NEXT ACTION" or "VIEW SUPPORTING EVIDENCE", function()
            menu.diagnosticView = menu.diagnosticView == "supplier" and "recovery" or "supplier"
            menu.refresh()
        end, true)
        row[3]:setColSpan(2)
        addButton(row, 3, workingCaseEvidenceMissing and "NO CONFIRMED MATCH - RETURN TO NEXT ACTION" or (workingEvidenceMissing and "RUN FRESH ANALYSIS - IDENTIFY THE CAUSE" or "OPEN EOC BACKGROUND TEST"), function()
            if workingCaseEvidenceMissing then menu.diagnosticView = "recovery"; menu.refresh(); return end
            if not workingEvidenceMissing then menu.diagnosticView = "stabilization"; menu.refresh(); return end
            if not workingEvidenceMissing then captureForcedVerificationScroll() end
            if startAction("analysis.run") then
                menu.analysisRunning = true
                if workingEvidenceMissing then
                    menu.pendingCaseEvidenceKey = verificationKey
                    raise("analysis.run", { investigate = true, station = stationName, subject = diagnosticSubject })
                else
                    menu.pendingVerificationKey = verificationKey
                    menu.verificationKey = nil
                    menu.verificationResult = "FRESH VERIFICATION RUNNING for " .. stationName .. " -> " .. diagnosticSubject
                    raise("analysis.run", { verify = true, station = stationName, subject = diagnosticSubject, severity = text(v(diagnosticCase, 2, "UNKNOWN")), amount = tonumber(v(diagnosticCase, 8, 0)) or 0 })
                end
            end
        end, not actionState("analysis.run").running)
    end
end

local function kpiStateLabel(score)
    if score >= 100 then
        return "CRITICAL"
    elseif score >= 65 then
        return "WARNING"
    elseif score >= 30 then
        return "WATCH"
    end
    return "HEALTHY"
end

function menu.attentionReason(item)
    local reasons = {}
    if (tonumber(item.critical) or 0) > 0 then table.insert(reasons, tostring(item.critical) .. " critical case(s)") end
    if (tonumber(item.warning) or 0) > 0 then table.insert(reasons, tostring(item.warning) .. " warning case(s)") end
    if (tonumber(item.issues) or 0) > 0 then table.insert(reasons, tostring(item.issues) .. " active issue(s)") end
    if item.trend == "WORSENING" then table.insert(reasons, "worsening") end
    if #reasons == 0 then table.insert(reasons, "no confirmed operational pressure") end
    return table.concat(reasons, "; ")
end

local function buildKpiRows()
    local rows = {}
    local healthWeights = {
        CRITICAL = 100,
        CHRONIC = 80,
        RELAPSED = 70,
        RECURRING = 55,
        TRANSIENT = 30,
        MONITORING = 0,
    }
    local priorityWeights = { CRITICAL = 35, WARNING = 20, NOTE = 5 }
    local trendWeights = { WORSENING = 20, IMPROVING = -10, STABLE = 0 }

    for index, station in ipairs(menu.stations or {}) do
        local name = text(v(station, 1, "Unknown station"))
        local health = string.upper(text(v(station, 3, "MONITORING")))
        local trend = string.upper(text(v(station, 4, "STABLE")))
        local priority = string.upper(text(v(station, 6, "NOTE")))
        local issues = tonumber(v(station, 8, 0)) or 0
        local criticalCases = 0
        local warningCases = 0
        for _, case in ipairs(menu.cases or {}) do
            if text(v(case, 1, "")) == name then
                local severity = string.upper(text(v(case, 2, "")))
                if severity == "CRITICAL" then
                    criticalCases = criticalCases + 1
                elseif severity == "WARNING" then
                    warningCases = warningCases + 1
                end
            end
        end

        local score = (healthWeights[health] or 15) + (priorityWeights[priority] or 0) +
            (trendWeights[trend] or 0) + issues * 8 + criticalCases * 30 + warningCases * 15
        score = math.max(0, math.floor(score))
        local reasons = {}
        if criticalCases > 0 then table.insert(reasons, criticalCases .. " critical case(s)") end
        if warningCases > 0 then table.insert(reasons, warningCases .. " warning case(s)") end
        if health ~= "MONITORING" then table.insert(reasons, "health " .. health) end
        if trend == "WORSENING" then table.insert(reasons, "worsening trend") end
        if issues > 0 then table.insert(reasons, issues .. " active issue(s)") end
        if #reasons == 0 then table.insert(reasons, "no confirmed operational pressure") end

        table.insert(rows, {
            index = index,
            station = station,
            name = name,
            role = text(v(station, 2, "UNDEFINED")),
            health = health,
            trend = trend,
            priority = priority,
            issues = issues,
            critical = criticalCases,
            warning = warningCases,
            score = score,
            state = kpiStateLabel(score),
            why = table.concat(reasons, "; "),
            recommendation = text(v(station, 7, "Continue monitoring.")),
        })
    end

    table.sort(rows, function(a, b)
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)
    return rows
end

local function kpiPagedRows(tableWidget, rows, renderRow, emptyText)
    if #rows == 0 then
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(emptyText or "No records are available for this view.", { wordwrap = true })
    end
    if #rows > 0 then
        local summary = tableWidget:addRow(false)
        summary[1]:setColSpan(4):createText(tostring(#rows) .. " KPI RESULTS | ADAPTIVE SCREEN BOUNDARY", { halign = "center", color = investigationNeutralColor })
    end
    local first, last = menu.adaptiveListNavigation(tableWidget, "kpi." .. tostring(menu.kpiView), #rows, { fixedRows = 8, rowUnits = 1 })
    for index = first, last do renderRow(rows[index], index) end
end

local function kpiHeader(tableWidget, labels)
    local row = tableWidget:addRow(false)
    for i = 1, 4 do row[i]:createText(labels[i] or "", { wordwrap = false, font = Helper.headerFont }) end
    local line = tableWidget:addRow(false)
    line[1]:setColSpan(4):createText(string.rep("━", 420), { wordwrap = false, fontsize = 3, color = navigationStoryColor })
end

local function kpiAttentionView(tableWidget)
    local rows = buildKpiRows()
    local counts = { CRITICAL = 0, WARNING = 0, WATCH = 0, HEALTHY = 0 }
    for _, item in ipairs(rows) do counts[item.state] = counts[item.state] + 1 end
    section(tableWidget, "EMPIRE KPI CENTER")
    pair(tableWidget, "CRITICAL", counts.CRITICAL, "WARNING", counts.WARNING)
    section(tableWidget, "EXECUTIVE ATTENTION QUEUE")
    local explanation = tableWidget:addRow(false)
    explanation[1]:setColSpan(4):createText("HOW TO READ THIS: EOC ranks the stations needing attention first. There is no player-facing numeric score: the state, issue count, and reason below explain the priority.", { wordwrap = true, color = navigationStoryColor })
    kpiHeader(tableWidget, { "RANK / STATE", "STATION", "HEALTH / TREND", "WHY IT IS RANKED" })
    kpiPagedRows(tableWidget, rows, function(item, rank)
        local selectedItem = item
        local row = tableWidget:addRow(true)
        row[1]:createText(rank .. ". " .. item.state)
        addButton(row, 2, item.name, function() menu.kpiSelected = selectedItem.index; menu.refresh() end, true)
        row[3]:createText(item.health .. " / " .. item.trend)
        row[4]:createText(menu.attentionReason(item), { wordwrap = true })
    end, "No player stations are currently available.")
    if #rows == 0 then return end
    local selectedIndex, selected = menu.kpiSelected or rows[1].index, rows[1]
    for _, item in ipairs(rows) do if item.index == selectedIndex then selected = item break end end
    menu.kpiSelected = selected.index
    section(tableWidget, "FOCUS: " .. selected.name)
    local summary = tableWidget:addRow(false)
    summary[1]:setColSpan(4):createText(selected.state .. " | " .. menu.attentionReason(selected) .. " | NEXT: " .. selected.recommendation, { wordwrap = true })
    local row = tableWidget:addRow(true)
    addButton(row, 1, "OPEN THIS STATION", function() menu.selected=selected.index; captureNavigation("KPI CENTER"); menu.page="stations"; menu.activeTab="stations"; menu.refresh() end, true)
    addButton(row, 2, "OPEN THIS STATION'S CASES", function() menu.selected=selected.index; captureNavigation("KPI CENTER"); menu.caseScope="station"; menu.caseSeverity="all"; menu.selectedCase=1; menu.casePage=1; menu.page="cases"; menu.activeTab="cases"; menu.refresh() end, selected.issues>0 or selected.critical>0 or selected.warning>0)
    addButton(row, 3, "OPEN THIS STATION'S GUIDED RECOVERY", function() menu.selected=selected.index; captureNavigation("KPI CENTER"); menu.diagnosticView="recovery"; menu.page="diagnostics"; menu.activeTab="diagnostics"; menu.refresh() end, true)
    addButton(row, 4, "RUN ANALYSIS", function() if not menu.analysisRunning then menu.analysisRunning=true; menu.analysisStatus="ANALYSIS RUNNING"; menu.refresh(); raise("analysis.run",{}) end end, not menu.analysisRunning)
end
local function kpiStationOptions()
    local names, seen = {}, {}
    for _, station in ipairs(menu.stations or {}) do local name = text(v(station, 1, "Unknown station")); if not seen[name] then seen[name] = true; table.insert(names, name) end end
    table.sort(names)
    local options = { { id = "__all__", text = "ALL STATIONS", icon = "", displayremoveoption = false } }
    for _, name in ipairs(names) do table.insert(options, { id = name, text = name, icon = "", displayremoveoption = false }) end
    return options, seen
end

local function kpiProtectedDropdown(row, column, options, selected, confirmed)
    for _, option in ipairs(options) do
        if not string.find(option.text or "", "SELECTED FILTER:", 1, true) then option.text = "SELECTED FILTER: " .. tostring(option.text or "") .. "  v" end
    end
    local dropdown = row[column]:setColSpan(4 - column + 1):createDropDown(options, { active = #options > 0, startOption = selected, height = Helper.standardButtonHeight, mouseOverText = "CLICK TO CHANGE KPI FILTER" })
    dropdown:setTextProperties({ fontsize = Helper.standardFontSize })
    row[column].handlers.onDropDownActivated = function() menu.kpiControlDropdownActive = true end
    row[column].handlers.onDropDownDeactivated = function() menu.kpiControlDropdownActive = false; menu.kpiNextRefreshAt = getElapsedTime() + menu.kpiRefreshInterval(menu.kpiView) end
    row[column].handlers.onDropDownConfirmed = function(_, value) menu.kpiControlDropdownActive = false; confirmed(value); menu.kpiResultPage = 1; menu.kpiNextRefreshAt = getElapsedTime(); menu.refresh() end
end

local function kpiControlLabel(row, label)
    row[1]:createText("FILTER  >  " .. label, { wordwrap = false, font = Helper.headerFont, color = investigationWarnColor, mouseOverText = "USE THE BLUE FIELD TO CHANGE THIS FILTER" })
end

local function kpiViewButtonCallback(view)
    return function()
        menu.kpiView = view
        menu.kpiResultPage = 1
        menu.kpiNextRefreshAt = getElapsedTime()
        menu.refresh()
    end
end

local function kpiDashboardControls(tableWidget)
    section(tableWidget, "LIVE KPI DASHBOARDS")
    local choices = {
        { "PREDICTIVE INTELLIGENCE", "predictive" },
        { "CASH FLOW", "cash" }, { "CONSTRUCTION PROGRESS", "construction" }, { "EXECUTIVE ATTENTION", "attention" },
        { "OPEN TRADE OFFERS", "trade" }, { "STORAGE LEVELS", "storage" },
        { "TOP EARNERS", "earners" }, { "CASH DRAINS", "drains" }, { "SHIPYARD ACTIVITY", "shipyard" }
    }
    local row
    for index, choice in ipairs(choices) do
        if ((index - 1) % 4) == 0 then row = tableWidget:addRow(true) end
        local label = choice[1]
        local view = choice[2]
        local column = ((index - 1) % 4) + 1
        addButton(row, column, label, kpiViewButtonCallback(view), true, menu.kpiView == view and selectedModeBackground or availableModeBackground)
    end
    if menu.kpiView == "cash" then
        local options = { { id="__player__", text="PLAYER ACCOUNT / EMPIRE", icon="", displayremoveoption=false } }
        local names, seen = {}, {}; for _, station in ipairs(menu.stations or {}) do local name=text(v(station,1,"Unknown station")); if not seen[name] then seen[name]=true; table.insert(names,name) end end; table.sort(names)
        for _,name in ipairs(names) do table.insert(options,{id=name,text=name,icon="",displayremoveoption=false}) end
        menu.kpiStation_cash=menu.kpiStation_cash or "__player__"; row=tableWidget:addRow(true); kpiControlLabel(row,"ACCOUNT / STATION FILTER"); kpiProtectedDropdown(row,2,options,menu.kpiStation_cash,function(name) menu.kpiStation_cash=name end)
    elseif menu.kpiView == "construction" then
        local options = { { id = "__all__", text = "ALL CONSTRUCTION STATIONS", icon = "", displayremoveoption = false } }
        local recordById = {}
        for _, record in ipairs(menu.constructionRecords or {}) do
            if (tonumber(v(record, 3, 0)) or 0) > 0 then
                local id = tostring(tonumber(v(record, 2, 0)) or 0)
                local name = text(v(record, 1, "Unknown station"))
                recordById[id] = { index = tonumber(v(record, 2, 0)) or 0, station = name }
                table.insert(options, { id = id, text = name, icon = "", displayremoveoption = false })
            end
        end
        table.sort(options, function(a,b)
            if a.id == "__all__" then return true end
            if b.id == "__all__" then return false end
            return a.text < b.text
        end)
        menu.kpiConstructionSelection = menu.kpiConstructionSelection or "__all__"
        if menu.kpiConstructionSelection ~= "__all__" and not recordById[menu.kpiConstructionSelection] then menu.kpiConstructionSelection = "__all__" end
        row = tableWidget:addRow(true); kpiControlLabel(row, "STATION UNDER CONSTRUCTION")
        kpiProtectedDropdown(row, 2, options, menu.kpiConstructionSelection, function(id)
            menu.kpiConstructionSelection = id
            if id == "__all__" then
                menu.activeConstructionSnapshot = nil
            else
                local selected = recordById[id]
                if selected then raise("construction.refresh", { index = selected.index, station = selected.station }) end
            end
        end)
    elseif menu.kpiView == "trade" or menu.kpiView == "storage" then
        local options, seen = kpiStationOptions(); local key = "kpiStation_" .. menu.kpiView; menu[key] = menu[key] or "__all__"; if menu[key] ~= "__all__" and not seen[menu[key]] then menu[key] = "__all__" end
        row = tableWidget:addRow(true); kpiControlLabel(row, "STATION FILTER")
        kpiProtectedDropdown(row, 2, options, menu[key], function(name) menu[key] = name end)
    elseif menu.kpiView == "shipyard" then
        local names, seen = {}, {}; local history = menu.kpiHistory or {}; local latest = history[#history] or {}
        for _, yard in ipairs(latest.shipyards or {}) do local name = text(yard.name, "Unknown shipyard"); if not seen[name] then seen[name] = true; table.insert(names, name) end end
        if #names == 0 then for _, route in ipairs(menu.shipWharfRoutes or {}) do local name = text(v(route, 2, "Unknown shipyard")); if not seen[name] then seen[name] = true; table.insert(names, name) end end end
        table.sort(names)
        local options = { { id="__all__", text="ALL SHIPYARDS", icon="", displayremoveoption=false } }; for _, name in ipairs(names) do table.insert(options, {id=name,text=name,icon="",displayremoveoption=false}) end
        menu.kpiShipyard = menu.kpiShipyard or "__all__"; row = tableWidget:addRow(true); kpiControlLabel(row, "SHIPYARD FILTER"); kpiProtectedDropdown(row, 2, options, menu.kpiShipyard, function(name) menu.kpiShipyard=name end)
    end
    row = tableWidget:addRow(true)
    addButton(row, 1, menu.kpiPaused and "RESUME LIVE" or "PAUSE LIVE", function() menu.kpiPaused = not menu.kpiPaused; if not menu.kpiPaused then menu.kpiNextRefreshAt = getElapsedTime() end; menu.refresh() end, true)
    addButton(row, 2, "REFRESH VIEW", function() menu.kpiNextRefreshAt = getElapsedTime(); menu.refresh(true) end, true)
    row[3]:setColSpan(2):createText("SCOPE: FILTERED VIEW | SELECT THE TIME RANGE BELOW EACH TREND", { wordwrap = false })
    row = tableWidget:addRow(false); local seconds = math.max(0, math.ceil((tonumber(menu.kpiNextRefreshAt) or getElapsedTime()) - getElapsedTime()))
    row[1]:setColSpan(4):createText((menu.kpiPaused and "LIVE PAUSED" or menu.kpiRefreshing and "LIVE REFRESH IN PROGRESS" or ("LIVE - " .. tostring(menu.kpiRefreshInterval(menu.kpiView)) .. "s | NEXT REFRESH: " .. tostring(seconds) .. "s")) .. " | Sampling stops when KPI Center closes or another page opens.", { wordwrap = true, color = investigationPassColor })
end

local function kpiBar(value, maximum) value=tonumber(value) or 0; maximum=math.max(1,tonumber(maximum) or 1); return (value<0 and "-" or "+") .. string.rep("=", math.max(1,math.min(30,math.floor((math.abs(value)/maximum)*30+0.5)))) end
local function stationMoneyMap(sample) local result={}; for _,station in ipairs((sample and sample.stations) or {}) do result[tostring(station.name or "Unknown station")]=tonumber(station.money) or 0 end; return result end
menu.KPI_GRAPH_RANGES = { { seconds = 300, label = "5 MIN" }, { seconds = 600, label = "10 MIN" }, { seconds = 1800, label = "30 MIN" }, { seconds = 3600, label = "1 HOUR" } }

function menu.kpiGraphHistory()
    local history = menu.kpiHistory or {}
    if #history == 0 then return {} end
    local seconds = tonumber(menu.kpiGraphRange) or 1800
    local endtime = tonumber(history[#history].time) or 0
    local cutoff, result = endtime - seconds, {}
    for _, sample in ipairs(history) do if (tonumber(sample.time) or 0) >= cutoff then table.insert(result, sample) end end
    return result
end

function menu.kpiGraphGranularity(minimum, maximum)
    local span = math.max(1, maximum - minimum)
    local raw = span / 8
    local magnitude = 10 ^ math.floor(math.log(raw) / math.log(10))
    local normalized = raw / magnitude
    local step = normalized <= 1 and 1 or normalized <= 2 and 2 or normalized <= 5 and 5 or 10
    return step * magnitude
end

function menu.kpiGraphRangeButtons(t)
    local row = t:addRow(true, { fixed = true })
    for column, choice in ipairs(menu.KPI_GRAPH_RANGES) do
        local selected = (tonumber(menu.kpiGraphRange) or 1800) == choice.seconds
        addButton(row, column, choice.label, function() menu.kpiGraphRange = choice.seconds; menu.refresh() end, true, selected and selectedModeBackground or availableModeBackground)
    end
end

menu.KPI_GRAPH_COLORS = { Color["transactionlog_graph_data"], investigationPassColor, investigationUnknownColor, investigationFailColor, investigationNeutralColor, navigationStoryColor }

function menu.kpiNativeGraph(t, title, series, yLabel, yUnit, fixedMinimum, fixedMaximum)
    local history = menu.kpiGraphHistory()
    if #history == 0 then pair(t, "STATUS", "EOC has not retained the first live sample yet.", "NEXT", "No player action — established collection continues."); return false end
    local endtime = tonumber(history[#history].time) or 0
    local range = tonumber(menu.kpiGraphRange) or 1800
    local minY, maxY
    local legendRow
    for index, definition in ipairs(series) do
        if ((index - 1) % 4) == 0 then legendRow = t:addRow(false, { fixed = true }) end
        legendRow[((index - 1) % 4) + 1]:createText(definition.label, { color = definition.color, wordwrap = false })
    end
    local row = t:addRow(false, { fixed = true })
    local graph = row[1]:setColSpan(4):createGraph({ height = Helper.scaleY(240), scaling = false }):setTitle(title, { font = Helper.titleFont, fontsize = Helper.scaleFont(Helper.titleFont, Helper.titleFontSize) })
    for _, definition in ipairs(series) do
        local record = graph:addDataRecord({ markertype = "square", markersize = 7, markercolor = definition.color, linetype = "normal", linewidth = 2, linecolor = definition.color, mouseOverText = definition.label })
        for _, sample in ipairs(history) do
            local value = tonumber(definition.value(sample))
            if value then
                minY = minY and math.min(minY, value) or value
                maxY = maxY and math.max(maxY, value) or value
                record:addData(((tonumber(sample.time) or endtime) - endtime) / 60, value)
            end
        end
    end
    minY, maxY = fixedMinimum or minY or 0, fixedMaximum or maxY or 1
    local granularity = menu.kpiGraphGranularity(minY, maxY)
    if maxY == minY then minY = minY - granularity; maxY = maxY + granularity else minY = math.floor(minY / granularity) * granularity; maxY = math.ceil(maxY / granularity) * granularity end
    local xGranularity = range <= 300 and 1 or range <= 600 and 2 or 5
    graph:setXAxis({ startvalue = -(range / 60), endvalue = 0, granularity = xGranularity, offset = 0, gridcolor = Color["graph_grid"], unittext = "min" })
    graph:setXAxisLabel("TIME")
    graph:setYAxis({ startvalue = minY, endvalue = maxY, granularity = granularity, offset = 0, gridcolor = Color["graph_grid"], unittext = yUnit or "" })
    graph:setYAxisLabel(yLabel)
    menu.kpiGraphRangeButtons(t)
    return true
end

function menu.kpiArrayValue(sample, field, name, valueField, secondaryField, secondary)
    for _, item in ipairs((sample and sample[field]) or {}) do if item.name == name and (not secondaryField or item[secondaryField] == secondary) then return item[valueField] end end
end

function menu.kpiLatestNames(field, filter, secondaryField)
    local history=menu.kpiGraphHistory(); local latest=history[#history] or {}; local result,seen={},{}
    for _,item in ipairs(latest[field] or {}) do if filter=="__all__" or item.name==filter then local label=secondaryField and (item.name.." / "..tostring(item[secondaryField])) or item.name; if not seen[label] then seen[label]=true; table.insert(result,{name=item.name,label=label,secondary=secondaryField and item[secondaryField] or nil}) end end end
    table.sort(result,function(a,b)return a.label<b.label end); while #result > 5 do table.remove(result) end; return result
end

function menu.kpiGraphDefinitions(field, names, valueField, secondaryField)
    local definitions={}
    for index,item in ipairs(names) do local current=item; table.insert(definitions,{label=current.label,color=menu.KPI_GRAPH_COLORS[((index-1)%#menu.KPI_GRAPH_COLORS)+1],value=function(sample)return menu.kpiArrayValue(sample,field,current.name,valueField,secondaryField,current.secondary)end}) end
    return definitions
end

function menu.kpiCashFlowGraph(t)
    local selected=menu.kpiStation_cash or "__player__"; local history=menu.kpiGraphHistory(); section(t,"CASH FLOW - VERIFIED ACCOUNT BALANCE")
    local definition
    if selected=="__player__" then definition={label="PLAYER ACCOUNT / EMPIRE",color=menu.KPI_GRAPH_COLORS[1],value=function(x)return x.credits end}
    else definition={label=selected,color=menu.KPI_GRAPH_COLORS[1],value=function(x)local map=stationMoneyMap(x); return map[selected] end} end
    menu.kpiNativeGraph(t,selected=="__player__" and "PLAYER ACCOUNT CASH FLOW" or (selected.." CASH FLOW"),{definition},"ACCOUNT","Cr")
end

function menu.kpiConstructionGraph(t)
    section(t,"CONSTRUCTION PROGRESS - ACTIVE STATIONS")
    local selected=menu.kpiConstructionSelection or "__all__"; local stationName="__all__"
    if selected~="__all__" then for _,record in ipairs(menu.constructionRecords or {}) do if tostring(tonumber(v(record,2,0)) or 0)==selected then stationName=text(v(record,1,"Unknown station")) end end end
    local names=menu.kpiLatestNames("constructionStations",stationName); menu.kpiNativeGraph(t,"MODULE COMPLETION BY STATION",menu.kpiGraphDefinitions("constructionStations",names,"percent"),"COMPLETE","%",0,100)
end

function menu.kpiTradeGraph(t)
    section(t,"OPEN TRADE OFFERS - AVAILABLE BUY / SELL QUANTITY")
    local selected=menu.kpiStation_trade or "__all__"; local names=menu.kpiLatestNames("tradeStations",selected)
    local definitions=menu.kpiGraphDefinitions("tradeStations",names,"amount")
    menu.kpiNativeGraph(t,"OPEN OFFER QUANTITY - NOT COMPLETED TRADE VOLUME",definitions,"QUANTITY","")
end

function menu.kpiStorageGraph(t)
    section(t,"STORAGE LEVELS - CAPACITY USED")
    local selected=menu.kpiStation_storage or "__all__"; local definitions={}
    if selected=="__all__" then
        local history=menu.kpiGraphHistory(); local latest=history[#history] or {}; local prior=history[#history-1] or {}; local stations, priorMap={},{}
        for _,x in ipairs(prior.storageStations or {}) do priorMap[x.name]=math.max(priorMap[x.name] or 0,tonumber(x.percent) or 0) end
        for _,x in ipairs(latest.storageStations or {}) do
            local name=tostring(x.name or "Unknown station"); local fill=tonumber(x.percent) or 0
            if not stations[name] or fill>stations[name].fill then stations[name]={name=name,fill=fill} end
        end
        local rows={}; for _,item in pairs(stations) do item.change=priorMap[item.name] and item.fill-priorMap[item.name] or nil; table.insert(rows,item) end
        table.sort(rows,function(a,b) if a.fill==b.fill then return a.name<b.name end return a.fill>b.fill end)
        local help=t:addRow(false); help[1]:setColSpan(4):createText("HIGHEST STORAGE FILL BY STATION — highest first. Green is below 80%, amber is 80–89.9%, and red is 90% or more. Change is measured from the prior live sample.",{wordwrap=true,color=navigationStoryColor})
        kpiHeader(t,{"STATION","STATUS","FILL / CHANGE","CAPACITY BAR"})
        for index=1,math.min(12,#rows) do
            local item=rows[index]; local state=item.fill>=90 and "CRITICAL — NEAR FULL" or item.fill>=80 and "HIGH" or "AVAILABLE"; local color=item.fill>=90 and investigationFailColor or item.fill>=80 and investigationUnknownColor or investigationPassColor
            local row=t:addRow(false); row[1]:createText(item.name,{wordwrap=true}); row[2]:createText(state,{color=color}); row[3]:createText(string.format("%.1f%% FULL%s",item.fill,item.change and string.format(" | %+.1f points",item.change) or " | FIRST SAMPLE"),{color=color}); row[4]:createText("["..string.rep("=",math.max(0,math.min(20,math.floor(item.fill/5+0.5))))..string.rep(".",math.max(0,20-math.min(20,math.floor(item.fill/5+0.5)))).."]",{color=color})
        end
        if #rows==0 then pair(t,"STATUS","EOC has not retained the first storage sample yet.","NEXT","No player action — background collection continues.") end
        return
    else
        local names=menu.kpiLatestNames("storageStations",selected,"kind"); definitions=menu.kpiGraphDefinitions("storageStations",names,"percent","kind")
    end
    menu.kpiNativeGraph(t,selected=="__all__" and "HIGHEST STORAGE FILL BY STATION" or "STORAGE FILL BY TYPE",definitions,"USED","%",0,100)
end

function menu.kpiShipyardGraph(t)
    section(t,"SHIPYARD ACTIVITY - LIVE WORKLOAD")
    local history=menu.kpiHistory or {}; local latest=history[#history] or {}; local selected=menu.kpiShipyard or "__all__"; local rows={}
    for _,yard in ipairs(latest.shipyards or {}) do if selected=="__all__" or yard.name==selected then table.insert(rows,yard) end end
    table.sort(rows,function(a,b) if (a.total or 0)==(b.total or 0) then return tostring(a.name)<tostring(b.name) end return (a.total or 0)>(b.total or 0) end)
    local totalYards=#rows; while #rows>8 do table.remove(rows) end
    kpiHeader(t,{"SHIPYARD","ACTIVE BUILDS","QUEUED BUILDS","TOTAL / MODULES / STATUS"})
    for _,yard in ipairs(rows) do local row=t:addRow(false); local total=(tonumber(yard.active) or 0)+(tonumber(yard.queued) or 0); row[1]:createText(yard.name or "Unknown shipyard"); row[2]:createText(tostring(yard.active or 0)); row[3]:createText(tostring(yard.queued or 0)); row[4]:createText(tostring(total).." / "..tostring(yard.modules or 0).." / "..(total>0 and "WORKING" or "IDLE"),{color=total>0 and investigationPassColor or investigationNeutralColor}) end
    if #rows==0 then pair(t,"STATUS","EOC has not retained a live shipyard sample yet.","NEXT","No player refresh is required.") elseif totalYards>#rows then pair(t,"DISPLAY","Eight busiest shipyards shown.","TOTAL SHIPYARDS",tostring(totalYards)) end
end

function menu.kpiEarnersDrainsGraph(t, drains)
    local history=menu.kpiGraphHistory(); section(t,drains and "CASH DRAINS - FIVE FASTEST DECLINES" or "TOP EARNERS - FIVE FASTEST GAINS")
    if #history<2 then pair(t,"STATUS","EOC has not retained the second live sample yet.","NEXT","No player action — established collection continues."); return end
    local first,last=stationMoneyMap(history[1]),stationMoneyMap(history[#history]); local ranked={}
    for name,amount in pairs(last) do local baseline=first[name]; if baseline and baseline>0 then local delta=amount-baseline; local change=delta*100/baseline; if (drains and delta<0) or (not drains and delta>0) then table.insert(ranked,{name=name,amount=amount,delta=delta,change=change,baseline=baseline}) end end end
    table.sort(ranked,function(a,b)
        if drains then return a.delta < b.delta end
        return a.delta > b.delta
    end); while #ranked>5 do table.remove(ranked) end
    local help=t:addRow(false); help[1]:setColSpan(4):createText("Ranked by actual credit movement in the selected window. The percentage is change from that station's starting account, not a score; a large percentage can come from a small starting balance.",{wordwrap=true,color=navigationStoryColor})
    kpiHeader(t,{"STATION","CURRENT ACCOUNT","CREDIT CHANGE","CHANGE FROM START"})
    for _,item in ipairs(ranked) do local color=item.delta<0 and investigationFailColor or investigationPassColor; local row=t:addRow(false); row[1]:createText(item.name,{wordwrap=true}); row[2]:createText(formatNumber(item.amount).." Cr"); row[3]:createText(string.format("%+.0f Cr",item.delta),{color=color}); row[4]:createText(string.format("%+.1f%% (start %s Cr)",item.change,formatNumber(item.baseline)),{color=color,wordwrap=true}) end
    if #ranked==0 then pair(t,"STATUS",drains and "No station account declined in this window." or "No station account increased in this window.","WINDOW","Select another range or continue playing.") end
end

function menu.kpiAttentionSummary(t)
    local rows=buildKpiRows(); section(t,"EXECUTIVE ATTENTION - FIVE HIGHEST PRIORITIES"); local help=t:addRow(false); help[1]:setColSpan(4):createText("Highest operational priority appears first. State and reasons replace the former unexplained numeric score.",{wordwrap=true,color=navigationStoryColor}); kpiHeader(t,{"RANK / STATE","STATION","HEALTH / TREND","WHY IT IS RANKED"})
    for index=1,math.min(5,#rows) do local item=rows[index]; local row=t:addRow(false); row[1]:createText(index..". "..item.state); row[2]:createText(item.name); row[3]:createText(item.health.." / "..item.trend); row[4]:createText(menu.attentionReason(item),{wordwrap=true}) end
    if #rows==0 then pair(t,"STATUS","No player stations are available.","PRIORITIES","0") end
end

local function kpiCashFlowView(t)
    local h = menu.kpiHistory or {}
    section(t, "EMPIRE CASH FLOW - VERIFIED PLAYER ACCOUNT")
    if #h == 0 then pair(t, "STATUS", "EOC has not retained the first live sample yet.", "NEXT", "No player action — established collection continues."); return end
    local latest = h[#h]
    pair(t, "CURRENT CREDITS", formatNumber(latest.credits) .. " Cr", "CHANGE SINCE LAST SAMPLE", formatNumber(latest.creditChange) .. " Cr")
    menu.kpiNativeGraph(t, "OVERALL WEALTH", { { label = "PLAYER ACCOUNT", color = Color["transactionlog_graph_data"], value = function(sample) return sample.credits end } }, "ACCOUNT", "Cr")
end

local function kpiStationProfitView(t)
    local h, rows = menu.kpiHistory or {}, {}
    if #h >= 2 then
        local current, previous = stationMoneyMap(h[#h]), stationMoneyMap(h[#h - 1])
        for name, money in pairs(current) do table.insert(rows, { time = h[#h].time, name = name, money = money, change = previous[name] and money - previous[name] or 0 }) end
        table.sort(rows, function(a,b) return a.change == b.change and a.name < b.name or a.change > b.change end)
    end
    section(t, "STATION ACCOUNT MOVEMENT - LATEST VERIFIED INTERVAL")
    kpiHeader(t, { "STATION", "ACCOUNT", "LATEST MOVEMENT", "DIRECTION" })
    kpiPagedRows(t, rows, function(item)
        local row=t:addRow(false); row[1]:createText(item.name); row[2]:createText(formatNumber(item.money).." Cr"); row[3]:createText(formatNumber(item.change).." Cr"); row[4]:createText(item.change>0 and "UP" or item.change<0 and "DOWN" or "UNCHANGED")
    end, "EOC has not retained the second live sample yet; no player action is required.")
end

local function kpiConstructionView(t)
    local selection, records = menu.kpiConstructionSelection or "__all__", {}
    for _, record in ipairs(menu.constructionRecords or {}) do local id=tostring(tonumber(v(record,2,0)) or 0); if (tonumber(v(record,3,0)) or 0)>0 and (selection=="__all__" or id==selection) then table.insert(records,record) end end
    if selection~="__all__" and menu.activeConstructionSnapshot and tostring(tonumber(v(menu.activeConstructionSnapshot,2,0)) or 0)==selection then records={menu.activeConstructionSnapshot} end
    table.sort(records,function(a,b)return text(v(a,1,""))<text(v(b,1,""))end)
    if selection=="__all__" then
        section(t,"CONSTRUCTION PROGRESS - ALL ACTIVE STATIONS"); kpiHeader(t,{"STATION","ACTIVE / PLANNED","TOTAL QUEUE","CURRENT MODULE"})
        kpiPagedRows(t,records,function(record) local current="NONE"; for _,item in ipairs(v(record,8,{})) do if string.upper(text(v(item,3,"")))=="UNDER CONSTRUCTION" then current=text(v(item,1,"Unknown module")).." / "..string.format("%.1f%%",tonumber(v(item,4,0)) or 0); break end end; local row=t:addRow(false); row[1]:createText(text(v(record,1,"Unknown station")),{wordwrap=true}); row[2]:createText(tostring(v(record,5,0)).." / "..tostring(v(record,4,0))); row[3]:createText(tostring(v(record,3,0))); row[4]:createText(current,{wordwrap=true}) end,"No active station construction detected.")
        return
    end
    local selected=records[1]; section(t,"CONSTRUCTION PROGRESS - ACTIVE STATION DRILLDOWN"); if not selected then pair(t,"STATUS","No active station construction detected for this filter.","MODULES","0"); return end
    kpiHeader(t,{"QUEUE","MODULE","CURRENT STATUS","PROGRESS"}); local items=v(selected,8,{})
    kpiPagedRows(t,items,function(item,index) local row=t:addRow(false); row[1]:createText("#"..tostring(v(item,8,index))); row[2]:createText(text(v(item,1,"Unknown module")),{wordwrap=true}); row[3]:createText(text(v(item,3,"PLANNED"))); row[4]:createText(string.format("%.1f%%",tonumber(v(item,4,0)) or 0)) end,"No module rows are available.")
end

local function kpiTradeView(t)
    local rows, selected, sortBy = {}, menu.kpiStation_trade or "__all__", menu.kpiSort_trade or "station"
    for _,x in ipairs(menu.tradeOffers or {}) do if selected=="__all__" or text(v(x,1,""))==selected then table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="ware" then return text(v(a,3,""))<text(v(b,3,"")) elseif sortBy=="type" then return text(v(a,2,""))<text(v(b,2,"")) elseif sortBy=="quantity" then return (tonumber(v(a,4,0)) or 0)>(tonumber(v(b,4,0)) or 0) end return text(v(a,1,""))<text(v(b,1,"")) end)
    section(t,"TRADE ACTIVITY - EOC-MANAGED OFFERS ONLY"); kpiHeader(t,{"STATION","BUY / SELL","WARE","QUANTITY / VERIFIED"})
    kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(text(v(x,1,"Unknown"))); row[2]:createText(text(v(x,2,"UNKNOWN"))); row[3]:createText(text(v(x,3,"Unknown ware"))); row[4]:createText(tostring(v(x,4,0)).." / "..(v(x,5,false) and "YES" or "NO")) end,"No EOC-managed offers match this filter.")
end

local function kpiLogisticsView(t)
    local rows, scope, sortBy = {}, menu.kpiLogisticsScope or "all", menu.kpiSort_logistics or "ship"
    if scope == "all" or scope == "registered" then for _,x in ipairs(menu.registeredShips or {}) do table.insert(rows,x) end end
    if scope == "all" or scope == "available" then for _,x in ipairs(menu.availableUnregisteredShips or {}) do table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="role" then return text(v(a,2,""))<text(v(b,2,"")) elseif sortBy=="status" then return text(v(a,7,""))<text(v(b,7,"")) elseif sortBy=="state" then return tostring(v(a,4,false))>tostring(v(b,4,false)) end return text(v(a,1,""))<text(v(b,1,"")) end)
    section(t,"LOGISTICS HEALTH - ELIGIBLE SHIP VISIBILITY")
    pair(t,"REGISTERED",#(menu.registeredShips or {}),"AVAILABLE - NOT REGISTERED",#(menu.availableUnregisteredShips or {}))
    kpiHeader(t,{"SHIP","ROLE / CLASS","OPERATIONAL","EOC STATUS"})
    kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(text(v(x,1,"Unknown ship"))); row[2]:createText(text(v(x,2,"Unknown")).." / "..text(v(x,3,"Unknown"))); row[3]:createText(v(x,4,false) and "YES" or "NO"); row[4]:createText(text(v(x,7,"REGISTERED"))) end,"No eligible ships match this scope. Available ships remain player-controlled until explicitly registered.")
end

local function kpiStorageView(t)
    local rows, selected, sortBy = {}, menu.kpiStation_storage or "__all__", menu.kpiSort_storage or "station"
    for _,x in ipairs(menu.storageRecords or {}) do if (selected=="__all__" or text(v(x,1,""))==selected) and (tonumber(v(x,4,0)) or 0)>0 then table.insert(rows,x) end end
    table.sort(rows,function(a,b) local ac=tonumber(v(a,4,0)) or 0; local bc=tonumber(v(b,4,0)) or 0; local af=ac>0 and (tonumber(v(a,3,0)) or 0)/ac or 0; local bf=bc>0 and (tonumber(v(b,3,0)) or 0)/bc or 0; if sortBy=="fill" then return af>bf elseif sortBy=="free" then return (tonumber(v(a,5,0)) or 0)>(tonumber(v(b,5,0)) or 0) elseif sortBy=="type" then return text(v(a,2,""))<text(v(b,2,"")) end local an=text(v(a,1,"")); local bn=text(v(b,1,"")); return an==bn and text(v(a,2,""))<text(v(b,2,"")) or an<bn end)
    section(t,"STORAGE LEVELS - VERIFIED STATION STORAGE TYPES"); kpiHeader(t,{"STATION / STORAGE TYPE","USED","CAPACITY / FREE","FILL %"})
    kpiPagedRows(t,rows,function(x) local used=tonumber(v(x,3,0)) or 0; local cap=tonumber(v(x,4,0)) or 0; local row=t:addRow(false); row[1]:createText(text(v(x,1,"Unknown")).." / "..text(v(x,2,"UNKNOWN"))); row[2]:createText(formatNumber(used)); row[3]:createText(formatNumber(cap).." / "..formatNumber(v(x,5,0))); row[4]:createText(cap>0 and string.format("%.1f%%",used*100/cap) or "UNAVAILABLE") end,"No verified storage capacity matches this filter.")
end

local function kpiWorkforceView(t)
    local rows, selected, sortBy = {}, menu.kpiStation_workforce or "__all__", menu.kpiSort_workforce or "station"
    if selected == "__all__" then
        local stations = {}
        for _,x in ipairs(menu.workforceRecords or {}) do
            local name = text(v(x,1,"Unknown station"))
            local item = stations[name]
            if not item then item={name=name,current=0,capacity=0,optimal=0,trend="UNKNOWN",change=0,worstProvision="NONE",worstCurrent=0,worstTarget=0,worstShortfall=0,details=0}; stations[name]=item end
            item.current=math.max(item.current,tonumber(v(x,3,0)) or 0); item.capacity=math.max(item.capacity,tonumber(v(x,4,0)) or 0); item.optimal=math.max(item.optimal,tonumber(v(x,5,0)) or 0); item.trend=text(v(x,6,item.trend)); item.change=tonumber(v(x,7,item.change)) or item.change; item.details=item.details+1
            local shortfall=tonumber(v(x,11,0)) or 0
            if shortfall>item.worstShortfall then item.worstProvision=text(v(x,8,"Unknown provision")); item.worstCurrent=tonumber(v(x,9,0)) or 0; item.worstTarget=tonumber(v(x,10,0)) or 0; item.worstShortfall=shortfall end
        end
        for _,item in pairs(stations) do table.insert(rows,item) end
        table.sort(rows,function(a,b) if sortBy=="population" then return a.current>b.current elseif sortBy=="change" then return a.change>b.change elseif sortBy=="shortfall" then return a.worstShortfall>b.worstShortfall end return a.name<b.name end)
        section(t,"WORKFORCE HEALTH - ONE SUMMARY PER STATION"); kpiHeader(t,{"STATION / DETAILS","CURRENT / CAP / OPTIMAL","TREND / CHANGE","WORST PROVISION CURRENT / TARGET / SHORT"})
        kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(x.name.." / "..x.details.." detail row(s)"); row[2]:createText(x.current.." / "..x.capacity.." / "..x.optimal); row[3]:createText(x.trend.." / "..x.change); row[4]:createText(x.worstProvision.."  "..x.worstCurrent.." / "..x.worstTarget.." / "..x.worstShortfall,{wordwrap=true}) end,"No workforce population is available.")
        return
    end
    for _,x in ipairs(menu.workforceRecords or {}) do if text(v(x,1,""))==selected then table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="population" then return (tonumber(v(a,3,0)) or 0)>(tonumber(v(b,3,0)) or 0) elseif sortBy=="change" then return (tonumber(v(a,7,0)) or 0)>(tonumber(v(b,7,0)) or 0) elseif sortBy=="shortfall" then return (tonumber(v(a,11,0)) or 0)>(tonumber(v(b,11,0)) or 0) end local an=text(v(a,1,"")); local bn=text(v(b,1,"")); return an==bn and text(v(a,2,""))<text(v(b,2,"")) or an<bn end)
    section(t,"WORKFORCE HEALTH - SELECTED STATION DETAIL"); kpiHeader(t,{"STATION / SPECIES","CURRENT / CAP / OPTIMAL","TREND / CHANGE","PROVISION CURRENT / TARGET / SHORT"})
    kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(text(v(x,1,"Unknown")).." / "..text(v(x,2,"Unknown species"))); row[2]:createText(tostring(v(x,3,0)).." / "..tostring(v(x,4,0)).." / "..tostring(v(x,5,0))); row[3]:createText(text(v(x,6,"UNKNOWN")).." / "..tostring(v(x,7,0))); row[4]:createText(text(v(x,8,"Unknown provision")).."  "..tostring(v(x,9,0)).." / "..tostring(v(x,10,0)).." / "..tostring(v(x,11,0)),{wordwrap=true}) end,"No workforce population matches this filter.")
end

local function kpiShipyardView(t)
    local selected, yardMap, rows = menu.kpiShipyard or "__all__", {}, {}
    for _,x in ipairs(menu.shipWharfRoutes or {}) do local name=text(v(x,2,"Unknown shipyard")); if (selected=="__all__" or name==selected) and not yardMap[name] then yardMap[name]={kind="YARD",a=name,b=v(x,6,0),c=v(x,7,0),d=v(x,8,0)} end end
    for _,x in pairs(yardMap) do table.insert(rows,x) end
    for _,x in ipairs(menu.shipOrderRecords or {}) do if selected=="__all__" or text(v(x,4,""))==selected then table.insert(rows,{kind="ORDER",a=text(v(x,1,"Unknown")),b=text(v(x,5,"Unknown ship")),c=text(v(x,4,"Unknown yard")),d=text(v(x,6,"Unknown task")).." / "..formatGameTime(v(x,7,0))}) end end
    table.sort(rows,function(a,b) return a.kind==b.kind and tostring(a.a)<tostring(b.a) or a.kind<b.kind end)
    section(t,"SHIPYARD ACTIVITY - RETAINED YARDS AND EOC ORDERS"); kpiHeader(t,{"TYPE / STATION","SHIP / QUEUED","YARD / ACTIVE","TASK / MODULES"})
    kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(x.kind.." / "..tostring(x.a)); row[2]:createText(tostring(x.b)); row[3]:createText(tostring(x.c)); row[4]:createText(tostring(x.d),{wordwrap=true}) end,"No shipyard activity matches this filter.")
end

local function kpiExtendedView(t,view)
    if view=="trade" then return kpiTradeView(t) elseif view=="logistics" then return kpiLogisticsView(t) elseif view=="storage" then return kpiStorageView(t) elseif view=="workforce" then return kpiWorkforceView(t) elseif view=="shipyard" then return kpiShipyardView(t) end
    local titles={earners="TOP EARNERS",drains="CASH DRAINS",casetrends="CASE TRENDS",growth="EMPIRE GROWTH"}; local h=menu.kpiHistory or {}; local rows={}
    section(t,(titles[view] or "KPI VIEW")..((view=="earners" or view=="drains") and " - LATEST VERIFIED INTERVAL" or " - NATIVE ROLLING GRAPH"))
    if view=="casetrends" or view=="growth" then
        if view=="casetrends" then
            menu.kpiNativeGraph(t, "OPEN CASE TREND", {
                { label="CRITICAL", color=investigationFailColor, value=function(x) return x.caseCritical end },
                { label="WARNING", color=investigationUnknownColor, value=function(x) return x.caseWarning end },
                { label="OTHER", color=investigationNeutralColor, value=function(x) return x.caseOther end },
            }, "CASES", "")
        else
            menu.kpiNativeGraph(t, "EMPIRE ASSET GROWTH", {
                { label="STATIONS", color=Color["transactionlog_graph_data"], value=function(x) return x.stationCount end },
                { label="REGISTERED SHIPS", color=investigationPassColor, value=function(x) return x.registeredShipCount end },
                { label="CONSTRUCTION", color=investigationUnknownColor, value=function(x) return x.constructionRecordCount end },
                { label="SHIP ORDERS", color=investigationNeutralColor, value=function(x) return x.shipOrderCount end },
            }, "COUNT", "")
        end
        return
    end
    if #h>=2 then local previous=stationMoneyMap(h[#h-1]); local current=stationMoneyMap(h[#h]); for station,amount in pairs(current) do local delta=(tonumber(amount) or 0)-(tonumber(previous[station]) or 0); if (view=="earners" and delta>0) or (view=="drains" and delta<0) then table.insert(rows,{station=station,delta=delta}) end end end
    table.sort(rows,function(a,b) return view=="earners" and a.delta>b.delta or view=="drains" and a.delta<b.delta end)
    while #rows>5 do table.remove(rows) end
    local maximum=1; for _,x in ipairs(rows) do maximum=math.max(maximum,math.abs(x.delta)) end
    kpiHeader(t,{"STATION","LATEST MOVEMENT","DIRECTION","RELATIVE BAR"})
    kpiPagedRows(t,rows,function(x) local row=t:addRow(false); row[1]:createText(x.station); row[2]:createText(formatNumber(x.delta).." Cr"); row[3]:createText(x.delta>0 and "UP" or "DOWN"); row[4]:createText(kpiBar(x.delta,maximum),{color=x.delta<0 and investigationFailColor or investigationPassColor}) end,"No qualifying movement occurred in the latest interval.")
end

function menu.predictiveIntelligenceView(t)
    section(t, "EOC 3.7 PREDICTIVE INTELLIGENCE")
    local store = menu.supplyModelStore()
    local state = store.views and store.views.balance or nil
    local current, previous = state and state.current or nil, state and state.previous or nil
    local intro = t:addRow(false)
    intro[1]:setColSpan(4):createText("Forecasts use your saved Supply checks, KPI history and Fleet coverage. Opening this page does not start a scan. More saved information gives EOC more confidence. UNKNOWN means EOC does not know yet.", { wordwrap = true })
    if not current then
        local row = t:addRow(false)
        row[1]:setColSpan(4):createText("NOT ENOUGH INFORMATION YET. EOC needs two checks taken at different times before it can show a trend. Do not keep this page open and do not press anything again. Keep playing; EOC will use the normal saved information when it is ready.", { wordwrap = true, color = investigationUnknownColor })
        row = t:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, "OPEN EMPIRE RESOURCE MATRIX", function()
            captureNavigation("PREDICTIVE INTELLIGENCE")
            menu.page = "supply"
            menu.activeTab = "supply"
            menu.supplyView = "balance"
            menu.supplyPages.balance = menu.supplyPages.balance or 1
            menu.refresh()
        end, true)
        return
    end
    local elapsed = previous and math.max(0, (tonumber(current.captured) or 0) - (tonumber(previous.captured) or 0)) or 0
    local meaningfulPrevious = previous and elapsed >= 300 and previous or nil
    local priorStations, coverage = {}, {}
    for _, station in ipairs((meaningfulPrevious and meaningfulPrevious.stations) or {}) do priorStations[tostring(station.id or station.name)] = station end
    for _, record in ipairs(menu.reconciledLogisticsCoverage()) do coverage[text(v(record, 1, "")) .. "|" .. menu.supplyWareId(v(record, 2, ""))] = record end
    local risks = {}
    local function add(category, severity, station, stationId, ware, outlook, confidence, evidence, leakage)
        risks[#risks + 1] = { category=category, severity=severity, station=station, stationId=stationId, ware=ware, outlook=outlook, confidence=confidence, evidence=evidence, leakage=leakage or 0 }
    end
    local function priorWare(station, ware)
        if not station then return nil end
        for _, record in ipairs(station.wares or {}) do if menu.supplyWareId(record.ware) == menu.supplyWareId(ware) then return record end end
        return nil
    end
    local function matchingCases(risk)
        local matches = {}
        local riskWare = menu.supplyWareId(risk.ware)
        for _, caseData in ipairs(menu.cases or {}) do
            if text(v(caseData, 1, "")) == risk.station then
                local subjectId = menu.supplyWareId(v(caseData, 4, ""))
                local actionId = menu.supplyWareId(v(caseData, 17, ""))
                local retainedId = menu.supplyWareId(v(caseData, 40, ""))
                if riskWare ~= "" and (riskWare == subjectId or riskWare == actionId or riskWare == retainedId) then matches[#matches + 1] = caseData end
            end
        end
        return matches
    end
    local function stationIndex(risk)
        for index, profile in ipairs(menu.stations or {}) do
            if (risk.stationId ~= "" and tostring(v(profile, 24, "")) == tostring(risk.stationId)) or text(v(profile, 1, "")) == risk.station then return index end
        end
        return menu.selected
    end
    local function caseNeedsShip(caseData)
        local cargo = text(v(caseData, 12, "UNKNOWN")):upper()
        local supported = cargo == "CONTAINER" or cargo == "SOLID" or cargo == "LIQUID"
        return supported and (tonumber(v(caseData, 24, 0)) or 0) == 0 and (tonumber(v(caseData, 9, 0)) or 0) > (tonumber(v(caseData, 8, 0)) or 0), cargo
    end
    local function openCase(risk, caseData)
        captureNavigation("PREDICTIVE INTELLIGENCE")
        menu.selected = stationIndex(risk)
        menu.caseScope = "station"
        menu.caseSeverity = "all"
        menu.casePage = 1
        menu.selectedCase = 1
        for index, candidate in ipairs(filteredCases()) do if candidate == caseData then menu.selectedCase = index; break end end
        menu.diagnosticCase = caseData
        menu.page = "cases"
        menu.activeTab = "cases"
        menu.refresh()
    end
    local function openCaseReview(risk)
        captureNavigation("PREDICTIVE INTELLIGENCE")
        menu.selected = stationIndex(risk)
        menu.caseScope = "station"
        menu.caseSeverity = "all"
        menu.casePage = 1
        menu.selectedCase = 1
        menu.diagnosticCase = nil
        menu.page = "cases"
        menu.activeTab = "cases"
        menu.refresh()
    end
    local function openShipRecommendation(risk, caseData)
        local _, cargo = caseNeedsShip(caseData)
        captureNavigation("PREDICTIVE INTELLIGENCE")
        menu.selected = stationIndex(risk)
        menu.fleetScope = "station"
        menu.fleetView = "recommendations"
        menu.fleetPage = 1
        menu.fleetRecommendationCargo = cargo
        menu.page = "fleet"
        menu.activeTab = "fleet"
        menu.refresh()
    end
    for _, station in ipairs(current.stations or {}) do
        local priorStation = priorStations[tostring(station.id or station.name)]
        local totalStock, priorTotal = 0, 0
        for _, record in ipairs(station.wares or {}) do totalStock = totalStock + math.max(0, tonumber(record.stock) or 0) end
        for _, record in ipairs((priorStation and priorStation.wares) or {}) do priorTotal = priorTotal + math.max(0, tonumber(record.stock) or 0) end
        local capacity = tonumber(station.storageCapacity) or 0
        if capacity > 0 and totalStock / capacity >= 0.90 then
            local sustained = priorStation and priorTotal / capacity >= 0.85
            add("SHARED-STORAGE CONGESTION", sustained and 1 or 2, station.name, station.id, "ALL WARES", "Storage is " .. formatNumber(totalStock * 100 / capacity) .. "% FULL — higher is worse; 100% means no capacity remains.", sustained and "HIGH" or "MEDIUM", sustained and "Two snapshots show the station remaining above the congestion threshold." or "Current occupancy is high; EOC is retaining later evidence automatically before claiming persistence.")
        end
        for _, record in ipairs(station.wares or {}) do
            local prior = priorWare(priorStation, record.ware)
            local stock, priorStock = math.max(0, tonumber(record.stock) or 0), prior and math.max(0, tonumber(prior.stock) or 0) or nil
            local production, consumption = math.max(0, tonumber(record.effectiveProduction) or 0), math.max(0, tonumber(record.effectiveConsumption) or 0)
            local netDepletion = math.max(0, consumption - production)
            local observedDepletion = priorStock and elapsed > 0 and math.max(0, (priorStock - stock) * 3600 / elapsed) or 0
            local depletion = math.max(netDepletion, observedDepletion)
            if record.resource and depletion > 0 then
                local hours = stock / depletion
                if hours <= 4 then
                    local confidence = prior and elapsed >= 300 and stock < priorStock and netDepletion > 0 and "HIGH" or prior and "MEDIUM" or "LOW"
                    add("APPROACHING SHORTAGE", hours <= 1 and 1 or 2, station.name, station.id, record.name, "Estimated depletion in " .. string.format("%.1f", hours) .. " hour(s).", confidence, "Stock " .. formatNumber(stock) .. (priorStock and ("; prior " .. formatNumber(priorStock)) or "; no prior ware sample") .. "; effective production/use " .. formatNumber(production) .. "/h / " .. formatNumber(consumption) .. "/h.")
                end
            end
            if (tonumber(record.installedProduction) or 0) > 0 and production <= 0 then
                local confirmed = prior and (tonumber(prior.effectiveProduction) or 0) <= 0
                add("PRODUCTION STALL", confirmed and 1 or 2, station.name, station.id, record.name, "Installed output is currently idle.", confirmed and "HIGH" or "MEDIUM", formatNumber(record.installedProduction) .. "/h installed versus 0/h effective" .. (confirmed and " across both retained snapshots." or "; a second separated snapshot is required to prove persistence."), (tonumber(record.installedProduction) or 0) * (tonumber(record.averageprice) or 0))
            end
            local cover = coverage[station.name .. "|" .. menu.supplyWareId(record.ware)]
            local target = cover and math.max(0, tonumber(v(cover, 6, 0)) or 0) or 0
            local working = cover and math.max(0, tonumber(v(cover, 8, 0)) or 0) or 0
            local assigned = cover and math.max(0, tonumber(v(cover, 7, 0)) or 0) or 0
            if record.product and target > 0 and stock >= target * 1.15 then
                local sustained = priorStock and priorStock >= target * 1.10
                add("SUSTAINED OVERSTOCK", sustained and 1 or 2, station.name, station.id, record.name, "Stock is " .. formatNumber(stock * 100 / target) .. "% OF TARGET — above 100% means excess inventory; " .. string.format("%.1f", stock / target) .. " times the target is currently stored.", sustained and "HIGH" or "MEDIUM", (sustained and "Both retained snapshots exceed target" or "Current stock exceeds target") .. "; assigned/working sellers " .. assigned .. "/" .. working .. ".", math.max(0, stock - target) * (tonumber(record.averageprice) or 0))
                if working <= 0 then add("INSUFFICIENT SELLING CAPACITY", 1, station.name, station.id, record.name, "Overstock has no seller currently working.", assigned > 0 and "HIGH" or "MEDIUM", "Assigned/working sellers " .. assigned .. "/" .. working .. "; stock/target " .. formatNumber(stock) .. "/" .. formatNumber(target) .. ".") end
            end
        end
    end
    for _, record in ipairs(menu.reconciledLogisticsCoverage()) do
        local assigned, working, blocked = tonumber(v(record,7,0)) or 0, tonumber(v(record,8,0)) or 0, tonumber(v(record,10,0)) or 0
        local stock, target = tonumber(v(record,5,0)) or 0, tonumber(v(record,6,0)) or 0
        if assigned > 0 and working == 0 and blocked == 0 and target > 0 and stock >= target then
            add("UNDERUSED SHIPS", 3, text(v(record,1,"Unknown station")), "", text(v(record,3,"Unknown ware")), tostring(assigned) .. " assigned ship(s) have no current work while stock is covered.", "MEDIUM", "Stock/target " .. formatNumber(stock) .. "/" .. formatNumber(target) .. "; work/wait/block " .. working .. "/" .. tostring(v(record,9,0)) .. "/" .. blocked .. ".")
        end
    end
    local history = menu.kpiHistory or {}
    local latest, priorKpi = history[#history], history[#history - 1]
    local priorWorkforce = {}
    for _, item in ipairs((priorKpi and priorKpi.workforceStations) or {}) do priorWorkforce[item.name] = item end
    for _, item in ipairs((latest and latest.workforceStations) or {}) do
        local old = priorWorkforce[item.name]
        if (tonumber(item.provision) or 100) < 25 and (tonumber(item.percent) or 0) < 90 then
            local declining = old and (tonumber(item.percent) or 0) < (tonumber(old.percent) or 0)
            add("WORKFORCE-SUPPLY COLLAPSE", declining and 1 or 2, item.name, "", "WORKFORCE", "Provision stock is " .. formatNumber(item.provision) .. "% OF ITS TARGET (100% = enough) while staffing is " .. formatNumber(item.percent) .. "% OF OPTIMAL WORKFORCE (100% = fully staffed).", declining and "HIGH" or (old and "MEDIUM" or "LOW"), declining and "Rolling KPI evidence shows staffing declining while provisions remain critical." or "Current KPI evidence is critical; more separated samples are required to prove direction.")
        end
    end
    -- Profit exposure is an impact of the originating operating condition, not
    -- a second incident or player action. Keep it on the primary forecast so a
    -- station/ware/case chain exposes exactly one governed route.
    for _, risk in ipairs(risks) do
        risk.cases = matchingCases(risk)
        risk.case = risk.cases[1]
        risk.shipNeed = false
        if risk.case then risk.shipNeed = caseNeedsShip(risk.case) end
        risk.actionable = risk.case ~= nil or (meaningfulPrevious ~= nil and risk.severity == 1 and risk.confidence ~= "LOW")
    end
    table.sort(risks, function(a,b) if a.severity == b.severity then if a.category == b.category then return a.station < b.station end return a.category < b.category end return a.severity < b.severity end)
    local status = t:addRow(false)
    status[1]:setColSpan(4):createText(#risks .. " FORECAST(S) | " .. (meaningfulPrevious and ("TWO MEANINGFUL SNAPSHOTS, " .. formatNumber(elapsed / 60) .. " MIN APART") or (previous and ("BASELINE ONLY — SNAPSHOTS " .. formatNumber(elapsed / 60) .. " MIN APART; 5 MIN REQUIRED") or "ONE SNAPSHOT — LOW CONFIDENCE BASELINE")) .. " | NO BACKGROUND SCAN", { halign="center", color=#risks > 0 and investigationUnknownColor or investigationPassColor })
    if #risks == 0 then local row=t:addRow(false); row[1]:setColSpan(4):createText("NO CURRENT FORECAST WARNING. EOC does not have enough evidence to warn you about a future problem. This does not mean a future problem is impossible.", {wordwrap=true,color=investigationPassColor}); return end
    menu.predictiveFilter = menu.predictiveFilter or "actionable"
    local controls=t:addRow(true)
    addButton(controls,1,(menu.predictiveFilter=="actionable" and "ACTIVE: " or "").."ACTIONABLE",function() menu.predictiveFilter="actionable"; menu.predictiveStationId=nil; menu.refresh() end,true,menu.predictiveFilter=="actionable" and investigationPassColor or nil)
    addButton(controls,2,(menu.predictiveFilter=="watch" and "ACTIVE: " or "").."WATCH",function() menu.predictiveFilter="watch"; menu.predictiveStationId=nil; menu.refresh() end,true,menu.predictiveFilter=="watch" and investigationPassColor or nil)
    addButton(controls,3,(menu.predictiveFilter=="all" and "ACTIVE: " or "").."ALL EVIDENCE",function() menu.predictiveFilter="all"; menu.predictiveStationId=nil; menu.refresh() end,true,menu.predictiveFilter=="all" and investigationPassColor or nil)
    addButton(controls,4,"EMPIRE SUMMARY",function() menu.predictiveStationId=nil; menu.refresh() end,menu.predictiveStationId~=nil)
    local groups, groupList = {}, {}
    for _, risk in ipairs(risks) do
        if menu.predictiveFilter=="all" or (menu.predictiveFilter=="actionable" and risk.actionable) or (menu.predictiveFilter=="watch" and not risk.actionable and risk.severity<=2) then
            local key=tostring(risk.stationId~="" and risk.stationId or risk.station)
            if not groups[key] then groups[key]={key=key,station=risk.station,stationId=risk.stationId,severity=risk.severity,actionable=0,watch=0,high=0,risks={},categories={}}; groupList[#groupList+1]=groups[key] end
            local group=groups[key]; group.severity=math.min(group.severity,risk.severity); group.actionable=group.actionable+(risk.actionable and 1 or 0); group.watch=group.watch+(risk.actionable and 0 or 1); group.high=group.high+(risk.confidence=="HIGH" and 1 or 0); group.risks[#group.risks+1]=risk; group.categories[risk.category]=true
        end
    end
    table.sort(groupList,function(a,b) if a.severity==b.severity then if a.high==b.high then return a.station<b.station end return a.high>b.high end return a.severity<b.severity end)
    if menu.predictiveStationId then
        local selectedGroup=groups[tostring(menu.predictiveStationId)]
        if not selectedGroup then menu.predictiveStationId=nil else
            local row=t:addRow(true); row[1]:setColSpan(4); addButton(row,1,"BACK TO RANKED EMPIRE RISKS",function() menu.predictiveStationId=nil; menu.refresh() end,true)
            row=t:addRow(false); row[1]:setColSpan(4):createText(selectedGroup.station.." | "..#selectedGroup.risks.." FORECAST(S) | "..selectedGroup.actionable.." ACTIONABLE | "..selectedGroup.watch.." COLLECTING/REVIEW | "..selectedGroup.high.." HIGH CONFIDENCE",{color=selectedGroup.actionable>0 and investigationFailColor or investigationUnknownColor})
            for _,risk in ipairs(selectedGroup.risks) do
                row=t:addRow(false); row[1]:createText(risk.category,{color=risk.actionable and investigationFailColor or investigationUnknownColor}); row[2]:createText(risk.ware); row[3]:createText(risk.outlook,{wordwrap=true}); row[4]:createText(risk.confidence.." CONFIDENCE")
                row=t:addRow(false); row[1]:setColSpan(4):createText("EVIDENCE: "..risk.evidence,{wordwrap=true})
                if risk.leakage > 0 then
                    row=t:addRow(false); row[1]:setColSpan(4):createText("BUSINESS IMPACT: Estimated exposed value/rate "..formatNumber(risk.leakage).." Cr. This is context from the same evidence, not a second incident or booked profit.",{wordwrap=true,color=navigationStoryColor})
                end
                row=t:addRow(false)
                local playerText
                if risk.case and risk.shipNeed then playerText = "EOC STATUS: EXACT CASE FOUND — PLAYER SHIP DECISION AVAILABLE. The case reports a real shortfall and zero compatible logistics ships; Fleet can evaluate one governed ship order."
                elseif risk.case then playerText = "EOC STATUS: EXACT CASE FOUND — FOLLOW ITS GUIDED NEXT STEP. EOC has not proven that this forecast requires another ship."
                elseif not meaningfulPrevious then playerText = "EOC STATUS: EVIDENCE COLLECTION REQUIRED — NO PLAYER ACTION YET. This baseline cannot prove whether delivery, an existing ship, or new construction is required."
                else playerText = "EOC STATUS: NO EXACT CASE YET — EOC HAS NOT PROVEN A PLAYER CHANGE. Review this station's evidence and run the case workflow before changing ships or construction." end
                row[1]:setColSpan(4):createText(playerText,{wordwrap=true,color=risk.actionable and navigationStoryColor or investigationUnknownColor})
                row=t:addRow(true)
                if risk.case and risk.shipNeed then
                    row[1]:setColSpan(2); addButton(row,1,"OPEN EXACT CASE",(function(chosenRisk,chosenCase) return function() openCase(chosenRisk,chosenCase) end end)(risk,risk.case),true)
                    row[3]:setColSpan(2); addButton(row,3,"REVIEW & AUTHORIZE 1 SHIP",(function(chosenRisk,chosenCase) return function() openShipRecommendation(chosenRisk,chosenCase) end end)(risk,risk.case),true,pendingChoiceBackground)
                elseif risk.case then
                    row[1]:setColSpan(4); addButton(row,1,"OPEN EXACT CASE — SEE WHAT EOC NEEDS",(function(chosenRisk,chosenCase) return function() openCase(chosenRisk,chosenCase) end end)(risk,risk.case),true)
                elseif not meaningfulPrevious then
                    row[1]:setColSpan(4); addButton(row,1,"COLLECT REQUIRED EVIDENCE — OPEN EMPIRE RESOURCE MATRIX",function() captureNavigation("PREDICTIVE INTELLIGENCE"); menu.page="supply"; menu.activeTab="supply"; menu.supplyView="balance"; menu.supplyPages.balance=menu.supplyPages.balance or 1; menu.refresh() end,true)
                else
                    row[1]:setColSpan(4); addButton(row,1,"OPEN STATION CASE REVIEW — NO EXACT CASE YET",(function(chosenRisk) return function() openCaseReview(chosenRisk) end end)(risk),true)
                end
            end
            row=t:addRow(true); row[1]:setColSpan(4); addButton(row,1,"OPEN STATION — RETURN PATH PRESERVED",function() for i,p in ipairs(menu.stations or {}) do if (selectedGroup.stationId~="" and tostring(v(p,24,""))==tostring(selectedGroup.stationId)) or text(v(p,1,""))==selectedGroup.station then menu.selected=i; break end end; captureNavigation("PREDICTIVE INTELLIGENCE"); menu.page="stations"; menu.activeTab="stations"; menu.refresh() end,true)
        end
    else
        local row=t:addRow(false); row[1]:setColSpan(4):createText(#groupList.." STATION(S) MATCH | RANKED BY SEVERITY, CONFIDENCE, THEN NAME | SELECT A STATION FOR RESOURCE EVIDENCE",{halign="center"})
        local first, last = menu.adaptiveListNavigation(t, "kpi.predictive.stations", #groupList, { fixedRows = 8, rowUnits = 3, columns = 2 })
        for index=first,last,2 do row=t:addRow(true); for offset=0,1 do local group=groupList[index+offset]; local col=1+offset*2; if group then row[col]:setColSpan(2); local categories={}; for category in pairs(group.categories) do categories[#categories+1]=category end; table.sort(categories); addButton(row,col,group.station.."\n"..group.actionable.." ACTIONABLE | "..group.watch.." COLLECTING/REVIEW | "..group.high.." HIGH CONFIDENCE\n"..table.concat(categories," / "),(function(chosen) return function() menu.predictiveStationId=chosen; menu.refresh() end end)(group.key),true,group.actionable>0 and investigationFailColor or investigationUnknownColor,Helper.standardButtonHeight*3,nil,nil,true) end end end
        if #groupList==0 then row=t:addRow(false); row[1]:setColSpan(4):createText("No stations match this filter. Choose WATCH or ALL EVIDENCE to widen the view.",{color=investigationUnknownColor}) end
    end
    DebugError("[JKEOC][B318][PREDICTIVE_INCIDENT_ROUTING] forecasts="..tostring(#risks).." ranked_stations="..tostring(#groupList).." meaningful_snapshots="..tostring(meaningfulPrevious~=nil).." elapsed="..tostring(elapsed).." derived_impact_rows=0 exact_case_routing=1 return_context=1 background_scan=0 recurring_supply_scan=0")
end

local function kpiCenterResults(tableWidget)
    menu.kpiView=menu.kpiView or "cash"
    if menu.kpiView=="workforce" or menu.kpiView=="casetrends" or menu.kpiView=="shortages" then menu.kpiView="cash" end
    if menu.kpiView=="predictive" then menu.predictiveIntelligenceView(tableWidget)
    elseif menu.kpiView=="construction" then menu.kpiConstructionGraph(tableWidget)
    elseif menu.kpiView=="attention" then menu.kpiAttentionSummary(tableWidget)
    elseif menu.kpiView=="trade" then menu.kpiTradeGraph(tableWidget)
    elseif menu.kpiView=="storage" then menu.kpiStorageGraph(tableWidget)
    elseif menu.kpiView=="earners" then menu.kpiEarnersDrainsGraph(tableWidget,false)
    elseif menu.kpiView=="drains" then menu.kpiEarnersDrainsGraph(tableWidget,true)
    elseif menu.kpiView=="shipyard" then menu.kpiShipyardGraph(tableWidget)
    else menu.kpiCashFlowGraph(tableWidget) end
end
local function dashboard(tableWidget)
    menu.narrativeScope = menu.narrativeScope or "30m"
    local now = 0
    for _, obs in ipairs(menu.observations or {}) do now = math.max(now, tonumber(v(obs, 16, 0)) or 0, tonumber(v(obs, 17, 0)) or 0, tonumber(v(obs, 18, 0)) or 0) end
    for _, report in ipairs(menu.reports or {}) do now = math.max(now, tonumber(v(report, 4, 0)) or 0) end
    if menu.narrativeSessionStart == 0 and now > 0 then menu.narrativeSessionStart = now end
    local cutoff = menu.narrativeScope == "30m" and now - 1800 or menu.narrativeScope == "1h" and now - 3600 or menu.narrativeScope == "session" and (menu.narrativeSessionStart or now) or menu.narrativeScope == "review" and narrativeStore().lastReview or 0
    section(tableWidget, "EOC STATION STORY")
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("A station-by-station recap of what EOC observed, how the evidence developed, what it means, and where attention is most useful.", {wordwrap=true})
    local choices={{"review","SINCE REVIEW"},{"30m","LAST 30 MIN"},{"1h","LAST HOUR"},{"session","THIS SESSION"}}
    row=tableWidget:addRow(true)
    for col,choice in ipairs(choices) do local c=choice; addButton(row,col,(menu.narrativeScope==c[1] and "ACTIVE: " or "")..c[2],function() menu.narrativeScope=c[1]; menu.refresh() end,true,menu.narrativeScope==c[1] and investigationPassColor or nil) end
    row=tableWidget:addRow(true); row[1]:setColSpan(2); addButton(row,1,(menu.narrativeScope=="history" and "ACTIVE: " or "").."RETAINED HISTORY",function() menu.narrativeScope="history"; menu.refresh() end,true); row[3]:setColSpan(2); addButton(row,3,"MARK STORY REVIEWED",function() local store=narrativeStore(); store.lastReview=now; saveNarrativeStore(store); menu.narrativeScope="review"; menu.refresh() end,true)
    local storyRecords = {}
    for stationIndex, station in ipairs(menu.stations or {}) do
        local name=text(v(station,1,"Station")); local observations={}; local categories={}; local counts={SYSTEMIC=0,RECURRING=0,CANDIDATE=0,RECOVERING=0,RELAPSED=0}; local leading=nil
        local stationReports={}; local reportKinds={}; for _,report in ipairs(menu.reports or {}) do local title=text(v(report,1,"EOC REPORT")); local body=text(v(report,2,"")); local stamp=tonumber(v(report,4,0)) or 0; if (menu.narrativeScope=="history" or cutoff<=0 or (menu.narrativeScope=="review" and stamp>cutoff) or (menu.narrativeScope~="review" and stamp>=cutoff)) and (string.find(title,name,1,true) or string.find(body,"Station: "..name,1,true)) then stationReports[#stationReports+1]=report; reportKinds[title]=true end end
        for _,obs in ipairs(stationObservations(name)) do local stamp=math.max(tonumber(v(obs,16,0)) or 0,tonumber(v(obs,17,0)) or 0,tonumber(v(obs,18,0)) or 0); if menu.narrativeScope=="history" or cutoff<=0 or stamp>=cutoff then observations[#observations+1]=obs; categories[text(v(obs,2,"OPERATIONS"))]=true; local state=text(v(obs,4,"BASELINE")); counts[state]=(counts[state] or 0)+1; if not leading or (({RELAPSED=5,SYSTEMIC=4,RECURRING=3,CANDIDATE=2,RECOVERING=1})[state] or 0) > (({RELAPSED=5,SYSTEMIC=4,RECURRING=3,CANDIDATE=2,RECOVERING=1})[text(v(leading,4,"BASELINE"))] or 0) then leading=obs end end end
        local cases=stationCases(name)
        if #observations>0 or #cases>0 or #stationReports>0 then storyRecords[#storyRecords+1]={ stationIndex=stationIndex, station=station, name=name, observations=observations, categories=categories, counts=counts, leading=leading, reports=stationReports, reportKinds=reportKinds, cases=cases } end
    end
    if #storyRecords == 0 then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("No station evidence falls inside this time window. Choose a wider period or continue until the next analysis.",{wordwrap=true}); return end
    local firstStation, lastStation = menu.adaptiveListNavigation(tableWidget, "overview.story." .. tostring(menu.narrativeScope), #storyRecords, { fixedRows = 6, rowUnits = 7, maximum = 2 })
    for recordIndex = firstStation, lastStation do
        local record=storyRecords[recordIndex]; local stationIndex=record.stationIndex; local station=record.station; local name=record.name; local observations=record.observations; local categories=record.categories; local counts=record.counts; local leading=record.leading; local stationReports=record.reports; local reportKinds=record.reportKinds; local cases=record.cases
        local categoryCount=0; for _ in pairs(categories) do categoryCount=categoryCount+1 end; local health=text(v(station,3,"MONITORING")); local trend=text(v(station,4,"STABLE")); section(tableWidget,name.." | "..health.." / "..trend); local active=counts.SYSTEMIC+counts.RECURRING+counts.CANDIDATE+counts.RELAPSED; local story
            if active==1 and counts.SYSTEMIC==1 then story="One issue currently drives this status. Fixing it may materially improve health, but CHRONIC clears only after later recovery samples and stable remaining systems."
            elseif categoryCount>1 then story=active.." active retained issues span "..categoryCount.." operating areas. Fixing only the leading issue is unlikely to restore overall health."
            elseif active>1 then story=active.." retained issues are concentrated in one operating area. Address the leading blocker; EOC will re-evaluate related evidence automatically."
            elseif counts.RECOVERING>0 then story="Earlier evidence is improving, but EOC is retaining it until later samples prove recovery holds."
            else story="No current escalation appears in this period; retained history remains available for comparison." end
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("STORY: "..story,{wordwrap=true,color=stationStatusColor(health)}); if leading then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("LEADING EVIDENCE: "..text(v(leading,3,"Operations")).." - "..text(v(leading,5,"No evidence summary available")),{wordwrap=true}); row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("OUTLOOK: "..(trend=="DETERIORATING" and "Evidence is worsening." or trend=="IMPROVING" and "Evidence is improving; EOC will verify whether it holds." or "Evidence is stable.").." DO THIS NEXT: "..text(v(leading,7,"Ask EOC once for a background test; EOC will return the answer.")),{wordwrap=true}) end
            local reportKindCount=0; for _ in pairs(reportKinds) do reportKindCount=reportKindCount+1 end
            if #stationReports>0 then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("RECENT ACTIVITY: "..#stationReports.." report(s) recorded in this period across "..reportKindCount.." consolidated report type(s). Latest: "..text(v(stationReports[1],1,"Station report")).." at "..text(v(stationReports[1],3,"-")),{wordwrap=true,color=navigationStoryColor}) end
        pair(tableWidget,"EVIDENCE",#observations.." retained / "..categoryCount.." area(s)","CASES / REPORTS",#cases.." / "..#stationReports); row=tableWidget:addRow(true); local selected=stationIndex; row[1]:setColSpan(2); addButton(row,1,"OPEN THIS STATION'S CASES",function() menu.selected=selected; captureNavigation("OVERVIEW"); menu.caseScope="station"; menu.caseSeverity="all"; menu.page="cases"; menu.activeTab="cases"; menu.refresh() end,true); row[3]:setColSpan(2); addButton(row,3,"OPEN THIS STATION'S DIAGNOSTICS",function() menu.selected=selected; captureNavigation("OVERVIEW"); menu.diagnosticView="recovery"; menu.page="diagnostics"; menu.activeTab="diagnostics"; menu.refresh() end,true)
    end
end
local function createStationNavigator(frame, x, y, width, height)
    local tableWidget = frame:addTable(3, {
        tabOrder = 2,
        x = x,
        y = y,
        width = width,
        reserveScrollBar = true,
        borderEnabled = true,
    })
    local nameWidth = math.floor(width * 0.54)
    local roleWidth = math.floor(width * 0.20)

    tableWidget:setColWidth(1, nameWidth, false)
    tableWidget:setColWidth(2, roleWidth, false)
    tableWidget.properties.maxVisibleHeight = height

    local row = tableWidget:addRow(false, { fixed = true })
    row[1]:setColSpan(3):createText("STATION NAVIGATOR  |  " .. #menu.stations .. " STATIONS", {
        font = Helper.headerFont,
        fontsize = Helper.standardFontSize + 1,
    })

    row = tableWidget:addRow(false, { fixed = true })
    row[1]:createText("STATION")
    row[2]:createText("ROLE")
    row[3]:createText("STATUS")

    if #menu.stations == 0 then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(3):createText("No player stations are currently available.", {
            wordwrap = true,
        })
    else
        local first, last, page, pageCount = menu.adaptiveListWindow(#menu.stations, "stations.navigator", { contentPixels = height, fixedRows = 3, rowUnits = 1 })
        if pageCount > 1 then
            if pageCount > 2 then
                row = tableWidget:addRow(true, { fixed = true })
                addButton(row, 1, "RETURN TO PAGE 1", function() menu.listPages["stations.navigator"] = 1; menu.refresh() end, page > 1)
            end
            row = tableWidget:addRow(true, { fixed = true })
            addButton(row, 1, "PREVIOUS", function() menu.listPages["stations.navigator"] = math.max(1, page - 1); menu.refresh() end, page > 1)
            row[2]:createText("PAGE " .. page .. " / " .. pageCount, { halign = "center" })
            addButton(row, 3, "NEXT", function() menu.listPages["stations.navigator"] = math.min(pageCount, page + 1); menu.refresh() end, page < pageCount)
        end
        for index = first, last do
            local station = menu.stations[index]
            local stationIndex = index
            row = tableWidget:addRow(true)
            local isSelectedStation = stationIndex == menu.selected
            row[1]:createButton({
                active = true,
                bgColor = isSelectedStation and inactiveModeBackground or nil,
            }):setText(text(v(station, 1, "Station")))
            row[1].handlers.onClick = function()
                menu.selected = stationIndex
                menu.refresh()
            end
            local stationRole = text(v(station, 2, "UNDEFINED"))
            local stationStatus = text(v(station, 3, "MONITORING"))
            row[2]:createText(stationRole, {
                fontsize = Helper.standardFontSize - 1,
                color = stationRole == "UNDEFINED" and investigationUnknownColor or investigationPassColor,
            })
            row[3]:createText(stationStatus, {
                fontsize = Helper.standardFontSize - 1,
                color = stationStatusColor(stationStatus),
            })
        end
    end

    if #menu.stations > 0 then
        tableWidget:setSelectedRow(menu.selected + 2)
    end
    return tableWidget
end

local function addRoleControls(tableWidget, station)
    section(tableWidget, "PERSISTENT EOC ROLE - REMAINS UNTIL YOU CHANGE IT")
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("GREEN = CURRENT ROLE | AMBER = PREVIEW AWAITING CONFIRMATION | GRAY = AVAILABLE ROLE", { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("ROLE SCOPE: These buttons change only the selected station's persistent EOC role. Select once to preview; select CONFIRM to apply.", { wordwrap = true })

    for roleIndex = 1, #roles, 4 do
        row = tableWidget:addRow(true)
        for column = 1, 4 do
            local role = roles[roleIndex + column - 1]
            if role then
                local stationIndex = v(station, 16, menu.selected)
                local current = text(v(station, 2, "UNDEFINED")) == role
                local confirming = menu.pendingRole and menu.pendingRole.index == stationIndex and menu.pendingRole.role == role
                local roleLabel = current and ("CURRENT: " .. role) or (confirming and ("CONFIRM: " .. role) or role)
                addStationChoiceButton(row, column, roleLabel, current, confirming, function()
                    if current then
                        menu.roleConfirmation = role .. " is already the selected station's persistent EOC role. No change is needed."
                        menu.refresh()
                        return
                    end
                    if not confirming then
                        menu.pendingRole = { index = stationIndex, role = role }
                        menu.roleConfirmation = "CONFIRM ROLE CHANGE: Select CONFIRM: " .. role .. " to change " .. text(v(station, 1, "this station")) .. ". No role has changed yet."
                        menu.refresh()
                        return
                    end
                    if not startAction("station.role") then return end
                    menu.pendingRole = nil
                    menu.roleConfirmation = nil
                    raise("station.role", { index = stationIndex, role = role })
                    station[2] = role
                    menu.refresh()
                end)
            end
        end
    end

    if menu.roleConfirmation then
        local confirmRow = tableWidget:addRow(false)
        confirmRow[1]:setColSpan(4):createText(menu.roleConfirmation, { wordwrap = true })
    end
    actionResult(tableWidget, "station.role", "ROLE CONTROL: Role changes require two deliberate clicks. The first click previews; the second confirms.")

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(
        row,
        1,
        actionLabel("station.auto", "ACTION: ASSIGN UNDEFINED STATION ROLES", "ASSIGNING STATION ROLES"),
        function()
            if startAction("station.auto") then
                raise("station.auto", {})
            end
        end,
        not actionState("station.auto").running
    )
    actionResult(
        tableWidget,
        "station.auto",
        "EMPIRE-WIDE ACTION: Assigns roles only to player stations that are currently undefined. Existing persistent roles are not changed."
    )
end

local function addStationIssues(tableWidget, station)
    local cases = stationCases(station)
    section(tableWidget, "WHAT NEEDS ATTENTION")

    if #cases == 0 then
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("EOC CONCLUSION: No critical or warning case currently requires player action. DO THIS NEXT: Continue monitoring.", { wordwrap = true })
        return
    end

    local case = cases[1]
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(
        "FIRST CASE TO HANDLE: " .. text(v(case, 4, "GENERAL OPERATIONS")) .. " - " .. text(v(case, 2, "ISSUE")) .. ". " ..
        (#cases > 1 and ("There are " .. #cases .. " active cases; Cases shows the full list.") or "This is the station's only active case."),
        { wordwrap = true }
    )
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHY IT IS OPEN: " .. text(v(case, 6, "Evidence requires review")), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("DO THIS NEXT: Open Cases, then select Guided Next Action.", { wordwrap = true })
end
local function addOperationsControls(tableWidget)
    if menu.settingsStatus then
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:setColSpan(4):createText(menu.settingsStatus, { wordwrap = true })
    end
    section(tableWidget, "OPERATIONS")
    pair(tableWidget, "Trade Order Mode", menu.mode, "EOC-owned Offers", menu.offers)
    pair(
        tableWidget,
        "Ship Assignment Mode",
        menu.shipmode,
        "Active Cases",
        v(menu.summary, 11, 0)
    )

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, "TRADE MODE: ADVISOR", menu.mode == "ADVISOR", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING ADVISOR MODE..."
        raise("trade.advisor", {})
        menu.mode = "ADVISOR"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "TRADE MODE: MANAGED", menu.mode == "MANAGED", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING MANAGED TRADE..."
        raise("trade.managed", {})
        menu.mode = "MANAGED"
        menu.refresh()
    end)

    section(tableWidget, "SHIP ASSIGNMENT")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addModeButton(
        row,
        1,
        menu.shipmode == "DISABLED" and "SHIP ASSIGNMENT: DISABLED" or "SHIP ASSIGNMENT: ENABLED",
        menu.shipmode ~= "DISABLED",
        not menu.settingsChangeRunning,
        function()
            menu.settingsChangeRunning = true
            menu.settingsStatus = "STATUS: APPLYING SHIP ASSIGNMENT TOGGLE..."
            if menu.shipmode == "DISABLED" then
                menu.shipmode = menu.previousShipmode or "APPROVAL REQUIRED"
            else
                menu.previousShipmode = menu.shipmode
                menu.shipmode = "DISABLED"
            end
            raise("shipping.toggle", {})
            menu.refresh()
        end
    )

    local assignmentEnabled = menu.shipmode ~= "DISABLED"
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, "APPROVAL REQUIRED", menu.shipmode == "APPROVAL REQUIRED", assignmentEnabled and not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING APPROVAL REQUIRED..."
        raise("shipping.approval", {})
        menu.shipmode = "APPROVAL REQUIRED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "AUTO-ASSIGN REGISTERED", menu.shipmode == "AUTO-ASSIGN REGISTERED", assignmentEnabled and not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING AUTO-ASSIGN REGISTERED..."
        raise("shipping.auto", {})
        menu.shipmode = "AUTO-ASSIGN REGISTERED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)

    section(tableWidget, "ONE-TIME OPERATION ACTIONS - RUN ONLY WHEN SELECTED")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("ACTION SCOPE: Each explanation below begins with the exact button it describes. These are commands, not persistent station settings.", { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(true)
    addButton(row, 1, actionLabel("trade.review", "ACTION: REVIEW EOC TRADE ORDERS", "REVIEWING ORDERS"), function()
        if startAction("trade.review") then
            raise("trade.review", {})
        end
    end, not actionState("trade.review").running)
    addButton(row, 2, actionLabel("shipping.scan", "ACTION: SCAN SHIPPING NEEDS", "SCANNING SHIPPING NEEDS"), function()
        if startAction("shipping.scan") then
            raise("shipping.scan", {})
        end
    end, not actionState("shipping.scan").running)
    row[3]:setColSpan(2)
    addButton(row, 3, actionLabel("analysis.run", "ACTION: RUN EMPIRE ANALYSIS", "ANALYSIS RUNNING"), function()
        if startAction("analysis.run") then
            menu.analysisRunning = true
            raise("analysis.run", {})
        end
    end, not actionState("analysis.run").running)
    actionResult(
        tableWidget,
        "trade.review",
        "REVIEW EOC TRADE ORDERS: Checks EOC-owned trade offers; Managed mode may create, verify, or remove them."
    )
    actionResult(
        tableWidget,
        "shipping.scan",
        "SCAN SHIPPING NEEDS: Checks logistics needs and registered ships; Auto mode may assign a compatible ship."
    )
    actionResult(
        tableWidget,
        "analysis.run",
        "RUN EMPIRE ANALYSIS: Refreshes EOC intelligence and recommendations; it does not authorize new operations."
    )
end

local function addReportsControls(tableWidget)
    section(tableWidget, "REPORTS")

    if menu.reportStatus then
        pair(tableWidget, "STATUS", menu.reportStatus, "REPORT", menu.lastReport or "EOC REPORT")
    end

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "GENERATE REPORT: SELECTED STATION", function()
        captureReportOrigin("stations", "STATIONS - " .. text(v(selectedStation(), 1, "SELECTED STATION")))
        menu.pendingReport = "SELECTED STATION"
        raise("report.station", { index = v(selectedStation(), 16, menu.selected) })
    end, #menu.stations > 0)
    row[3]:setColSpan(2)
    addButton(row, 3, "GENERATE REPORT: OPERATIONAL REMEDIATION", function()
        captureReportOrigin("stations", "STATIONS - " .. text(v(selectedStation(), 1, "SELECTED STATION")))
        menu.pendingReport = "OPERATIONAL REMEDIATION"
        raise("report.remediation", {})
    end, true)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "GENERATE REPORT: TRADE ORDER STATUS", function()
        captureReportOrigin("stations", "STATIONS - " .. text(v(selectedStation(), 1, "SELECTED STATION")))
        menu.pendingReport = "TRADE ORDER STATUS"
        raise("report.trade", {})
    end, true)

    section(tableWidget, "REPORT DELIVERY")
    pair(
        tableWidget,
        "READ NOW",
        "Completed reports open automatically in the REPORTS tab.",
        "ARCHIVE COPY",
        "Also saved to Player Information > Logbook > Tips."
    )
end

local function reportsCenter(tableWidget)
    section(tableWidget, "EOC REPORT CENTER")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("PURPOSE: Read EOC's completed finding, then use Return to continue exactly where you left off. Logbook archiving happens automatically.", { wordwrap = true })
    pair(
        tableWidget,
        "INFO",
        "Newest completed report is selected automatically.",
        "ARCHIVE",
        "Permanent copies remain in Logbook > Tips."
    )

    if menu.reportOrigin then
        local row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, "RETURN TO " .. text(menu.reportOrigin.label), function()
            local origin = menu.reportOrigin
            menu.selected = origin.selected or menu.selected
            menu.selectedCase = origin.selectedCase or menu.selectedCase
            menu.caseScope = origin.caseScope or menu.caseScope
            menu.caseSeverity = origin.caseSeverity or menu.caseSeverity
            menu.casePage = origin.casePage or menu.casePage
            menu.fleetScope = origin.fleetScope or menu.fleetScope
            menu.fleetView = origin.fleetView or menu.fleetView
            menu.fleetPage = origin.fleetPage or menu.fleetPage
            menu.reportOrigin = nil
            menu.page = origin.page
            menu.activeTab = origin.page
            menu.refresh()
        end, true)
    end

    if #menu.reports == 0 then
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(
            "NO REPORTS GENERATED THIS SESSION\n\nGenerate a report from the Stations or Overview tab. " ..
            "EOC will open the completed report here automatically.",
            { wordwrap = true }
        )
        return
    end

    section(tableWidget, "RECENT REPORTS  |  " .. #menu.reports .. " OF 20")
    local firstReport, lastReport = menu.adaptiveListNavigation(tableWidget, "reports.recent", #menu.reports, { fixedRows = 16, rowUnits = 1, maximum = 8 })
    for index = firstReport, lastReport do
        local report = menu.reports[index]
        local reportIndex = index
        local row = tableWidget:addRow(true)
        row[1]:setColSpan(3)
        addButton(row, 1, text(v(report, 1, "EOC REPORT")), function()
            menu.selectedReport = reportIndex
            menu.refresh()
        end, true)
        row[4]:createText(text(v(report, 3, "THIS SESSION")), { halign = "right" })
    end

    local selected = menu.reports[menu.selectedReport] or menu.reports[1]
    section(tableWidget, text(v(selected, 1, "EOC REPORT")))
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(text(v(selected, 2, "No report text was returned.")), {
        wordwrap = true,
        x = Helper.borderSize,
        y = Helper.borderSize,
    })
end

local function stationWorkspace(tableWidget)
    local station = selectedStation()
    section(tableWidget, "SELECTED STATION")

    if not station then
        pair(tableWidget, "INFO", "No station selected", "", "")
        section(tableWidget, "STATUS")
        local emptyStatus = tableWidget:addRow(false)
        emptyStatus[1]:setColSpan(4):createText("Select a station from the navigator.", { wordwrap = true })
        return
    end

    local cases = stationCases(station)
    local observations = stationObservations(station)
    local health = string.upper(text(v(station, 3, "MONITORING")))
    local trend = string.upper(text(v(station, 4, "STABLE")))
    local systemic, recurring, candidate, recovering, relapsed = 0, 0, 0, 0, 0
    local topSubject, topEvidence, topState = nil, nil, nil
    for _, observation in ipairs(observations) do
        local state = string.upper(text(v(observation, 4, "BASELINE")))
        if state == "SYSTEMIC" then systemic = systemic + 1
        elseif state == "RECURRING" then recurring = recurring + 1
        elseif state == "CANDIDATE" then candidate = candidate + 1
        elseif state == "RECOVERING" then recovering = recovering + 1
        elseif state == "RELAPSED" then relapsed = relapsed + 1 end
        if not topSubject and (state == "SYSTEMIC" or state == "RELAPSED" or state == "RECURRING" or state == "CANDIDATE") then
            topSubject = text(v(observation, 3, "General operations"))
            topEvidence = text(v(observation, 5, "No evidence summary available"))
            topState = state
        end
    end

    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(text(v(station, 1, "Station")), { font = Helper.headerFont, fontsize = Helper.standardFontSize + 2 })
    pair(tableWidget, "ROLE", v(station, 2, "UNDEFINED"), "HEALTH / TREND", health .. " / " .. trend)
    pair(tableWidget, "ACTIVE CASES", #cases, "RETAINED ISSUES", #observations)

    local constructionRecord = constructionRecordForSelected()
    local constructionCount = math.max(tonumber(v(station, 12, 0)) or 0, tonumber(v(constructionRecord, 3, 0)) or 0)
    if constructionCount > 0 then
        local underway = tonumber(v(constructionRecord, 5, 0)) or 0
        local waiting = tonumber(v(constructionRecord, 4, 0)) or 0
        section(tableWidget, "ONGOING CONSTRUCTION DETECTED - " .. tostring(constructionCount) .. " MODULE(S)")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(tostring(underway) .. " UNDERWAY / " .. tostring(waiting) .. " WAITING", { color = underway > 0 and investigationPassColor or resultColor("UNKNOWN"), font = Helper.headerFont })
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, "ONGOING CONSTRUCTION - OPEN CONSTRUCTION CONTROL", function()
            captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
            menu.page = "construction"; menu.activeTab = "construction"; menu.refresh()
        end, true)
    end

    section(tableWidget, "STATION STATUS TESTS")
    pair(tableWidget, "ACTIVE CASE TEST", #cases > 0 and ("ATTENTION - " .. #cases .. " OPEN") or "PASS - NONE OPEN", "HISTORY TEST", #observations > 0 and (#observations .. " RETAINED") or "PASS - CLEAR")
    pair(tableWidget, "PERSISTENCE TEST", systemic .. " SYSTEMIC / " .. recurring .. " RECURRING", "CHANGE TEST", relapsed .. " RELAPSED / " .. recovering .. " RECOVERING")
    row = tableWidget:addRow(false)
    local reason
    if health == "CHRONIC" then
        reason = "WHY CHRONIC: " .. systemic .. " systemic and " .. recurring .. " recurring retained issue(s) remain after repeated evidence."
    elseif health == "RELAPSED" or trend == "RELAPSED" then
        reason = "WHY RELAPSED: " .. math.max(1, relapsed) .. " previously improving or resolved issue(s) returned in later evidence."
    elseif health == "TRANSIENT" then
        reason = "WHY TRANSIENT: " .. math.max(1, candidate) .. " recent issue candidate(s) exist, but repeated evidence has not yet made them recurring or systemic."
    elseif health == "RECURRING" then
        reason = "WHY RECURRING: " .. math.max(1, recurring) .. " retained issue(s) repeated across samples but have not reached systemic status."
    else
        reason = "WHY " .. health .. ": Current cases and retained history do not meet Chronic, Relapsed, or Transient escalation conditions."
    end
    row[1]:setColSpan(4):createText(reason, { wordwrap = true, color = stationStatusColor(health) })
    if topSubject then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("LEADING CONTRIBUTOR - " .. topState .. " - " .. topSubject .. ": " .. topEvidence, { wordwrap = true, color = resultColor(topState) })
    end

    section(tableWidget, "STATUS DEFINITIONS")
    row = tableWidget:addRow(false)
    row[1]:createText("TRANSIENT - new evidence", { wordwrap = true, color = stationStatusColor("TRANSIENT") })
    row[2]:createText("RECURRING - repeated", { wordwrap = true, color = stationStatusColor("RECURRING") })
    row[3]:setColSpan(2):createText("CHRONIC - systemic persistence", { wordwrap = true, color = stationStatusColor("CHRONIC") })
    row = tableWidget:addRow(false)
    row[1]:createText("RECOVERING - improving", { wordwrap = true, color = stationStatusColor("RECOVERING") })
    row[2]:createText("RELAPSED - returned", { wordwrap = true, color = stationStatusColor("RELAPSED") })
    row[3]:setColSpan(2):createText("MONITORING - no escalation", { wordwrap = true, color = stationStatusColor("MONITORING") })

    section(tableWidget, "STATION ACTIONS")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, actionLabel("analysis.run", "RUN FRESH EMPIRE ANALYSIS", "EMPIRE ANALYSIS RUNNING"), function()
        if startAction("analysis.run") then
            menu.analysisRunning = true
            raise("analysis.run", {})
        end
    end, not actionState("analysis.run").running)
    row[3]:setColSpan(2)
    addButton(row, 3, "GENERATE STATION REPORT", function()
        captureReportOrigin("stations", "STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.pendingReport = "SELECTED STATION"
        raise("report.station", { index = v(station, 16, menu.selected) })
    end, true)

    if (tonumber(v(station, 12, 0)) or 0) > 0 then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, "ONGOING CONSTRUCTION DETECTED - VIEW CHECKLIST", function()
            captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
            menu.page = "construction"; menu.activeTab = "construction"; menu.refresh()
        end, true)
    end

    section(tableWidget, "STATION ROLE")
    for roleIndex = 1, #roles, 4 do
        row = tableWidget:addRow(true)
        for column = 1, 4 do
            local role = roles[roleIndex + column - 1]
            if role then
                local stationIndex = v(station, 16, menu.selected)
                local current = text(v(station, 2, "UNDEFINED")) == role
                local confirming = menu.pendingRole and menu.pendingRole.index == stationIndex and menu.pendingRole.role == role
                addStationChoiceButton(row, column, current and ("CURRENT: " .. role) or (confirming and ("CONFIRM: " .. role) or role), current, confirming, function()
                    if current then menu.roleConfirmation = role .. " is already current. No change made."
                    elseif not confirming then menu.pendingRole = { index = stationIndex, role = role }; menu.roleConfirmation = "PREVIEW: Change this station's role to " .. role .. ". Select CONFIRM to apply."
                    elseif startAction("station.role") then menu.pendingRole = nil; menu.roleConfirmation = nil; raise("station.role", { index = stationIndex, role = role }); station[2] = role end
                    menu.refresh()
                end)
            end
        end
    end

    section(tableWidget, "STATUS - UPDATES HERE")
    local status = menu.roleConfirmation or menu.settingsStatus or menu.clickStatus
    local roleState = actionState("station.role")
    local analysisState = actionState("analysis.run")
    if roleState.running then status = "WORKING: Applying the selected station role..."
    elseif roleState.result then status = "RESULT: " .. text(roleState.result)
    elseif analysisState.running then status = "WORKING: Running a fresh empire analysis. The selected station result will follow when it completes..."
    elseif analysisState.result then status = "EMPIRE ANALYSIS COMPLETE: " .. tostring(#(menu.stations or {})) .. " stations analyzed. SELECTED STATION RESULT: " .. text(v(station, 1, "Selected station")) .. " is " .. health .. " / " .. trend .. " with " .. #cases .. " active case(s) and " .. #observations .. " retained issue(s)."
    elseif menu.reportStatus then status = text(menu.reportStatus) end
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(status or "READY: Run a fresh empire analysis, generate a station report, open focused evidence, or preview a role change.", { wordwrap = true, color = menu.pendingRole and investigationUnknownColor or navigationStoryColor })
end

local function commandIdentitySetup(tableWidget, firstRun)
    local store = commandIdentityStore()
    menu.identityDraft = menu.identityDraft or store.name or ""
    local returnToStaffing = tableWidget:addRow(true)
    returnToStaffing[1]:setColSpan(4)
    addButton(returnToStaffing, 1, "RETURN TO FLEET STAFFING", function()
        menu.page = "fleet"
        menu.activeTab = "fleet"
        menu.fleetView = "staffing"
        menu.fleetPage = 1
        menu.refresh()
    end, true, investigationPassColor)
    section(tableWidget, firstRun and "EOC COMMAND INTELLIGENCE INITIALIZATION" or "COMMAND INTELLIGENCE IDENTITY")
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(firstRun and ("I recognize you as " .. playerDisplayName() .. ". Before we begin, what would you like to call me?") or ("I currently answer to " .. intelligenceName() .. ". You may give me a new name at any time."), { wordwrap = true, color = navigationStoryColor })
    row = tableWidget:addRow(true)
    row[1]:createText("SYSTEM NAME")
    row[2]:setColSpan(3):createEditBox({ height = Helper.standardButtonHeight }):setText(menu.identityDraft)
    row[2].handlers.onEditBoxDeactivated = function(_, entered) menu.identityDraft = tostring(entered or "") end
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, firstRun and "ACTIVATE THIS IDENTITY" or "SAVE NEW NAME", function()
        local name = tostring(menu.identityDraft or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then menu.identityStatus = "Please enter the name you want me to remember."; menu.refresh(); return end
        if #name > 32 then name = string.sub(name, 1, 32) end
        store.name = name
        store.initialized = true
        saveCommandIdentityStore(store)
        menu.identityDraft = name
        menu.identityStatus = name .. " ONLINE - Thank you, " .. playerDisplayName() .. ". I'm ready to begin."
        if firstRun then
            menu.page = "boot"
            menu.activeTab = "boot"
            menu.osBootStages = buildOSBootStages()
            menu.osBootStage = 1
            menu.osBootNextAt = getElapsedTime() + EOC_OS_BOOT_DELAY
        end
        menu.refresh()
    end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, firstRun and "USE EOC FOR NOW" or "KEEP CURRENT NAME", function()
        if firstRun then
            store.name = "EOC"
            store.initialized = true
            saveCommandIdentityStore(store)
        end
        menu.identityDraft = intelligenceName()
        menu.identityStatus = intelligenceName() .. " ONLINE - I'm ready, " .. playerDisplayName() .. "."
        if firstRun then
            menu.page = "boot"
            menu.activeTab = "boot"
            menu.osBootStages = buildOSBootStages()
            menu.osBootStage = 1
            menu.osBootNextAt = getElapsedTime() + EOC_OS_BOOT_DELAY
        end
        menu.refresh()
    end, true)
    if menu.identityStatus then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(menu.identityStatus, { wordwrap = true, color = investigationPassColor }) end
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("I will use this name selectively during investigations, monitoring, verification, and other important moments. You remain in command.", { wordwrap = true })
end

local function commandOSBoot(tableWidget)
    local stages = menu.osBootStages or buildOSBootStages()
    menu.osBootStages = stages
    local stage = clamp(tonumber(menu.osBootStage) or 1, 1, #stages)
    section(tableWidget, "EOC OPERATING SYSTEM - BUILD " .. tostring(EOC_OS_BUILD))
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("PERSONALITY STARTUP SEQUENCE - ENTERTAINMENT STATUS ONLY. Operational evidence comes from EOC analysis after startup.", { wordwrap = true, color = investigationNeutralColor })

    for index = 1, stage do
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(stages[index], { wordwrap = true, color = index == #stages and investigationPassColor or navigationStoryColor })
    end

    if stage < #stages then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("Please stand by...", { wordwrap = true, color = investigationUnknownColor })
    else
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(intelligenceName() .. " at your disposal, " .. playerDisplayName() .. ". Ready for instructions.", { wordwrap = true, color = investigationPassColor })
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, "ENTER EXECUTIVE OPERATIONS CENTER", function()
            local store = commandIdentityStore()
            menu.sessionBootComplete = true
            menu.page = "dashboard"
            menu.activeTab = "dashboard"
            menu.osBootStage = nil
            menu.osBootNextAt = nil
            menu.refresh()
        end, true)
    end
end

local function globalSettings(tableWidget)
    commandIdentitySetup(tableWidget, false)
    section(tableWidget, "STARTUP EXPERIENCE")
    local identity = commandIdentityStore()
    local savedStartupEnabled = type(menu.savedStartupPreference) == "boolean" and menu.savedStartupPreference or identity.startupSequenceEnabled ~= false
    if type(menu.pendingStartupPreference) ~= "boolean" then menu.pendingStartupPreference = savedStartupEnabled end
    local startupEnabled = menu.pendingStartupPreference
    local startupDirty = startupEnabled ~= savedStartupEnabled
    local startupRow = tableWidget:addRow(true)
    startupRow[1]:setColSpan(4)
    addButton(startupRow, 1, startupEnabled and "COMPUTER LOADING SCREEN: ON" or "COMPUTER LOADING SCREEN: OFF", function()
        menu.pendingStartupPreference = not menu.pendingStartupPreference
        menu.settingsStatus = "UNSAVED GLOBAL SETTINGS: Select SAVE GLOBAL SETTINGS to commit this change."
        menu.refresh()
    end, true, startupDirty and investigationUnknownColor or investigationPassColor)
    local startupInfo = tableWidget:addRow(false)
    startupInfo[1]:setColSpan(4):createText("This changes only the visual startup sequence. Analysis, evidence collection, and station scanning always continue.", { wordwrap = true })
    local saveRow = tableWidget:addRow(true)
    saveRow[1]:setColSpan(4)
    addButton(saveRow, 1, startupDirty and "SAVE GLOBAL SETTINGS" or "GLOBAL SETTINGS SAVED", function()
        if not startupDirty then return end
        local store = commandIdentityStore()
        menu.startupPreference = menu.pendingStartupPreference
        menu.savedStartupPreference = menu.startupPreference
        store.startupSequenceEnabled = menu.startupPreference
        saveCommandIdentityStore(store)
        raise(menu.startupPreference and "startup.sequence.on" or "startup.sequence.off", {})
        menu.settingsStatus = "GLOBAL SETTINGS SAVED. The startup preference will be restored from the save on the next load."
        menu.refresh()
    end, startupDirty, startupDirty and investigationUnknownColor or investigationPassColor)

    actionResult(tableWidget, "minimum.build", "AUTOMATIC MINIMUM BUILD: reports the last bounded one-ship procurement result. It never bypasses player-owned blueprints, shipyard compatibility, normal resources, or the current shortage check.")

    section(tableWidget, "GLOBAL SHIP MINIMUMS")
    local minimumHelp = tableWidget:addRow(false)
    minimumHelp[1]:setColSpan(4):createText("Every value defaults to zero. Zero disables that category. EOC fills at most one verified shortage per scan using compatible idle registered ships; it never creates free ships or queues an empire-wide build order.", { wordwrap = true })
    local function minimumField(label, key, maximum)
        local minimumRow = tableWidget:addRow(true)
        minimumRow[1]:setColSpan(2):createText(label)
        minimumRow[3]:setColSpan(2):createEditBox({ height = Helper.standardButtonHeight }):setText(tostring(menu.minimumDraft[key] or 0))
        minimumRow[3].handlers.onEditBoxDeactivated = function(_, entered)
            local number = math.floor(tonumber(entered) or 0)
            menu.minimumDraft[key] = clamp(number, 0, maximum)
        end
    end
    minimumField("MINERS PER APPLICABLE STATION", "mining", 99)
    minimumField("TRADERS PER APPLICABLE STATION", "trade", 99)
    minimumField("BUILD-STORAGE TRADERS WHILE CONSTRUCTION IS ACTIVE", "buildstorage", 99)
    minimumField("DEFENCE SHIPS PER STATION", "defence", 99)
    minimumField("ESCORTS PER ELIGIBLE CARGO / SUPPLY SHIP (HARD CAP 3)", "escort", 3)
    local minimumSave = tableWidget:addRow(true)
    minimumSave[1]:setColSpan(4)
    addButton(minimumSave, 1, "SAVE GLOBAL SHIP MINIMUMS", function()
        local d = menu.minimumDraft
        d.mining = clamp(math.floor(tonumber(d.mining) or 0), 0, 99)
        d.trade = clamp(math.floor(tonumber(d.trade) or 0), 0, 99)
        d.buildstorage = clamp(math.floor(tonumber(d.buildstorage) or 0), 0, 99)
        d.defence = clamp(math.floor(tonumber(d.defence) or 0), 0, 99)
        d.escort = clamp(math.floor(tonumber(d.escort) or 0), 0, 3)
        raise("minimums.save", { mining=d.mining, trade=d.trade, buildstorage=d.buildstorage, defence=d.defence, escort=d.escort })
        menu.settingsStatus = "GLOBAL SHIP MINIMUMS SAVED. Zero-valued categories are disabled."
        menu.refresh(true)
    end, true, investigationPassColor)
    section(tableWidget, "GLOBAL EOC SETTINGS")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("CHANGE ONLY WHAT YOU INTEND: EOC acts only within the authorities selected below. Construction funding uses the exact X4-reported shortfall; it does not alter the station plan or cancel ordinary player orders.", { wordwrap = true })
    pair(tableWidget, "Trade Order Control", menu.mode, "Ship Assignment Authority", menu.shipmode)
    pair(tableWidget, "Construction Funding Authority", menu.constructionAuthority, "Funding Rule", "EXACT VERIFIED SHORTFALL ONLY")
    if menu.settingsStatus then
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:setColSpan(4):createText(menu.settingsStatus, { wordwrap = true })
    end

    local minimumApprove = tableWidget:addRow(true)
    minimumApprove[1]:setColSpan(4)
    addButton(minimumApprove, 1, "AUTHORIZE PENDING MINIMUM ASSIGNMENT", function()
        raise("minimums.authorize", {})
        menu.settingsStatus = "Pending minimum assignment authorization submitted for verification."
        menu.refresh(true)
    end, menu.shipmode == "APPROVAL REQUIRED", investigationUnknownColor)

    section(tableWidget, "CONSTRUCTION FUNDING AUTHORITY")
    pair(tableWidget, "APPROVAL", "Player confirms each exact station shortfall.", "DO IT ALL", "Funds verified construction and assigns eligible idle builders automatically.")
    local constructionRow = tableWidget:addRow(true)
    constructionRow[1]:setColSpan(2)
    addModeButton(constructionRow, 1, "APPROVAL REQUIRED", menu.constructionAuthority == "APPROVAL REQUIRED", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING CONSTRUCTION APPROVAL MODE..."
        menu.constructionAuthority = "APPROVAL REQUIRED"
        raise("construction.authority.approval", {})
        menu.refresh()
    end)
    constructionRow[3]:setColSpan(2)
    addModeButton(constructionRow, 3, "DO IT ALL", menu.constructionAuthority == "DO IT ALL", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: ENABLING DO IT ALL MODE..."
        menu.constructionAuthority = "DO IT ALL"
        raise("construction.authority.auto", {})
        menu.refresh()
    end)
    section(tableWidget, "TRADE ORDER CONTROL")
    pair(
        tableWidget,
        "INFO",
        "Advisor gives instructions only.",
        "MANAGED",
        "May create evidence-supported EOC trade offers."
    )
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, "ADVISOR MODE", menu.mode == "ADVISOR", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING ADVISOR MODE..."
        raise("trade.advisor", {})
        menu.mode = "ADVISOR"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "MANAGED TRADE", menu.mode == "MANAGED", not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING MANAGED TRADE..."
        raise("trade.managed", {})
        menu.mode = "MANAGED"
        menu.refresh()
    end)

    section(tableWidget, "SHIP-MANAGER MOD COMPATIBILITY")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WARNING: Other automatic trading or ship-management mods may compete with EOC for the same idle ships. If ships are repeatedly reassigned, disable one automation system or use EOC Approval Required mode.", { wordwrap = true, color = resultColor("UNKNOWN") })

    section(tableWidget, "SHIP ASSIGNMENT AUTHORITY")
    pair(
        tableWidget,
        "INFO",
        "Approval Required waits for player confirmation.",
        "AUTO",
        "May assign only eligible registered ships."
    )
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addModeButton(
        row,
        1,
        menu.shipmode == "DISABLED" and "SHIP ASSIGNMENT: DISABLED" or "SHIP ASSIGNMENT: ENABLED",
        menu.shipmode ~= "DISABLED",
        not menu.settingsChangeRunning,
        function()
            menu.settingsChangeRunning = true
            menu.settingsStatus = "STATUS: APPLYING SHIP ASSIGNMENT TOGGLE..."
            if menu.shipmode == "DISABLED" then
                menu.shipmode = menu.previousShipmode or "APPROVAL REQUIRED"
            else
                menu.previousShipmode = menu.shipmode
                menu.shipmode = "DISABLED"
            end
            raise("shipping.toggle", {})
            menu.refresh()
        end
    )

    local assignmentEnabled = menu.shipmode ~= "DISABLED"
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, "APPROVAL REQUIRED", menu.shipmode == "APPROVAL REQUIRED", assignmentEnabled and not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING APPROVAL REQUIRED..."
        raise("shipping.approval", {})
        menu.shipmode = "APPROVAL REQUIRED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "AUTO-ASSIGN REGISTERED", menu.shipmode == "AUTO-ASSIGN REGISTERED", assignmentEnabled and not menu.settingsChangeRunning, function()
        menu.settingsChangeRunning = true
        menu.settingsStatus = "STATUS: APPLYING AUTO-ASSIGN REGISTERED..."
        raise("shipping.auto", {})
        menu.shipmode = "AUTO-ASSIGN REGISTERED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)

    section(tableWidget, "STATION AUTOMATION ACTIONS")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(
        row,
        1,
        actionLabel("station.auto", "ACTION: ASSIGN UNDEFINED STATION ROLES", "ASSIGNING STATION ROLES"),
        function()
            if startAction("station.auto") then
                raise("station.auto", {})
            end
        end,
        not actionState("station.auto").running
    )
    actionResult(
        tableWidget,
        "station.auto",
        "One-time check: assigns roles only to player stations that are currently undefined."
    )
end

function menu.create()
    Helper.clearDataForRefresh(menu, config.layer)
    menu.mainTable = nil
    menu.stationNavigatorTable = nil

    local identityState = commandIdentityStore()
    if identityState.initialized and not menu.sessionBootComplete and startupSequenceEnabled() then
        menu.page = "boot"
        menu.activeTab = "boot"
    elseif identityState.initialized and not menu.sessionBootComplete then
        menu.sessionBootComplete = true
    end

    local maxWidth = math.max(
        600,
        math.min(Helper.scaleX(config.maxWidth), Helper.viewWidth - 2 * Helper.borderSize)
    )
    local maxHeight = math.max(
        420,
        math.min(Helper.scaleY(config.maxHeight), Helper.viewHeight - 2 * Helper.borderSize)
    )
    local minWidth = math.min(Helper.scaleX(config.minWidth), maxWidth)
    local minHeight = math.min(Helper.scaleY(config.minHeight), maxHeight)
    local width = clamp(math.floor(Helper.viewWidth * config.widthRatio), minWidth, maxWidth)
    local height = clamp(math.floor(Helper.viewHeight * config.heightRatio), minHeight, maxHeight)

    menu.frame = Helper.createFrameHandle(menu, {
        layer = config.layer,
        x = (Helper.viewWidth - width) / 2,
        y = (Helper.viewHeight - height) / 2,
        width = width,
        height = height,
    })
    menu.frame:setBackground("solid", { color = frameBackground })

    local headerHeight = createHeader(menu.frame, width)
    local contentY = Helper.borderSize + headerHeight + Helper.borderSize
    local contentHeight = height - contentY - 2 * Helper.borderSize
    menu.coverageContentHeight = contentHeight
    menu.listContentHeight = contentHeight

    if menu.page == "stations" then
        local usableWidth = width - 2 * Helper.borderSize
        local gap = Helper.borderSize
        local leftWidth = math.floor(usableWidth * 0.31)
        local rightWidth = usableWidth - leftWidth - gap

        menu.stationNavigatorTable = createStationNavigator(
            menu.frame,
            Helper.borderSize,
            contentY,
            leftWidth,
            contentHeight
        )

        local tableWidget = menu.frame:addTable(4, {
            tabOrder = 3,
            x = Helper.borderSize + leftWidth + gap,
            y = contentY,
            width = rightWidth,
            reserveScrollBar = true,
            borderEnabled = true,
        })
        configureFourColumns(tableWidget, rightWidth)
        tableWidget.properties.maxVisibleHeight = contentHeight
        menu.mainTable = tableWidget
        if menu.clickStatus and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
            local feedbackRow = tableWidget:addRow(false)
            feedbackRow[1]:setColSpan(4):createText(menu.clickStatus, { wordwrap = true })
        end
        if menu.navigationOrigin and menu.page ~= menu.navigationOrigin.page then
            local returnRow = tableWidget:addRow(true)
            returnRow[1]:setColSpan(4)
            addButton(returnRow, 1, "RETURN TO " .. text(menu.navigationOrigin.label), restoreNavigation, true)
        end
        menu.addPlayerPageGuide(tableWidget, "stations")
        stationWorkspace(tableWidget)
    elseif menu.page == "kpi" then
        local contentWidth = width - 2 * Helper.borderSize
        local gap = Helper.borderSize
        local controlsHeight = math.min(math.floor(contentHeight * 0.48), Helper.scaleY(500))
        local resultsHeight = contentHeight - controlsHeight - gap

        local controlsTable = menu.frame:addTable(4, {
            tabOrder = 2,
            x = Helper.borderSize,
            y = contentY,
            width = contentWidth,
            reserveScrollBar = true,
            borderEnabled = true,
        })
        configureFourColumns(controlsTable, contentWidth)
        controlsTable.properties.maxVisibleHeight = controlsHeight
        addWorkingStationBanner(controlsTable)
        menu.addPlayerPageGuide(controlsTable, "kpi")
        kpiDashboardControls(controlsTable)

        local resultsTable = menu.frame:addTable(4, {
            tabOrder = 3,
            x = Helper.borderSize,
            y = contentY + controlsHeight + gap,
            width = contentWidth,
            reserveScrollBar = true,
            borderEnabled = true,
        })
        configureFourColumns(resultsTable, contentWidth)
        resultsTable.properties.maxVisibleHeight = resultsHeight
        menu.mainTable = resultsTable
        kpiCenterResults(resultsTable)
    else
        local contentWidth = width - 2 * Helper.borderSize
        local tableWidget = menu.frame:addTable(4, {
            tabOrder = 2,
            x = Helper.borderSize,
            y = contentY,
            width = contentWidth,
            reserveScrollBar = true,
            borderEnabled = true,
        })
        configureFourColumns(tableWidget, contentWidth)
        tableWidget.properties.maxVisibleHeight = contentHeight
        menu.mainTable = tableWidget
        if menu.clickStatus and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
            local feedbackRow = tableWidget:addRow(false)
            feedbackRow[1]:setColSpan(4):createText(menu.clickStatus, { wordwrap = true })
        end
        if menu.navigationOrigin and menu.page ~= menu.navigationOrigin.page then
            local returnRow = tableWidget:addRow(true)
            returnRow[1]:setColSpan(4)
            addButton(returnRow, 1, "RETURN TO " .. text(menu.navigationOrigin.label), restoreNavigation, true)
        end
        addWorkingStationBanner(tableWidget)
        if menu.page ~= "identity" and menu.page ~= "boot" then
            menu.addPlayerPageGuide(tableWidget, menu.page)
        end

        if menu.page == "identity" then
            commandIdentitySetup(tableWidget, true)
        elseif menu.page == "boot" then
            commandOSBoot(tableWidget)
        elseif menu.page == "dashboard" then
            dashboard(tableWidget)
        elseif menu.page == "supply" then
            menu.supplyModelCenter(tableWidget)
        elseif menu.page == "solution" then
            solutionPlannerCenter(tableWidget)
        elseif menu.page == "construction" then
            constructionCenter(tableWidget)
        elseif menu.page == "cases" then
            casesCenter(tableWidget)
        elseif menu.page == "reports" then
            reportsCenter(tableWidget)
        elseif menu.page == "fleet" then
            fleetCenter(tableWidget)
        elseif menu.page == "diagnostics" then
            diagnosticsCenter(tableWidget)
        else
            globalSettings(tableWidget)
        end
    end

    if menu.mainTable and menu.restoreTablePage == menu.page then
        if menu.restoreTableTopRow then pcall(menu.mainTable.setTopRow, menu.mainTable, menu.restoreTableTopRow) end
        if menu.restoreTableSelectedRow then pcall(menu.mainTable.setSelectedRow, menu.mainTable, menu.restoreTableSelectedRow) end
    end
    if menu.stationNavigatorTable and menu.restoreNavigatorPage == menu.page then
        if menu.restoreNavigatorTopRow then pcall(menu.stationNavigatorTable.setTopRow, menu.stationNavigatorTable, menu.restoreNavigatorTopRow) end
        if menu.restoreNavigatorSelectedRow then pcall(menu.stationNavigatorTable.setSelectedRow, menu.stationNavigatorTable, menu.restoreNavigatorSelectedRow) end
    end
    menu.restoreTablePage = nil
    menu.restoreTableTopRow = nil
    menu.restoreTableSelectedRow = nil
    menu.restoreNavigatorPage = nil
    menu.restoreNavigatorTopRow = nil
    menu.restoreNavigatorSelectedRow = nil

    menu.frame:display()
    menu.renderedPage = menu.page
    if menu.forcedVerificationRestoreReady then
        menu.forcedVerificationTopRow = nil
        menu.forcedVerificationPage = nil
        menu.forcedVerificationScrollLocked = nil
        menu.forcedVerificationRestoreReady = nil
    end
end

function menu.refresh(preserveScroll)
    local samePage = menu.renderedPage == nil or menu.renderedPage == menu.page
    local shouldPreserve = preserveScroll ~= false and samePage
    if shouldPreserve and menu.mainTable then
        local tableId = menu.mainTable.id
        local ok, topRow = false, nil
        if tableId ~= nil then ok, topRow = pcall(GetTopRow, tableId) end
        if menu.forcedVerificationScrollLocked and menu.forcedVerificationPage == menu.page and menu.forcedVerificationTopRow ~= nil then
            ok = true
            topRow = menu.forcedVerificationTopRow
        end
        if ok then
            menu.restoreTableTopRow = topRow
            if not menu.scrollCaptureConfirmed then
                DebugError("[JKEOC][B277][SCROLL_CAPTURE_CONFIRMED] page=" .. tostring(menu.page) .. " top=" .. tostring(topRow))
                menu.scrollCaptureConfirmed = true
            end
        elseif not menu.scrollCaptureFailureLogged then
            DebugError("[JKEOC][B277][SCROLL_CAPTURE_FAILED] page=" .. tostring(menu.page) .. " tableid=" .. tostring(tableId))
            menu.scrollCaptureFailureLogged = true
        end
        if Helper.currentTableRow and tableId then menu.restoreTableSelectedRow = Helper.currentTableRow[tableId] end
        menu.restoreTablePage = menu.page
    else
        menu.restoreTablePage = nil
        menu.restoreTableTopRow = nil
        menu.restoreTableSelectedRow = nil
    end
    if shouldPreserve and menu.stationNavigatorTable then
        local tableId = menu.stationNavigatorTable.id
        local ok, topRow = false, nil
        if tableId ~= nil then ok, topRow = pcall(GetTopRow, tableId) end
        if ok then menu.restoreNavigatorTopRow = topRow end
        if Helper.currentTableRow and tableId then menu.restoreNavigatorSelectedRow = Helper.currentTableRow[tableId] end
        menu.restoreNavigatorPage = menu.page
    else
        menu.restoreNavigatorPage = nil
        menu.restoreNavigatorTopRow = nil
        menu.restoreNavigatorSelectedRow = nil
    end
    menu.create()
end

function menu.onCloseElement(reason, layer)
    -- X4 can deliver a stale close callback after another full-screen menu has
    -- already removed EOC from the tracked menu stack. Calling closeMenu again
    -- in that state closes/exposes the menu now owned by X4 (including the
    -- Station Build Plan). A missing frame or an in-flight close is therefore
    -- a no-op; only the live EOC frame may alter the menu stack.
    if menu.frame == nil or menu.closeInProgress then
        DebugError("[JKEOC][B312][MENU_CLOSE_SUPPRESSED] reason=" .. tostring(reason or "close") .. " frame_present=" .. tostring(menu.frame ~= nil) .. " close_in_progress=" .. tostring(menu.closeInProgress == true))
        return
    end
    menu.closeInProgress = true
    raise("closed", { reason = reason or "close" })
    Helper.closeMenu(menu, reason or "close", layer)
    menu.frame = nil
    menu.closeInProgress = false
end

function menu.solutionRefreshSelection()
    local caseData = menu.solutionCase or menu.diagnosticCase
    local standalone = menu.solutionAgreedStandaloneKey and menu.agreedBuildPlans and menu.agreedBuildPlans[menu.solutionAgreedStandaloneKey] or nil
    local monitoredPlan = standalone
    if not monitoredPlan and caseData then
        local commandKey = checklistCaseKey(caseData)
        if menu.solutionAgreedKey ~= commandKey then return nil end
        local readiness = menu.expansionReadiness
        local nativePlan = readiness and readiness.key == commandKey and readiness.nativePlan or nil
        local wareId = nativePlan and nativePlan.ware or v(caseData, 40, "")
        local agreedKey = wareId ~= "" and menu.agreedPlanKey(text(v(caseData, 1, "")), wareId) or ""
        monitoredPlan = agreedKey ~= "" and menu.agreedBuildPlans and menu.agreedBuildPlans[agreedKey] or nil
    end
    return menu.savedPlanRefreshTarget(monitoredPlan)
end

function menu.onUpdate()
    local now = getElapsedTime()

    if menu.kpiView == "shortages" then menu.kpiView = "cash" end
    if menu.page == "kpi" and not menu.kpiPaused and not menu.kpiRefreshing and not menu.kpiControlDropdownActive and now >= (tonumber(menu.kpiNextRefreshAt) or 0) then
        menu.kpiRefreshing = true
        menu.kpiNextRefreshAt = now + menu.kpiRefreshInterval(menu.kpiView)
        raise("kpi.refresh", { view = menu.kpiView })
    elseif menu.page == "construction" and not menu.constructionRefreshing and now >= (tonumber(menu.constructionNextRefreshAt) or 0) then
        local record = constructionRecordForSelected()
        local stationName = text(v(record, 1, "SELECTED STATION"))
        local index = tonumber(v(record, 2, menu.selected)) or menu.selected
        menu.constructionRefreshing = true
        menu.constructionNextRefreshAt = now + KPI_REFRESH_SECONDS
        raise("construction.refresh", { index = index, station = stationName })
    elseif menu.page == "solution" and not menu.constructionRefreshing and now >= (tonumber(menu.plannerNextRefreshAt) or 0) then
        local target = menu.solutionRefreshSelection()
        if target and target.index > 0 then
            menu.constructionRefreshing = true
            menu.plannerNextRefreshAt = now + 60
            menu.plannerRefreshStatus = "WATCHING SAVED PLAN: EOC refreshes this visible saved build list about once per minute."
            raise("construction.refresh", { index = target.index, station = target.station })
        else
            menu.plannerNextRefreshAt = now + 60
        end
    end

    if menu.page == "boot" and (tonumber(menu.osBootStage) or 1) < #(menu.osBootStages or {}) and menu.osBootNextAt and now >= menu.osBootNextAt then
        menu.osBootStage = (tonumber(menu.osBootStage) or 1) + 1
        menu.osBootNextAt = now + EOC_OS_BOOT_DELAY
        menu.refresh()
        return
    end

    if menu.analysisStatusUntil and now >= menu.analysisStatusUntil then
        menu.analysisStatusUntil = nil
        menu.analysisStatus = nil
        menu.refresh()
        return
    end

    if menu.clickStatusUntil and now >= menu.clickStatusUntil then
        menu.clickStatusUntil = nil
        menu.clickStatus = nil
        menu.lastClickedLabel = nil
        menu.refresh()
        return
    end


    if menu.reportStatusUntil and now >= menu.reportStatusUntil then
        menu.reportStatusUntil = nil
        menu.reportStatus = nil
        menu.lastReport = nil
        menu.refresh()
    end
end

function menu.onRowChanged()
end

function menu.onSelectElement()
end

function menu.viewCreated()
end

init()
