-- Stateless native supply preparation. MD must independently reserve and permit execution.
local ffi=require('ffi')
local C=ffi.C
if not pcall(ffi.typeof,'EquipmentWareInfo') then ffi.cdef[[typedef struct { const char* type; const char* ware; const char* macro; int amount; } EquipmentWareInfo;]] end
if not pcall(ffi.typeof,'SoftwareSlot') then ffi.cdef[[typedef struct { const char* max; const char* current; } SoftwareSlot;]] end
ffi.cdef[[
    bool HasSuitableBuildModule(UniverseID containerid, UniverseID defensibleid, const char* macroname);
    uint32_t GetNumContainerBuilderMacros(UniverseID containerid);
    uint32_t GetContainerBuilderMacros(const char** result, uint32_t resultlen, UniverseID containerid);
    uint32_t GetNumSoftwareSlots(UniverseID controllableid, const char* macroname);
    uint32_t GetSoftwareSlots(SoftwareSlot* result, uint32_t resultlen, UniverseID controllableid, const char* macroname);
    uint32_t GetNumAvailableEquipment(UniverseID containerid, const char* classid);
    uint32_t GetAvailableEquipment(EquipmentWareInfo* result, uint32_t resultlen, UniverseID containerid, const char* classid);
]]
local P={}
JKEOC_SupplyPrepare=P
local function count(v,max)
    return assert(JKEOC_SupplyReceipts.integer(v,max),'Native catalogue count unavailable or above bound')
end
local function component(v)
    local key=assert(JKEOC_SupplyReceipts.key(v),'Invalid supplier identity')
    local id=ConvertStringTo64Bit(key)
    assert(JKEOC_SupplyReceipts.key(id)==key,'Supplier identity changed during conversion')
    return id,key
