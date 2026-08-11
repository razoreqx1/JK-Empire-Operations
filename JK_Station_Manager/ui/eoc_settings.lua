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
        return "—"
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
            captureNavigation("RESULT — " .. action)
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
local function verificationResultReceived(_, value) menu.pendingVerificationResult = text(value, "UNKNOWN — no verification detail returned.") end

local function prerequisiteRows(caseData)
    local rows = {}
    local function add(label, state, evidence) table.insert(rows, { label = label, state = state, evidence = evidence }) end
    local family = string.upper(text(v(caseData, 3, "STATION ISSUE")))
    local storageCase = string.find(family, "STORAGE", 1, true) ~= nil
    local logisticsCase = string.find(family, "LOGISTICS", 1, true) ~= nil or string.find(family, "SUPPORT SHIPS", 1, true) ~= nil
    local supplyCase = not storageCase and not logisticsCase
    local capacity, free = tonumber(v(caseData, 13, 0)) or 0, tonumber(v(caseData, 14, 0)) or 0
    local immediateNeed = tonumber(v(caseData, 30, 0)) or 0
    if not logisticsCase then
        add("STORAGE INSTALLED", capacity > 0 and "PASS" or "FAIL", text(v(caseData, 12, "UNKNOWN")) .. " capacity " .. formatNumber(capacity))
        local freeState = capacity <= 0 and "UNKNOWN" or ((immediateNeed <= 0 or free >= immediateNeed) and "PASS" or "FAIL")
        add("STORAGE FREE SPACE", freeState, formatNumber(free) .. " free; " .. formatNumber(immediateNeed) .. " required now")
    end
    if supplyCase then
        local stationFunds = tonumber(v(caseData, 32, 0)) or 0
        local minimumPrice = tonumber(v(caseData, 21, 0)) or 0
        local requiredBudget = immediateNeed > 0 and minimumPrice > 0 and (immediateNeed * minimumPrice) or 0
        local fundingState = requiredBudget > 0 and (stationFunds >= requiredBudget and "PASS" or "FAIL") or (stationFunds > 0 and "PASS" or "UNKNOWN")
        add("STATION OPERATING FUNDS", fundingState, formatNumber(stationFunds) .. " Cr available; estimated immediate purchase " .. formatNumber(requiredBudget) .. " Cr")
        local suppliers = tonumber(v(caseData, 18, 0)) or 0
        add("REACHABLE SUPPLY", suppliers > 0 and "PASS" or "FAIL", suppliers .. " offers: own " .. text(v(caseData, 19, 0)) .. ", NPC " .. text(v(caseData, 20, 0)) .. "; NPC price " .. text(v(caseData, 21, 0)) .. "–" .. text(v(caseData, 22, 0)) .. " Cr")
    end
    if supplyCase or logisticsCase then
        local traders, compatible = tonumber(v(caseData, 23, 0)) or 0, tonumber(v(caseData, 24, 0)) or 0
        add("STATION TRADER", compatible > 0 and "PASS" or "FAIL", traders .. " assigned; " .. compatible .. " compatible")
    end
    if supplyCase then
        local produces, paused = tonumber(v(caseData, 15, 0)) or 0, v(caseData, 29, false)
        add("LOCAL PRODUCTION", produces > 0 and (paused and "FAIL" or "PASS") or "NOT APPLICABLE", produces > 0 and (paused and "production is paused" or text(v(caseData, 16, 0)) .. " module(s)") or "import case does not require local production")
        local missing = tonumber(v(caseData, 27, 0)) or 0
        add("PRODUCTION INPUTS", produces == 0 and "NOT APPLICABLE" or (missing == 0 and "PASS" or "FAIL"), produces == 0 and "no local production chain to inspect" or (missing > 0 and text(v(caseData, 28, "missing input unnamed")) or text(v(caseData, 26, "no missing input reported"))))
    end
    if #rows == 0 then add("CASE EVIDENCE", "UNKNOWN", "No family-specific prerequisite set is available; follow the case root cause and manual action.") end
    return rows
