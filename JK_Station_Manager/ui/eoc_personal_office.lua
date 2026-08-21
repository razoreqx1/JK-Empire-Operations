--- EOC Docked-menu integration adapter.
-- @module eoc_personal_office
-- @responsibility Register exactly one bounded callback with the DockedMenu
-- owned by the declared UI Extensions and HUD dependency, then
-- raise JKEOC_PersonalOfficeAccess when the player clicks the EOC button.
-- @lifecycle init() retries registration for at most 60 seconds at startup; after
-- registration there is no watcher, polling loop, or per-frame repair.
-- @boundary This file opens EOC only. It does not scan stations, mutate ships,
-- create trade offers, or own persistent game state.
-- @contract JKEOC_Settings_Interface.xml consumes the raised UI event.
-- @invariant EOC must not ship a competing menu_docked.xpl; the shared upstream
-- callback surface is the sole owner of DockedMenu integration.

local integration = {
    callbackID = "jk_eoc_b255_shared_ui_access",
    menu = nil,
    registered = false,
    attempts = 0,
    maxAttempts = 60,
    renderCount = 0,
    clickCount = 0,
}

--- Raise the Lua-to-Mission-Director event that requests the full EOC window.
-- Kept separate from the click handler so the DockedMenu can close before MD
-- starts transporting current state into eoc_settings.lua.
local function signalEOC()
    DebugError("[JKEOC][B255][DOCK_ACCESS] stage=OPEN_EVENT_RAISED event=JKEOC_PersonalOfficeAccess")
    AddUITriggeredEvent("JKEOC_PersonalOfficeAccess", "open", nil)
end

--- Handle the player-facing Docked-menu button.
-- Closes DockedMenu first, then schedules one delayed open event to avoid two
-- overlapping X4 menus competing for focus.
local function openEOC()
    integration.clickCount = integration.clickCount + 1
    DebugError("[JKEOC][B255][DOCK_ACCESS] stage=BUTTON_CLICKED count=" .. tostring(integration.clickCount))
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

--- Render the EOC access row into X4's existing Docked-menu table.
-- @param tableHeader X4 UI table supplied by the registered callback surface.
local function addEOCAction(tableHeader)
    integration.renderCount = integration.renderCount + 1
    DebugError("[JKEOC][B255][DOCK_ACCESS] stage=BUTTON_RENDERED count=" .. tostring(integration.renderCount))

    local row = tableHeader:addRow(true, { fixed = true })
    row[1]:setColSpan(11):createButton({
        helpOverlayID = "jkeoc_personal_office_open",
        helpOverlayText = " ",
        helpOverlayHighlightOnly = true,
        uiTriggerID = "jkeoc_personal_office_open",
    }):setText("OPEN EXECUTIVE OPERATIONS CENTER", { halign = "center" })
    row[1].handlers.onClick = openEOC
end

--- Register the bounded Docked-menu callback.
-- Registration is idempotent; callbackID prevents duplicate ownership.
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
        DebugError("[JKEOC][B255][DOCK_ACCESS] stage=CALLBACK_REGISTERED owner=UI_EXTENSIONS attempts=" .. tostring(integration.attempts + 1) .. " recurring_watchdog=0")
        return
    end

    integration.attempts = integration.attempts + 1
    if integration.attempts < integration.maxAttempts and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(init, true, getElapsedTime() + 1)
    else
        DebugError("[JKEOC][B255][LUA_ERROR] UI Extensions DockedMenu callback unavailable after retries=" .. tostring(integration.attempts))
    end
end

init()
