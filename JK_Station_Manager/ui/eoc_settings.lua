---@diagnostic disable: undefined-global, undefined-field

local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
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
    heightRatio = 0.78,
    minWidth = 1060,
    minHeight = 650,
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
local EOC_OS_BUILD = 202
local KPI_REFRESH_SECONDS = 10
local KPI_MAX_SAMPLES = 36
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

local formatGameTime
local pair
local captureNavigation

local function formatNumber(value)
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
    ["shipping.register"] = "Review Registered Ships, then run Scan Shipping Needs.",
    ["shipping.scan"] = "Review Pending in Approval Required mode, or Registered Ships in Auto-Assign mode.",
    ["shipping.approve"] = "Review Pending to confirm the completed row was removed.",
    ["trade.review"] = "Review Fleet & Logistics > Trade Offers.",
    ["station.auto"] = "Review Stations for any role that remains UNDEFINED.",
    ["station.role"] = "Review the selected station, then open Diagnostics or Cases if attention is still required.",
    ["diagnostics.goal"] = "Run Refresh Bounded Analysis to update recommendations.",
    ["analysis.run"] = "Open Cases or View Stations Requiring Action.",
    ["diagnostics.status"] = "Open the player Logbook > Tips to read the saved status.",
    ["diagnostics.probe"] = "Read the mailbox result below; no additional authority was granted.",
    ["diagnostics.proof"] = "Review the result and debug log for verification and automatic rollback.",
    ["case.create"] = "Review the new player-requested case, then choose Diagnostics or the station workspace for the recommended test.",
    ["case.close"] = "The player-requested case was closed. EOC-confirmed evidence remains separate and is not deleted.",
    ["case.monitor"] = "Continue playing normally. Return to this case after a later EOC analysis or when EOC reports a meaningful change.",
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

local function actionResult(tableWidget, action, purpose)
    local state = actionState(action)
    local row = tableWidget:addRow(false)
    local message = state.result and ("RESULT: " .. state.result) or ("WHAT THIS DOES: " .. purpose)
    row[1]:setColSpan(4):createText(message, { wordwrap = true })
    if state.result and actionNextSteps[action] then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("DO THIS NEXT: " .. actionNextSteps[action], { wordwrap = true })
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