end
local function manualNextAction(caseData, rows)
    for _, check in ipairs(rows) do
        if check.state == "FAIL" or check.state == "UNKNOWN" then
            if check.label == "STORAGE INSTALLED" then return "Open the Station Build Plan and add compatible " .. text(v(caseData, 12, "cargo")) .. " storage; wait until it is operational."
            elseif check.label == "STORAGE FREE SPACE" then return "Open Logical Station Overview and move, sell, or reallocate stock until the required " .. text(v(caseData, 12, "cargo")) .. " storage space is free."
            elseif check.label == "STATION OPERATING FUNDS" then local required = math.max(0, ((tonumber(v(caseData, 30, 0)) or 0) * (tonumber(v(caseData, 21, 0)) or 0)) - (tonumber(v(caseData, 32, 0)) or 0)); return "Open the station Information account and transfer at least " .. formatNumber(required) .. " Cr for the immediate purchase. EOC will not move player credits."
            elseif check.label == "REACHABLE SUPPLY" then return "Open the station buy offer for " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " and verify trade rule, price, and manager range permit a supplier."
            elseif check.label == "STATION TRADER" then return "Assign one operational trader compatible with " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " to " .. text(v(caseData, 1, "the station")) .. "."
            elseif check.label == "LOCAL PRODUCTION" and v(caseData, 29, false) then return "Resume the paused local production module for " .. text(v(caseData, 4, "the affected ware")) .. "."
            elseif check.label == "PRODUCTION INPUTS" then return "Restore the confirmed missing production input: " .. text(v(caseData, 28, "review station inputs")) .. "." end
        end
    end
    return "No reported prerequisite requires a change. Observe one operating or delivery cycle, then run Verify Result. Do not add ships, storage, or production unless verification still shows a blocker."
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
        menu.verificationResult = menu.pendingVerificationResult or "UNKNOWN — the rescan completed without a comparison result."
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
    DebugError("[JKEOC][B144][LUA_ERROR] Helper.registerMenu unavailable")
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
    menu.shipOrderState = menu.shipOrderState or {}
    menu.pendingShipQueueRefresh = nil
    menu.probesRun = {}
    menu.lastProbeVerb = nil
    menu.pendingVerificationKey = nil
    menu.verificationKey = nil
    menu.verificationResult = nil
    menu.navigationStack = menu.navigationStack or {}
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

local function addButton(row, column, label, handler, active)
    local properties = { active = active ~= false }
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
            menu.reportStatus = "REPORT RUNNING — waiting for EOC result"
        end
        menu.refresh()
        handler()
    end
end

