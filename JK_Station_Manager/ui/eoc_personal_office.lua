local integration = {
    callbackID = "jk_eoc_b195_universal_access",
    menu = nil,
    registered = false,
    attempts = 0,
    maxAttempts = 60,
}

local function signalEOC()
    AddUITriggeredEvent("JKEOC_PersonalOfficeAccess", "open", nil)
end

local function openEOC()
    if integration.menu and type(integration.menu.onCloseElement) == "function" then
        integration.menu.onCloseElement("close")
    elseif integration.menu and Helper and type(Helper.closeMenu) == "function" then
        Helper.closeMenu(integration.menu, "close")
    end

    if Helper and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(signalEOC, true, getElapsedTime() + 0.1)
    else
        signalEOC()
    end
end

local function addEOCAction(tableHeader)

    local row = tableHeader:addRow(true, { fixed = true })
    row[1]:setColSpan(11):createButton({
        helpOverlayID = "jkeoc_personal_office_open",
        helpOverlayText = " ",
        helpOverlayHighlightOnly = true,
        uiTriggerID = "jkeoc_personal_office_open",
    }):setText("OPEN EXECUTIVE OPERATIONS CENTER", { halign = "center" })
    row[1].handlers.onClick = openEOC
end

local function init()
    if integration.registered then
        return
    end

    integration.menu = Helper.getMenu("DockedMenu")
    if integration.menu and type(integration.menu.registerCallback) == "function" then
        integration.menu.registerCallback(
            "display_on_after_main_interactions",
            addEOCAction,
            integration.callbackID
        )
        integration.registered = true
        DebugError("[JKEOC][B199][UNIVERSAL_ACCESS] callback=REGISTERED attempts=" .. tostring(integration.attempts + 1))
        return
    end

    integration.attempts = integration.attempts + 1
    if integration.attempts < integration.maxAttempts and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(init, true, getElapsedTime() + 1)
    else
        DebugError("[JKEOC][B199][LUA_ERROR] Universal Dock Interactions callback unavailable after retries=" .. tostring(integration.attempts))
    end
end

init()