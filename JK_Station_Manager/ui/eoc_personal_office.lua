--- EOC Docked-menu access adapter.
-- @module eoc_personal_office
-- @responsibility Register exactly one bounded callback with the active
-- DockedMenu implementation, then
-- raise JKEOC_PersonalOfficeAccess when the player clicks the EOC button.
-- @lifecycle init() retries registration for at most 60 seconds at startup,
-- then performs exactly one delayed reconciliation with the final DockedMenu
-- owner. There is no watcher, polling loop, or per-frame repair.
-- @boundary This file opens EOC only. It does not scan stations, mutate ships,
-- create trade offers, or own persistent game state.
-- @contract JKEOC_Settings_Interface.xml consumes the raised UI event.
-- @invariant Build 265's self-contained DockedMenu preserves pre-existing
-- callback tables before it becomes active, so integrations registered on an
-- earlier owner are not stranded.

local integration = {
    callbackID = "jk_eoc_b257_standalone_access",
    menu = nil,
    registeredMenus = {},
    attempts = 0,
    maxAttempts = 60,
    finalReconcileScheduled = false,
    renderCount = 0,
    clickCount = 0,
}

--- Raise the Lua-to-Mission-Director event that requests the full EOC window.
-- Kept separate from the click handler so the DockedMenu can close before MD
-- starts transporting current state into eoc_settings.lua.
local function signalEOC()
    DebugError("[JKEOC][B265][DOCK_ACCESS] stage=OPEN_EVENT_RAISED event=JKEOC_PersonalOfficeAccess")
    AddUITriggeredEvent("JKEOC_PersonalOfficeAccess", "open", nil)
end

--- Handle the player-facing Docked-menu button.
-- Closes DockedMenu first, then schedules one delayed open event to avoid two
-- overlapping X4 menus competing for focus.
local function openEOC()
    integration.clickCount = integration.clickCount + 1
    DebugError("[JKEOC][B265][DOCK_ACCESS] stage=BUTTON_CLICKED count=" .. tostring(integration.clickCount))
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
    DebugError("[JKEOC][B265][DOCK_ACCESS] stage=BUTTON_RENDERED count=" .. tostring(integration.renderCount))

    local row = tableHeader:addRow(true, { fixed = true })
    row[1]:setColSpan(11):createButton({
        helpOverlayID = "jkeoc_personal_office_open",
        helpOverlayText = " ",
        helpOverlayHighlightOnly = true,
        uiTriggerID = "jkeoc_personal_office_open",
    }):setText("OPEN EXECUTIVE OPERATIONS CENTER", { halign = "center" })
    row[1].handlers.onClick = openEOC
end

--- Register on one concrete DockedMenu owner.
-- The table identity guard prevents duplicate registration on the same owner.
local function registerOnMenu(targetMenu, owner)
    if not targetMenu or type(targetMenu.registerCallback) ~= "function" then
        return false
    end
    if integration.registeredMenus[targetMenu] then
        integration.menu = targetMenu
        return true
    end

    targetMenu.registerCallback(
            "display_on_after_main_interactions",
            addEOCAction,
            integration.callbackID
    )
    integration.registeredMenus[targetMenu] = true
    integration.menu = targetMenu
    DebugError("[JKEOC][B265][DOCK_ACCESS] stage=CALLBACK_REGISTERED owner=" .. tostring(owner) .. " attempts=" .. tostring(integration.attempts + 1) .. " recurring_watchdog=0")
    return true
end

--- Perform one final, delayed owner check after all UI addons have settled.
-- If another mod replaced DockedMenu after the initial registration, EOC
-- registers once on that final owner. This callback never reschedules itself.
local function reconcileFinalOwner()
    local previousMenu = integration.menu
    local finalMenu = Helper.getMenu("DockedMenu")
    local changed = finalMenu ~= previousMenu
    local registered = registerOnMenu(finalMenu, "FINAL_ACTIVE_MENU")
    DebugError("[JKEOC][B265][DOCK_ACCESS] stage=FINAL_OWNER_RECONCILED changed=" .. tostring(changed) .. " registered=" .. tostring(registered) .. " recurring_watchdog=0")
end

local function scheduleFinalReconcile()
    if integration.finalReconcileScheduled then
        return
    end
    integration.finalReconcileScheduled = true
    if Helper and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(reconcileFinalOwner, true, getElapsedTime() + 10)
    else
        reconcileFinalOwner()
    end
end

--- Register the bounded initial Docked-menu callback.
local function init()
    local activeMenu = Helper.getMenu("DockedMenu")
    if registerOnMenu(activeMenu, "INITIAL_ACTIVE_MENU") then
        scheduleFinalReconcile()
        return
    end

    integration.attempts = integration.attempts + 1
    if integration.attempts < integration.maxAttempts and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(init, true, getElapsedTime() + 1)
    else
        DebugError("[JKEOC][B265][LUA_ERROR] DockedMenu callback unavailable after retries=" .. tostring(integration.attempts))
    end
end

init()
