local ffi = require("ffi")

ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);
    UniverseID GetPlayerID(void);
    const char* GetPlayerCurrentControlGroup(void);
]]

local C = ffi.C
local integration = {
    callbackID = "jk_eoc_b139_personal_office",
    menu = nil,
    registered = false,
    attempts = 0,
    maxAttempts = 60,
}

local function isPersonalOfficeChair()
    local controlgroup = C.GetPlayerCurrentControlGroup()
    local isEmpireControl = controlgroup ~= nil and ffi.string(controlgroup) == "empirecontrol"

    local room = C.GetContextByClass(C.GetPlayerID(), "room", false)
    local isPersonalOffice = false
    if room ~= 0 then
        local roommacro = GetComponentData(ConvertStringToLuaID(tostring(room)), "macro")
        isPersonalOffice = roommacro == "room_gen_playeroffice_01_macro"
    end

    return isEmpireControl or isPersonalOffice
end

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

local function addPersonalOfficeAction(tableHeader)
    if not isPersonalOfficeChair() then
        return
    end

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
            addPersonalOfficeAction,
            integration.callbackID
        )
        integration.registered = true
        DebugError("[JKEOC][B157][PERSONAL_OFFICE] callback=REGISTERED attempts=" .. tostring(integration.attempts + 1))
        return
    end

    integration.attempts = integration.attempts + 1
    if integration.attempts < integration.maxAttempts and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(init, true, getElapsedTime() + 1)
    else
        DebugError("[JKEOC][B157][LUA_ERROR] Personal Office callback unavailable after retries=" .. tostring(integration.attempts))
    end
end

init()