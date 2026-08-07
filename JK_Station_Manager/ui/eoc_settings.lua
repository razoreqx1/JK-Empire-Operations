---@diagnostic disable: undefined-global, undefined-field

local menu = {
    name = "JKEOC_SettingsMenu",
    title = "EOC - EXECUTIVE OPERATIONS CENTER",
    page = "dashboard",
    selected = 1,
    analysisRunning = false,
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
        return "UNAVAILABLE"
    end
    return tostring(value)
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function formatGameTime(value)
    local seconds = math.max(0, math.floor(tonumber(value) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function analysisComplete(_, payload)
    menu.analysisRunning = false
    menu.analysisStatus = "ANALYSIS COMPLETE"
    menu.analysisStatusUntil = getElapsedTime() + 3

    if type(payload) == "table" then
        menu.summary = v(payload, 1, menu.summary)
        menu.inbox = v(payload, 2, menu.inbox)
        menu.lastUpdated = formatGameTime(v(payload, 3, 0))
        menu.analysisOutput = text(v(payload, 4, "Analysis completed."))
    end

    if menu.frame then
        menu.refresh()
    end
end

local function reportSaved(_, payload)
    menu.reportStatus = "REPORT SAVED TO TIPS"
    menu.reportStatusUntil = getElapsedTime() + 4

    if type(payload) == "table" then
        menu.lastReport = text(v(payload, 1, "EOC REPORT"))
        menu.reportOutput = text(v(payload, 2, "Report saved to Tips."))
    else
        menu.lastReport = text(payload)
        menu.reportOutput = "Report saved to Tips."
    end

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
        DebugError("[JKEOC][B83G_R6][LUA_ERROR] Helper.registerMenu unavailable")
    end

    AddUITriggeredEvent(menu.name, "INIT", nil)
    RegisterEvent(menu.name .. ".INIT", menu.PrepareMenuData)
    RegisterEvent(menu.name .. ".analysis.complete", analysisComplete)
    RegisterEvent(menu.name .. ".report.saved", reportSaved)
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
    menu.analysisOutput = menu.analysisOutput or "Run Analyze Now to generate the current executive analysis."
    menu.reportOutput = menu.reportOutput or "Generate a report to preview its current output here."
    menu.selected = clamp(menu.selected or 1, 1, math.max(1, #menu.stations))
    menu.create()
    raise("opened", { mode = menu.mode })
end

local function addButton(row, column, label, handler, active)
    row[column]:createButton({ active = active ~= false }):setText(label)
    row[column].handlers.onClick = handler
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
    row[column].handlers.onClick = handler
end

local function addTabButton(row, column, label, page)
    local properties = { active = true }

    if menu.page == page then
        properties.bgColor = activeTabBackground
    end

    row[column]:createButton(properties):setText(label)
    row[column].handlers.onClick = function()
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

local function pair(tableWidget, leftLabel, leftValue, rightLabel, rightValue)
    local row = tableWidget:addRow(false)
    row[1]:createText(leftLabel)
    row[2]:createText(text(leftValue), { halign = "right" })
    row[3]:createText(rightLabel)
    row[4]:createText(text(rightValue), { halign = "right" })
end

local function selectedStation()
    return menu.stations[menu.selected]
end

local function createHeader(frame, parentWidth)
    local titleHeight = Helper.scaleY(42)
    local tabHeight = Helper.scaleY(38)
    local headerHeight = titleHeight + tabHeight
    local usableWidth = parentWidth - 2 * Helper.borderSize
    local tableWidget = frame:addTable(3, {
        tabOrder = 1,
        x = Helper.borderSize,
        y = Helper.borderSize,
        width = usableWidth,
        borderEnabled = true,
    })
    local columnWidth = math.floor(usableWidth / 3)

    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)

    local row = tableWidget:addRow(false, {
        fixed = true,
        minRowHeight = titleHeight,
    })
    row[1]:setColSpan(3):createText(menu.title, {
        halign = "center",
        font = Helper.titleFont,
        fontsize = Helper.standardFontSize + 4,
    })

    row = tableWidget:addRow(true, {
        fixed = true,
        minRowHeight = tabHeight,
    })
    addTabButton(row, 1, "STATIONS", "stations")
    addTabButton(row, 2, "DASHBOARD", "dashboard")
    addTabButton(row, 3, "GLOBAL SETTINGS", "settings")

    local activeColumns = {
        stations = 1,
        dashboard = 2,
        settings = 3,
    }
    tableWidget:setSelectedRow(2)
    tableWidget:setSelectedCol(activeColumns[menu.activeTab or menu.page] or 2)

    tableWidget.properties.maxVisibleHeight = headerHeight
    return headerHeight
end

local function dashboard(tableWidget)
    section(tableWidget, "EXECUTIVE INTELLIGENCE DASHBOARD")
    pair(
        tableWidget,
        "STATUS",
        menu.analysisRunning and "ANALYSIS RUNNING..." or (menu.analysisStatus or "READY"),
        "LAST UPDATED",
        menu.lastUpdated or "NOT RUN THIS SESSION"
    )
    pair(tableWidget, "Empire Health", v(menu.summary, 1, 0), "Trend", v(menu.summary, 2, "STABLE"))
    pair(tableWidget, "Economy", v(menu.summary, 3, 0), "Logistics", v(menu.summary, 4, 0))
    pair(tableWidget, "Workforce", v(menu.summary, 5, 0), "Defense", v(menu.summary, 6, 0))
    pair(tableWidget, "Growth", v(menu.summary, 7, 0), "Ship Utilization", v(menu.summary, 10, 0))
    pair(tableWidget, "Stations", v(menu.summary, 8, #menu.stations), "Productive", v(menu.summary, 9, 0))
    pair(tableWidget, "Active Cases", v(menu.summary, 11, 0), "Require Attention", v(menu.summary, 12, 0))

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
        menu.analysisRunning and "ANALYSIS RUNNING..." or "ACTION: ANALYZE NOW",
        function()
            if not menu.analysisRunning then
                menu.analysisRunning = true
                menu.analysisStatus = "ANALYSIS RUNNING..."
                menu.refresh()
                raise("analysis.run", {})
            end
        end,
        not menu.analysisRunning
    )
    row[3]:setColSpan(2)
    addButton(row, 3, menu.reportStatus or "REPORT: EMPIRE EXECUTIVE", function()
        raise("report.empire", {})
    end, true)

    row = tableWidget:addRow(false, { minRowHeight = Helper.scaleY(190) })
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

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "AUTO-ASSIGN UNDEFINED ROLES", function()
        raise("station.auto", {})
    end, true)
end

local function addOperationsControls(tableWidget)
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
    addModeButton(row, 1, "TRADE MODE: ADVISOR", menu.mode == "ADVISOR", true, function()
        raise("trade.advisor", {})
        menu.mode = "ADVISOR"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "TRADE MODE: MANAGED", menu.mode == "MANAGED", true, function()
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
        true,
        function()
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
    addModeButton(row, 1, "APPROVAL REQUIRED", menu.shipmode == "APPROVAL REQUIRED", assignmentEnabled, function()
        raise("shipping.approval", {})
        menu.shipmode = "APPROVAL REQUIRED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "AUTO-ASSIGN REGISTERED", menu.shipmode == "AUTO-ASSIGN REGISTERED", assignmentEnabled, function()
        raise("shipping.auto", {})
        menu.shipmode = "AUTO-ASSIGN REGISTERED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)

    section(tableWidget, "OPERATION ACTIONS")
    row = tableWidget:addRow(true)
    addButton(row, 1, "REVIEW ORDERS", function()
        raise("trade.review", {})
    end, true)
    addButton(row, 2, "SCAN SHIPPING NOW", function()
        raise("shipping.scan", {})
    end, true)
    row[3]:setColSpan(2)
    addButton(row, 3, "ACTION: ANALYZE NOW", function()
        raise("analysis.run", {})
    end, true)
end

local function addReportsControls(tableWidget)
    section(tableWidget, "REPORTS")

    if menu.reportStatus then
        pair(tableWidget, "STATUS", menu.reportStatus, "REPORT", menu.lastReport or "EOC REPORT")
    end

    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addButton(row, 1, "REPORT: SELECTED STATION", function()
        raise("report.station", { index = menu.selected })
    end, #menu.stations > 0)
    row[3]:setColSpan(2)
    addButton(row, 3, "REPORT: OPERATIONAL REMEDIATION", function()
        raise("report.remediation", {})
    end, true)

    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "REPORT: TRADE ORDER STATUS", function()
        raise("report.trade", {})
    end, true)

    section(tableWidget, "REPORT DELIVERY")
    pair(
        tableWidget,
        "Location",
        "Player Information > Logbook > Tips",
        "Termination",
        "Final page shows END OF REPORT"
    )
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

    addRoleControls(tableWidget, station)
    addOperationsControls(tableWidget)
    addReportsControls(tableWidget)
end

local function globalSettings(tableWidget)
    section(tableWidget, "GLOBAL EOC SETTINGS")
    pair(tableWidget, "Trade Order Control", menu.mode, "Ship Assignment Authority", menu.shipmode)

    section(tableWidget, "TRADE ORDER CONTROL")
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2)
    addModeButton(row, 1, "ADVISOR MODE", menu.mode == "ADVISOR", true, function()
        raise("trade.advisor", {})
        menu.mode = "ADVISOR"
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "MANAGED TRADE", menu.mode == "MANAGED", true, function()
        raise("trade.managed", {})
        menu.mode = "MANAGED"
        menu.refresh()
    end)

    section(tableWidget, "SHIP ASSIGNMENT AUTHORITY")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addModeButton(
        row,
        1,
        menu.shipmode == "DISABLED" and "SHIP ASSIGNMENT: DISABLED" or "SHIP ASSIGNMENT: ENABLED",
        menu.shipmode ~= "DISABLED",
        true,
        function()
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
    addModeButton(row, 1, "APPROVAL REQUIRED", menu.shipmode == "APPROVAL REQUIRED", assignmentEnabled, function()
        raise("shipping.approval", {})
        menu.shipmode = "APPROVAL REQUIRED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)
    row[3]:setColSpan(2)
    addModeButton(row, 3, "AUTO-ASSIGN REGISTERED", menu.shipmode == "AUTO-ASSIGN REGISTERED", assignmentEnabled, function()
        raise("shipping.auto", {})
        menu.shipmode = "AUTO-ASSIGN REGISTERED"
        menu.previousShipmode = menu.shipmode
        menu.refresh()
    end)

    section(tableWidget, "STATION AUTOMATION ACTIONS")
    row = tableWidget:addRow(true)
    row[1]:setColSpan(4)
    addButton(row, 1, "RUN UNDEFINED STATION ROLE ASSIGNMENT", function()
        raise("station.auto", {})
    end, true)
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

        if menu.page == "dashboard" then
            dashboard(tableWidget)
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
