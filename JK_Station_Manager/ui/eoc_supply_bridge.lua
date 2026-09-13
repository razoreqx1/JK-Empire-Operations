-- Bounded MD-driven transport. No UI/page/open hook can start purchasing.
local ffi=require('ffi')
local C=ffi.C
local B={quotes={},pending=nil}
JKEOC_SupplyBridge=B
local fields={station=true,yard=true,cargo=true,cursor=true,macro=true,price=true,task=true,reserve=true,orderCap=true}
local function send(control,payload) AddUITriggeredEvent('JKEOC_SettingsMenu','supply.'..control,payload) end
local function key(v)
    local id=JKEOC_SupplyReceipts.key(v)
    if not id and type(v)=='userdata' then
        local ok,result=pcall(ConvertIDTo64Bit,v)
        if ok then id=JKEOC_SupplyReceipts.key(result) end
    end
    return id
end
function B.begin(value)
    B.pending=nil
    if type(value)=='string' and #value<=64 and value:match('^%d+:%d+$') then B.pending={token=value,count=0} end
end
function B.field(name,value)
    local p=B.pending
    if not p then return end
    if not fields[name] or p[name]~=nil then p.invalid=true;return end
    p[name]=value;p.count=p.count+1
end
function B.choose(p)
    local reply={token=p.token,status='END'}
    local yard=assert(key(p.yard),'Invalid supplier')
    local station=assert(key(p.station),'Invalid destination')
    local cursor=assert(JKEOC_SupplyReceipts.integer(p.cursor,2049),'Invalid hull cursor')
    assert(cursor>=1,'Invalid hull cursor')
    local id=ConvertStringTo64Bit(yard)
    local n=assert(JKEOC_SupplyReceipts.integer(C.GetNumContainerBuilderMacros(id),2048),'Supplier catalogue above bound')
    if cursor>n then return reply end
    local buf=ffi.new('const char*[?]',n)
    assert(tonumber(C.GetContainerBuilderMacros(buf,n,id))==n,'Supplier catalogue changed')
    -- Stable sorted catalogue, one prepared hull per pulse; no nested galaxy scan.
    local hulls,seen={},{}
    for i=0,n-1 do
        local macro=ffi.string(buf[i]);assert(macro~='' and not seen[macro],'Ambiguous hull catalogue')
        seen[macro]=true;hulls[#hulls+1]=macro
    end
    table.sort(hulls)
    local macro=hulls[cursor]
    reply.status='NEXT';reply.cursor=cursor+1
    local q=JKEOC_SupplyPrepare.read(yard,macro,p.cargo)
    if q.status~='QUOTED' then return reply end
    local cap=assert(JKEOC_SupplyReceipts.integer(p.orderCap,1000000000),'Invalid spending ceiling')
    if q.price>cap then return reply end
    q.macro=macro;q.station=station;q.token=p.token;q.preparedAt=getElapsedTime()
    -- At most four active job quotes. Expired quotes carry no financial authority.
    local total=0
    for token,old in pairs(B.quotes) do
        if old.used or getElapsedTime()<old.preparedAt or getElapsedTime()-old.preparedAt>30 then B.quotes[token]=nil else total=total+1 end
    end
    assert(total<4 and not B.quotes[p.token],'Quote cache full or duplicate token')
    B.quotes[p.token]=q
    return {token=p.token,status='QUOTED',macro=macro,price=q.price,owned=q.owned}
end
function B.execute(operation)
    local p=B.pending;B.pending=nil
    if not p or p.invalid or p.count~=9 then return end
    p.station=key(p.station);p.yard=key(p.yard)
    if not p.station or not p.yard then return end
    if operation=='quote' then
        local ok,result=pcall(B.choose,p)
        send('quote',ok and result or {token=p.token,status='UNVERIFIED'})
    elseif operation=='permit' then
        local q=B.quotes[p.token]
        -- Exact MD-consumed permit must match the unspent quote, not replace it.
        if not q or q.station~=p.station or q.yard~=p.yard or q.macro~=p.macro or q.price~=p.price then return end
        local result=JKEOC_SupplySubmit.execute(q,{consumed=true,token=p.token,station=p.station,yard=p.yard,macro=p.macro,price=p.price,orderCap=p.orderCap,reserve=p.reserve})
        B.quotes[p.token]=nil;result.token=p.token
        send('receipt',result)
    elseif operation=='receipt' then
        local result=JKEOC_SupplyReceipts.read({task=p.task,yard=p.yard,macro=p.macro,price=p.price})
        send('observed',{token=p.token,task=p.task,status=result.status,object=result.component or ''})
    end
end
RegisterEvent('JKEOC_Supply.begin',function(_,v) B.begin(v) end)
for name in pairs(fields) do local field=name;RegisterEvent('JKEOC_Supply.'..field,function(_,v) B.field(field,v) end) end
RegisterEvent('JKEOC_Supply.execute',function(_,v) B.execute(v) end)
function B.policyBegin(v)
    B.policyPending=nil
    if type(v)=='number' and v==math.floor(v) and v>0 and v<2147483000 and v>(B.policySequence or 0) then B.policyPending={sequence=v,count=0} end
end
function B.policyField(name,v)
    local p=B.policyPending;if not p then return end
    if p[name]~=nil then p.invalid=true;return end
    if name=='status' then
        if type(v)~='string' then p.invalid=true;return end
    elseif type(v)~='number' or not JKEOC_SupplyReceipts.integer(v,1000000000) then p.invalid=true;return end
    p[name]=v;p.count=p.count+1
end
function B.policyComplete(v)
    local p=B.policyPending;B.policyPending=nil
    if not p or p.invalid or p.sequence~=v or p.count~=6 or p.enabled>1 or p.orderCap<=0 or p.hourCap<p.orderCap or p.jobs>32 then return end
    B.state=p;B.policySequence=v;B.policyError=nil
    if B.onStatus then B.onStatus() end
end
RegisterEvent('JKEOC_Supply.policy.begin',function(_,v) B.policyBegin(v) end)
for _,name in ipairs({'enabled','orderCap','hourCap','reserve','jobs','status'}) do local field=name;RegisterEvent('JKEOC_Supply.policy.'..field,function(_,v) B.policyField(field,v) end) end
RegisterEvent('JKEOC_Supply.policy.complete',function(_,v) B.policyComplete(v) end)
RegisterEvent('JKEOC_Supply.policy.error',function(_,v)
    B.policyPending=nil;B.state=nil
    B.policyError=type(v)=='string' and v or 'Saved supply settings could not be verified.'
    if B.onStatus then B.onStatus() end
end)
