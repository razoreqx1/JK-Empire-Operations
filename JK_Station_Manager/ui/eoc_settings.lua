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
}

local function actionResult(tableWidget, action, purpose)
    local state = actionState(action)
    local row = tableWidget:addRow(false)
    local message = state.result and ("STATUS: " .. state.result) or purpose
    row[1]:setColSpan(4):createText(message, { wordwrap = true })
    if state.result and actionNextSteps[action] then
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("NEXT STEP: " .. actionNextSteps[action], { wordwrap = true })
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
    DebugError("[JKEOC][GA17][LUA_ERROR] Helper.registerMenu unavailable")
    end

    AddUITriggeredEvent(menu.name, "INIT", nil)
    RegisterEvent(menu.name .. ".INIT", menu.PrepareMenuData)
    RegisterEvent(menu.name .. ".analysis.complete", analysisComplete)
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
    menu.caseScope = menu.caseScope or "global"
    menu.caseSeverity = menu.caseSeverity or "all"
    menu.selectedCase = clamp(menu.selectedCase or 1, 1, math.max(1, #menu.cases))
    menu.casePage = math.max(1, tonumber(menu.casePage) or 1)
    menu.fleetScope = menu.fleetScope or "global"
    menu.fleetView = menu.fleetView or "stations"
    menu.fleetPage = math.max(1, tonumber(menu.fleetPage) or 1)
    menu.diagnosticView = menu.diagnosticView or "recovery"
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

local function captureNavigation(label)
    menu.navigationOrigin = {
        page = menu.page,
        activeTab = menu.activeTab,
        label = label,
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
end

local function restoreNavigation()
    local origin = menu.navigationOrigin
    if not origin then
        return
    end
    menu.selected = origin.selected or menu.selected
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
    menu.navigationOrigin = nil
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
    local tableWidget = frame:addTable(7, {
        tabOrder = 1,
        x = Helper.borderSize,
        y = Helper.borderSize,
        width = usableWidth,
        borderEnabled = true,
    })
    local columnWidth = math.floor(usableWidth / 7)

    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setColWidth(4, columnWidth, false)
    tableWidget:setColWidth(5, columnWidth, false)
    tableWidget:setColWidth(6, columnWidth, false)

    local row = tableWidget:addRow(false, { fixed = true })
    row[1]:setColSpan(7):createText(menu.title, {
        halign = "center",
        font = Helper.titleFont,
        fontsize = Helper.standardFontSize + 4,
    })

    row = tableWidget:addRow(true, { fixed = true })
    addTabButton(row, 1, "STATIONS", "stations")
    addTabButton(row, 2, "OVERVIEW", "dashboard")
    addTabButton(row, 3, "FLEET & LOGISTICS", "fleet")
    addTabButton(row, 4, "DIAGNOSTICS", "diagnostics")
    addTabButton(row, 5, "CASES", "cases")
    addTabButton(row, 6, "REPORTS", "reports")
    addTabButton(row, 7, "GLOBAL SETTINGS", "settings")

    local activeColumns = {
        stations = 1,
        dashboard = 2,
        fleet = 3,
        diagnostics = 4,
        cases = 5,
        reports = 6,
        settings = 7,
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
    pair(tableWidget, "EVIDENCE - CURRENT", formatNumber(v(selected, 8, 0)), "TARGET / CAPACITY", formatNumber(v(selected, 9, 0)) .. " / " .. formatNumber(v(selected, 10, 0)))

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

    section(tableWidget, "EOC DIAGNOSTICS CENTER")
    pair(tableWidget, "SELECTED STATION", stationName, "ACTIVE CASES", #cases)
    pair(tableWidget, "STABILIZATION GOAL", menu.stabilizationGoal, "BOUNDED FINDINGS", menu.stabilizationFindings)

    local row = tableWidget:addRow(true)
    addModeButton(row, 1, (menu.diagnosticView == "recovery" and "ACTIVE: " or "") .. "GUIDED RECOVERY", menu.diagnosticView == "recovery", true, function()
        menu.diagnosticView = "recovery"
        menu.refresh()
    end)
    addModeButton(row, 2, (menu.diagnosticView == "supplier" and "ACTIVE: " or "") .. "SUPPLIER DIAGNOSTICS", menu.diagnosticView == "supplier", true, function()
        menu.diagnosticView = "supplier"
        menu.refresh()
    end)
    addModeButton(row, 3, (menu.diagnosticView == "stabilization" and "ACTIVE: " or "") .. "STABILIZATION", menu.diagnosticView == "stabilization", true, function()
        menu.diagnosticView = "stabilization"
        menu.refresh()
    end)
    addModeButton(row, 4, (menu.diagnosticView == "engineering" and "ACTIVE: " or "") .. "ENGINEERING TOOLS", menu.diagnosticView == "engineering", true, function()
        menu.diagnosticView = "engineering"
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
        section(tableWidget, "UPSTREAM SUPPLIER DIAGNOSTICS")
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
        section(tableWidget, "STABILIZATION OPERATING GOAL")
        row = tableWidget:addRow(true)
        addModeButton(row, 1, "MARKET-SUPPORTED", menu.stabilizationGoal == "MARKET-SUPPORTED STABILIZATION", true, function()
            if startAction("diagnostics.goal") then
                menu.stabilizationGoal = "MARKET-SUPPORTED STABILIZATION"
                raise("diagnostics.goal", { index = v(station, 16, 0), goal = menu.stabilizationGoal })
            end
        end)
        addModeButton(row, 2, "SELF-SUFFICIENT", menu.stabilizationGoal == "SELF-SUFFICIENT STABILIZATION", true, function()
            if startAction("diagnostics.goal") then
                menu.stabilizationGoal = "SELF-SUFFICIENT STABILIZATION"
                raise("diagnostics.goal", { index = v(station, 16, 0), goal = menu.stabilizationGoal })
            end
        end)
        addModeButton(row, 3, "BALANCED / LEAST-COST", menu.stabilizationGoal == "BALANCED / LEAST-COST STABILIZATION", true, function()
            if startAction("diagnostics.goal") then
                menu.stabilizationGoal = "BALANCED / LEAST-COST STABILIZATION"
                raise("diagnostics.goal", { index = v(station, 16, 0), goal = menu.stabilizationGoal })
            end
        end)
        addModeButton(row, 4, "OBSERVE AND ADVISE", menu.stabilizationGoal == "OBSERVE AND ADVISE ONLY", true, function()
            if startAction("diagnostics.goal") then
                menu.stabilizationGoal = "OBSERVE AND ADVISE ONLY"
                raise("diagnostics.goal", { index = v(station, 16, 0), goal = menu.stabilizationGoal })
            end
        end)
        actionResult(tableWidget, "diagnostics.goal", "Select a goal for the selected station, or the default goal when no station is selected. Run analysis afterward to refresh recommendations.")
        row = tableWidget:addRow(true)
        row[1]:setColSpan(2)
        addButton(row, 1, actionLabel("analysis.run", "REFRESH BOUNDED ANALYSIS", "REFRESHING BOUNDED ANALYSIS"), function()
            if startAction("analysis.run") then
                menu.analysisRunning = true
                raise("analysis.run", {})
            end
        end, not actionState("analysis.run").running)
        row[3]:setColSpan(2)
        addButton(row, 3, "SAVE STABILIZATION STATUS TO LOGBOOK", function()
            if startAction("diagnostics.status") then
                raise("diagnostics.status", {})
            end
        end, not actionState("diagnostics.status").running)
        actionResult(tableWidget, "analysis.run", "Refreshes current intelligence without granting additional automation authority.")
        actionResult(tableWidget, "diagnostics.status", "Saves the bounded stabilization summary and up to five detailed findings to the Logbook.")
    else
        section(tableWidget, "ADVANCED ENGINEERING AND PERMISSION PROBES")
        pair(tableWidget, "MAILBOX STATUS", v(menu.mailboxStatus, 1, "READY"), "PROOF STATUS", menu.proofStatus)
        row = tableWidget:addRow(false)
        row[1]:setColSpan(4):createText("These bounded tools use the existing MD permission mailbox. They do not broaden EOC authority. The Medical Supplies proof creates one temporary player-only buy offer, verifies it, and automatically removes it.", { wordwrap = true })
        row = tableWidget:addRow(true)
        addButton(row, 1, "PROBE RESERVED CARGO", function()
            if startAction("diagnostics.probe") then
                raise("diagnostics.probe", { verb = "PROBE_RESERVED_CARGO", index = v(station, 16, 0) })
            end
        end, not actionState("diagnostics.probe").running)
        addButton(row, 2, "PROBE MODIFY TRADE RULE", function()
            if startAction("diagnostics.probe") then
                raise("diagnostics.probe", { verb = "PROBE_MODIFY_TRADE_RULE", index = v(station, 16, 0) })
            end
        end, not actionState("diagnostics.probe").running)
        addButton(row, 3, "PROBE ASSIGN SHIP", function()
            if startAction("diagnostics.probe") then
                raise("diagnostics.probe", { verb = "PROBE_ASSIGN_SHIP", index = v(station, 16, 0) })
            end
        end, not actionState("diagnostics.probe").running)
        addButton(row, 4, "MEDICAL SUPPLIES BUY-OFFER PROOF", function()
            if startAction("diagnostics.proof") then
                raise("diagnostics.proof", {})
            end
        end, not actionState("diagnostics.proof").running)
        actionResult(tableWidget, "diagnostics.probe", text(v(menu.mailboxStatus, 2, "No engineering probe has been submitted.")))
        actionResult(tableWidget, "diagnostics.proof", "Runs only the pre-approved one-unit Medical Supplies proof when its verified target exists.")
    end
end

local function dashboard(tableWidget)
    section(tableWidget, "EXECUTIVE INTELLIGENCE OVERVIEW")
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
            addButton(row, 1, text(v(station, 1, "Station")), function()
                menu.selected = stationIndex
                menu.refresh()
            end, true)
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
                addButton(row, column, role, function()
                    if not startAction("station.role") then
                        return
                    end
                    raise("station.role", {
                        index = v(station, 16, menu.selected),
                        role = role,
                    })
                    station[2] = role
                    menu.refresh()
                end, true)
            end
        end
    end

    actionResult(tableWidget, "station.role", "Choose a role to apply it to the selected station.")

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

    addRoleControls(tableWidget, station)
    addOperationsControls(tableWidget)
    addReportsControls(tableWidget)
end

local function globalSettings(tableWidget)
    section(tableWidget, "GLOBAL EOC SETTINGS")
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

        if menu.page == "dashboard" then
            dashboard(tableWidget)
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
