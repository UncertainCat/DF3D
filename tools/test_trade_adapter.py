"""Asset-free depot adapter regression; test-only lupa provides Lua execution."""
from pathlib import Path
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local ordinary_ipairs=ipairs
function vec(values)
 return setmetatable({_dfvec=true,data=values or {}},{__len=function(t)return #t.data end,__index=function(t,k)if type(k)=='number' then return t.data[k+1]end end})
end
function ipairs(t)
 if type(t)=='table' and rawget(t,'_dfvec') then local i=-1;return function()i=i+1;if i<#t then return i,t[i]end end end
 return ordinary_ipairs(t)
end
function xyz2pos(x,y,z)return {x=x,y=y,z=z}end
items={}
function item(id)
 local t={id=id,flags={},x=2,y=2,z=1,description='wood '..id,getStackSize=function()return 1 end}
 items[id]=t;return t
end
depot={id=7,centerx=5,centery=5,z=1,kind='depot',stage=3,trade_flags={trader_requested=false,anyone_can_trade=false},accessible=true,jobs=vec({}),contained_items=vec({}),getBuildStage=function(self)return self.stage end,getMaxBuildStage=function()return 3 end}
df={job_type={DestroyBuilding=1,TradeAtDepot=2,BringItemToDepot=3},building_item_role_type={TEMP=0},building={find=function(id)if id==7 then return depot end end},building_tradedepotst={is_instance=function(_,d)return d.kind=='depot' end},item={find=function(id)return items[id]end},historical_entity={find=function()return {name='Mountainhome'}end},caravan_state={T_trade_state={[0]='AtDepot'}},global={world={buildings={other={TRADE_DEPOT=vec({depot})}},items={other={IN_PLAY=vec({})}}},plotinfo={caravans=vec({{entity=1,trade_state=0,time_remaining=240}})}}}
marked=0
reads=0
dfhack={df2utf=function(s)return s end,translation={translateName=function(s)return s end},units={getReadableName=function(u)return u.name end},job={getWorker=function(j)return j.worker end,removeJob=function(j)for i,v in ordinary_ipairs(depot.jobs.data)do if v==j then table.remove(depot.jobs.data,i);break end end end},items={
 canTradeWithContents=function(i)return not (i.flags.in_job or i.flags.owned or i.flags.artifact or i.mandated)end,
 getPosition=function(i)return i.x,i.y,i.z end,getDescription=function(i)reads=reads+1;return i.description end,
 markForTrade=function(i,d)marked=marked+1;i.flags.in_job=true;table.insert(d.jobs.data,{id=100+marked,job_type=3});return true end},
 maps={isValidTilePos=function(p)return p.x~=nil and p.x>=0 end,getTileFlags=function(p)return {hidden=p.y==99}end,canWalkBetween=function(a,b)return a.x~=99 end}}
function request(seq,action,depot_id,item_id,revision,requested,anyone,query,cursor)
 return {seq=seq,action=action,trade={depot_id=depot_id or 7,item_id=item_id or -1,expected_revision=revision or 0,requested=requested or -1,anyone=anyone or -1,query=query or '',cursor=cursor or 0}}
end
function populate(n)
 local rows={};items={};for i=1,n do rows[i]=item(i)end
 df.global.world.items.other.IN_PLAY=vec(rows)
end
''')
helper=lua.execute(Path('bridge/plugin/trade.lua').read_text())
def call(seq=1,action=38,depot=7,item=-1,revision=0,requested=-1,anyone=-1,query='',cursor=0):
    return helper(lua.globals().request(seq,action,depot,item,revision,requested,anyone,query,cursor))
first=call()
assert len(first['depots'])==1 and first['caravans'][1]['id']==0
assert first['caravans'][1]['days_remaining']==2
revision=first['depots'][1]['revision']
assert not call(action=40,revision=1,requested=1)['ok']
assert not lua.globals().depot['trade_flags']['trader_requested']
changed=call(action=40,revision=revision,requested=1)
assert changed['ok'] and changed['depots'][1]['requested']
assert not call(action=40,revision=revision,requested=0)['ok']
lua.execute('depot.jobs=vec({{id=12,job_type=2,worker={name="Broker"}},{id=13,job_type=3}})')
assert call(action=39)['depots'][1]['broker']=='Broker'
assert call(action=40,revision=changed['depots'][1]['revision'],requested=0)['ok']
assert len(lua.globals().depot['jobs']['data'])==1 # only trader job removed
lua.execute('populate(20)')
for flag in ('forbid','removed','garbage_collect','trader','hostile','in_inventory','in_building','construction','on_fire','murder','owned','artifact','in_job'):
    lua.execute('items[1].flags={'+flag+'=true}')
    assert not call(action=42,item=1)['ok'],flag
lua.execute('items[1].flags={};items[1].mandated=true')
assert not call(action=42,item=1)['ok']
lua.execute('items[1].mandated=false;items[1].y=99')
assert not call(action=42,item=1)['ok']
lua.execute('items[1].y=2;items[1].x=99')
assert not call(action=42,item=1)['ok']
lua.execute('items[1].x=2;depot.stage=1')
assert not call(action=42,item=1)['ok']
lua.execute('depot.stage=3')
assert call(action=42,item=1)['ok']
assert not call(action=42,item=1)['ok'] and lua.globals().marked==1
# Sparse search spans updates. ID rows retained in first slice are revalidated.
lua.execute("populate(600);for i=2,600 do items[i].description='stone' end;items[600].description='wood last';reads=0")
page=call(seq=50,action=41,query='wood')
assert page['pending'] and lua.globals().reads==256
lua.execute('items[1].flags.in_job=true')
page=call(seq=50,action=41,query='wood')
assert page['pending']
page=call(seq=50,action=41,query='wood')
assert not page['pending'] and len(page['goods'])==1 and page['goods'][1]['id']==600
# A new request discards a previous pending scan, and replacement world IDs are resolved afresh.
assert call(seq=51,action=41,query='missing')['pending']
lua.execute('populate(3)')
page=call(seq=52,action=41)
assert len(page['goods'])==3 and page['goods'][1]['id']==1
lua.execute('populate(100)')
page=call(seq=53,action=41)
assert len(page['goods'])==64 and page['next_cursor']==64
next_page=call(seq=54,action=41,cursor=64)
assert len(next_page['goods'])==36 and next_page['next_cursor']==0
print('TRADE_ADAPTER_PASS')