formatGameTime = function(value)
    local seconds = math.max(0, math.floor(tonumber(value) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
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
        add("STORAGE INSTALLED", capacity > 0 and "PASS" or "FAIL", text(v(caseData, 12, "UNKNOWN")) .. " capacity " .. formatNumber(capacity))
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
            if check.label == "INCIDENT EVIDENCE" then return text(v(caseData, 7, "Review the grouped retained evidence, then run a focused diagnostic before changing the station."))
            elseif check.label == "DELIVERY PATH" then return "Open the " .. text(v(caseData, 17, v(caseData, 4, "required ware"))) .. " buy offer first. Confirm its ware-specific trade rule permits the intended NPC supplier; then verify at least one assigned station trader can carry " .. text(v(caseData, 12, "the required cargo")) .. ". Change no station-wide rule unless you intend the wider effect."
            elseif check.label == "STORAGE INSTALLED" then return "Open the Station Build Plan and add compatible " .. text(v(caseData, 12, "cargo")) .. " storage; wait until it is operational."
            elseif check.label == "STORAGE FREE SPACE" then return "Open Logical Station Overview and move, sell, or reallocate stock until the required " .. text(v(caseData, 12, "cargo")) .. " storage space is free."
            elseif check.label == "STATION OPERATING FUNDS" then local required = math.max(0, ((tonumber(v(caseData, 30, 0)) or 0) * (tonumber(v(caseData, 21, 0)) or 0)) - (tonumber(v(caseData, 32, 0)) or 0)); return "Open the station Information account and transfer at least " .. formatNumber(required) .. " Cr for the immediate purchase. EOC will not move player credits."
            elseif check.label == "REACHABLE SUPPLY" then return "Open the station buy offer for " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " and verify trade rule, price, and manager range permit a supplier."
            elseif check.label == "STATION TRADER" then return "Assign one operational trader compatible with " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " to " .. text(v(caseData, 1, "the station")) .. "."
            elseif check.label == "LOCAL PRODUCTION" and v(caseData, 29, false) then return "Local production is inactive, but a manual pause is not confirmed. Investigate root cause before changing the module."
            elseif check.label == "PRODUCTION INPUTS" then return "Restore the confirmed missing production input: " .. text(v(caseData, 28, "review station inputs")) .. "." end
        end
    end
    return "No reported prerequisite requires a change. Observe one operating or delivery cycle, then run Verify Result. Do not add ships, storage, or production unless verification still shows a blocker."
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
    if missing > 0 then return "CONFIRMED", "Production is blocked by missing input: " .. text(v(caseData, 28, "unnamed input")) .. ".", "Restore the confirmed missing input, then run Verify Result.", facts, unknowns end
    for _, check in ipairs(rows) do
        if check.state == "FAIL" and check.label ~= "LOCAL PRODUCTION" then return "CONFIRMED", check.label .. " failed: " .. check.evidence .. ".", manualNextAction(caseData, rows), facts, unknowns end
    end
    if produces > 0 and inactive then
        unknowns[#unknowns + 1] = "X4 reports inactive local production, but the current evidence does not prove the player manually paused it."
        return "MORE OBSERVATION REQUIRED", "Local production is inactive; manual pause is not confirmed. Inputs currently show no empty production input.", "Save this as a monitored case. EOC will compare later observations before recommending a change.", facts, unknowns
    end
    if #unknowns > 0 then return "MORE OBSERVATION REQUIRED", "The snapshot contains unresolved evidence and does not support a single root cause yet.", "Save this as a monitored case and continue normal play while EOC gathers later observations.", facts, unknowns end
    return "PROBABLE", text(v(caseData, 6, "No single blocker is confirmed.")), "Observe one operating cycle, then run Verify Result before changing station configuration.", facts, unknowns
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

    if menu.pendingVerificationKey then
        menu.verificationKey = menu.pendingVerificationKey
        menu.verificationClass = menu.pendingVerificationClass or "UNKNOWN"
        menu.verificationResult = menu.pendingVerificationResult or "UNKNOWN - the rescan completed without a comparison result."
        menu.pendingVerificationClass = nil
        menu.pendingVerificationResult = nil
        menu.pendingVerificationKey = nil
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
    menu.reportStatus = "REPORT SAVED TO TIPS"
    menu.reportStatusUntil = getElapsedTime() + 4

    menu.lastReport = text(menu.pendingReportTitle or menu.pendingReport or "EOC REPORT")
    menu.reportOutput = text(menu.pendingReportText or "Report saved to Tips.")

    table.insert(menu.reports, 1, {
        menu.lastReport,
        menu.reportOutput,
        formatGameTime(menu.pendingReportTime),
        tonumber(menu.pendingReportTime) or 0,
    })
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
    menu.constructionRefresh = { record = {}, queue = {}, queueRow = {}, wares = {}, wareRow = {} }
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
local function constructionQueueIndex(_, value) constructionRefreshState().queueRow[8] = tonumber(value) or 0 end
local function constructionQueueCommit()
    local refresh = constructionRefreshState(); table.insert(refresh.queue, refresh.queueRow); refresh.queueRow = {}
end
local function constructionWareName(_, value) constructionRefreshState().wareRow[1] = tostring(value or "Unknown ware") end
local function constructionWareCount(_, value) constructionRefreshState().wareRow[2] = tonumber(value) or 0 end
local function constructionWareCommit()
    local refresh = constructionRefreshState(); table.insert(refresh.wares, refresh.wareRow); refresh.wareRow = {}
end
local function constructionRefreshComplete()
    local refresh = constructionRefreshState()
    local snapshot = refresh.record
    snapshot[8] = refresh.queue
    snapshot[11] = refresh.wares
    local target = tonumber(v(snapshot, 2, 0)) or 0
    local targetName = text(v(snapshot, 1, ""))
    local retained = {}
    for _, record in ipairs(menu.constructionRecords or {}) do
        local sameIndex = target > 0 and (tonumber(v(record, 2, 0)) or 0) == target
        local sameName = targetName ~= "" and text(v(record, 1, "")) == targetName
        if not sameIndex and not sameName then table.insert(retained, record) end
    end
    table.insert(retained, 1, snapshot)
    menu.constructionRecords = retained
    menu.activeConstructionSnapshot = snapshot
    menu.constructionRefresh = nil
    menu.constructionRefreshing = false
    menu.constructionStatus = "REFRESH COMPLETE: Latest station construction facts loaded."
    if menu.frame then menu.refresh() end
end
local function constructionFundingResult(_, value)
    local result = text(value or "Construction action completed.")
    menu.constructionFundingPending = nil
    if string.sub(result, 1, 29) == "CONFIRM BUILDER REASSIGNMENT:" then menu.constructionBuilderPending = true else menu.constructionBuilderPending = nil end
    menu.constructionStatus = result
    if menu.frame then menu.refresh() end
end
function menu.kpiRefreshBegin()
    menu.kpiRefreshIncoming = { stations = {}, station = {} }
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
function menu.kpiRefreshComplete()
    local state = menu.kpiRefreshState()
    menu.kpiHistory = menu.kpiHistory or {}
    local previous = menu.kpiHistory[#menu.kpiHistory]
    local sample = { time = tonumber(state.time) or 0, credits = tonumber(state.credits) or 0, stations = state.stations or {}, shortageCritical = 0, shortageWarning = 0, caseCritical = 0, caseWarning = 0, caseOther = 0, constructionActive = 0, constructionProgress = 0, stationCount = #(menu.stations or {}), registeredShipCount = #(menu.registeredShips or {}), constructionRecordCount = #(menu.constructionRecords or {}), shipOrderCount = #(menu.shipOrderRecords or {}) }
    for _, case in ipairs(menu.cases or {}) do
        local severity = string.upper(text(v(case, 2, "")))
        local caseType = string.upper(text(v(case, 3, "")))
        if string.find(caseType, "WARE", 1, true) or string.find(caseType, "SHORT", 1, true) or (tonumber(v(case, 30, 0)) or 0) > 0 then
            if severity == "CRITICAL" then sample.shortageCritical = sample.shortageCritical + 1 elseif severity == "WARNING" then sample.shortageWarning = sample.shortageWarning + 1 end
        end
    end
    local progressTotal, progressCount = 0, 0
    for _, record in ipairs(menu.constructionRecords or {}) do
        if (tonumber(v(record, 3, 0)) or 0) > 0 then sample.constructionActive = sample.constructionActive + 1 end
        for _, item in ipairs(v(record, 8, {})) do
            if string.upper(text(v(item, 3, ""))) == "UNDER CONSTRUCTION" then progressTotal = progressTotal + (tonumber(v(item, 4, 0)) or 0); progressCount = progressCount + 1 end
        end
    end
    sample.constructionProgress = progressCount > 0 and (progressTotal / progressCount) or 0
    sample.creditChange = previous and (sample.credits - (tonumber(previous.credits) or sample.credits)) or 0
    table.insert(menu.kpiHistory, sample)
    while #menu.kpiHistory > KPI_MAX_SAMPLES do table.remove(menu.kpiHistory, 1) end
    menu.kpiRefreshIncoming = nil
    menu.kpiRefreshing = false
    menu.kpiLastRefreshAt = getElapsedTime()
    menu.kpiNextRefreshAt = menu.kpiLastRefreshAt + KPI_REFRESH_SECONDS
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
    DebugError("[JKEOC][B216][LUA_ERROR] Helper.registerMenu unavailable")
    end

    AddUITriggeredEvent(menu.name, "INIT", nil)
    RegisterEvent(menu.name .. ".INIT", menu.PrepareMenuData)
    RegisterEvent(menu.name .. ".analysis.complete", analysisComplete)
    RegisterEvent(menu.name .. ".verification.class", verificationClassReceived)
    RegisterEvent(menu.name .. ".verification.result", verificationResultReceived)
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
    RegisterEvent(menu.name .. ".construction.queue.index", constructionQueueIndex)
    RegisterEvent(menu.name .. ".construction.queue.commit", constructionQueueCommit)
    RegisterEvent(menu.name .. ".construction.ware.name", constructionWareName)
    RegisterEvent(menu.name .. ".construction.ware.count", constructionWareCount)
    RegisterEvent(menu.name .. ".construction.ware.commit", constructionWareCommit)
    RegisterEvent(menu.name .. ".construction.refresh.complete", constructionRefreshComplete)
    RegisterEvent(menu.name .. ".construction.funding.result", constructionFundingResult)
    RegisterEvent(menu.name .. ".kpi.refresh.begin", menu.kpiRefreshBegin)
    RegisterEvent(menu.name .. ".kpi.time", menu.kpiGameTime)
    RegisterEvent(menu.name .. ".kpi.playercredits", menu.kpiPlayerCredits)
    RegisterEvent(menu.name .. ".kpi.station.name", menu.kpiStationName)
    RegisterEvent(menu.name .. ".kpi.station.money", menu.kpiStationMoney)
    RegisterEvent(menu.name .. ".kpi.station.commit", menu.kpiStationCommit)
    RegisterEvent(menu.name .. ".kpi.refresh.complete", menu.kpiRefreshComplete)
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
    local rawStartupPreference = v(menu.param, 26, 1)
    local restoredStartupPreference = tonumber(rawStartupPreference) ~= 0
    DebugError("[JKEOC][B216][STARTUP_PREFERENCE_LUA] raw=" .. tostring(rawStartupPreference) .. " decoded=" .. (restoredStartupPreference and "ON" or "OFF"))
    if type(menu.savedStartupPreference) ~= "boolean" then
        menu.savedStartupPreference = restoredStartupPreference
        menu.pendingStartupPreference = restoredStartupPreference
    end
    menu.startupPreference = menu.savedStartupPreference
    menu.kpiView = menu.kpiView or "cash"
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
    menu.fleetView = menu.fleetView or "stations"
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

local function addButton(row, column, label, handler, active, background)
    local properties = { active = active ~= false, bgColor = background }
    if menu.reportRunning and (string.find(label, "GENERATE REPORT", 1, true) == 1 or string.find(label, "REPORT RUNNING", 1, true) == 1) then
        properties.active = false
    end
    if menu.lastClickedLabel == label and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
        properties.bgColor = selectedModeBackground
    end
    row[column]:createButton(properties):setText(label)
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
        if string.find(label, "GENERATE REPORT", 1, true) == 1 then
            if menu.reportRunning then return end
            menu.reportRunning = true
            menu.reportStatus = "REPORT RUNNING - waiting for EOC result"
        end
        menu.refresh()
        handler()
    end
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
    }):setText(label)
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
        menu.refresh()
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
    row[column]:createButton({ active = true, bgColor = background }):setText(label)
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
        menu.refresh()
        handler()
    end
end

local function addTabButton(row, column, label, page)
    local properties = { active = true }

    if menu.page == page then
        properties.bgColor = activeTabBackground
    end

    row[column]:createButton(properties):setText(label)
    row[column].handlers.onClick = function()
        menu.navigationOrigin = nil
        menu.navigationStack = {}
        menu.reportOrigin = nil
        if page == "cases" then
            menu.caseScope = (menu.stations and menu.stations[menu.selected]) and "station" or "global"
            menu.caseSeverity = "all"
            menu.selectedCase = 1
            menu.casePage = 1
            menu.diagnosticCase = nil
        end
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
    row[1]:setColSpan(4):createText(label, {
        font = Helper.headerFont,
        fontsize = Helper.standardFontSize + 2,
    })
end

pair = function(tableWidget, leftLabel, leftValue, rightLabel, rightValue)
    local row = tableWidget:addRow(false)
    row[1]:createText(leftLabel)
    row[2]:createText(text(leftValue), { halign = "right" })
    row[3]:createText(rightLabel)
    row[4]:createText(text(rightValue), { halign = "right" })
end

local function selectedStation()
    return menu.stations[menu.selected]
end

local function addWorkingStationBanner(tableWidget)
    local station = selectedStation()
    if not station then return end
    local stationName = text(v(station, 1, "SELECTED STATION"))
    local caseSubject = menu.diagnosticCase and text(v(menu.diagnosticCase, 1, "")) == stationName and text(v(menu.diagnosticCase, 4, "")) or nil
    local label = "WORKING STATION - " .. stationName
    if caseSubject and caseSubject ~= "-" then label = label .. "  |  CASE - " .. caseSubject end
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    row[1]:createButton({ active = true, bgColor = inactiveModeBackground }):setText(label)
    row[1].handlers.onClick = function()
        menu.navigationOrigin = nil
        menu.navigationStack = {}
        menu.page = "stations"
        menu.activeTab = "stations"
        menu.refresh()
    end
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
        verify = "Run Empire Analysis after the change. Confirm the evidence improves before closing or ignoring the case.",
    }

    local function has(word) return string.find(searchable, word, 1, true) ~= nil end
    local function rootHas(word) return string.find(rootCause, word, 1, true) ~= nil end
    if rootHas("import remediation") or rootHas("known sell offer") or ((has("ware") or has("shortage") or has("supply") or has("import") or has("allographyne")) and not (has("workforce") or has("food") or has("habitat") or has("storage") or has("capacity") or has("fund") or has("credit") or has("budget") or has("money") or has("production") or has("paused") or has("miner") or has("mining") or has("resource") or has("ore") or has("silicon") or has("hydrogen") or has("methane") or has("helium") or has("ice") or has("construction") or has("build") or has("builder") or has("defen") or has("attack") or has("threat"))) then
        playbook.family = "WARE SUPPLY AND DELIVERY"
        playbook.impact = "Required stock is below its operational target and may stop production, workforce support, construction, or terraforming delivery."
        playbook.investigate = "Check, in order: buy offer and requested amount; correct free storage; trade rule; manager range; compatible available trader; reachable supplier stock and price."
        playbook.player = "Correct the first failed check in Logical Station Overview or ship orders. If all checks pass, observe one delivery cycle before adding production."
        playbook.verify = "Run Empire Analysis after a delivery attempt. Confirm stock rises, an incoming order exists, or the shortage trend improves."
    elseif rootHas("local production exists") or rootHas("empty production input") or rootHas("production module") or rootHas("paused") then
        playbook.family = "PRODUCTION CHAIN"
        playbook.impact = "A paused module or missing upstream input is reducing or stopping station output."
        playbook.investigate = "Check module status, the first empty required input, storage allocation, production method, and whether planned construction already addresses the gap."
        playbook.player = "Restore the deepest missing input first or resume the affected module. Add production only after imports and existing capacity are proven insufficient."
        playbook.verify = "Run Empire Analysis after at least one production cycle and confirm output resumes and the input shortage trend improves."
    elseif has("workforce") or has("food") or has("habitat") then
        playbook.family = "WORKFORCE SUPPORT"
        playbook.impact = "Workforce supply or habitat support is limiting the station's sustainable production bonus."
        playbook.investigate = "Check habitat demand, Food Rations and Medical Supplies targets, current stock, compatible storage, reachable supply, and assigned container traders."
        playbook.player = "Restore the missing workforce ware through imports or local production. Do not add habitat capacity until current demand is supplied."
        playbook.verify = "Run Empire Analysis after supply arrives and confirm workforce stock and workforce trend improve."
    elseif has("storage") or has("capacity") or has("full") then
        playbook.family = "STORAGE CAPACITY OR ALLOCATION"
        playbook.impact = "Missing, full, or incorrectly allocated storage can block buying, mining deliveries, production, and sales."
        playbook.investigate = "Confirm the ware's cargo type, allocated amount, free capacity, automatic storage target, and whether another ware is consuming the same storage pool."
        playbook.player = "Adjust ware allocation in Logical Station Overview. Add the correct storage module only when the existing storage pool is genuinely insufficient."
        playbook.verify = "Run Empire Analysis after the allocation change or first successful transfer and confirm usable capacity and flow recover."
    elseif has("fund") or has("credit") or has("budget") or has("money") then
        playbook.family = "STATION FUNDING"
        playbook.impact = "The station may be unable to place required purchases even when offers, ships, and suppliers exist."
        playbook.investigate = "Compare station account balance with the manager's operating-budget estimate and the cost of the immediate shortage."
        playbook.player = "Transfer an appropriate operating reserve through the station Information account. EOC does not transfer player funds."
        playbook.verify = "Run Empire Analysis after funding and confirm buy orders appear or required stock begins increasing."
    elseif has("production") or has("input") or has("module") or has("paused") then
        playbook.family = "PRODUCTION CHAIN"
        playbook.impact = "A paused module or missing upstream input is reducing or stopping station output."
        playbook.investigate = "Check module status, the first empty required input, storage allocation, production method, and whether planned construction already addresses the gap."
        playbook.player = "Restore the deepest missing input first or resume the affected module. Add production only after imports and existing capacity are proven insufficient."
        playbook.verify = "Run Empire Analysis after at least one production cycle and confirm output resumes and the input shortage trend improves."
    elseif has("miner") or has("mining") or has("resource") or has("ore") or has("silicon") or has("hydrogen") or has("methane") or has("helium") or has("ice") then
        playbook.family = "MINING AND RAW RESOURCES"
        playbook.impact = "The station is not receiving enough raw resource throughput for its demand."
        playbook.investigate = "Check resource demand, correct miner cargo type, subordinate assignment, resource probes, sector reach, blacklists, and whether miners are operational or stalled."
        playbook.player = "Reassign or add a suitable mineral or gas miner only after confirming demand and access. EOC can use only eligible registered ships within granted assignment authority."
        playbook.verify = "Run Empire Analysis after a mining delivery and confirm raw stock and production throughput rise."
    elseif has("construction") or has("build") or has("builder") then
        playbook.family = "CONSTRUCTION"
        playbook.impact = "An incomplete build plan or missing construction supply is delaying new station capability."
        playbook.investigate = "Check builder assignment, build storage funds, missing build wares, reachable sell offers, docking access, and whether the planned module is still required."
        playbook.player = "Fund build storage, supply the missing build ware, assign a builder, or revise the plan through the vanilla Build Plan interface. EOC does not alter construction plans."
        playbook.verify = "Run Empire Analysis after construction progresses and confirm the missing-ware or builder condition clears."
    elseif has("defen") or has("attack") or has("threat") or has("shield") or has("turret") then
        playbook.family = "DEFENSE READINESS"
        playbook.impact = "The station's assigned defense or fitted capability may not match its operational risk."
        playbook.investigate = "Review local threats, defense subordinates, operational state, station module loadout, ammunition supply, and replacement readiness."
        playbook.player = "Assign or repair defensive assets and correct station loadout through normal X4 controls. EOC will not purchase ships or redesign the station."
        playbook.verify = "Run Empire Analysis after assets are operational and confirm defense readiness or case severity improves."
    elseif has("ship") or has("trader") or has("logistic") or has("assignment") then
        playbook.family = "SHIP ASSIGNMENT AND LOGISTICS"
        playbook.impact = "A needed logistics role lacks a suitable, available, correctly assigned ship."
        playbook.investigate = "Check ship purpose, cargo class, commander, current orders, operational state, station assignment, range, and EOC registration or pending approval."
        playbook.player = "Use Fleet and Logistics to inspect registered and pending ships. Build, free, or manually assign a suitable ship if no eligible ship exists."
        playbook.verify = "Run the shipping scan and Empire Analysis after assignment; confirm the ship is working and the station need begins improving."
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
        diagnosticView = menu.diagnosticView,
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
    menu.diagnosticView = origin.diagnosticView or menu.diagnosticView
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

local function createHeader(frame, parentWidth)
    local titleHeight = Helper.scaleY(42)
    local tabHeight = Helper.scaleY(38)
    local headerHeight = titleHeight + tabHeight
    local usableWidth = parentWidth - 2 * Helper.borderSize
    local tableWidget = frame:addTable(9, {
        tabOrder = 1,
        x = Helper.borderSize,
        y = Helper.borderSize,
        width = usableWidth,
        borderEnabled = true,
    })
    local columnWidth = math.floor(usableWidth / 9)

    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setColWidth(4, columnWidth, false)
    tableWidget:setColWidth(5, columnWidth, false)
    tableWidget:setColWidth(6, columnWidth, false)
    tableWidget:setColWidth(7, columnWidth, false)
    tableWidget:setColWidth(8, columnWidth, false)

    local row = tableWidget:addRow(false, { fixed = true })
    row[1]:setColSpan(9):createText(menu.title, {
        halign = "center",
        font = Helper.titleFont,
        fontsize = Helper.standardFontSize + 4,
    })

    row = tableWidget:addRow(true, { fixed = true })
    addTabButton(row, 1, "STATIONS", "stations")
    addTabButton(row, 2, "OVERVIEW", "dashboard")
    addTabButton(row, 3, "KPI CENTER", "kpi")
    addTabButton(row, 4, "FLEET & LOGISTICS", "fleet")
    addTabButton(row, 5, "DIAGNOSTICS", "diagnostics")
    addTabButton(row, 6, "CONSTRUCTION", "construction")
    addTabButton(row, 7, "CASES", "cases")
    addTabButton(row, 8, "REPORTS", "reports")
    addTabButton(row, 9, "GLOBAL SETTINGS", "settings")

    local activeColumns = {
        stations = 1,
        dashboard = 2,
        kpi = 3,
        fleet = 4,
        diagnostics = 5,
        construction = 6,
        cases = 7,
        reports = 8,
        settings = 9,
    }
    tableWidget:setSelectedRow(2)
    tableWidget:setSelectedCol(activeColumns[menu.activeTab or menu.page] or 2)

    tableWidget.properties.maxVisibleHeight = headerHeight
    return headerHeight
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
    row[1]:setColSpan(4):createText(total > 0 and "ONGOING CONSTRUCTION DETECTED" or "NO ONGOING CONSTRUCTION DETECTED", { color = total > 0 and Helper.color.green or Helper.color.white })
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
    check("BUILD PLAN / QUEUE", total > 0 and "MET" or "NOT MET", total > 0 and (tostring(total) .. " planned or active module(s) detected.") or "No planned or active modules were found.", total > 0 and Helper.color.green or resultColor("UNKNOWN"))
    check("BUILDER ASSIGNED", builders > 0 and "MET" or (total > 0 and "STALLED - CHECK BUILDER" or "NOT REQUIRED"), builders > 0 and "X4 reports a construction vessel assigned to this station build." or (total > 0 and "No construction vessel is currently assigned. Assign a builder, then refresh Construction Status." or "No construction plan requires a builder."), builders > 0 and Helper.color.green or (total > 0 and resultColor("FAILED") or resultColor("UNKNOWN")))
    check("BUILD-STORAGE SHIP", buildStorage > 0 and "MET" or "OPTIONAL", buildStorage > 0 and (tostring(buildStorage) .. " assigned build-storage trader(s) detected.") or "No player build-storage trader is assigned. NPC deliveries may still satisfy construction, so this is not treated as a failure.", buildStorage > 0 and Helper.color.green or resultColor("UNKNOWN"))
    check("CONSTRUCTION PROGRESS", building > 0 and "MET" or "WAITING", building > 0 and (tostring(building) .. " module(s) currently under construction.") or (planned > 0 and "Modules are queued but none is currently building." or "No construction progress to measure."), building > 0 and Helper.color.green or resultColor("UNKNOWN"))
    local budgetMet = wantedBudget <= 0 or budget >= wantedBudget
    local shortfall = math.max(0, wantedBudget - budget)
    row = tableWidget:addRow(shortfall > 0)
    row[1]:createText(budgetMet and "MET" or "NOT FUNDED", { color = budgetMet and Helper.color.green or resultColor("FAILED") })
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
    check("BUILD WARES", #missingWares == 0 and "MET" or "MISSING", #missingWares == 0 and "No remaining construction-ware deficit is reported." or (tostring(#missingWares) .. " construction ware type(s) are still required; see the list below."), #missingWares == 0 and Helper.color.green or resultColor("FAILED"))
    if #missingWares > 0 then
        section(tableWidget, "MISSING CONSTRUCTION WARES")
        for _, ware in ipairs(missingWares) do
            row = tableWidget:addRow(false); row[1]:setColSpan(2):createText(text(v(ware, 1, "Unknown ware"))); row[3]:createText("REMAINING"); row[4]:createText(tostring(v(ware, 2, 0)))
        end
    end

    section(tableWidget, "ORDERED BUILD QUEUE AND PROGRESS")
    if #queue == 0 then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("No construction modules are currently in the detected queue.") end
    for queueIndex, item in ipairs(queue) do
        local progress = tonumber(v(item, 4, 0)) or 0
        row = tableWidget:addRow(false)
        row[1]:createText("#" .. tostring(v(item, 8, queueIndex)))
        row[2]:createText(text(v(item, 1, "Unknown module")), { wordwrap = true })
        row[3]:createText(text(v(item, 3, "PLANNED")), { color = progress > 0 and Helper.color.green or resultColor("UNKNOWN") })
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

local function focusCaseStation(case)
    local stationName = text(v(case, 1, ""))
    for index, station in ipairs(menu.stations) do
        if text(v(station, 1, "")) == stationName then
            menu.selected = index
            break
        end
    end
end

local function casesCenter(tableWidget)
    local pageSize = 8
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
    brief[1]:setColSpan(4):createText(menu.caseScope == "station" and "STATION REVIEW: This screen is locked to the working station. It shows every retained observation contributing to its operational history, confirmed cases, and player-requested investigations. Choose ALL STATIONS only when you want to leave this station context." or "DECISION BRIEF: Select a station to review its confirmed cases and complete retained observation history.", { wordwrap = true })
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

    section(tableWidget, "STATION HEALTH AND ISSUE INVENTORY")
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
    section(tableWidget, "OPERATIONAL INCIDENTS FOR THIS STATION  |  " .. #incidentOrder .. " INCIDENT(S) / " .. #selectedObservations .. " OBSERVATION(S)")
    if #incidentOrder == 0 then
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("No retained issue record is available for this station. Run a fresh Empire Analysis to reconcile its profile.", { wordwrap = true })
    else
        for _, subject in ipairs(incidentOrder) do
            local incident, leading = incidents[subject], incidents[subject].leading
            local existing = observationHasPlayerCase(text(v(selectedProfile, 1, "")), subject)
            section(tableWidget, subject .. " FLOW INCIDENT | " .. #incident.observations .. " SUPPORTING OBSERVATION(S)")
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("STORY: EOC grouped these records because they concern the same station and subject. They may represent one operating chain rather than separate failures.",{wordwrap=true,color=investigationUnknownColor})
            local missionStation, missionWare, missionText = text(v(menu.missionContext,1,"")), text(v(menu.missionContext,2,"")), text(v(menu.missionContext,3,""))
            if missionStation == text(v(selectedProfile,1,"")) and missionWare == subject then
                row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("MISSION CONTEXT CONFIRMED: "..missionText.." EOC recognizes this as project demand; only proven operational effects contribute to station health.",{wordwrap=true,color=navigationStoryColor})
            end
            for _, observation in ipairs(incident.observations) do
                local state=string.upper(text(v(observation,4,"BASELINE")))
                row=tableWidget:addRow(false); row[1]:setColSpan(4):createText(state.." - "..text(v(observation,2,"OBSERVATION"))..": "..text(v(observation,5,"No evidence summary available")),{wordwrap=true,color=resultColor(state)})
            end
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("LEADING EXPLANATION: "..text(v(leading,6,"Cause not yet confirmed")).." DO THIS NEXT: "..text(v(leading,7,"Continue monitoring")),{wordwrap=true})
            row=tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row,1,"OPEN ONE PLAYER INVESTIGATION: "..subject,function()
                if existing then
                    local createState = actionState("case.create")
                    createState.result = nil
                    createState.lastRun = nil
                    menu.caseDuplicateNotice = "CASE ALREADY EXISTS: A player-requested case is already open for " .. text(v(selectedProfile,1,"this station")) .. " and " .. subject .. ". No duplicate was created."
                    menu.refresh()
                elseif selectedProfile and startAction("case.create") then
                    table.insert(menu.cases,{text(v(selectedProfile,1,"Selected station")),"PLAYER","PLAYER-REPORTED",subject,"OPEN - PLAYER REQUESTED",text(v(leading,6,"Grouped retained evidence requires focused investigation.")),text(v(leading,7,"Review grouped evidence and run focused diagnostics.")),#incident.observations,0,0,"PLAYER"})
                    raise("case.create",{index=v(selectedProfile,16,menu.selected),subject=subject,issues=#incident.observations,rootcause=text(v(leading,6,"Grouped retained evidence requires focused investigation.")),corrective=text(v(leading,7,"Review grouped evidence and run focused diagnostics.")),observationindex=v(leading,14,0),observationcount=#incident.observations})
                    menu.refresh()
                end
            end,not actionState("case.create").running)
            if existing and menu.caseDuplicateNotice then
                row=tableWidget:addRow(false); row[1]:setColSpan(4):createText(menu.caseDuplicateNotice,{wordwrap=true,color=investigationUnknownColor})
            end
        end
    end    actionResult(tableWidget, "case.create", "Creates one persistent player-requested investigation for the selected issue. Existing issue-specific cases are not duplicated.")
    local cases = filteredCases()
    if #cases == 0 then
        section(tableWidget, "NO MATCHING ACTIVE CASES")
        pair(tableWidget, "STATUS", "No confirmed recovery case matches the current filters.", "ACTION", (#selectedObservations > 0 and "Review retained issues above or open a player investigation." or "Run a fresh Empire Analysis."))
        return
    end

    local pageCount = math.max(1, math.ceil(#cases / pageSize))
    menu.casePage = clamp(menu.casePage, 1, pageCount)
    local first = (menu.casePage - 1) * pageSize + 1
    local last = math.min(first + pageSize - 1, #cases)
    if menu.selectedCase < first or menu.selectedCase > last then
        menu.selectedCase = first
    end
    section(tableWidget, "ACTIVE CASES  |  " .. #cases .. "  |  PAGE " .. menu.casePage .. " OF " .. pageCount)
    local header = tableWidget:addRow(false)
    header[1]:setColSpan(2):createText("STATION")
    header[3]:createText("SEVERITY")
    header[4]:createText("SUBJECT")
    for index = first, last do
        local case = cases[index]
        local caseIndex = index
        local caseData = case
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addModeButton(row, 1, "OPEN CASE: " .. text(v(caseData, 1, "Unknown station")), caseIndex == menu.selectedCase, true, function()
            menu.selectedCase = caseIndex
            focusCaseStation(caseData)
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

    if pageCount > 1 then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "PREVIOUS PAGE - " .. math.max(1, menu.casePage - 1) .. " OF " .. pageCount, function()
            menu.casePage = math.max(1, menu.casePage - 1)
            menu.selectedCase = (menu.casePage - 1) * pageSize + 1
            menu.refresh()
        end, menu.casePage > 1)
        row[3]:setColSpan(2)
        addButton(row, 3, "NEXT PAGE - " .. math.min(pageCount, menu.casePage + 1) .. " OF " .. pageCount, function()
            menu.casePage = math.min(pageCount, menu.casePage + 1)
            menu.selectedCase = (menu.casePage - 1) * pageSize + 1
            menu.refresh()
        end, menu.casePage < pageCount)
    end

    menu.selectedCase = clamp(menu.selectedCase, 1, #cases)
    local selected = cases[menu.selectedCase]
    section(tableWidget, "SELECTED CASE: " .. text(v(selected, 1, "Unknown station")) .. " -> " .. text(v(selected, 4, "GENERAL OPERATIONS")))
    pair(tableWidget, "SEVERITY", v(selected, 2, "ISSUE"), "STATE", v(selected, 5, "OPEN"))
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHY THIS CASE IS OPEN: " .. text(v(selected, 6, "Evidence requires review")), { wordwrap = true })

    local checks = prerequisiteRows(selected)
    local firstProblem = nil
    local passCount, notApplicableCount = 0, 0
    for _, check in ipairs(checks) do
        if check.state == "PASS" then passCount = passCount + 1
        elseif check.state == "NOT APPLICABLE" then notApplicableCount = notApplicableCount + 1
        elseif not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN" or check.state == "NOT YET TESTED") then firstProblem = check end
    end

    section(tableWidget, "CURRENT BLOCKER")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " - " .. firstProblem.label .. ": " .. firstProblem.evidence) or "PASS - NO VERIFIED BLOCKER: all reported prerequisites pass or do not apply.", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })
    section(tableWidget, "DO THIS NEXT")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(manualNextAction(selected, checks), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("SUPPORTING RESULTS: " .. passCount .. " PASS | " .. notApplicableCount .. " NOT APPLICABLE - open Guided Recovery to view details.", { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("EVIDENCE SNAPSHOT: Values came from " .. (menu.lastUpdated and ("the EOC analysis at " .. menu.lastUpdated) or "the last EOC analysis") .. ". They may differ from the current vanilla station screen until verification runs.", { wordwrap = true })
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "OPEN GUIDED NEXT ACTION: " .. text(v(selected, 4, "SELECTED CASE")), function()
        focusCaseStation(selected)
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
        focusCaseStation(selected)
        captureNavigation("CASES")
        menu.page = "stations"
        menu.activeTab = "stations"
        menu.refresh()
    end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "GENERATE REPORT: SELECTED STATION", function()
        focusCaseStation(selected)
        captureReportOrigin("cases", "CASES - " .. text(v(selected, 1, "SELECTED STATION")))
        menu.pendingReport = "SELECTED STATION"
        raise("report.station", { index = v(selectedStation(), 16, menu.selected) })
    end, true)

    if v(selected, 11, "") == "PLAYER" then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(4)
        addButton(row, 1, actionLabel("case.close", "CLOSE PLAYER-REQUESTED CASE", "CLOSING PLAYER CASE"), function()
            if startAction("case.close") then
                focusCaseStation(selected)
                local stationName = text(v(selected, 1, ""))
                for index = #menu.cases, 1, -1 do
                    if text(v(menu.cases[index], 1, "")) == stationName and text(v(menu.cases[index], 4, "")) == text(v(selected, 4, "")) and v(menu.cases[index], 11, "") == "PLAYER" then table.remove(menu.cases, index) end
                end
                menu.selectedCase = 1
                menu.casePage = 1
                raise("case.close", { index = v(selectedStation(), 16, menu.selected), subject = text(v(selected, 4, "")) })
                menu.refresh()
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
            for _,template in ipairs(templates) do
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
            for index,entry in ipairs(draft.entries) do
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
        local perPage=6;local pages=math.max(1,math.ceil(#catalog/perPage));state.catalogPage=clamp(state.catalogPage or 1,1,pages);local first=(state.catalogPage-1)*perPage+1
        for index=first,math.min(#catalog,first+perPage-1) do
            local blueprint=catalog[index];row=tableWidget:addRow(true);row[1]:setColSpan(3):createText(text(v(blueprint,1,"Owned ship")).." ("..text(v(blueprint,2,"?"))..")",{wordwrap=true})
            addButton(row,4,"ADD ONE",function()
                local macro=text(v(blueprint,3,""));local found
                for _,existing in ipairs(draft.entries) do if existing.macro==macro then found=existing break end end
                if found then found.amount=math.min(FLEET_MAX_PER_ENTRY,found.amount+1) else draft.entries[#draft.entries+1]={name=text(v(blueprint,1,"Owned ship")),size=text(v(blueprint,2,"?")),macro=macro,amount=1} end
                state.result=nil;menu.refresh()
            end,fleetShipCount(draft)<FLEET_MAX_SHIPS)
        end
        if pages>1 then
            row=tableWidget:addRow(true);row[1]:setColSpan(2);addButton(row,1,"PREVIOUS BLUEPRINT PAGE",function()state.catalogPage=math.max(1,state.catalogPage-1);menu.refresh()end,state.catalogPage>1)
            row[3]:setColSpan(2);addButton(row,3,"NEXT BLUEPRINT PAGE  "..state.catalogPage.." / "..pages,function()state.catalogPage=math.min(pages,state.catalogPage+1);menu.refresh()end,state.catalogPage<pages)
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
    for _,entry in ipairs(template.entries or {}) do pair(tableWidget,entry.name,entry.size,"QUANTITY",entry.amount) end
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
        for _,job in ipairs(plan.jobs or {}) do pair(tableWidget,job.yard.name,job.yard.sector,job.entry.name,job.amount) end
        if #(plan.skipped or {})>0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("SKIPPED - NO COMPATIBLE PLAYER YARD: "..table.concat(plan.skipped,", "),{wordwrap=true}) end
        row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,plan.submitted and "FLEET ORDER SUBMITTED - LOCKED" or "CONFIRM: BUILD THIS FLEET",function()
            local success,result=executeFleetBuildPlan(plan);state.result=result;raise(success and "fleetbuild.queued" or "fleetbuild.partial",{name=template.name,accepted=plan.accepted or 0,requested=plan.total or 0});menu.refresh()
        end,not plan.error and plan.total>0 and not plan.submitted,not plan.error and plan.total>0 and not plan.submitted and pendingChoiceBackground or nil)
    end
    if state.result then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("STATUS: "..state.result,{wordwrap=true}) end
    row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,"RETURN TO SAVED FLEET TEMPLATES",function()state.mode="list";state.plan=nil;state.result=nil;state.deleteConfirm=false;menu.refresh()end,true)
end
local function fleetCenter(tableWidget)
    local station = selectedStation()
    local stationName = text(v(station, 1, "SELECTED STATION"))
    local pageSize = 7
    local entries = {}

    local function selectFleetView(view)
        menu.fleetView = view
        menu.fleetPage = 1
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
        stations = "STATIONS",
        ships = "REGISTERED AVAILABLE SHIPS",
        offers = "EOC-OWNED TRADE OFFERS",
        pending = "PENDING ASSIGNMENTS",
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
    addModeButton(row, 1, (menu.fleetView == "stations" and "ACTIVE: " or "") .. "STATIONS", menu.fleetView == "stations", true, function()
        selectFleetView("stations")
    end)
    addModeButton(row, 2, (menu.fleetView == "ships" and "ACTIVE: " or "") .. "REGISTERED SHIPS", menu.fleetView == "ships", true, function()
        selectFleetView("ships")
    end)
    addModeButton(row, 3, (menu.fleetView == "offers" and "ACTIVE: " or "") .. "TRADE OFFERS", menu.fleetView == "offers", true, function()
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
        menu.fleetPage = 1
        menu.refresh()
    end, menu.fleetScope ~= "global")

    if menu.fleetView == "fleetbuild" then
        fleetBuildManager(tableWidget)
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
        for _, offer in ipairs(menu.tradeOffers) do
            if menu.fleetScope == "global" or text(v(offer, 1, "")) == stationName then
                addEntry({
                    v(offer, 1, "Station"),
                    text(v(offer, 2, "OFFER")) .. " " .. text(v(offer, 3, "Ware")),
                    "AMOUNT / STATUS",
                    formatNumber(v(offer, 4, 0)) .. " / " .. (v(offer, 5, false) and "VERIFIED" or "UNVERIFIED"),
                })
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
        offers = "EOC TRADE OFFERS",
        pending = "PENDING ASSIGNMENTS",
        recommendations = "SHIP RECOMMENDATIONS",
        fleetbuild = "FLEET MANAGEMENT",
    }
    local pageCount = math.max(1, math.ceil(#entries / pageSize))
    menu.fleetPage = clamp(menu.fleetPage, 1, pageCount)
    section(tableWidget, viewTitles[menu.fleetView] .. "  |  " .. #entries .. "  |  PAGE " .. menu.fleetPage .. " OF " .. pageCount)

    if #entries == 0 then
        local emptyMessages = {
            stations = "No station logistics records match the selected scope.",
            ships = "No eligible ships are registered. Use Register Suitable Unassigned Ships below. EOC accepts operational M/L/XL trade or mining ships with supported cargo, no commander, and no subordinates.",
            offers = "No EOC-created or EOC-tracked trade offers match the selected scope. This view does not list every vanilla trade offer.",
            pending = menu.shipmode == "APPROVAL REQUIRED" and
                "No assignments await approval. Entries appear when EOC finds a supported need and a compatible registered ship." or
                "No assignments await approval. Pending normally remains empty unless Ship Assignment Authority is Approval Required.",
            recommendations = "No verified case currently shows both a real logistics shortfall and zero compatible ships. EOC will not recommend purchasing a ship without that evidence.",
        }
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:createText("STATUS")
        statusRow[2]:setColSpan(3):createText(emptyMessages[menu.fleetView], { wordwrap = true })
    else
        local first = (menu.fleetPage - 1) * pageSize + 1
        local last = math.min(first + pageSize - 1, #entries)
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
                        orderMessage = "ORDER STATUS: NOT SUBMITTED. " .. text(orderState.error)
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
                    unavailable[1]:setColSpan(4):createText("SHIP SIZE: " .. availability .. " No order can be previewed or submitted.", { wordwrap = true })
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

    if pageCount > 1 then
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "PREVIOUS PAGE - " .. math.max(1, menu.fleetPage - 1) .. " OF " .. pageCount, function()
            menu.fleetPage = math.max(1, menu.fleetPage - 1)
            menu.refresh()
        end, menu.fleetPage > 1)
        row[3]:setColSpan(2)
        addButton(row, 3, "NEXT PAGE - " .. math.min(pageCount, menu.fleetPage + 1) .. " OF " .. pageCount, function()
            menu.fleetPage = math.min(pageCount, menu.fleetPage + 1)
            menu.refresh()
        end, menu.fleetPage < pageCount)
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
    actionResult(tableWidget, "shipping.register", "Registers eligible unassigned trade and mining ships. The Executive Advisor pinwheel remains available as an alternative.")

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

local function diagnosticsCenter(tableWidget)
    local station = selectedStation()
    local stationName = text(v(station, 1, "NO STATION SELECTED"))
    local cases = station and stationCases(station) or {}
    local diagnosticCase = menu.diagnosticCase
    if diagnosticCase and text(v(diagnosticCase, 1, "")) ~= text(v(station, 1, "")) then diagnosticCase = nil end
    if not diagnosticCase then diagnosticCase = cases[1] end
    local diagnosticPlaybook = diagnosticCase and casePlaybook(diagnosticCase) or nil
    local diagnosticSubject = diagnosticCase and text(v(diagnosticCase, 4, "SELECTED CASE")) or "NO CASE"
    local verificationKey = stationName .. "|" .. diagnosticSubject

    section(tableWidget, "EOC GUIDED RECOVERY")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("ONE STEP AT A TIME: EOC shows the first unresolved check, one player action, and then verification. Values are from the last EOC scan; supporting evidence is available separately.", { wordwrap = true })
    pair(tableWidget, "WORKING STATION", stationName, "ACTIVE CASES", #cases)
    if diagnosticCase then
        section(tableWidget, "WORKING CASE: " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
    end

    local row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.diagnosticView == "recovery" and "ACTIVE: " or "") .. "NEXT ACTION", menu.diagnosticView == "recovery", true, function()
        menu.diagnosticView = "recovery"
        menu.refresh()
    end)
    addModeButton(row, 2, (menu.diagnosticView == "supplier" and "ACTIVE: " or "") .. "EVIDENCE DETAILS", menu.diagnosticView == "supplier", true, function()
        menu.diagnosticView = "supplier"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, (menu.diagnosticView == "stabilization" and "ACTIVE: " or "") .. "VERIFY RESULT", menu.diagnosticView == "stabilization", true, function()
        menu.diagnosticView = "stabilization"
        menu.refresh()
    end)

    if menu.diagnosticView == "investigation" then
        if not diagnosticCase then section(tableWidget, "NO CASE AVAILABLE"); row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("Select an active case before starting a root-cause investigation.", { wordwrap = true }); return end
        local investigationChecks = prerequisiteRows(diagnosticCase)
        local confidence, cause, recommendation, facts, unknowns = rootCauseAssessment(diagnosticCase, investigationChecks)
        section(tableWidget, "ROOT-CAUSE INVESTIGATION - " .. confidence)
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("CURRENT FINDING: " .. cause, { wordwrap = true })
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("RECOMMENDED NEXT STEP: " .. recommendation, { wordwrap = true })
        section(tableWidget, "FACTS COLLECTED BY THIS INVESTIGATION")
        for _, check in ipairs(investigationChecks) do
            local checkColor = resultColor(check.state)
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(check.state .. " - " .. check.label .. ": " .. check.evidence, { wordwrap = true, color = checkColor })
        end
        if #unknowns > 0 then section(tableWidget, "WHAT EOC STILL NEEDS TO LEARN"); for _, item in ipairs(unknowns) do row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("UNKNOWN - " .. item, { wordwrap = true, color = investigationUnknownColor }) end end
        if confidence == "MORE OBSERVATION REQUIRED" then
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
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("I found the immediate blocker, " .. playerDisplayName() .. ". Restore the missing input, then let me verify the station after the next analysis.", { wordwrap = true, color = navigationStoryColor })
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
            row[1]:setColSpan(4):createText((health == "CHRONIC" and "This station is CHRONIC because retained observations reached SYSTEMIC status, but no confirmed recovery case is active. Diagnostics requires one exact working case. Open Cases to review every contributing issue and create an issue-specific player investigation." or "No confirmed recovery case is active for this station. Open Cases to review its " .. #observations .. " retained observation(s) or request an investigation."), { wordwrap = true, color = health == "CHRONIC" and investigationUnknownColor or nil })
            row = tableWidget:addRow(true); row[1]:setColSpan(4)
            addButton(row, 1, "OPEN THIS STATION'S CASE REVIEW", function() menu.caseScope = "station"; menu.caseSeverity = "all"; menu.selectedCase = 1; menu.casePage = 1; menu.diagnosticCase = nil; menu.page = "cases"; menu.activeTab = "cases"; menu.refresh() end, true)
            return
        end

        row = tableWidget:addRow(true); row[1]:setColSpan(4)
        addButton(row, 1, "INVESTIGATE ROOT CAUSE - COLLECT AND EXPLAIN EVIDENCE", function() menu.diagnosticView = "investigation"; menu.refresh() end, true)

        local diagnosticChecks = prerequisiteRows(diagnosticCase)
        local firstProblem = nil
        for _, check in ipairs(diagnosticChecks) do
            if not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN" or check.state == "NOT YET TESTED") then firstProblem = check end
        end
        local nextAction = manualNextAction(diagnosticCase, diagnosticChecks)

        section(tableWidget, "STEP 1 OF 3 - WHAT FAILED FIRST")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " - " .. firstProblem.label) or "PASS - ALL REPORTED PREREQUISITES", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and ("EVIDENCE: " .. firstProblem.evidence) or "EVIDENCE: No failed or unknown prerequisite was returned.", { wordwrap = true, color = firstProblem and resultColor(firstProblem.state) or investigationPassColor })

        section(tableWidget, "STEP 2 OF 3 - DO THIS NOW")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(nextAction, { wordwrap = true })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("PLAYER CONTROL: EOC will not cancel or replace trader orders, move credits, or alter station configuration. Complete this action manually.", { wordwrap = true })

        local marketEligible = firstProblem and (firstProblem.label == "DELIVERY PATH" or firstProblem.label == "REACHABLE SUPPLY" or firstProblem.label == "STORAGE FREE SPACE")
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
        addButton(row, 3, "ACTION COMPLETE - GO TO VERIFY RESULT", function() menu.diagnosticView = "stabilization"; menu.refresh() end, true)

        section(tableWidget, "STEP 3 OF 3 - VERIFY AFTER THE ACTION")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("After completing the player action, open Verify Result and run one fresh analysis. EOC will report RESOLVED, IMPROVING, UNCHANGED, or WORSENING.", { wordwrap = true })
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
            row = tableWidget:addRow(false); row[1]:setColSpan(4):createText(marketType == "BUY" and "Creates one bounded NPC-enabled EOC BUY offer. Your existing Empire-only ware rule and ordinary offers remain untouched." or "Creates one bounded NPC-enabled EOC SELL offer for evidenced excess. Your existing ware rule and ordinary offers remain untouched.", { wordwrap = true, color = navigationStoryColor })
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
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("EVIDENCE SNAPSHOT: Values came from " .. (menu.lastUpdated and ("the EOC analysis at " .. menu.lastUpdated) or "the last EOC analysis") .. ". Run Verify Result to refresh and compare it.", { wordwrap = true })
            row = tableWidget:addRow(false)
            local awaitingEvidence = false
            for _, check in ipairs(detailChecks) do
                local state = string.upper(text(check.state))
                if state == "UNKNOWN" or state == "NOT YET TESTED" then awaitingEvidence = true; break end
            end
            row[1]:setColSpan(4):createText((awaitingEvidence and "SUSPECTED CAUSE - CONFIRMATION REQUIRED: " or "ROOT CAUSE: ") .. text(v(diagnosticCase, 6, "Evidence requires review.")), { wordwrap = true })
            local caseType = string.upper(text(v(diagnosticCase, 3, "")))
            local currentStock = tonumber(v(diagnosticCase, 8, 0)) or 0
            local targetStock = tonumber(v(diagnosticCase, 9, 0)) or 0
            local maximumStock = tonumber(v(diagnosticCase, 10, 0)) or 0
            local storagePressure = caseType == "STORAGE PRESSURE"
            row = tableWidget:addRow(false)
            if storagePressure then
                row[1]:setColSpan(4):createText("CURRENT STOCK: " .. formatNumber(currentStock) .. " | TARGET: " .. formatNumber(targetStock) .. " | MAXIMUM: " .. formatNumber(maximumStock), { wordwrap = true })
            else
                row[1]:setColSpan(4):createText("CURRENT STOCK: " .. formatNumber(currentStock) .. " | TARGET: " .. formatNumber(targetStock) .. " | MAXIMUM: " .. formatNumber(maximumStock) .. " | STATION OPERATING ACCOUNT: " .. formatNumber(v(diagnosticCase, 32, 0)) .. " Cr", { wordwrap = true })
            end
            section(tableWidget, "BIG TAKEAWAY")
            row = tableWidget:addRow(false)
            if storagePressure then
                row[1]:setColSpan(4):createText(text(v(diagnosticCase, 4, "This ware")) .. " storage is effectively full. Incoming deliveries, mining, production, or trade may stall. Reduce the ware target or allocation, add matching storage, or improve outbound use and sales; then run Verify Result.", { wordwrap = true, color = investigationUnknownColor })
            elseif awaitingEvidence then
                row[1]:setColSpan(4):createText(intelligenceName() .. " has identified a suspected blocker that still requires focused evidence. The colored checks below show what is supported and what remains untested.", { wordwrap = true, color = investigationUnknownColor })
            else
                row[1]:setColSpan(4):createText(intelligenceName() .. " has isolated the immediate blocker. The colored checks below show what is working and what needs attention.", { wordwrap = true, color = navigationStoryColor })
            end
            section(tableWidget, intelligenceName() .. " - HERE IS WHAT I FOUND")
            section(tableWidget, "EVIDENCE CHECKS - GREEN PASSED | RED FAILED | AMBER NEEDS MORE EVIDENCE")
            for _, check in ipairs(detailChecks) do
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText(check.state .. " - " .. check.label .. ": " .. check.evidence, { wordwrap = true, color = resultColor(check.state) })
            end
            section(tableWidget, "WHY THIS CASE MATTERS")
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText(diagnosticPlaybook.impact, { wordwrap = true })
        else
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("No working case is selected.", { wordwrap = true })
        end
    elseif menu.diagnosticView == "stabilization" then
        section(tableWidget, "VERIFY RECOVERY")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("This page does not change the station role or EOC operating policy. Complete the working case's recommended player action, then run a fresh analysis and compare evidence, severity, and trend.", { wordwrap = true })
        if string.upper(text(v(diagnosticCase, 2, ""))) == "PLAYER" then row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("VERIFICATION LOCKED: This player-requested incident is NOT YET TESTED. Collect supported focused evidence before claiming recovery.", { wordwrap = true, color = investigationUnknownColor }) end
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, actionLabel("analysis.run", "VERIFY: RUN FRESH ANALYSIS", "VERIFYING WITH FRESH ANALYSIS"), function()
            if startAction("analysis.run") then
                menu.analysisRunning = true
                menu.pendingVerificationKey = verificationKey
                menu.verificationKey = nil
                menu.verificationResult = "FRESH VERIFICATION RUNNING for " .. stationName .. " -> " .. diagnosticSubject
                raise("analysis.run", { verify = true, station = stationName, subject = diagnosticSubject, severity = text(v(diagnosticCase, 2, "UNKNOWN")), amount = tonumber(v(diagnosticCase, 8, 0)) or 0 })
            end
        end, not actionState("analysis.run").running and string.upper(text(v(diagnosticCase, 2, ""))) ~= "PLAYER")
        row[3]:setColSpan(2)
        addButton(row, 3, "RETURN TO GUIDED RECOVERY", function() menu.diagnosticView = "recovery"; menu.refresh() end, true)
        if menu.verificationKey == verificationKey then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CASE VERIFICATION: " .. text(menu.verificationClass, "UNKNOWN") .. "\n" .. text(menu.verificationResult) .. "\nWORKING CASE: " .. stationName .. " -> " .. diagnosticSubject, { wordwrap = true, color = resultColor(string.upper(text(menu.verificationClass, "UNKNOWN"))) })
        elseif menu.pendingVerificationKey == verificationKey then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CASE VERIFICATION: RUNNING\n" .. text(menu.verificationResult), { wordwrap = true })
        else
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CASE VERIFICATION: NOT RUN FOR THIS WORKING CASE\nACTION: Select VERIFY: RUN FRESH ANALYSIS", { wordwrap = true })
        end
    else
        section(tableWidget, "GUIDED RECOVERY")
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("The requested diagnostics view is unavailable. Select Next Action, Evidence Details, or Verify Result.", { wordwrap = true })
    end

    if diagnosticCase and menu.diagnosticView ~= "recovery" and menu.diagnosticView ~= "options" then
        section(tableWidget, "WHERE WOULD YOU LIKE TO GO NEXT?")
        row = tableWidget:addRow(false); row[1]:setColSpan(4):createText("These choices do not change the diagnosis. Pick where " .. intelligenceName() .. " should take you next.", { wordwrap = true, color = navigationStoryColor })
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "OPEN EOC STATIONS - RETURN TO THIS CASE", function()
            captureNavigation("DIAGNOSTICS - " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
            menu.page = "stations"
            menu.activeTab = "stations"
            menu.refresh()
        end, true)
        row[3]:setColSpan(2)
        addButton(row, 3, "OPEN EOC FLEET & LOGISTICS - RETURN TO THIS CASE", function()
            captureNavigation("DIAGNOSTICS - " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
            menu.fleetScope = "station"
            menu.fleetView = "stations"
            menu.fleetPage = 1
            menu.page = "fleet"
            menu.activeTab = "fleet"
            menu.refresh()
        end, true)
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, menu.diagnosticView == "supplier" and "RETURN TO NEXT ACTION" or "VIEW SUPPORTING EVIDENCE", function()
            menu.diagnosticView = menu.diagnosticView == "supplier" and "recovery" or "supplier"
            menu.refresh()
        end, true)
        row[3]:setColSpan(2)
        addButton(row, 3, actionLabel("analysis.run", "VERIFY: RUN EMPIRE ANALYSIS", "VERIFYING WITH EMPIRE ANALYSIS"), function()
            if startAction("analysis.run") then
                menu.analysisRunning = true
                menu.pendingVerificationKey = verificationKey
                menu.verificationKey = nil
                menu.verificationResult = "FRESH VERIFICATION RUNNING for " .. stationName .. " -> " .. diagnosticSubject
                raise("analysis.run", { verify = true, station = stationName, subject = diagnosticSubject, severity = text(v(diagnosticCase, 2, "UNKNOWN")), amount = tonumber(v(diagnosticCase, 8, 0)) or 0 })
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

local KPI_MAX_VISIBLE_ROWS = 8

local function kpiTruncationNotice(tableWidget, total, shown)
    if total > shown then
        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("DISPLAY LIMIT: Showing " .. tostring(shown) .. " of " .. tostring(total) .. " rows. Use a filter for detail; " .. tostring(total - shown) .. " additional row(s) are hidden to protect the X4 widget height.", { wordwrap = true, color = investigationWarnColor })
    end
end

local function kpiAttentionView(tableWidget)
    local rows = buildKpiRows()
    local counts = { CRITICAL = 0, WARNING = 0, WATCH = 0, HEALTHY = 0 }
    for _, item in ipairs(rows) do counts[item.state] = counts[item.state] + 1 end

    section(tableWidget, "EMPIRE KPI CENTER")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("PURPOSE: This page answers which station deserves attention first. Scores rank review priority; they never authorize an operation.", { wordwrap = true })
    section(tableWidget, "EOC CONCLUSION")
    local pulse = tableWidget:addRow(false)
    pulse[1]:setColSpan(4):createText(
        ((counts.CRITICAL + counts.WARNING) > 0 and ((counts.CRITICAL + counts.WARNING) .. " station(s) need review. ") or "No station currently needs urgent review. ") ..
        "DO THIS NEXT: Start with the first station in the queue.",
        { wordwrap = true }
    )
    pair(tableWidget, "CRITICAL", counts.CRITICAL, "WARNING", counts.WARNING)

    section(tableWidget, "EXECUTIVE ATTENTION QUEUE")
    if #rows == 0 then
        pair(tableWidget, "STATUS", "No player stations are currently available.", "NEXT STEP", "Wait for the EOC property scan.")
        return
    end

    local header = tableWidget:addRow(false)
    header[1]:createText("RANK / STATE")
    header[2]:createText("STATION")
    header[3]:createText("HEALTH / TREND")
    header[4]:createText("SCORE / ISSUES")
    local headerLine = tableWidget:addRow(false)
    headerLine[1]:setColSpan(4):createText(string.rep("━", 420), { wordwrap = false, fontsize = 3, color = navigationStoryColor })

    for rank = 1, math.min(#rows, KPI_MAX_VISIBLE_ROWS) do
        local item = rows[rank]
        local selectedItem = item
        local row = tableWidget:addRow(true)
        row[1]:createText(rank .. ". " .. item.state)
        addButton(row, 2, item.name, function()
            menu.kpiSelected = selectedItem.index
            menu.refresh()
        end, true)
        row[3]:createText(item.health .. " / " .. item.trend)
        row[4]:createText(item.score .. " / " .. item.issues)
    end

    local selectedIndex = menu.kpiSelected or rows[1].index
    local selected = rows[1]
    for _, item in ipairs(rows) do
        if item.index == selectedIndex then selected = item break end
    end
    menu.kpiSelected = selected.index

    section(tableWidget, "FOCUS: " .. selected.name)
    pair(tableWidget, "ATTENTION STATE", selected.state, "ATTENTION SCORE", selected.score)
    pair(tableWidget, "ROLE", selected.role, "PRIORITY", selected.priority)
    pair(tableWidget, "CRITICAL CASES", selected.critical, "WARNING CASES", selected.warning)

    local whyRow = tableWidget:addRow(false)
    whyRow[1]:setColSpan(4):createText("WHY THIS RANKS HERE: " .. selected.why, { wordwrap = true })
    local actionRow = tableWidget:addRow(false)
    actionRow[1]:setColSpan(4):createText("RECOMMENDED NEXT ACTION: " .. selected.recommendation, { wordwrap = true })

    local row = tableWidget:addRow(true)
    addButton(row, 1, "OPEN STATION", function()
        menu.selected = selected.index
        captureNavigation("KPI CENTER")
        menu.page = "stations"
        menu.activeTab = "stations"
        menu.refresh()
    end, true)
    addButton(row, 2, "OPEN STATION CASES", function()
        menu.selected = selected.index
        captureNavigation("KPI CENTER")
        menu.caseScope = "station"
        menu.caseSeverity = "all"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.page = "cases"
        menu.activeTab = "cases"
        menu.refresh()
    end, selected.issues > 0 or selected.critical > 0 or selected.warning > 0)
    addButton(row, 3, "OPEN DIAGNOSTICS", function()
        menu.selected = selected.index
        captureNavigation("KPI CENTER")
        menu.diagnosticView = "recovery"
        menu.page = "diagnostics"
        menu.activeTab = "diagnostics"
        menu.refresh()
    end, true)
    addButton(row, 4, "RUN EMPIRE ANALYSIS", function()
        if not menu.analysisRunning then
            menu.analysisRunning = true
            menu.analysisStatus = "ANALYSIS RUNNING"
            menu.refresh()
            raise("analysis.run", {})
        end
    end, not menu.analysisRunning)

    local guide = tableWidget:addRow(false)
    guide[1]:setColSpan(4):createText(
        "SCORING GUIDE: confirmed cases, persistent health states, worsening trends, priority, and issue count raise attention. " ..
        "Scores rank focus; they do not authorize or perform any operation.",
        { wordwrap = true }
    )
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
    row[column]:setColSpan(4 - column + 1):createDropDown(options, { active = #options > 0, startOption = selected })
    row[column].handlers.onDropDownActivated = function() menu.kpiControlDropdownActive = true end
    row[column].handlers.onDropDownDeactivated = function() menu.kpiControlDropdownActive = false; menu.kpiNextRefreshAt = getElapsedTime() + KPI_REFRESH_SECONDS end
    row[column].handlers.onDropDownConfirmed = function(_, value) menu.kpiControlDropdownActive = false; confirmed(value); menu.kpiNextRefreshAt = getElapsedTime() + KPI_REFRESH_SECONDS; menu.refresh() end
end

local function kpiControlLabel(row, label)
    row[1]:createText(label, { wordwrap = false, font = Helper.headerFont, color = investigationWarnColor })
end

local function kpiHeader(tableWidget, labels)
    local row = tableWidget:addRow(false)
    for i = 1, 4 do row[i]:createText(labels[i] or "", { wordwrap = false, font = Helper.headerFont }) end
    local line = tableWidget:addRow(false)
    line[1]:setColSpan(4):createText(string.rep("━", 420), { wordwrap = false, fontsize = 3, color = navigationStoryColor })
end

local function kpiViewButtonCallback(view)
    return function()
        menu.kpiView = view
        menu.refresh()
    end
end

local function kpiDashboardControls(tableWidget)
    section(tableWidget, "LIVE KPI DASHBOARDS")
    local choices = {
        { "EMPIRE CASH FLOW", "cash" }, { "STATION PROFIT", "profit" }, { "CONSTRUCTION PROGRESS", "construction" }, { "WARE SHORTAGES", "shortages" },
        { "EXECUTIVE ATTENTION", "attention" }, { "TRADE ACTIVITY", "trade" }, { "LOGISTICS HEALTH", "logistics" }, { "STORAGE LEVELS", "storage" },
        { "TOP EARNERS", "earners" }, { "CASH DRAINS", "drains" }, { "SHIPYARD ACTIVITY", "shipyard" }, { "WORKFORCE HEALTH", "workforce" },
        { "CASE TRENDS", "casetrends" }, { "EMPIRE GROWTH", "growth" }
    }
    local row
    for index, choice in ipairs(choices) do
        if ((index - 1) % 4) == 0 then row = tableWidget:addRow(true) end
        local label = choice[1]
        local view = choice[2]
        local column = ((index - 1) % 4) + 1
        addButton(row, column, label, kpiViewButtonCallback(view), true, menu.kpiView == view and selectedModeBackground or availableModeBackground)
    end
    if menu.kpiView == "construction" then
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
    elseif menu.kpiView == "shortages" or menu.kpiView == "trade" or menu.kpiView == "storage" or menu.kpiView == "workforce" or menu.kpiView == "logistics" then
        local options, seen = kpiStationOptions(); local key = "kpiStation_" .. menu.kpiView; menu[key] = menu[key] or "__all__"; if menu[key] ~= "__all__" and not seen[menu[key]] then menu[key] = "__all__" end
        row = tableWidget:addRow(true); kpiControlLabel(row, "STATION FILTER")
        kpiProtectedDropdown(row, 2, options, menu[key], function(name) menu[key] = name end)
        local function sortOption(id, label)
            return { id = id, text = label, icon = "", displayremoveoption = false }
        end
        local sortChoices = {
            trade = { sortOption("station", "STATION"), sortOption("ware", "WARE"), sortOption("type", "BUY / SELL"), sortOption("quantity", "QUANTITY") },
            logistics = { sortOption("ship", "SHIP"), sortOption("role", "ROLE"), sortOption("station", "COMMANDER / HOME"), sortOption("state", "OPERATIONAL STATE") },
            storage = { sortOption("station", "STATION"), sortOption("fill", "FILL %"), sortOption("free", "FREE SPACE"), sortOption("type", "STORAGE TYPE") },
            workforce = { sortOption("station", "STATION"), sortOption("population", "POPULATION"), sortOption("change", "WORKFORCE CHANGE"), sortOption("shortfall", "PROVISION SHORTFALL") }
        }
        local sortKey = "kpiSort_" .. menu.kpiView
        menu[sortKey] = menu[sortKey] or "station"
        row = tableWidget:addRow(true); kpiControlLabel(row, "SORT BY")
        kpiProtectedDropdown(row, 2, sortChoices[menu.kpiView], menu[sortKey], function(value) menu[sortKey] = value end)
    elseif menu.kpiView == "shipyard" then
        local names, seen = {}, {}; for _, route in ipairs(menu.shipWharfRoutes or {}) do local name = text(v(route, 2, "Unknown shipyard")); if not seen[name] then seen[name] = true; table.insert(names, name) end end; table.sort(names)
        local options = { { id="__all__", text="ALL SHIPYARDS", icon="", displayremoveoption=false } }; for _, name in ipairs(names) do table.insert(options, {id=name,text=name,icon="",displayremoveoption=false}) end
        menu.kpiShipyard = menu.kpiShipyard or "__all__"; row = tableWidget:addRow(true); kpiControlLabel(row, "SHIPYARD FILTER"); kpiProtectedDropdown(row, 2, options, menu.kpiShipyard, function(name) menu.kpiShipyard=name end)
    end
    row = tableWidget:addRow(true)
    addButton(row, 1, menu.kpiPaused and "RESUME LIVE" or "PAUSE LIVE", function() menu.kpiPaused = not menu.kpiPaused; if not menu.kpiPaused then menu.kpiNextRefreshAt = getElapsedTime() end; menu.refresh() end, true)
    addButton(row, 2, "RESET VIEW", function() menu.kpiHistory = {}; menu.kpiNextRefreshAt = getElapsedTime(); menu.refresh() end, true)
    row[3]:setColSpan(2):createText("SCOPE: FILTERED VIEW | PERIOD: LIVE SESSION", { wordwrap = false })
    row = tableWidget:addRow(false); local seconds = math.max(0, math.ceil((tonumber(menu.kpiNextRefreshAt) or getElapsedTime()) - getElapsedTime()))
    row[1]:setColSpan(4):createText((menu.kpiPaused and "LIVE PAUSED" or menu.kpiRefreshing and "LIVE REFRESH IN PROGRESS" or ("LIVE - 10s | NEXT REFRESH: " .. tostring(seconds) .. "s")) .. " | Sampling stops when KPI Center closes or another page opens.", { wordwrap = true, color = investigationPassColor })
end

local function kpiBar(value, maximum) value=tonumber(value) or 0; maximum=math.max(1,tonumber(maximum) or 1); return (value<0 and "-" or "+") .. string.rep("=", math.max(1,math.min(30,math.floor((math.abs(value)/maximum)*30+0.5)))) end
local function stationMoneyMap(sample) local result={}; for _,station in ipairs((sample and sample.stations) or {}) do result[tostring(station.name or "Unknown station")]=tonumber(station.money) or 0 end; return result end

local function kpiCashFlowView(t)
    local h=menu.kpiHistory or {}; section(t,"EMPIRE CASH FLOW - VERIFIED PLAYER ACCOUNT"); if #h==0 then pair(t,"STATUS","Waiting for first live sample.","REFRESH","Automatic in 10 seconds."); return end
    local latest=h[#h]; pair(t,"CURRENT CREDITS",formatNumber(latest.credits).." Cr","CHANGE SINCE LAST SAMPLE",formatNumber(latest.creditChange).." Cr"); local maximum=1; for _,s in ipairs(h) do maximum=math.max(maximum,math.abs(tonumber(s.creditChange) or 0)) end
    kpiHeader(t,{"GAME TIME","ACCOUNT","10s CHANGE","CHANGE CHART"}); local first=math.max(1,#h-KPI_MAX_VISIBLE_ROWS+1); for i=first,#h do local s=h[i]; local r=t:addRow(false); r[1]:createText(formatGameTime(s.time)); r[2]:createText(formatNumber(s.credits).." Cr"); r[3]:createText(formatNumber(s.creditChange).." Cr"); r[4]:createText(kpiBar(s.creditChange,maximum),{color=s.creditChange<0 and investigationFailColor or investigationPassColor}) end
    kpiTruncationNotice(t,#h,#h-first+1)
end

local function kpiStationProfitView(t)
    local h=menu.kpiHistory or {}; section(t,"STATION ACCOUNT MOVEMENT - LIVE"); if #h==0 then pair(t,"STATUS","Waiting for first live sample.","REFRESH","Automatic in 10 seconds."); return end
    local current=stationMoneyMap(h[#h]); local previous=stationMoneyMap(h[#h-1]); local rows={}; for name,money in pairs(current) do table.insert(rows,{name=name,money=money,change=previous[name] and money-previous[name] or 0}) end; table.sort(rows,function(a,b) return a.change==b.change and a.name<b.name or a.change>b.change end)
    kpiHeader(t,{"STATION","ACCOUNT","10s MOVEMENT","DIRECTION"}); local shown=math.min(KPI_MAX_VISIBLE_ROWS,#rows); for i=1,shown do local x=rows[i]; local r=t:addRow(false); r[1]:createText(x.name); r[2]:createText(formatNumber(x.money).." Cr"); r[3]:createText(formatNumber(x.change).." Cr"); r[4]:createText(x.change>0 and "UP" or x.change<0 and "DOWN" or "UNCHANGED") end
    kpiTruncationNotice(t,#rows,shown); local r=t:addRow(false); r[1]:setColSpan(4):createText("Account movement is verified; it is not identical to transaction profit.",{wordwrap=true})
end

local function kpiConstructionView(t)
    local selection=menu.kpiConstructionSelection or "__all__"; local records={}
    for _,record in ipairs(menu.constructionRecords or {}) do local id=tostring(tonumber(v(record,2,0)) or 0); if (tonumber(v(record,3,0)) or 0)>0 and (selection=="__all__" or id==selection) then table.insert(records,record) end end
    if selection~="__all__" and menu.activeConstructionSnapshot then local snapshotId=tostring(tonumber(v(menu.activeConstructionSnapshot,2,0)) or 0); if snapshotId==selection then records={menu.activeConstructionSnapshot} end end
    table.sort(records,function(a,b)return text(v(a,1,""))<text(v(b,1,""))end)
    if selection=="__all__" then
        section(t,"CONSTRUCTION PROGRESS - ALL ACTIVE STATIONS"); if #records==0 then pair(t,"STATUS","No active station construction detected.","MODULES","0"); return end
        kpiHeader(t,{"STATION","ACTIVE / PLANNED","TOTAL QUEUE","CURRENT MODULE"}); local shown=math.min(KPI_MAX_VISIBLE_ROWS,#records)
        for i=1,shown do local record=records[i]; local current="NONE"; for _,item in ipairs(v(record,8,{})) do if string.upper(text(v(item,3,"")))=="UNDER CONSTRUCTION" then current=text(v(item,1,"Unknown module")).." / "..string.format("%.1f%%",tonumber(v(item,4,0)) or 0); break end end; local r=t:addRow(false); r[1]:createText(text(v(record,1,"Unknown station")),{wordwrap=true}); r[2]:createText(tostring(v(record,5,0)).." / "..tostring(v(record,4,0))); r[3]:createText(tostring(v(record,3,0))); r[4]:createText(current,{wordwrap=true}) end
        kpiTruncationNotice(t,#records,shown); return
    end
    local selected=records[1]; section(t,"CONSTRUCTION PROGRESS - ACTIVE STATION DRILLDOWN"); if not selected then pair(t,"STATUS","No active station construction detected for this filter.","MODULES","0"); return end
    pair(t,"ACTIVE / PLANNED MODULES",tostring(v(selected,5,0)).." / "..tostring(v(selected,4,0)),"TOTAL QUEUE",v(selected,3,0)); kpiHeader(t,{"QUEUE","MODULE","CURRENT STATUS","PROGRESS"}); local items=v(selected,8,{}); local shown=math.min(KPI_MAX_VISIBLE_ROWS,#items)
    for i=1,shown do local item=items[i]; local r=t:addRow(false); r[1]:createText("#"..tostring(v(item,8,i))); r[2]:createText(text(v(item,1,"Unknown module")),{wordwrap=true}); r[3]:createText(text(v(item,3,"PLANNED"))); r[4]:createText(string.format("%.1f%%",tonumber(v(item,4,0)) or 0)) end
    kpiTruncationNotice(t,#items,shown)
end

local function kpiShortageView(t)
    section(t,"WARE SHORTAGES - STATION AND RESOURCE DRILLDOWN"); local filtered={}; local selected=menu.kpiStation_shortages or "__all__"; for _,c in ipairs(menu.cases or {}) do local sev=string.upper(text(v(c,2,""))); local typ=string.upper(text(v(c,3,""))); if (sev=="CRITICAL" or sev=="WARNING") and (string.find(typ,"WARE",1,true) or string.find(typ,"SHORT",1,true) or (tonumber(v(c,30,0)) or 0)>0) and (selected=="__all__" or text(v(c,1,""))==selected) then table.insert(filtered,c) end end
    kpiHeader(t,{"STATION","WARE / RESOURCE","SEVERITY","CURRENT / TARGET / SHORTFALL"}); if #filtered==0 then local r=t:addRow(false); r[1]:setColSpan(4):createText("No confirmed ware shortages are present for this station filter. Run Empire Analysis after conditions change.",{wordwrap=true}) end; local shown=math.min(KPI_MAX_VISIBLE_ROWS,#filtered)
    for i=1,shown do local c=filtered[i]; local cur=tonumber(v(c,8,0)) or 0; local target=tonumber(v(c,9,0)) or 0; local short=tonumber(v(c,31,0)) or math.max(0,target-cur); local r=t:addRow(false); r[1]:createText(text(v(c,1,"Unknown station"))); r[2]:createText(text(v(c,4,"Unknown resource"))); r[3]:createText(text(v(c,2,"WARNING"))); r[4]:createText(cur.." / "..target.." / "..short) end; kpiTruncationNotice(t,#filtered,shown)
end

local function kpiTradeView(t)
    section(t,"TRADE ACTIVITY - EOC-MANAGED OFFERS ONLY"); local selected=menu.kpiStation_trade or "__all__"; local sortBy=menu.kpiSort_trade or "station"; local rows={}; for _,x in ipairs(menu.tradeOffers or {}) do if selected=="__all__" or text(v(x,1,""))==selected then table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="ware" then return text(v(a,3,""))<text(v(b,3,"")) elseif sortBy=="type" then return text(v(a,2,""))<text(v(b,2,"")) elseif sortBy=="quantity" then return (tonumber(v(a,4,0)) or 0)>(tonumber(v(b,4,0)) or 0) end return text(v(a,1,""))<text(v(b,1,"")) end)
    pair(t,"EOC-MANAGED OFFERS",#rows,"ALL X4 STATION ORDERS","UNAVAILABLE IN CURRENT FEED"); kpiHeader(t,{"STATION","BUY / SELL","WARE","QUANTITY / VERIFIED"}); local shown=math.min(KPI_MAX_VISIBLE_ROWS,#rows); for i=1,shown do local x=rows[i]; local r=t:addRow(false); r[1]:createText(text(v(x,1,"Unknown"))); r[2]:createText(text(v(x,2,"UNKNOWN"))); r[3]:createText(text(v(x,3,"Unknown ware"))); r[4]:createText(tostring(v(x,4,0)).." / "..(v(x,5,false) and "YES" or "NO")) end; kpiTruncationNotice(t,#rows,shown)
end

local function kpiLogisticsView(t)
    section(t,"LOGISTICS HEALTH - EOC-REGISTERED SHIPS"); local selected=menu.kpiStation_logistics or "__all__"; local sortBy=menu.kpiSort_logistics or "ship"; local rows={}; for _,x in ipairs(menu.registeredShips or {}) do local commander=text(v(x,5,"AVAILABLE")); if selected=="__all__" or commander==selected then table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="role" then return text(v(a,2,""))<text(v(b,2,"")) elseif sortBy=="station" then return text(v(a,5,""))<text(v(b,5,"")) elseif sortBy=="state" then return tostring(v(a,4,false))>tostring(v(b,4,false)) end return text(v(a,1,""))<text(v(b,1,"")) end)
    local note=t:addRow(false); note[1]:setColSpan(4):createText("Reports only ships registered with EOC: role, class, operational state, commander/home, and assignment. It is not the entire player fleet.",{wordwrap=true}); kpiHeader(t,{"SHIP","ROLE / CLASS","OPERATIONAL","COMMANDER / ASSIGNMENT"}); if #rows==0 then local r=t:addRow(false); r[1]:setColSpan(4):createText("No EOC-registered logistics ships match this station filter.",{wordwrap=true}) end; local shown=math.min(KPI_MAX_VISIBLE_ROWS,#rows); for i=1,shown do local x=rows[i]; local r=t:addRow(false); r[1]:createText(text(v(x,1,"Unknown ship"))); r[2]:createText(text(v(x,2,"Unknown")).." / "..text(v(x,3,"Unknown"))); r[3]:createText(v(x,4,false) and "YES" or "NO"); r[4]:createText(text(v(x,5,"AVAILABLE")).." / "..text(v(x,6,"UNASSIGNED"))) end; kpiTruncationNotice(t,#rows,shown)
end

local function kpiStorageView(t)
    section(t,"STORAGE LEVELS - VERIFIED STATION STORAGE TYPES"); local selected=menu.kpiStation_storage or "__all__"; local sortBy=menu.kpiSort_storage or "station"; local rows={}; for _,x in ipairs(menu.storageRecords or {}) do if (selected=="__all__" or text(v(x,1,""))==selected) and (tonumber(v(x,4,0)) or 0)>0 then table.insert(rows,x) end end
    table.sort(rows,function(a,b) local ac=tonumber(v(a,4,0)) or 0; local bc=tonumber(v(b,4,0)) or 0; local af=ac>0 and (tonumber(v(a,3,0)) or 0)/ac or 0; local bf=bc>0 and (tonumber(v(b,3,0)) or 0)/bc or 0; if sortBy=="fill" then return af>bf elseif sortBy=="free" then return (tonumber(v(a,5,0)) or 0)>(tonumber(v(b,5,0)) or 0) elseif sortBy=="type" then return text(v(a,2,""))<text(v(b,2,"")) end local an=text(v(a,1,"")); local bn=text(v(b,1,"")); return an==bn and text(v(a,2,""))<text(v(b,2,"")) or an<bn end)
    kpiHeader(t,{"STATION / STORAGE TYPE","USED","CAPACITY / FREE","FILL %"}); if #rows==0 then local r=t:addRow(false); r[1]:setColSpan(4):createText("No verified storage capacity is exposed for this station filter.",{wordwrap=true}) end; local shown=math.min(KPI_MAX_VISIBLE_ROWS,#rows); for i=1,shown do local x=rows[i]; local used=tonumber(v(x,3,0)) or 0; local cap=tonumber(v(x,4,0)) or 0; local r=t:addRow(false); r[1]:createText(text(v(x,1,"Unknown")).." / "..text(v(x,2,"UNKNOWN"))); r[2]:createText(formatNumber(used)); r[3]:createText(formatNumber(cap).." / "..formatNumber(v(x,5,0))); r[4]:createText(cap>0 and string.format("%.1f%%",used*100/cap) or "UNAVAILABLE") end; kpiTruncationNotice(t,#rows,shown)
end

local function kpiWorkforceView(t)
    section(t,"WORKFORCE HEALTH - POPULATION AND PROVISION DEMAND"); local selected=menu.kpiStation_workforce or "__all__"; local sortBy=menu.kpiSort_workforce or "station"; local rows={}; for _,x in ipairs(menu.workforceRecords or {}) do if selected=="__all__" or text(v(x,1,""))==selected then table.insert(rows,x) end end
    table.sort(rows,function(a,b) if sortBy=="population" then return (tonumber(v(a,3,0)) or 0)>(tonumber(v(b,3,0)) or 0) elseif sortBy=="change" then return (tonumber(v(a,7,0)) or 0)>(tonumber(v(b,7,0)) or 0) elseif sortBy=="shortfall" then return (tonumber(v(a,11,0)) or 0)>(tonumber(v(b,11,0)) or 0) end local an=text(v(a,1,"")); local bn=text(v(b,1,"")); return an==bn and text(v(a,2,""))<text(v(b,2,"")) or an<bn end)
    kpiHeader(t,{"STATION / SPECIES","CURRENT / CAP / OPTIMAL","TREND / CHANGE","PROVISION CURRENT / TARGET / SHORT"}); if #rows==0 then local r=t:addRow(false); r[1]:setColSpan(4):createText("No workforce population is exposed for this station filter.",{wordwrap=true}) end; local shown=math.min(KPI_MAX_VISIBLE_ROWS,#rows); for i=1,shown do local x=rows[i]; local r=t:addRow(false); r[1]:createText(text(v(x,1,"Unknown")).." / "..text(v(x,2,"Unknown species"))); r[2]:createText(tostring(v(x,3,0)).." / "..tostring(v(x,4,0)).." / "..tostring(v(x,5,0))); r[3]:createText(text(v(x,6,"UNKNOWN")).." / "..tostring(v(x,7,0))); r[4]:createText(text(v(x,8,"Unknown provision")).."  "..tostring(v(x,9,0)).." / "..tostring(v(x,10,0)).." / "..tostring(v(x,11,0)),{wordwrap=true}) end; kpiTruncationNotice(t,#rows,shown)
end

local function kpiShipyardView(t)
    section(t,"SHIPYARD ACTIVITY - EOC ORDERS AND VERIFIED YARD QUEUES"); local selected=menu.kpiShipyard or "__all__"; local yardMap={}; for _,x in ipairs(menu.shipWharfRoutes or {}) do local name=text(v(x,2,"Unknown shipyard")); if (selected=="__all__" or name==selected) and not yardMap[name] then yardMap[name]={name=name,queued=v(x,6,0),active=v(x,7,0),modules=v(x,8,0)} end end; local yards={}; for _,x in pairs(yardMap) do table.insert(yards,x) end; table.sort(yards,function(a,b)return a.name<b.name end)
    local split=math.floor(KPI_MAX_VISIBLE_ROWS/2); kpiHeader(t,{"SHIPYARD","QUEUED","IN PROGRESS","BUILD MODULES"}); local yardShown=math.min(split,#yards); for i=1,yardShown do local x=yards[i]; local r=t:addRow(false); r[1]:createText(x.name); r[2]:createText(tostring(x.queued)); r[3]:createText(tostring(x.active)); r[4]:createText(tostring(x.modules)) end; kpiTruncationNotice(t,#yards,yardShown)
    local orders={}; for _,x in ipairs(menu.shipOrderRecords or {}) do if selected=="__all__" or text(v(x,4,""))==selected then table.insert(orders,x) end end; local r=t:addRow(false); r[1]:setColSpan(4):createText("EOC order records are EOC-created orders only. Compatible blueprint routes are not displayed as active orders.",{wordwrap=true}); kpiHeader(t,{"INTENDED STATION","SHIP","SHIPYARD","TASK / QUEUED TIME"}); local orderShown=math.min(split,#orders); for i=1,orderShown do local x=orders[i]; r=t:addRow(false); r[1]:createText(text(v(x,1,"Unknown"))); r[2]:createText(text(v(x,5,"Unknown ship"))); r[3]:createText(text(v(x,4,"Unknown yard"))); r[4]:createText(text(v(x,6,"Unknown task")).." / "..formatGameTime(v(x,7,0))) end; kpiTruncationNotice(t,#orders,orderShown)
end

local function kpiExtendedView(t,view)
    if view=="trade" then return kpiTradeView(t) elseif view=="logistics" then return kpiLogisticsView(t) elseif view=="storage" then return kpiStorageView(t) elseif view=="workforce" then return kpiWorkforceView(t) elseif view=="shipyard" then return kpiShipyardView(t) end
    local titles={earners="TOP EARNERS",drains="CASH DRAINS",casetrends="CASE TRENDS",growth="EMPIRE GROWTH"}; section(t,(titles[view] or "KPI VIEW").." - VERIFIED EOC SNAPSHOT")
    if view=="casetrends" or view=="growth" then local h=menu.kpiHistory or {}; kpiHeader(t,view=="casetrends" and {"GAME TIME","CRITICAL","WARNING","OTHER / TOTAL"} or {"GAME TIME","STATIONS / SHIPS","CONSTRUCTION","SHIP ORDERS"}); if #h==0 then local r=t:addRow(false); r[1]:setColSpan(4):createText("Waiting for the first verified 10-second sample.",{wordwrap=true}) end; local first=math.max(1,#h-KPI_MAX_VISIBLE_ROWS+1); for i=first,#h do local x=h[i]; local r=t:addRow(false); r[1]:createText(formatGameTime(x.time)); if view=="casetrends" then local total=(tonumber(x.caseCritical) or 0)+(tonumber(x.caseWarning) or 0)+(tonumber(x.caseOther) or 0); r[2]:createText(tostring(x.caseCritical or 0)); r[3]:createText(tostring(x.caseWarning or 0)); r[4]:createText(tostring(x.caseOther or 0).." / "..tostring(total)) else r[2]:createText(tostring(x.stationCount or 0).." / "..tostring(x.registeredShipCount or 0)); r[3]:createText(tostring(x.constructionRecordCount or 0)); r[4]:createText(tostring(x.shipOrderCount or 0)) end end; kpiTruncationNotice(t,#h,#h-first+1); return end
    local h=menu.kpiHistory or {}; local changes={}; if #h>=2 then local p=stationMoneyMap(h[#h-1]); local c=stationMoneyMap(h[#h]); for station,amount in pairs(c) do local delta=(tonumber(amount) or 0)-(tonumber(p[station]) or 0); if (view=="earners" and delta>0) or (view=="drains" and delta<0) then table.insert(changes,{station,delta}) end end end; table.sort(changes,function(a,b)return view=="earners" and a[2]>b[2] or view=="drains" and a[2]<b[2] end); kpiHeader(t,{"STATION","10s ACCOUNT MOVEMENT","DIRECTION","NOTE"}); local shown=math.min(KPI_MAX_VISIBLE_ROWS,#changes); for i=1,shown do local x=changes[i]; local r=t:addRow(false); r[1]:createText(x[1]); r[2]:createText(formatNumber(x[2]).." Cr"); r[3]:createText(x[2]>0 and "UP" or "DOWN"); r[4]:createText("Account movement") end; kpiTruncationNotice(t,#changes,shown)
end
local function kpiCenter(tableWidget)
    menu.kpiView=menu.kpiView or "cash"; kpiDashboardControls(tableWidget)
    if menu.kpiView=="profit" then kpiStationProfitView(tableWidget) elseif menu.kpiView=="construction" then kpiConstructionView(tableWidget) elseif menu.kpiView=="shortages" then kpiShortageView(tableWidget) elseif menu.kpiView=="attention" then kpiAttentionView(tableWidget) elseif menu.kpiView~="cash" then kpiExtendedView(tableWidget,menu.kpiView) else kpiCashFlowView(tableWidget) end
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
    for col,choice in ipairs(choices) do local c=choice; addButton(row,col,(menu.narrativeScope==c[1] and "ACTIVE: " or "")..c[2],function() menu.narrativeScope=c[1]; menu.refresh() end,true,menu.narrativeScope==c[1] and Helper.color.green or nil) end
    row=tableWidget:addRow(true); row[1]:setColSpan(2); addButton(row,1,(menu.narrativeScope=="history" and "ACTIVE: " or "").."RETAINED HISTORY",function() menu.narrativeScope="history"; menu.refresh() end,true); row[3]:setColSpan(2); addButton(row,3,"MARK STORY REVIEWED",function() local store=narrativeStore(); store.lastReview=now; saveNarrativeStore(store); menu.narrativeScope="review"; menu.refresh() end,true)
    local shown=0
    for stationIndex,station in ipairs(menu.stations or {}) do
        local name=text(v(station,1,"Station")); local observations={}; local categories={}; local counts={SYSTEMIC=0,RECURRING=0,CANDIDATE=0,RECOVERING=0,RELAPSED=0}; local leading=nil
        local stationReports={}; local reportKinds={}; for _,report in ipairs(menu.reports or {}) do local title=text(v(report,1,"EOC REPORT")); local body=text(v(report,2,"")); local stamp=tonumber(v(report,4,0)) or 0; if (menu.narrativeScope=="history" or cutoff<=0 or (menu.narrativeScope=="review" and stamp>cutoff) or (menu.narrativeScope~="review" and stamp>=cutoff)) and (string.find(title,name,1,true) or string.find(body,"Station: "..name,1,true)) then stationReports[#stationReports+1]=report; reportKinds[title]=true end end
        for _,obs in ipairs(stationObservations(name)) do local stamp=math.max(tonumber(v(obs,16,0)) or 0,tonumber(v(obs,17,0)) or 0,tonumber(v(obs,18,0)) or 0); if menu.narrativeScope=="history" or cutoff<=0 or stamp>=cutoff then observations[#observations+1]=obs; categories[text(v(obs,2,"OPERATIONS"))]=true; local state=text(v(obs,4,"BASELINE")); counts[state]=(counts[state] or 0)+1; if not leading or (({RELAPSED=5,SYSTEMIC=4,RECURRING=3,CANDIDATE=2,RECOVERING=1})[state] or 0) > (({RELAPSED=5,SYSTEMIC=4,RECURRING=3,CANDIDATE=2,RECOVERING=1})[text(v(leading,4,"BASELINE"))] or 0) then leading=obs end end end
        local cases=stationCases(name); if #observations>0 or #cases>0 or #stationReports>0 then shown=shown+1; local categoryCount=0; for _ in pairs(categories) do categoryCount=categoryCount+1 end; local health=text(v(station,3,"MONITORING")); local trend=text(v(station,4,"STABLE")); section(tableWidget,name.." | "..health.." / "..trend); local active=counts.SYSTEMIC+counts.RECURRING+counts.CANDIDATE+counts.RELAPSED; local story
            if active==1 and counts.SYSTEMIC==1 then story="One issue currently drives this status. Fixing it may materially improve health, but CHRONIC clears only after later recovery samples and stable remaining systems."
            elseif categoryCount>1 then story=active.." active retained issues span "..categoryCount.." operating areas. Fixing only the leading issue is unlikely to restore overall health."
            elseif active>1 then story=active.." retained issues are concentrated in one operating area. Address the leading blocker, then recheck related evidence."
            elseif counts.RECOVERING>0 then story="Earlier evidence is improving, but EOC is retaining it until later samples prove recovery holds."
            else story="No current escalation appears in this period; retained history remains available for comparison." end
            row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("STORY: "..story,{wordwrap=true,color=stationStatusColor(health)}); if leading then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("LEADING EVIDENCE: "..text(v(leading,3,"Operations")).." - "..text(v(leading,5,"No evidence summary available")),{wordwrap=true}); row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("OUTLOOK: "..(trend=="DETERIORATING" and "Evidence is worsening." or trend=="IMPROVING" and "Evidence is improving; verify it holds." or "Evidence is stable.").." DO THIS NEXT: "..text(v(leading,7,"Run a fresh analysis after a meaningful operating cycle.")),{wordwrap=true}) end
            local reportKindCount=0; for _ in pairs(reportKinds) do reportKindCount=reportKindCount+1 end
            if #stationReports>0 then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("RECENT ACTIVITY: "..#stationReports.." report(s) recorded in this period across "..reportKindCount.." consolidated report type(s). Latest: "..text(v(stationReports[1],1,"Station report")).." at "..text(v(stationReports[1],3,"-")),{wordwrap=true,color=navigationStoryColor}) end
            pair(tableWidget,"EVIDENCE",#observations.." retained / "..categoryCount.." area(s)","CASES / REPORTS",#cases.." / "..#stationReports); row=tableWidget:addRow(true); local selected=stationIndex; row[1]:setColSpan(2); addButton(row,1,"OPEN THIS STATION'S CASES",function() menu.selected=selected; captureNavigation("OVERVIEW"); menu.caseScope="station"; menu.caseSeverity="all"; menu.page="cases"; menu.activeTab="cases"; menu.refresh() end,true); row[3]:setColSpan(2); addButton(row,3,"OPEN THIS STATION'S DIAGNOSTICS",function() menu.selected=selected; captureNavigation("OVERVIEW"); menu.diagnosticView="recovery"; menu.page="diagnostics"; menu.activeTab="diagnostics"; menu.refresh() end,true)
        end
    end
    if shown==0 then row=tableWidget:addRow(false); row[1]:setColSpan(4):createText("No station evidence falls inside this time window. Choose a wider period or continue until the next analysis.",{wordwrap=true}) end
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
        for index, station in ipairs(menu.stations) do
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

    tableWidget.properties.maxVisibleHeight = height
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
    for index, report in ipairs(menu.reports) do
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
        row[1]:setColSpan(4):createText(tostring(underway) .. " UNDERWAY / " .. tostring(waiting) .. " WAITING", { color = underway > 0 and Helper.color.green or resultColor("UNKNOWN"), font = Helper.headerFont })
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
    addButton(row, 1, actionLabel("analysis.run", "RUN FRESH STATUS CHECK", "STATUS CHECK RUNNING"), function()
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

    row = tableWidget:addRow(true)
    addButton(row, 1, "OPEN STATION CASES", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.caseScope = "station"; menu.caseSeverity = "all"; menu.selectedCase = 1; menu.casePage = 1; menu.diagnosticCase = nil
        menu.page = "cases"; menu.activeTab = "cases"; menu.refresh()
    end, true)
    addButton(row, 2, "GUIDED DIAGNOSTICS", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.diagnosticView = "recovery"; menu.page = "diagnostics"; menu.activeTab = "diagnostics"; menu.refresh()
    end, true)
    addButton(row, 3, "FLEET & LOGISTICS", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.page = "fleet"; menu.activeTab = "fleet"; menu.refresh()
    end, true)
    addButton(row, 4, "GLOBAL SETTINGS", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.page = "settings"; menu.activeTab = "settings"; menu.refresh()
    end, true)

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
    elseif analysisState.running then status = "WORKING: Refreshing this station's status evidence through a fresh empire analysis..."
    elseif analysisState.result then status = "RESULT: " .. text(v(station, 1, "Selected station")) .. " is " .. health .. " / " .. trend .. " with " .. #cases .. " active case(s) and " .. #observations .. " retained issue(s)."
    elseif menu.reportStatus then status = text(menu.reportStatus) end
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(status or "READY: Run a fresh status check, generate a station report, open focused evidence, or preview a role change.", { wordwrap = true, color = menu.pendingRole and investigationUnknownColor or navigationStoryColor })
end

local function commandIdentitySetup(tableWidget, firstRun)
    local store = commandIdentityStore()
    menu.identityDraft = menu.identityDraft or store.name or ""
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
    end, true, startupDirty and investigationUnknownColor or Helper.color.green)
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
    end, startupDirty, startupDirty and investigationUnknownColor or Helper.color.green)

    section(tableWidget, "GLOBAL EOC SETTINGS")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("CHANGE ONLY WHAT YOU INTEND: EOC acts only within the authorities selected below. Construction funding uses the exact X4-reported shortfall; it does not alter the station plan or cancel ordinary player orders.", { wordwrap = true })
    pair(tableWidget, "Trade Order Control", menu.mode, "Ship Assignment Authority", menu.shipmode)
    pair(tableWidget, "Construction Funding Authority", menu.constructionAuthority, "Funding Rule", "EXACT VERIFIED SHORTFALL ONLY")
    if menu.settingsStatus then
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:setColSpan(4):createText(menu.settingsStatus, { wordwrap = true })
    end

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

    if menu.page == "stations" then
        local usableWidth = width - 2 * Helper.borderSize
        local gap = Helper.borderSize
        local leftWidth = math.floor(usableWidth * 0.31)
        local rightWidth = usableWidth - leftWidth - gap

        createStationNavigator(
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
        if menu.clickStatus and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
            local feedbackRow = tableWidget:addRow(false)
            feedbackRow[1]:setColSpan(4):createText(menu.clickStatus, { wordwrap = true })
        end
        if menu.navigationOrigin and menu.page ~= menu.navigationOrigin.page then
            local returnRow = tableWidget:addRow(true)
            returnRow[1]:setColSpan(4)
            addButton(returnRow, 1, "RETURN TO " .. text(menu.navigationOrigin.label), restoreNavigation, true)
        end
        stationWorkspace(tableWidget)
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

        if menu.page == "identity" then
            commandIdentitySetup(tableWidget, true)
        elseif menu.page == "boot" then
            commandOSBoot(tableWidget)
        elseif menu.page == "dashboard" then
            dashboard(tableWidget)
        elseif menu.page == "kpi" then
            kpiCenter(tableWidget)
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
        if menu.restoreTableTopRow then menu.mainTable:setTopRow(menu.restoreTableTopRow) end
        if menu.restoreTableSelectedRow then menu.mainTable:setSelectedRow(menu.restoreTableSelectedRow) end
    end
    menu.restoreTablePage = nil
    menu.restoreTableTopRow = nil
    menu.restoreTableSelectedRow = nil

    menu.frame:display()
end

function menu.refresh(preserveScroll)
    if preserveScroll and menu.mainTable and menu.page == "kpi" then
        local ok, topRow = pcall(GetTopRow, menu.mainTable)
        if ok then menu.restoreTableTopRow = topRow end
        if Helper.currentTableRow then menu.restoreTableSelectedRow = Helper.currentTableRow[menu.mainTable] end
        menu.restoreTablePage = menu.page
    else
        menu.restoreTablePage = nil
        menu.restoreTableTopRow = nil
        menu.restoreTableSelectedRow = nil
    end
    menu.create()
end

function menu.onCloseElement(reason, layer)
    raise("closed", { reason = reason or "close" })
    Helper.closeMenu(menu, reason or "close", layer)
    menu.frame = nil
end

function menu.onUpdate()
    local now = getElapsedTime()

    if menu.page == "kpi" and not menu.kpiPaused and not menu.kpiRefreshing and not menu.kpiControlDropdownActive and now >= (tonumber(menu.kpiNextRefreshAt) or 0) then
        menu.kpiRefreshing = true
        menu.kpiNextRefreshAt = now + KPI_REFRESH_SECONDS
        raise("kpi.refresh", {})
    elseif menu.page == "construction" and not menu.constructionRefreshing and now >= (tonumber(menu.constructionNextRefreshAt) or 0) then
        local record = constructionRecordForSelected()
        local stationName = text(v(record, 1, "SELECTED STATION"))
        local index = tonumber(v(record, 2, menu.selected)) or menu.selected
        menu.constructionRefreshing = true
        menu.constructionNextRefreshAt = now + KPI_REFRESH_SECONDS
        raise("construction.refresh", { index = index, station = stationName })
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





