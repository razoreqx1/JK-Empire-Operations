-- Read-only receipt reconciliation. MD retains purchase authority and reservations.
-- No startup scan, timer, payment, assignment, cancellation or retry is installed.
-- ABI is declared by eoc_settings.lua, loaded before this file.
local ffi = require('ffi')
local C = ffi.C
local R = {}
JKEOC_SupplyReceipts = R

function R.key(value, allowZero)
    local kind = type(value)
    if kind ~= 'string' and kind ~= 'cdata' and kind ~= 'number' then return nil end
    if kind == 'number' and (value ~= value or value < 0 or value % 1 ~= 0 or value > 9007199254740991) then return nil end
    local s = tostring(value):gsub('ULL$', ''):gsub('LL$', '')
    if not s:match('^%d+$') then return nil end
    s = s:gsub('^0+', '')
    if s == '' then return allowZero and '0' or nil end
    if #s > 20 or (#s == 20 and s > '18446744073709551615') then return nil end
    return s
end

function R.integer(value, maximum)
    local n = tonumber(value)
    if n and n == n and n >= 0 and n <= maximum and n % 1 == 0 then return n end
end

-- Pure comparison shared by the native adapter and exact-data regression tests.
-- A matching task has not necessarily finished, has a captain, or is assignable.
function R.match(expected, rows)
    local unknown = {status='UNVERIFIED', reason='Purchase receipt could not be verified. Keep its reservation; do not repurchase.'}
    if type(expected) ~= 'table' or type(rows) ~= 'table' then return unknown end
    local task, yard = R.key(expected.task), R.key(expected.yard)
    local price = R.integer(expected.price, 9000000000000)
    if not task or not yard or not price or type(expected.macro) ~= 'string' or expected.macro == '' or #rows > 1024 then return unknown end
    local found
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or not R.key(row.task) then return unknown end
        if R.key(row.task) == task then
            -- A transition between the two native lists may produce a duplicate.
            -- Retain uncertainty, even if both copies currently look identical.
            if found then return unknown end
            if row.faction ~= 'player' or R.key(row.yard) ~= yard or row.macro ~= expected.macro or R.integer(row.price,9000000000000) ~= price then return unknown end
            local component = R.key(row.component, true)
            if not component or (row.phase ~= 'QUEUED' and row.phase ~= 'BUILDING') then return unknown end
            found = {task=task, yard=yard, macro=expected.macro, price=price, component=component, phase=row.phase}
        end
    end
    if not found then return unknown end
    found.status = found.component == '0' and 'PENDING' or 'IDENTIFIED'
    found.reason = found.component == '0' and 'Exact build task is queued without a ship object. Purchase remains pending.' or 'Exact build task and ship object identified. Delivery, captain and assignment still require verification.'
    return found
end

function R.read(expected)
    -- Validate the requested receipt before touching native APIs.
    if type(expected) ~= 'table' or not R.key(expected.task) or not R.key(expected.yard) or not R.integer(expected.price,9000000000000) or type(expected.macro) ~= 'string' or expected.macro == '' then return R.match(nil,nil) end
    local ok, result = pcall(function()
        local rows = {}
        for _, inProgress in ipairs({true,false}) do
            local count = R.integer(C.GetNumPlayerShipBuildTasks(inProgress,false),1024)
            if not count or #rows + count > 1024 then return R.match(nil,nil) end
            if count > 0 then
                local buffer = ffi.new('BuildTaskInfo[?]',count)
                local received = R.integer(C.GetPlayerShipBuildTasks(buffer,count,inProgress,false),count)
                -- A changing list is not a complete snapshot. Never allocate a retry.
                if received ~= count then return R.match(nil,nil) end
                for i=0,received-1 do
                    local item = buffer[i]
                    rows[#rows+1] = {task=R.key(item.id),yard=R.key(item.buildingcontainer),component=R.key(item.component,true),macro=ffi.string(item.macro),faction=ffi.string(item.factionid),price=tonumber(item.price),phase=inProgress and 'BUILDING' or 'QUEUED'}
                end
            end
        end
        return R.match(expected,rows)
    end)
    if ok then return result end
    return R.match(nil,nil)
end
