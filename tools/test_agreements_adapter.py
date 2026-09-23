"""Asset-free pinned-shape agreement tests; no native state is changed."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
function vec(values)
 local t={};for i,v in ipairs(values)do t[i-1]=v end
 return setmetatable(t,{__len=function()return #values end})
end
function agr(id,kind,site)
 return {id=id,flags={petition_not_accepted=false,convicted_accepted=false},
 parties=vec({{id=8,entity_ids=vec({1001}),histfig_ids=vec({})},{id=12,entity_ids=vec({1003}),histfig_ids=vec({})}}),
 details=vec({{id=4,type=kind or 12,year=105,year_tick=0,data={Location={site=site or 7,applicant=8,government=12,type=2,tier=1,profession=3,deity_type=-1,deity_data={practice_id=-1}}}}})}
end
rows={};for i=0,1099 do rows[#rows+1]=agr(i)end
df={global={world={agreements={all=vec(rows)}},plotinfo={site_id=7,petitions=vec({0}),continuing_agreement_id=vec({1})}},
agreement_details_type={[12]='Location',[2]='Residency',[99]='Unknown'},abstract_building_type={[2]='GUILDHALL'},profession={[3]='MASON'},religious_practice_type={}}
df.agreement={find=function(id)for _,v in ipairs(rows)do if v.id==id then return v end end end}
df.historical_entity={find=function(id)return {name='Entity '..id}end}
df.historical_figure={find=function(id)return {name='Figure '..id}end}
dfhack={df2utf=function(s)return s end,translation={translateName=function(n)return n end}}
rows[1].flags.petition_not_accepted=true
function request(seq,id,before,query,pending)
 return {seq=seq,action=id>=0 and 37 or 36,agreement={id=id,before_id=before,query=query or '',pending_only=pending or false}}
end
''')
helper = lua.execute(Path('bridge/plugin/agreements.lua').read_text())

def call(seq=1, id=-1, before=-1, query='', pending=False):
    return helper(lua.globals().request(seq, id, before, query, pending))

page = call()
assert len(page['agreements']) == 16 and page['agreements'][1]['id'] == 1099
assert page['next_before_id'] == 1084
assert call(2, before=1084)['agreements'][1]['id'] == 1083
zero = call(3, id=0)['agreements'][1]
assert zero['status'] == 0 and zero['not_approved']
assert zero['parties'][1]['id'] == 8 and zero['parties'][1]['entity_ids'][1] == 1001
assert zero['details'][1]['applicant_party'] == 8
assert call(4, id=1)['agreements'][1]['continuing']
assert call(5, id=2)['agreements'][1]['status'] == 1
lua.execute('rows[3].flags.petition_not_accepted=true;rows[4].flags.convicted_accepted=true')
assert call(6, id=2)['agreements'][1]['status'] == 2
assert call(7, id=3)['agreements'][1]['status'] == 3
# Unknown union arm must never read Location. Nonlocal records are excluded.
lua.execute("rows[5].details[0].type=99;rows[5].details[0].data=setmetatable({},{__index=function()error('union read')end});df.global.plotinfo.petitions=vec({0,4});rows[6].details[0].data.Location.site=900")
unknown = call(8, id=4)['agreements'][1]
assert unknown['details'][1]['kind'] == 99 and not unknown['complete']
assert 'terms are not yet displayed' in unknown['reason']
assert not call(9, id=5)['ok']
value = call(10, pending=True)
assert value['pending']
while value['pending']:
    value = call(10, pending=True)
assert len(value['agreements']) == 2
# Searches inspect at most16 records per update and tolerate removal.
value = call(11, query='no-match')
assert value['pending']
lua.execute('table.remove(rows,1);df.global.world.agreements.all=vec(rows)')
while value['pending']:
    value = call(11, query='no-match')
assert len(value['agreements']) == 0
lua.execute("rows[2].parties[0].entity_ids=vec({1001});dfhack.translation.translateName=function(n)return string.rep('x',3000)end;dfhack.df2utf=function(s)return s:gsub('x',utf8.char(0x263a))end")
value = call(12, id=2)['agreements'][1]
assert not value['complete']
assert len(value['parties'][1]['name'].encode('utf-8')) <= 2048
assert value['parties'][1]['name'].endswith('\u263a')
assert not call(13, id=999999)['ok']
lua.execute("rows[7].details[0].type=2;rows[7].details[0].data={Residency={site=7,applicant=8,government=12,end_year=120,end_season_tick=300,reason=0}}")
partial = call(14, id=7)['agreements'][1]
assert not partial['complete'] and 'terms are not yet displayed' in partial['reason']
print('AGREEMENTS_ADAPTER_PASS')
