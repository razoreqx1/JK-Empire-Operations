---@diagnostic disable: undefined-global, undefined-field

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
    local message = state.result and ("STATUS: RESULT READY — " .. state.result) or purpose
    row[1]:setColSpan(4):createText(message, { wordwrap = true })
    if state.result and actionNextSteps[action] then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("NEXT STEP: " .. actionNextSteps[action], { wordwrap = true })
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
    if not logisticsCase then
        add("STORAGE INSTALLED", capacity > 0 and "PASS" or "FAIL", text(v(caseData, 12, "UNKNOWN")) .. " capacity " .. formatNumber(capacity))
        add("STORAGE FREE SPACE", capacity <= 0 and "UNKNOWN" or (free > 0 and "PASS" or "FAIL"), formatNumber(free) .. " free")
    end
    if supplyCase then
        local suppliers = tonumber(v(caseData, 18, 0)) or 0
        add("REACHABLE SUPPLY", suppliers > 0 and "PASS" or "FAIL", suppliers .. " offers: own " .. text(v(caseData, 19, 0)) .. ", NPC " .. text(v(caseData, 20, 0)) .. "; NPC price " .. text(v(caseData, 21, 0)) .. "–" .. text(v(caseData, 22, 0)) .. " Cr")
    end
    if supplyCase or logisticsCase then
        local traders, compatible = tonumber(v(caseData, 23, 0)) or 0, tonumber(v(caseData, 24, 0)) or 0
        add("STATION TRADER", compatible > 0 and "PASS" or "FAIL", traders .. " assigned; " .. compatible .. " compatible")
    end
    if supplyCase then
        local produces, paused = tonumber(v(caseData, 15, 0)) or 0, v(caseData, 29, false)
        add("LOCAL PRODUCTION", produces > 0 and (paused and "FAIL" or "PASS") or "UNKNOWN", produces > 0 and (paused and "production is paused" or text(v(caseData, 16, 0)) .. " module(s)") or "ware is not produced locally")
        local missing = tonumber(v(caseData, 27, 0)) or 0
        add("PRODUCTION INPUTS", produces == 0 and "UNKNOWN" or (missing == 0 and "PASS" or "FAIL"), missing > 0 and text(v(caseData, 28, "missing input unnamed")) or text(v(caseData, 26, "no missing input reported")))
    end
    if #rows == 0 then add("CASE EVIDENCE", "UNKNOWN", "No family-specific prerequisite set is available; follow the case root cause and manual action.") end
    return rows
