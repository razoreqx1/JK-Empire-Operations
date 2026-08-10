local ffi = require("ffi")

ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);
    UniverseID GetPlayerID(void);
    const char* GetPlayerCurrentControlGroup(void);
]]

local C = ffi.C
local integration = {
    callbackID = "jk_eoc_ga18_personal_office",
    menu = nil,
}

local function isPersonalOfficeChair()
    local controlgroup = C.GetPlayerCurrentControlGroup()
    if controlgroup == nil or ffi.string(controlgroup) ~= "empirecontrol" then
        return false
    end

    local room = C.GetContextByClass(C.GetPlayerID(), "room", false)
    if room == 0 then
        return false
    end

    local roommacro = GetComponentData(ConvertStringToLuaID(tostring(room)), "macro")
    return roommacro == "room_gen_playeroffice_01_macro"
end

local function openEOC()
    AddUITriggeredEvent("JKEOC_PersonalOfficeAccess", "open", nil)
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
    integration.menu = Helper.getMenu("DockedMenu")
    if integration.menu and type(integration.menu.registerCallback) == "function" then
        integration.menu.registerCallback(
            "display_on_after_main_interactions",
            addPersonalOfficeAction,
            integration.callbackID
        )
    else
        DebugError("[JKEOC][GA18][LUA_ERROR] Personal Office callback unavailable")
    end
end

init()