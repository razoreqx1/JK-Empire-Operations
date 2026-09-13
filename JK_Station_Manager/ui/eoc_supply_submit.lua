-- One-shot native adapter. Not registered to any event until MD-owned permits are integrated.
local ffi=require('ffi')
local C=ffi.C
ffi.cdef[[
    BuildTaskInfo GetBuildTaskInfo(BuildTaskID id);
    void SetBuildTaskTransferredMoney(BuildTaskID id, int64_t value);
]]
local S={}
JKEOC_SupplySubmit=S
local function amount(v)
    return assert(JKEOC_SupplyReceipts.integer(v,9000000000000),'Invalid money amount')
end
local function identity(value)
    local key=assert(JKEOC_SupplyReceipts.key(value),'Invalid native identity')
    local id=ConvertStringTo64Bit(key)
    assert(JKEOC_SupplyReceipts.key(id)==key,'Identity changed during conversion')
    return id,key
end
function S.execute(q,permit)
    local result={status='UNVERIFIED',attempted=false,paid=0,task='',object=''}
    if type(q)~='table' or q.used or type(permit)~='table' or permit.consumed~=true or type(q.token)~='string' or q.token=='' or permit.token~=q.token then
        result.reason='No matching consumed transaction permit; nothing attempted.';return result
    end
    -- A stale/invalid permit is still consumed locally. No retry can reuse this quote.
    q.used=true
    local ok,err=pcall(function()
        assert(q.status=='QUOTED' and type(q.owned)=='boolean','Prepared quote missing')
        assert(type(q.preparedAt)=='number' and getElapsedTime()>=q.preparedAt and getElapsedTime()-q.preparedAt<=30,'Prepared quote expired')
        local station=identity(q.station)
        assert(C.IsComponentOperational(station) and GetComponentData(station,'isplayerowned')==true,'Destination changed')
        local fresh=JKEOC_SupplyPrepare.read(q.yard,q.macro,q.cargo)
        assert(fresh.status=='QUOTED' and fresh.owned==q.owned and fresh.price==q.price and JKEOC_SupplyPrepare.same(fresh.wares,q.wares),'Supplier, equipment or quote changed')
        local yard=identity(q.yard)
        local price=amount(q.price);local reserve=amount(permit.reserve)
        assert(price==amount(permit.price) and price<=amount(permit.orderCap),'Price differs from reserved amount')
        assert(JKEOC_SupplyReceipts.key(permit.station)==JKEOC_SupplyReceipts.key(q.station) and JKEOC_SupplyReceipts.key(permit.yard)==JKEOC_SupplyReceipts.key(q.yard) and permit.macro==q.macro,'Permit target changed')
        assert(q.owned or price>0,'NPC ship cannot be free')
        local before=amount(GetPlayerMoney())
        assert(before>=price+reserve,'Player funds or reserve changed')
        local task=Helper.callLoadoutFunction(fresh.plan,nil,function(loadout,crew)
            -- Reprice exactly the buffer being submitted, not an editor representation.
            local exact=JKEOC_SupplyPrepare.price(yard,q.macro,loadout,q.cargo)
            assert(exact.price==price and exact.owned==q.owned and JKEOC_SupplyPrepare.same(exact.wares,q.wares),'Final serialized loadout or price changed')
            local info=ffi.new('AddBuildTask6Container');info.paintmodwareid=''
            result.attempted=true -- BEFORE transfer/build, including thrown native calls.
            if not q.owned then
                TransferPlayerMoneyTo(price,yard)
                assert(amount(GetPlayerMoney())==before-price,'Payment readback uncertain; inspect retained transaction')
                result.paid=price
            end
            local id=C.AddBuildTask6(yard,0,q.macro,loadout,price,crew,false,'',info)
            result.task=assert(JKEOC_SupplyReceipts.key(id),'Native build receipt missing after attempt')
            if not q.owned then C.SetBuildTaskTransferredMoney(id,price) end
            return id
        end,nil,'UILoadout2')
        -- This is the fresh returned task only. Failure/zero component does not cancel/rebuy it.
        local read,object=pcall(function()
            local info=C.GetBuildTaskInfo(task)
            if JKEOC_SupplyReceipts.key(info.id)~=result.task or JKEOC_SupplyReceipts.key(info.buildingcontainer)~=JKEOC_SupplyReceipts.key(q.yard) or ffi.string(info.macro)~=q.macro or ffi.string(info.factionid)~='player' or tonumber(info.price)~=price then return '' end
            return JKEOC_SupplyReceipts.key(info.component) or ''
        end)
        if read then result.object=object end
        result.status='SUBMITTED'
        result.reason=result.object~='' and 'Native order submitted; exact MD build/payment and eventual delivery remain to be verified.' or 'Native task submitted without a component witness yet; keep reservation and reconcile, never repurchase.'
    end)
    Helper.ffiClearNewHelper()
    if not ok then
        result.status=result.attempted and 'UNCERTAIN' or 'NOT_ATTEMPTED'
        result.reason=tostring(err)
    end
    return result
end