end
local function manualNextAction(caseData, rows)
    for _, check in ipairs(rows) do
        if check.state ~= "PASS" then
            if check.label == "STORAGE INSTALLED" then return "Open the Station Build Plan and add compatible " .. text(v(caseData, 12, "cargo")) .. " storage; wait until it is operational."
            elseif check.label == "STORAGE FREE SPACE" then return "Move or sell stock to create free " .. text(v(caseData, 12, "cargo")) .. " storage space."
            elseif check.label == "REACHABLE SUPPLY" then return "Open the station buy offer for " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " and verify trade rule, price, and manager range permit a supplier."
            elseif check.label == "STATION TRADER" then return "Assign one operational trader compatible with " .. text(v(caseData, 17, v(caseData, 4, "the required ware"))) .. " to " .. text(v(caseData, 1, "the station")) .. "."
            elseif check.label == "LOCAL PRODUCTION" and v(caseData, 29, false) then return "Resume the paused local production module for " .. text(v(caseData, 4, "the affected ware")) .. "."
            elseif check.label == "PRODUCTION INPUTS" then return "Restore the confirmed missing production input: " .. text(v(caseData, 28, "review station inputs")) .. "." end
        end
    end
    return text(v(caseData, 7, "Make the smallest manual correction shown by the case, then verify again."))
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
    DebugError("[JKEOC][GA19][LUA_ERROR] Helper.registerMenu unavailable")
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
    if string.find(label, "GENERATE REPORT", 1, true) == 1 and menu.reportRunning then
        properties.active = false
    end
    if menu.lastClickedLabel == label and menu.clickStatusUntil and getElapsedTime() < menu.clickStatusUntil then
        properties.bgColor = selectedModeBackground
    end
    row[column]:createButton(properties):setText(label)
    row[column].handlers.onClick = function()
        acknowledgeClick(label)
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
        addButton(row, 1, text(v(caseData, 1, "Unknown station")), function()
            menu.selectedCase = caseIndex
            focusCaseStation(caseData)
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
    section(tableWidget, "CASE DETAILS: " .. text(v(selected, 1, "Unknown station")))
    pair(tableWidget, "SEVERITY", v(selected, 2, "ISSUE"), "STATE", v(selected, 5, "OPEN"))
    pair(tableWidget, "CASE TYPE", v(selected, 3, "STATION ISSUE"), "SUBJECT", v(selected, 4, "GENERAL OPERATIONS"))

    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("ROOT CAUSE: " .. text(v(selected, 6, "Evidence requires review")), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("RECOMMENDED ACTION: " .. text(v(selected, 7, "Review the station recommendation")), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("EVIDENCE: current " .. formatNumber(v(selected, 8, 0)) .. "; target " .. formatNumber(v(selected, 9, 0)) .. "; capacity " .. formatNumber(v(selected, 10, 0)) .. "; immediate need " .. formatNumber(v(selected, 30, 0)) .. "; target shortfall " .. formatNumber(v(selected, 31, 0)) .. "; station funds " .. formatNumber(v(selected, 32, 0)) .. " Cr.", { wordwrap = true })
    local checks = prerequisiteRows(selected)
    section(tableWidget, "CASE PREREQUISITES — PASS / FAIL / UNKNOWN")
    local firstProblem = nil
    for _, check in ipairs(checks) do
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(check.state .. " — " .. check.label .. ": " .. check.evidence, { wordwrap = true })
        if not firstProblem and check.state ~= "PASS" then firstProblem = check end
    end
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("FIRST FAILED OR UNKNOWN CHECK: " .. (firstProblem and (firstProblem.state .. " — " .. firstProblem.label .. ": " .. firstProblem.evidence) or "NONE — all reported prerequisites pass."), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("NEXT PLAYER ACTION: " .. manualNextAction(selected, checks), { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("SUPPLY ACTION SAFETY: EOC will not cancel or replace a trader's orders. Perform the action manually, then run verification.", { wordwrap = true })
    local playbook = casePlaybook(selected)
    section(tableWidget, "PLAYER ACTION PATH: " .. playbook.family)
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("WHY THIS MATTERS: " .. playbook.impact, { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("INVESTIGATE: " .. playbook.investigate, { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("PLAYER ACTION: " .. playbook.player, { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("AUTHORITY: " .. playbook.authority, { wordwrap = true })
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText("VERIFICATION: " .. playbook.verify, { wordwrap = true })

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "INVESTIGATE ROOT CAUSE: " .. text(v(selected, 4, "SELECTED CASE")), function()
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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: This screen explains whether EOC found a station need, a compatible ship, an approval requirement, or a capability gap. Automatic modes act only within the authority shown below.", { wordwrap = true })
    pair(tableWidget, "ASSIGNMENT MODE", menu.shipmode, "TRADE ORDER MODE", menu.mode)
    pair(tableWidget, "REGISTERED AVAILABLE SHIPS", #menu.registeredShips, "EOC-OWNED TRADE OFFERS", #menu.tradeOffers)
    pair(tableWidget, "PENDING ASSIGNMENTS", #menu.pendingAssignments, "PLAYER STATIONS", #menu.stations)
    local fleetScopeLabel = menu.fleetScope == "global" and "EMPIRE - ALL STATIONS" or
        ("SELECTED STATION - " .. stationName)
    local fleetViewLabels = {
        stations = "STATIONS",
        ships = "REGISTERED AVAILABLE SHIPS",
        offers = "EOC-OWNED TRADE OFFERS",
        pending = "PENDING ASSIGNMENTS",
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
    row[1]:setColSpan(4)
    addButton(row, 1, "CLEAR FILTERS", function()
        menu.fleetScope = "global"
        menu.fleetPage = 1
        menu.refresh()
    end, menu.fleetScope ~= "global")

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
        }
        local statusRow = tableWidget:addRow(false)
        statusRow[1]:createText("STATUS")
        statusRow[2]:setColSpan(3):createText(emptyMessages[menu.fleetView], { wordwrap = true })
    else
        local first = (menu.fleetPage - 1) * pageSize + 1
        local last = math.min(first + pageSize - 1, #entries)
        for index = first, last do
            local entry = entries[index]
            pair(tableWidget, entry[1], entry[2], entry[3], entry[4])
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

    section(tableWidget, "EOC DIAGNOSTICS CENTER")
    local brief = tableWidget:addRow(false)
    brief[1]:setColSpan(4):createText("DECISION BRIEF: Diagnose the selected station, follow the evidence chain, perform the smallest supported test, then rerun analysis so EOC can verify the result. NAVIGATION DOES NOT EXECUTE A CHECK; only buttons beginning PROBE, PROOF, VERIFY, or RUN submit work.", { wordwrap = true })
    pair(tableWidget, "SELECTED STATION", stationName, "ACTIVE CASES", #cases)
    if diagnosticCase then
        section(tableWidget, "WORKING CASE: " .. stationName .. " -> " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
        local contextRow = tableWidget:addRow(false)
        contextRow[1]:setColSpan(4):createText("CURRENT STEP: Follow the evidence checklist.  NEXT: perform the first failed check, then verify recovery with a fresh analysis.", { wordwrap = true })
    end
    pair(tableWidget, "EOC OPERATING POLICY", menu.stabilizationGoal, "BOUNDED FINDINGS", menu.stabilizationFindings)

    local row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.diagnosticView == "recovery" and "ACTIVE: " or "") .. "GUIDED RECOVERY", menu.diagnosticView == "recovery", true, function()
        menu.diagnosticView = "recovery"
        menu.refresh()
    end)
    addModeButton(row, 2, (menu.diagnosticView == "supplier" and "ACTIVE: " or "") .. "SUPPLIER CHECKLIST", menu.diagnosticView == "supplier", true, function()
        menu.diagnosticView = "supplier"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, (menu.diagnosticView == "stabilization" and "ACTIVE: " or "") .. "VERIFY RECOVERY", menu.diagnosticView == "stabilization", true, function()
        menu.diagnosticView = "stabilization"
        menu.refresh()
    end)

    if menu.diagnosticView == "recovery" then
        section(tableWidget, "STATION INTELLIGENCE AND GUIDED RECOVERY")
        if not station then
            pair(tableWidget, "STATUS", "No player station is selected.", "ACTION", "Select a station on the Stations tab, then return here.")
            local routeRow = tableWidget:addRow(true)
            routeRow[1]:setColSpan(4)
            addButton(routeRow, 1, "GO TO STATIONS - RETURN TO DIAGNOSTICS", function()
                captureNavigation("DIAGNOSTICS")
                menu.page = "stations"
                menu.activeTab = "stations"
                menu.refresh()
            end, true)
            return
        end
        pair(tableWidget, "HEALTH", v(station, 3, "MONITORING"), "TREND", v(station, 4, "STABLE"))
        pair(tableWidget, "ROLE", v(station, 2, "UNDEFINED"), "PRIORITY", v(station, 6, "NOTE"))
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("CURRENT RECOMMENDATION: " .. text(v(station, 7, "No recommendation is currently available.")), { wordwrap = true })
        if diagnosticCase and diagnosticPlaybook then
            section(tableWidget, "FOCUSED INVESTIGATION: " .. text(v(diagnosticCase, 4, "SELECTED CASE")))
            pair(tableWidget, "ISSUE FAMILY", diagnosticPlaybook.family, "SOURCE", v(diagnosticCase, 11, "EOC-CONFIRMED"))
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("WHY THIS MATTERS: " .. diagnosticPlaybook.impact, { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("ROOT-CAUSE PATH: " .. diagnosticPlaybook.investigate, { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("WHAT THE PLAYER DOES: " .. diagnosticPlaybook.player, { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("WHAT EOC MAY DO: " .. diagnosticPlaybook.authority, { wordwrap = true })
            row = tableWidget:addRow(false)
            row[1]:setColSpan(4):createText("PROOF OF RECOVERY: " .. diagnosticPlaybook.verify, { wordwrap = true })
        end
        if #cases == 0 then
            pair(tableWidget, "STATUS", "No critical or warning recovery case is active for this station.", "ACTION", "Continue monitoring and refresh analysis when conditions change.")
        else
            for index, case in ipairs(cases) do
                section(tableWidget, "RECOVERY CASE " .. index .. ": " .. text(v(case, 4, "GENERAL OPERATIONS")))
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText("ROOT CAUSE: " .. text(v(case, 6, "Evidence requires review.")), { wordwrap = true })
                row = tableWidget:addRow(false)
                row[1]:setColSpan(4):createText("NEXT RECOVERY STEP: " .. text(v(case, 7, "Review the station recommendation and supporting evidence.")), { wordwrap = true })
                pair(tableWidget, "CURRENT EVIDENCE", formatNumber(v(case, 8, 0)), "TARGET / CAPACITY", formatNumber(v(case, 9, 0)) .. " / " .. formatNumber(v(case, 10, 0)))
            end
        end
        section(tableWidget, "DELIVERY RECOVERY CHECKLIST")
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(
            "1. Confirm an active buy offer exists for the required ware and requests more than zero units.\n" ..
            "2. Confirm the correct storage type is allocated and has free capacity.\n" ..
            "3. Confirm the buy-offer trade rule allows the intended supplier.\n" ..
            "4. Confirm manager skill and gate range can reach that supplier.\n" ..
            "5. Confirm an assigned trader is available and supports the required cargo type.\n" ..
            "6. Confirm a reachable supplier has stock available at an acceptable price.",
            { wordwrap = true }
        )
    elseif menu.diagnosticView == "supplier" then
        section(tableWidget, "SUPPLIER CHECKLIST: " .. (diagnosticCase and text(v(diagnosticCase, 4, "SELECTED WARE")) or "NO CASE SELECTED"))
        if diagnosticCase then
            pair(tableWidget, "STATION", stationName, "SUPPLIER EVIDENCE", "Known sell offers exist; individual supplier names are unavailable in the current evidence payload.")
        end
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(
            "Use this sequence for the ware identified by the selected station case.\n\n" ..
            "CHECK 1: Identify the intended supplier and confirm it has an active sell offer for the ware.\n" ..
            "CHECK 2: Confirm the supplier produces the ware locally and its production modules are operational.\n" ..
            "CHECK 3: Confirm the supplier has every required production input and none is critically low.\n" ..
            "CHECK 4: Test a small manual transfer to verify the destination storage and production path.\n\n" ..
            "Return to Guided Recovery after completing these checks and compare the result with the current case evidence.",
            { wordwrap = true }
        )
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
        row[1]:setColSpan(4):createText("The requested diagnostics view is unavailable. Select Guided Recovery, Supplier Checklist, or Verify Recovery.", { wordwrap = true })
    end

    if diagnosticCase then
        section(tableWidget, "INVESTIGATION ROUTES")
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
        addButton(row, 1, menu.diagnosticView == "supplier" and "RETURN TO GUIDED RECOVERY" or "OPEN SUPPLIER CHECKLIST", function()
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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: Rankings prioritize review; they do not prove root cause or authorize action. Open the station, its cases, or diagnostics for evidence and an executable next step.", { wordwrap = true })
    pair(tableWidget, "EMPIRE HEALTH", v(menu.summary, 1, 0), "DIRECTION", v(menu.summary, 2, "STABLE"))
    pair(tableWidget, "PLAYER STATIONS", #rows, "REQUIRE ATTENTION", counts.CRITICAL + counts.WARNING)
    pair(tableWidget, "CRITICAL", counts.CRITICAL, "WARNING", counts.WARNING)
    pair(tableWidget, "WATCH", counts.WATCH, "HEALTHY", counts.HEALTHY)

    local pulse = tableWidget:addRow(false)
    pulse[1]:setColSpan(4):createText(
        "EMPIRE PULSE: " .. counts.CRITICAL .. " critical | " .. counts.WARNING .. " warning | " ..
        counts.WATCH .. " watch | " .. counts.HEALTHY .. " healthy. Highest attention score appears first.",
        { wordwrap = true }
    )

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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: Start here to see what changed, what requires player attention, and what EOC handled. Open stations requiring action for evidence and next steps.", { wordwrap = true })
    pair(
        tableWidget,
        "STATUS",
        menu.analysisRunning and "ANALYSIS RUNNING" or (menu.analysisStatus or "READY"),
        "LAST UPDATED",
        menu.lastUpdated or "NOT RUN THIS SESSION"
    )
    pair(tableWidget, "Empire Health", v(menu.summary, 1, 0), "Trend", v(menu.summary, 2, "STABLE"))
    pair(tableWidget, "Economy", v(menu.summary, 3, 0), "Logistics", v(menu.summary, 4, 0))
    pair(tableWidget, "Workforce", v(menu.summary, 5, 0), "Defense", v(menu.summary, 6, 0))
    pair(tableWidget, "Growth", v(menu.summary, 7, 0), "Ship Utilization", v(menu.summary, 10, 0))
    pair(tableWidget, "Stations", v(menu.summary, 8, #menu.stations), "Productive", v(menu.summary, 9, 0))
    pair(tableWidget, "Active Cases", v(menu.summary, 11, 0), "Require Attention", v(menu.summary, 12, 0))

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
    section(tableWidget, "ACTIVE ISSUES  |  " .. #cases)

    if #cases == 0 then
        pair(
            tableWidget,
            "STATUS",
            "No critical or warning case currently requires player action.",
            "NEXT STEP",
            "Continue monitoring."
        )
        return
    end

    for index, case in ipairs(cases) do
        section(
            tableWidget,
            text(v(case, 2, "ISSUE")) .. " " .. index .. " — " .. text(v(case, 4, "GENERAL OPERATIONS"))
        )
        pair(
            tableWidget,
            "CASE TYPE",
            v(case, 3, "STATION ISSUE"),
            "STATE",
            v(case, 5, "OPEN")
        )

        local row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(
            "ROOT CAUSE: " .. text(v(case, 6, "Evidence requires review")),
            { wordwrap = true }
        )

        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText(
            "RECOMMENDED ACTION: " .. text(v(case, 7, "Review the station recommendation")),
            { wordwrap = true }
        )

        local amount = tonumber(v(case, 8, 0)) or 0
        local target = tonumber(v(case, 9, 0)) or 0
        local maximum = tonumber(v(case, 10, 0)) or 0
        if amount ~= 0 or target ~= 0 or maximum ~= 0 then
            pair(
                tableWidget,
                "EVIDENCE — CURRENT",
                amount,
                "TARGET / CAPACITY",
                tostring(target) .. " / " .. tostring(maximum)
            )
        end
    end
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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: Reports preserve evidence and decisions. Use the contextual Return button to resume the workflow that generated the report.", { wordwrap = true })
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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: This workspace reconciles the station profile with its actionable cases, shows EOC evidence, and routes to Cases or Diagnostics with a return path.", { wordwrap = true })

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

    section(tableWidget, "STATUS GUIDE")
    row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(
        "MONITORING: stable; EOC is watching.  TRANSIENT: recent condition awaiting confirmation.  " ..
        "RECURRING: repeated issue; review recommended.  CHRONIC: persistent serious issue; action recommended.  " ..
        "RELAPSED: a previously improved issue returned.  CRITICAL: immediate review recommended.",
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
    brief[1]:setColSpan(4):createText("DECISION BRIEF: These controls define EOC authority. Managed Trade maintains EOC-owned offers; Auto-Assign uses only eligible registered ships. Neither mode buys ships, transfers station funds, changes construction, or resolves every case.", { wordwrap = true })
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
