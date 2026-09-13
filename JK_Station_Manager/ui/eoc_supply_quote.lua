-- Read-only quote arithmetic for the eventual MD-owned supply purchase workflow.
-- A quote is not equipment availability, procurement permission or a reservation.
local ffi = require('ffi')
local C = ffi.C
ffi.cdef[[
    int64_t GetBuildWarePrice(UniverseID containerid, const char* warename);
    float GetContainerBuildPriceFactor(UniverseID containerid);
]]
local Q = {}
JKEOC_SupplyQuote = Q

local function number(value, maximum)
    local n=tonumber(value)
    assert(n and n==n and n>=0 and n<=maximum,'Native price or quantity unavailable')
    return n
end
local function integer(value,maximum)
    local n=number(value,maximum)
    assert(n%1==0,'Fractional equipment quantity')
    return n
end
local function ware(value)
    assert(type(value)=='string' and value~='' and #value<=256,'Equipment ware unavailable')
    return value
end

-- Read the actual native serialization, not the visible editor's duplicated lists.
function Q.wares(loadout)
    local entries={};local totalSlots=0
    local function add(id,amount,software)
        id=ware(id);amount=integer(amount,100000)
        if amount==0 then return end
        local key=(software and 'S:' or 'M:')..id
        if not entries[key] then entries[key]={ware=id,amount=0,software=software} end
        entries[key].amount=integer(entries[key].amount+amount,100000)
    end
    for _,category in ipairs({'engines','shields','weapons','turrets','turretgroups','shieldgroups','ammo','units','software'}) do
        local count=integer(loadout['num'..category],4096)
        totalSlots=totalSlots+count;assert(totalSlots<=4096,'Loadout exceeds bounded equipment size')
        for i=0,count-1 do
            local item=loadout[category][i]
            if category=='software' then add(ffi.string(item.ware),1,true)
            else
                local macro=ffi.string(item.macro)
                local amount=1
                if category=='ammo' or category=='units' then amount=item.amount
                elseif category=='turretgroups' or category=='shieldgroups' then amount=item.count end
                amount=integer(amount,100000)
                if macro~='' and amount>0 then add(GetMacroData(macro,'ware'),amount,false) end
            end
        end
    end
    assert(integer(loadout.numengines,4096)>0,'No engine in generated loadout')
    local thruster=ffi.string(loadout.thruster.macro)
    assert(thruster~='','No thruster in generated loadout')
    add(GetMacroData(thruster,'ware'),1,false)
    local result={}
    for key,item in pairs(entries) do item.key=key;result[#result+1]=item end
    assert(#result<=512,'Loadout exceeds bounded ware catalogue')
    table.sort(result,function(a,b)return a.key<b.key end)
    return result
end

function Q.read(yardID,macro,loadout)
    local ok,result=pcall(function()
        local key=assert(JKEOC_SupplyReceipts.key(yardID),'Invalid yard identity')
        local yard=ConvertStringTo64Bit(key)
        assert(JKEOC_SupplyReceipts.key(yard)==key,'Yard conversion changed identity')
        assert(type(macro)=='string' and macro~='' and #macro<=256,'Hull missing')
        local owned=GetComponentData(yard,'isplayerowned')
        assert(type(owned)=='boolean','Supplier ownership unavailable')
        local wares=Q.wares(loadout)
        local result={yard=key,macro=macro,wares=wares,owned=owned,price=0,hullprice=0,status='QUOTED',permission=false}
        if owned then
            for _,entry in ipairs(wares) do entry.price=0 end
            result.reason='No vendor payment at your yard. Native resources and build eligibility still required.'
            return result
        end
        local discounts=GetComponentData(yard,'discounts')
        assert(type(discounts)=='table' and #discounts<=128,'Supplier discounts unavailable')
        local factor=1
        for _,discount in ipairs(discounts) do
            assert(type(discount)=='table' and type(discount.applytoshipsales)=='boolean','Discount classification unavailable')
            if discount.applytoshipsales then factor=factor-number(discount.amount,100)/100 end
        end
        assert(factor>=0 and factor<=1,'Invalid combined discount')
        local total=number(C.GetBuildWarePrice(yard,ware(GetMacroData(macro,'ware'))),9000000000000)
        result.hullprice=total
        for _,entry in ipairs(wares) do
            local price
            if entry.software then
                price=factor*number(C.GetContainerBuildPriceFactor(yard),1000)*number(GetContainerWarePrice(ConvertStringToLuaID(key),entry.ware,false),9000000000000)
            else
                local volatile=GetWareData(entry.ware,'volatile')
                assert(type(volatile)=='boolean','Ware pricing classification unavailable')
                price=volatile and 0 or number(C.GetBuildWarePrice(yard,entry.ware),9000000000000)
            end
            entry.price=number(price,9000000000000)
            total=number(total+entry.amount*entry.price,9000000000000)
        end
        result.price=integer(RoundTotalTradePrice(total),9000000000000)
        assert(result.price>0,'NPC purchase cannot have a zero quote')
        result.reason='Native hull and equipment quote only. Availability, spending reservation and submission are not yet approved.'
        return result
    end)
    if ok then return result end
    return {status='UNVERIFIED',permission=false,reason='Quote unavailable: '..tostring(result)}
end