end
function P.hull(macro,cargo)
    assert(type(macro)=='string' and macro~='' and #macro<=256,'Missing hull')
    assert(cargo=='solid' or cargo=='liquid' or cargo=='container','Unsupported supply cargo')
    local purpose,tags=GetMacroData(macro,'primarypurpose','storagetags')
    local library=GetLibrary('shiptypes_m')
    assert(type(library)=='table' and #library<=2048,'Medium ship library unavailable or above bound')
    local found=false
    for _,entry in ipairs(library) do if entry.id==macro then found=true end end
    assert(found,'Automatic supply procurement currently selects known medium ships')
    assert(type(tags)=='table' and (tags[cargo]==true or tags.universal==true),'Hull cannot carry this resource')
    assert(purpose==(cargo=='container' and 'trade' or 'mine'),'Hull is not the required supply role')
end
function P.supplier(yardID,macro,cargo)
    P.hull(macro,cargo)
    local yard,key=component(yardID)
    local owned,trader=GetComponentData(yard,'isplayerowned','shiptrader')
    assert(type(owned)=='boolean' and type(trader)=='userdata','Supplier or ship trader unavailable')
    local traderID=ConvertIDTo64Bit(trader)
    assert(JKEOC_SupplyReceipts.key(traderID),'Ship trader unavailable')
    assert(C.IsComponentOperational(yard) and C.HasSuitableBuildModule(yard,0,macro) and C.CanGenerateValidLoadout(yard,macro),'Supplier cannot build this hull')
    local ware=GetMacroData(macro,'ware')
    assert(type(ware)=='string' and ware~='','Hull ware unavailable')
    local licence,blueprintOnly,research,limited=GetWareData(ware,'tradelicence','isblueprintsaleonly','productionresearchprecursors','islimited')
    assert(type(licence)=='string' and type(blueprintOnly)=='boolean' and type(limited)=='boolean' and (research==nil or type(research)=='table'),'Hull restrictions unavailable')
    assert(not limited and (not research or #research==0),'Limited or research hull excluded from automatic purchasing')
    if owned then
        local n=count(C.GetNumBlueprints('','',''),8192)
        local found=false
        if n>0 then
            local buf=ffi.new('UIBlueprint[?]',n)
            assert(count(C.GetBlueprints(buf,n,'','',''),8192)==n,'Blueprint catalogue changed')
            for i=0,n-1 do if ffi.string(buf[i].macro)==macro then found=true end end
        end
        assert(found,'Player yard lacks this hull blueprint')
    else
        assert(not blueprintOnly,'Hull is sold only as a blueprint')
        if licence~='' then
            local owner=GetComponentData(yard,'owner')
            assert(type(owner)=='string' and owner~='' and HasLicence('player',licence,owner)==true,'Required ship licence unavailable')
        end
    end
    local n=count(C.GetNumContainerBuilderMacros(yard),2048)
    assert(n>0,'Supplier hull catalogue is empty')
    local buf=ffi.new('const char*[?]',n)
    assert(count(C.GetContainerBuilderMacros(buf,n,yard),2048)==n,'Supplier hull catalogue changed')
    local found=false
    for i=0,n-1 do if ffi.string(buf[i])==macro then found=true end end
    assert(found,'Supplier no longer offers this hull')
    return yard,key,owned
end
function P.same(a,b)
    if type(a)~='table' or type(b)~='table' or #a~=#b then return false end
    for i,item in ipairs(a) do
        local other=b[i]
        if item.key~=other.key or item.ware~=other.ware or item.amount~=other.amount or item.software~=other.software then return false end
    end
    return true
end
function P.equipment(raw,cargo)
    local wares=JKEOC_SupplyQuote.wares(raw)
    if cargo=='solid' then
        local mining=false
        for _,category in ipairs({'weapons','turrets','turretgroups'}) do
            local n=count(raw['num'..category],4096)
            for i=0,n-1 do
                local item=raw[category][i]
                if category~='turretgroups' or count(item.count,100000)>0 then
                    local macro=ffi.string(item.macro)
                    if macro~='' and GetMacroData(macro,'isminingweapon')==true then mining=true end
                end
            end
        end
        assert(mining,'Generated mineral miner lacks mining equipment')
    end
    return wares
end
function P.price(yard,macro,raw,cargo)
    local wares=P.equipment(raw,cargo)
    local n=count(C.GetNumAvailableEquipment(yard,''),8192)
    assert(n>0,'Supplier equipment catalogue unavailable')
    local buf=ffi.new('EquipmentWareInfo[?]',n)
    assert(count(C.GetAvailableEquipment(buf,n,yard,''),8192)==n,'Supplier equipment catalogue changed')
    local available={}
    for i=0,n-1 do available[ffi.string(buf[i].ware)]=true end
    for _,entry in ipairs(wares) do assert(available[entry.ware],'Supplier lacks equipment: '..entry.ware) end
    local quote=JKEOC_SupplyQuote.read(yard,macro,raw)
    assert(quote.status=='QUOTED',quote.reason)
    return quote
end
function P.read(yardID,macro,cargo)
    local ok,result=pcall(function()
        local yard,key,owned=P.supplier(yardID,macro,cargo)
        local raw=Helper.getLoadoutHelper2(C.GenerateShipLoadout2,C.GenerateShipLoadoutCounts2,'UILoadout2',yard,0,macro,0.5)
        local expected=P.equipment(raw,cargo)
        local software={software={}}
        local n=count(C.GetNumSoftwareSlots(0,macro),128)
        if n>0 then
            local buf=ffi.new('SoftwareSlot[?]',n)
            assert(count(C.GetSoftwareSlots(buf,n,0,macro),128)==n,'Software slots changed')
            for i=0,n-1 do software.software[#software.software+1]={maxsoftware=ffi.string(buf[i].max),currentsoftware=ffi.string(buf[i].current)} end
        end
        local plan=Helper.convertLoadout(0,macro,raw,software,'UILoadout2')
        plan.deployable={};plan.countermeasure={};plan.crew={};plan.hascrewexperience=false
        local quote=Helper.callLoadoutFunction(plan,nil,function(final)
            assert(P.same(expected,P.equipment(final,cargo)),'Generated equipment changed during serialization')
            return P.price(yard,macro,final,cargo)
        end,nil,'UILoadout2')
        quote.plan=plan;quote.cargo=cargo;quote.yard=key;quote.owned=owned
        quote.reason='Supply hull and equipment checked. Persistent budget approval and final recheck required before ordering.'
        return quote
    end)
    Helper.ffiClearNewHelper()
    if ok then return result end
    return {status='UNVERIFIED',permission=false,reason='Supply preparation unavailable: '..tostring(result)}
end