local function addModeButton(row, column, label, selected, enabled, handler)
    local isEnabled = enabled ~= false
    local background = inactiveModeBackground

    if isEnabled then
        if selected then
            background = selectedModeBackground
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
    local label = "WORKING STATION — " .. stationName
    if caseSubject and caseSubject ~= "—" then label = label .. "  |  CASE — " .. caseSubject end
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
    menu.caseScope = "global"
    menu.caseSeverity = "all"
    menu.selectedCase = 1
    menu.casePage = 1
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
    local tableWidget = frame:addTable(8, {
        tabOrder = 1,
        x = Helper.borderSize,
        y = Helper.borderSize,
        width = usableWidth,
        borderEnabled = true,
    })
    local columnWidth = math.floor(usableWidth / 8)

    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setColWidth(4, columnWidth, false)
    tableWidget:setColWidth(5, columnWidth, false)
    tableWidget:setColWidth(6, columnWidth, false)
    tableWidget:setColWidth(7, columnWidth, false)

    local row = tableWidget:addRow(false, { fixed = true })
    row[1]:setColSpan(8):createText(menu.title, {
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
    addTabButton(row, 6, "CASES", "cases")
    addTabButton(row, 7, "REPORTS", "reports")
    addTabButton(row, 8, "GLOBAL SETTINGS", "settings")

    local activeColumns = {
        stations = 1,
        dashboard = 2,
        kpi = 3,
        fleet = 4,
        diagnostics = 5,
        cases = 6,
        reports = 7,
        settings = 8,
    }
    tableWidget:setSelectedRow(2)
    tableWidget:setSelectedCol(activeColumns[menu.activeTab or menu.page] or 2)

    tableWidget.properties.maxVisibleHeight = headerHeight
    return headerHeight
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
    local selectedDifference = math.max(0, selectedProfileIssues - selectedEOCCases)
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("DECISION BRIEF: Cases require tracked action. Profile issues may include observations that have not matured into cases. Select a station to reconcile both counts or request an investigation.", { wordwrap = true })
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

    section(tableWidget, "PLAYER CASE DESK")
    pair(tableWidget, "SELECTED STATION", text(v(selectedProfile, 1, "NONE")), "PROFILE ISSUES", selectedProfileIssues)
    pair(tableWidget, "EOC-CONFIRMED CASES", selectedEOCCases, "PLAYER-REQUESTED CASES", selectedPlayerCases)
    pair(tableWidget, "UNRECONCILED OBSERVATIONS", selectedDifference, "PLAYER AUTHORITY", "REQUEST INVESTIGATION / MONITOR")
    local hasPlayerCase = false
    if selectedProfile then
        for _, candidate in ipairs(stationCases(selectedProfile)) do
            if v(candidate, 11, "") == "PLAYER" then hasPlayerCase = true break end
        end
    end
    row = tableWidget:addRow(true)
    row[1]:setColSpan(3)
    addButton(row, 1, actionLabel("case.create", "CREATE PLAYER CASE FOR SELECTED STATION", "CREATING PLAYER CASE"), function()
        if selectedProfile and startAction("case.create") then
            local stationName = text(v(selectedProfile, 1, "Selected station"))
            local subject = selectedProfileIssues > 0 and (selectedProfileIssues .. " detected issue(s) require reconciliation") or "Player-requested station review"
            table.insert(menu.cases, { stationName, "PLAYER", "PLAYER-REPORTED", subject, "OPEN - PLAYER REQUESTED", "The player requested EOC investigation of this station.", "Review existing evidence, open Diagnostics, and define a verification step.", selectedProfileIssues, 0, 0, "PLAYER" })
            menu.caseScope = "station"
            menu.caseSeverity = "all"
            menu.selectedCase = #menu.cases
            menu.casePage = math.max(1, math.ceil(#stationCases(selectedProfile) / 8))
            raise("case.create", { index = v(selectedProfile, 16, menu.selected), subject = subject, issues = selectedProfileIssues })
            menu.refresh()
        end
    end, selectedProfile ~= nil and not hasPlayerCase and not actionState("case.create").running)
    addButton(row, 4, "CHOOSE STATION - RETURN TO CASES", function()
        captureNavigation("CASES", true)
        menu.page = "stations"
        menu.activeTab = "stations"
        menu.refresh()
    end, true)
    if hasPlayerCase then
        local existingRow = tableWidget:addRow(false)
        existingRow[1]:setColSpan(4):createText("STATUS: This station already has a player-requested case. Select it below instead of creating a duplicate.", { wordwrap = true })
    end
    actionResult(tableWidget, "case.create", "Creates a persistent player-requested investigation. It remains PLAYER-REPORTED until evidence confirms severity.")

    local cases = filteredCases()
    if #cases == 0 then
        section(tableWidget, "NO MATCHING ACTIVE CASES")
        pair(tableWidget, "STATUS", "No critical or warning case matches the current filters.", "ACTION", "Continue monitoring.")
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
        elseif not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN") then firstProblem = check end
    end

    section(tableWidget, "CURRENT BLOCKER")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " — " .. firstProblem.label .. ": " .. firstProblem.evidence) or "NO VERIFIED BLOCKER — all reported prerequisites pass or do not apply.", { wordwrap = true })
    section(tableWidget, "DO THIS NEXT")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(manualNextAction(selected, checks), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("SUPPORTING RESULTS: " .. passCount .. " PASS | " .. notApplicableCount .. " NOT APPLICABLE — open Guided Recovery to view details.", { wordwrap = true })
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
                    if text(v(menu.cases[index], 1, "")) == stationName and v(menu.cases[index], 11, "") == "PLAYER" then table.remove(menu.cases, index) end
                end
                menu.selectedCase = 1
                menu.casePage = 1
                raise("case.close", { index = v(selectedStation(), 16, menu.selected) })
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
    section(tableWidget,"FLEET BUILD MANAGER — EOC 2.2 GA")
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
                addButton(row,3,"ADD 1 — NOW "..entry.amount,function()entry.amount=math.min(FLEET_MAX_PER_ENTRY,(entry.amount or 1)+1);state.result=nil;menu.refresh()end,fleetShipCount(draft)<FLEET_MAX_SHIPS)
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
        row[3]:setColSpan(2);addButton(row,3,"CANCEL — RETURN TO TEMPLATES",function()state.mode="list";state.draft=nil;state.originalName=nil;state.result=nil;menu.refresh()end,true)
        if state.result then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("STATUS: "..state.result,{wordwrap=true}) end
        return
    end
    local template=findFleetTemplate(state.selected)
    if not template then state.mode="list";state.selected=nil;state.plan=nil;menu.refresh();return end
    section(tableWidget,"FLEET TEMPLATE — "..template.name)
    for _,entry in ipairs(template.entries or {}) do pair(tableWidget,entry.name,entry.size,"QUANTITY",entry.amount) end
    row=tableWidget:addRow(true);row[1]:setColSpan(2);addButton(row,1,"EDIT TEMPLATE",function()state.mode="edit";state.originalName=template.name;state.draft=copySerializable(template);state.plan=nil;state.result=nil;menu.refresh()end,true)
    row[3]:setColSpan(2);addButton(row,3,state.deleteConfirm and "CONFIRM DELETE TEMPLATE" or "DELETE TEMPLATE",function()if state.deleteConfirm then deleteFleetTemplate(template.name);state.mode="list";state.selected=nil;state.deleteConfirm=false;state.plan=nil;state.result=nil else state.deleteConfirm=true end;menu.refresh()end,true)
    section(tableWidget,"BUILD CONTROL")
    row=tableWidget:addRow(true);row[1]:setColSpan(2);addModeButton(row,1,(state.distribute and "" or "ACTIVE: ").."ONE COMPATIBLE SHIPYARD",not state.distribute,true,function()state.distribute=false;state.plan=nil;state.result=nil;menu.refresh()end)
    row[3]:setColSpan(2);addModeButton(row,3,(state.distribute and "ACTIVE: " or "").."SPREAD ACROSS COMPATIBLE SHIPYARDS",state.distribute,true,function()state.distribute=true;state.plan=nil;state.result=nil;menu.refresh()end)
    row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,"PREVIEW FLEET BUILD — "..fleetShipCount(template).." SHIPS",function()state.plan=computeFleetBuildPlan(template,state.distribute==true);state.result=state.plan.error;menu.refresh()end,true)
    local plan=state.plan
    if plan then
        section(tableWidget,"FLEET BUILD PREVIEW")
        row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("PLAN: "..plan.total.." ship(s) across "..plan.yards.." player shipyard(s). Preview does not place orders.",{wordwrap=true})
        for _,job in ipairs(plan.jobs or {}) do pair(tableWidget,job.yard.name,job.yard.sector,job.entry.name,job.amount) end
        if #(plan.skipped or {})>0 then row=tableWidget:addRow(false);row[1]:setColSpan(4):createText("SKIPPED — NO COMPATIBLE PLAYER YARD: "..table.concat(plan.skipped,", "),{wordwrap=true}) end
        row=tableWidget:addRow(true);row[1]:setColSpan(4);addButton(row,1,plan.submitted and "FLEET ORDER SUBMITTED — LOCKED" or "CONFIRM: BUILD THIS FLEET",function()
            local success,result=executeFleetBuildPlan(plan);state.result=result;raise(success and "fleetbuild.queued" or "fleetbuild.partial",{name=template.name,accepted=plan.accepted or 0,requested=plan.total or 0});menu.refresh()
        end,not plan.error and plan.total>0 and not plan.submitted)
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
                    headline[1]:setColSpan(4):createText("EOC ORDER COMPLETE — EXACTLY 1 SHIP WAS SUBMITTED", { wordwrap = true, fontsize = Helper.headerRow1FontSize or Helper.standardFontSize })
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
                    addButton(choices, 1, (selectedSize == "M" and "SELECTED: " or "CHOOSE: ") .. "MEDIUM — " .. text(v(mediumBlueprint, 1, "Medium ship")), function()
                        orderState.selectedSize = "M"
                        orderState.preview = false
                        orderState.error = nil
                        menu.refresh()
                    end, true)
                    choices[3]:setColSpan(2)
                    addButton(choices, 3, (selectedSize == "L" and "SELECTED: " or "CHOOSE: ") .. "LARGE — " .. text(v(largeBlueprint, 1, "Large ship")), function()
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
                    addButton(submitted, 1, "ORDER SUBMITTED — EXACTLY 1 SHIP", function() end, false)
                    local persistedStatus = tableWidget:addRow(false)
                    persistedStatus[1]:setColSpan(4):createText("ORDER STATUS: SUBMITTED — X4 ACCEPTED TASK " .. text(v(persisted, 6, "recorded")) .. ". EOC has locked this station-and-cargo need against every hull size. No further EOC action is required.", { wordwrap = true })
                elseif selectedAvailable then
                    local blueprintStatus = tableWidget:addRow(false)
                    blueprintStatus[1]:setColSpan(4):createText("BLUEPRINT: FOUND — " .. selectedShip .. " (" .. selectedSize .. ").", { wordwrap = true })
                    local distance = tonumber(v(selectedWharf, 5, -1)) or -1
                    local distanceText = distance >= 0 and (formatNumber(distance) .. " gate(s)") or "route unavailable"
                    local wharfStatus = tableWidget:addRow(false)
                    wharfStatus[1]:setColSpan(4):createText("EOC BUILD LOCATION: " .. text(v(selectedWharf, 2, "Unknown wharf")) .. " — " .. text(v(selectedWharf, 3, "Unknown sector")) .. ". DISTANCE: " .. distanceText .. ". CURRENT LOAD: " .. formatNumber(v(selectedWharf, 6, 0)) .. " queued, " .. formatNumber(v(selectedWharf, 7, 0)) .. " building; " .. formatNumber(v(selectedWharf, 8, 0)) .. " build module(s).", { wordwrap = true })

                    local review = tableWidget:addRow(true)
                    review[1]:setColSpan(4)
                    if persisted or orderState.task then
                        addButton(review, 1, "ORDER SUBMITTED — EXACTLY 1 SHIP", function() end, false)
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
                        end, true)
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
                        orderMessage = "ORDER STATUS: SUBMITTED — X4 ACCEPTED TASK " .. text(orderState.task) .. ". EOC has finished this one-shot order and locked this station-and-cargo need against every hull size. The player-owned shipyard now handles normal resource delivery and construction scheduling; no further EOC action is required."
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

    if menu.diagnosticView == "recovery" then
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
            row[1]:setColSpan(4):createText("No critical or warning recovery case is active for this station. Continue monitoring or choose another case.", { wordwrap = true })
            return
        end

        local diagnosticChecks = prerequisiteRows(diagnosticCase)
        local firstProblem = nil
        for _, check in ipairs(diagnosticChecks) do
            if not firstProblem and (check.state == "FAIL" or check.state == "UNKNOWN") then firstProblem = check end
        end
        local nextAction = manualNextAction(diagnosticCase, diagnosticChecks)

        section(tableWidget, "STEP 1 OF 3 — WHAT FAILED FIRST")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and (firstProblem.state .. " — " .. firstProblem.label) or "PASS — ALL REPORTED PREREQUISITES", { wordwrap = true })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(firstProblem and ("EVIDENCE: " .. firstProblem.evidence) or "EVIDENCE: No failed or unknown prerequisite was returned.", { wordwrap = true })

        section(tableWidget, "STEP 2 OF 3 — DO THIS NOW")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(nextAction, { wordwrap = true })
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("PLAYER CONTROL: EOC will not cancel or replace trader orders, move credits, or alter station configuration. Complete this action manually.", { wordwrap = true })

        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "VIEW SUPPORTING EVIDENCE", function() menu.diagnosticView = "supplier"; menu.refresh() end, true)
        row[3]:setColSpan(2)
        addButton(row, 3, "ACTION COMPLETE — GO TO VERIFY RESULT", function() menu.diagnosticView = "stabilization"; menu.refresh() end, true)

        section(tableWidget, "STEP 3 OF 3 — VERIFY AFTER THE ACTION")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("After completing the player action, open Verify Result and run one fresh analysis. EOC will report RESOLVED, IMPROVING, UNCHANGED, or WORSENING.", { wordwrap = true })
    elseif menu.diagnosticView == "supplier" then
        section(tableWidget, "SUPPORTING EVIDENCE: " .. (diagnosticCase and text(v(diagnosticCase, 4, "SELECTED CASE")) or "NO CASE SELECTED"))
        if diagnosticCase then
            local detailChecks = prerequisiteRows(diagnosticCase)
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("EVIDENCE SNAPSHOT: Values came from " .. (menu.lastUpdated and ("the EOC analysis at " .. menu.lastUpdated) or "the last EOC analysis") .. ". Run Verify Result to refresh and compare it.", { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("ROOT CAUSE: " .. text(v(diagnosticCase, 6, "Evidence requires review.")), { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CURRENT STOCK: " .. formatNumber(v(diagnosticCase, 8, 0)) .. " | TARGET: " .. formatNumber(v(diagnosticCase, 9, 0)) .. " | MAXIMUM: " .. formatNumber(v(diagnosticCase, 10, 0)) .. " | STATION FUNDS: " .. formatNumber(v(diagnosticCase, 32, 0)) .. " Cr", { wordwrap = true })
            section(tableWidget, "PREREQUISITE RESULTS — PASS / FAIL / UNKNOWN")
            for _, check in ipairs(detailChecks) do
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText(check.state .. " — " .. check.label .. ": " .. check.evidence, { wordwrap = true })
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
        end, not actionState("analysis.run").running)
        row[3]:setColSpan(2)
        addButton(row, 3, "RETURN TO GUIDED RECOVERY", function() menu.diagnosticView = "recovery"; menu.refresh() end, true)
        if menu.verificationKey == verificationKey then
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("CASE VERIFICATION: " .. text(menu.verificationClass, "UNKNOWN") .. "\n" .. text(menu.verificationResult) .. "\nWORKING CASE: " .. stationName .. " -> " .. diagnosticSubject, { wordwrap = true })
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

    if diagnosticCase and menu.diagnosticView ~= "recovery" then
        section(tableWidget, "OPTIONAL ROUTES")
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, "OPEN SELECTED STATION - RETURN TO DIAGNOSTICS", function()
            captureNavigation("DIAGNOSTICS - " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
            menu.page = "stations"
            menu.activeTab = "stations"
            menu.refresh()
        end, true)
        row[3]:setColSpan(2)
        addButton(row, 3, "OPEN FLEET & LOGISTICS - RETURN TO DIAGNOSTICS", function()
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

local function kpiCenter(tableWidget)
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

    for rank = 1, math.min(#rows, 10) do
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
local function dashboard(tableWidget)
    section(tableWidget, "EXECUTIVE INTELLIGENCE OVERVIEW")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("START HERE: EOC states the empire finding, then gives one next action. Detailed messages remain below only as supporting evidence.", { wordwrap = true })
    section(tableWidget, "EOC CONCLUSION")
    local conclusion = tonumber(v(menu.summary, 12, 0)) > 0 and
        (formatNumber(v(menu.summary, 12, 0)) .. " station(s) require attention.") or
        "No station currently requires player action."
    local conclusionRow = tableWidget:addRow(false)
    conclusionRow[1]:setColSpan(4):createText(conclusion .. " Empire health is " .. text(v(menu.summary, 1, 0)) .. "/100 and trend is " .. text(v(menu.summary, 2, "STABLE")) .. ".", { wordwrap = true })
    local nextRow = tableWidget:addRow(false)
    nextRow[1]:setColSpan(4):createText(tonumber(v(menu.summary, 12, 0)) > 0 and "DO THIS NEXT: Open Stations Requiring Action." or "DO THIS NEXT: Continue normal operations. Analyze again after a meaningful change or delivery cycle.", { wordwrap = true })
    pair(tableWidget, "STATUS", menu.analysisRunning and "ANALYSIS RUNNING" or (menu.analysisStatus or "READY"), "LAST ANALYSIS", menu.lastUpdated or "NOT RUN THIS SESSION")

    local actionRow = tableWidget:addRow(true)
    actionRow[1]:setColSpan(4)
    addButton(
        actionRow,
        1,
        "VIEW STATIONS REQUIRING ACTION",
        openCasesCenter,
        #(menu.cases or {}) > 0
    )

    section(tableWidget, "WHAT CHANGED?")
    pair(tableWidget, "New Issues", v(menu.summary, 13, 0), "Resolved", v(menu.summary, 14, 0))
    pair(tableWidget, "Worsening", v(menu.summary, 15, 0), "Improving", v(menu.summary, 16, 0))

    section(tableWidget, "EXECUTIVE INBOX")
    if #menu.inbox == 0 then
        pair(tableWidget, "INFO", "No executive messages yet", "", "")
    else
        for index = 1, math.min(#menu.inbox, 8) do
            local message = menu.inbox[index]
            pair(tableWidget, text(v(message, 1, "UPDATE")), v(message, 2, ""), "", "")
        end
    end

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(
        row,
        1,
        menu.analysisRunning and "ANALYSIS RUNNING" or "ACTION: ANALYZE NOW",
        function()
            if not menu.analysisRunning then
                menu.analysisRunning = true
                menu.analysisStatus = "ANALYSIS RUNNING"
                menu.refresh()
                raise("analysis.run", {})
            end
        end,
        not menu.analysisRunning
    )
    row[3]:setColSpan(2)
    addButton(row, 3, menu.reportStatus or "GENERATE REPORT: EMPIRE EXECUTIVE", function()
        captureReportOrigin("dashboard", "OVERVIEW")
        menu.pendingReport = "EMPIRE EXECUTIVE"
        raise("report.empire", {})
    end, true)

    row = tableWidget:addRow(false)
    row[1]:setColSpan(2):createText(menu.analysisOutput, {
        wordwrap = true,
        x = Helper.borderSize,
        y = Helper.borderSize,
    })
    row[3]:setColSpan(2):createText(menu.reportOutput, {
        wordwrap = true,
        x = Helper.borderSize,
        y = Helper.borderSize,
    })
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
            row[2]:createText(text(v(station, 2, "UNDEFINED")), {
                fontsize = Helper.standardFontSize - 1,
            })
            row[3]:createText(text(v(station, 3, "MONITORING")), {
                fontsize = Helper.standardFontSize - 1,
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
    section(tableWidget, "ROLE CONTROL")

    for roleIndex = 1, #roles, 4 do
        local row = tableWidget:addRow(true)
        for column = 1, 4 do
            local role = roles[roleIndex + column - 1]
            if role then
                local stationIndex = v(station, 16, menu.selected)
                local confirming = menu.pendingRole and menu.pendingRole.index == stationIndex and menu.pendingRole.role == role
                addButton(row, column, confirming and ("CONFIRM: " .. role) or role, function()
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
                end, true)
            end
        end
    end

    if menu.roleConfirmation then
        local confirmRow = tableWidget:addRow(false)
        confirmRow[1]:setColSpan(4):createText(menu.roleConfirmation, { wordwrap = true })
    end
    actionResult(tableWidget, "station.role", "Role changes require two deliberate clicks. The first click previews; the second confirms.")

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
        "Assigns roles only to player stations that are currently undefined."
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
        "FIRST CASE TO HANDLE: " .. text(v(case, 4, "GENERAL OPERATIONS")) .. " — " .. text(v(case, 2, "ISSUE")) .. ". " ..
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

    section(tableWidget, "OPERATION ACTIONS")
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
        "Checks EOC-owned trade offers; Managed mode may create, verify, or remove them."
    )
    actionResult(
        tableWidget,
        "shipping.scan",
        "Checks logistics needs and registered ships; Auto mode may assign a compatible ship."
    )
    actionResult(
        tableWidget,
        "analysis.run",
        "Refreshes EOC intelligence and recommendations; it does not authorize new operations."
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
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("START HERE: EOC shows the first case this station needs handled. Open Cases for the guided action; use the remaining controls only when you intentionally want to change station policy or authority.", { wordwrap = true })

    if not station then
        pair(tableWidget, "INFO", "No station selected", "", "")
        return
    end

    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(text(v(station, 1, "Station")), {
        font = Helper.headerFont,
        fontsize = Helper.standardFontSize + 2,
    })
    pair(tableWidget, "Current Role", v(station, 2, "UNDEFINED"), "Priority", v(station, 6, "NOTE"))
    pair(tableWidget, "Health", v(station, 3, "MONITORING"), "Trend", v(station, 4, "STABLE"))
    pair(tableWidget, "Issues", v(station, 8, 0), "Assigned Ships", v(station, 9, 0))
    pair(tableWidget, "Miners", v(station, 10, 0), "Traders", v(station, 11, 0))

    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(
        "RECOMMENDATION: " .. text(v(station, 7, "No recommendation")),
        { wordwrap = true }
    )


    addStationIssues(tableWidget, station)

    section(tableWidget, "CONTEXTUAL NAVIGATION")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "OPEN CASES - RETURN TO STATION", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.caseScope = "station"
        menu.caseSeverity = "all"
        menu.selectedCase = 1
        menu.casePage = 1
        menu.page = "cases"
        menu.activeTab = "cases"
        menu.refresh()
    end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "OPEN DIAGNOSTICS - RETURN TO STATION", function()
        captureNavigation("STATIONS - " .. text(v(station, 1, "SELECTED STATION")))
        menu.diagnosticView = "recovery"
        menu.page = "diagnostics"
        menu.activeTab = "diagnostics"
        menu.refresh()
    end, true)

    addRoleControls(tableWidget, station)

    section(tableWidget, "EOC OPERATING POLICY - CHANGES EOC RECOMMENDATION BEHAVIOR")
    pair(tableWidget, "CURRENT POLICY", menu.stabilizationGoal, "FORMAL STATION ROLE", v(station, 2, "UNDEFINED") .. " (not changed here)")
    local policies = {
        { "MARKET-SUPPORTED", "MARKET-SUPPORTED STABILIZATION" },
        { "SELF-SUFFICIENT", "SELF-SUFFICIENT STABILIZATION" },
        { "BALANCED / LEAST-COST", "BALANCED / LEAST-COST STABILIZATION" },
        { "OBSERVE AND ADVISE", "OBSERVE AND ADVISE ONLY" },
    }
    row = tableWidget:addRow(true)
    for column, policy in ipairs(policies) do
        local label, goal = policy[1], policy[2]
        local stationIndex = v(station, 16, menu.selected)
        local confirming = menu.pendingPolicy and menu.pendingPolicy.index == stationIndex and menu.pendingPolicy.goal == goal
        addButton(row, column, confirming and ("CONFIRM POLICY: " .. label) or label, function()
            if not confirming then
                menu.pendingPolicy = { index = stationIndex, goal = goal }
                menu.policyConfirmation = "PREVIEW ONLY: Change EOC policy for " .. text(v(station, 1, "this station")) .. " from " .. text(menu.stabilizationGoal) .. " to " .. goal .. ". This changes EOC recommendations, not the formal station role. Click CONFIRM POLICY to apply."
                menu.refresh()
                return
            end
            if not startAction("diagnostics.goal") then return end
            menu.pendingPolicy = nil
            menu.policyConfirmation = nil
            menu.stabilizationGoal = goal
            raise("diagnostics.goal", { index = stationIndex, goal = goal })
            menu.refresh()
        end, true)
    end
    if menu.policyConfirmation then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(menu.policyConfirmation, { wordwrap = true })
    end
    actionResult(tableWidget, "diagnostics.goal", "Policy changes require preview and confirmation. They alter EOC recommendations but never change the formal station role.")

    addOperationsControls(tableWidget)
    addReportsControls(tableWidget)
end

local function globalSettings(tableWidget)
    section(tableWidget, "GLOBAL EOC SETTINGS")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("CHANGE ONLY WHAT YOU INTEND: These settings grant EOC operating authority. They never buy ships, move station money, change construction, or cancel ordinary player orders.", { wordwrap = true })
    pair(tableWidget, "Trade Order Control", menu.mode, "Ship Assignment Authority", menu.shipmode)
    if menu.settingsStatus then
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:setColSpan(4):createText(menu.settingsStatus, { wordwrap = true })
    end

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

        if menu.page == "dashboard" then
            dashboard(tableWidget)
        elseif menu.page == "kpi" then
            kpiCenter(tableWidget)
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

    menu.frame:display()
end

function menu.refresh()
    menu.create()
end

function menu.onCloseElement(reason, layer)
    raise("closed", { reason = reason or "close" })
    Helper.closeMenu(menu, reason or "close", layer)
    menu.frame = nil
end

function menu.onUpdate()
    local now = getElapsedTime()

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
