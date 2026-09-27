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
 details=vec({{id=4,type=kind or 12,year=105,year_tick=0,data={Location={site=site or 7,applicant=8,government=12,type=11,tier=1,profession=9,deity_type=-1,deity_data={practice_id=-1}}}}})}
end
rows={};for i=0,1099 do rows[#rows+1]=agr(i)end
df={global={world={agreements={all=vec(rows)}},plotinfo={site_id=7,petitions=vec({0}),continuing_agreement_id=vec({1})}},
agreement_details_type={[12]='Location',[2]='Residency',[3]='Citizenship',[4]='Parley',[99]='Unknown'},abstract_building_type={[11]='GUILDHALL',[2]='TEMPLE'},profession={[9]='MASON'},religious_practice_type={[0]='WORSHIP_HFID',[1]='RELIGION_ENID'}}
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
assert unknown['reason'] == 'Partial record: some native subject terms are not yet displayed; Pending native petition; response controls are not yet verified'
assert call(9, id=5)['message'] == 'Agreement is unavailable or unrelated to this fortress'
value = call(10, pending=True)
assert value['pending'] and value['message'] == 'Searching native agreements'
while value['pending']:
    value = call(10, pending=True)
assert len(value['agreements']) == 2
# Searches inspect at most16 records per update and tolerate removal.
value = call(11, query='no-match')
assert value['pending'] and value['message'] == 'Searching native agreements'
lua.execute('table.remove(rows,1);df.global.world.agreements.all=vec(rows)')
while value['pending']:
    value = call(11, query='no-match')
assert len(value['agreements']) == 0
lua.execute("rows[2].parties[0].entity_ids=vec({1001});dfhack.translation.translateName=function(n)return string.rep('x',3000)end;dfhack.df2utf=function(s)return s:gsub('x',utf8.char(0x263a))end")
value = call(12, id=2)['agreements'][1]
assert not value['complete']
assert len(value['parties'][1]['name'].encode('utf-8')) <= 2048
assert value['parties'][1]['name'].endswith('\u263a')
assert call(13, id=999999)['message'] == 'Agreement is unavailable or unrelated to this fortress'
lua.execute("rows[7].details[0].type=2;rows[7].details[0].data={Residency={site=7,applicant=8,government=12,end_year=120,end_season_tick=300,reason=0}}")
partial = call(14, id=7)['agreements'][1]
assert not partial['complete'] and partial['reason'] == 'Partial record: some native subject terms are not yet displayed'

# agreements.lua:21 status precedence, :35-57 enum-key descriptions.
# e8/findings.md Native wording and e12/findings.md 2,4,8: pin current bridge
# captions and indistinguishable denial/lapse pending 07-B.
PARTIAL = 'Partial record: some native subject terms are not yet displayed'
LIMIT = 'Partial record: native data, names or text are unavailable or exceed display limits'
PENDING = 'Pending native petition; response controls are not yet verified'
DETAIL = 'Pending means a native unapproved petition. Accepted and concluded are native states; no denial or expiry is inferred.'
seq = 100

def fresh(code=''):
    lua.execute('''
    rows={agr(0)};df.global.world.agreements.all=vec(rows)
    df.global.plotinfo.petitions=vec({});df.global.plotinfo.continuing_agreement_id=vec({})
    dfhack.df2utf=function(s)return s end
    dfhack.translation.translateName=function(n)return n end
    df.historical_entity.find=function(id)return {name='Entity '..id}end
    df.historical_figure.find=function(id)return {name='Figure '..id}end
    ''' + code)

def inspect():
    global seq
    seq += 1
    reply = call(seq, id=0)
    assert reply['ok'] and reply['message'] == 'Native agreements'
    assert reply['detail'] == DETAIL and reply['next_before_id'] == -1
    return reply['agreements'][1]

def listed(**kwargs):
    global seq
    seq += 1
    reply = call(seq, **kwargs)
    while reply['pending']:
        assert reply['message'] == 'Searching native agreements'
        reply = call(seq, **kwargs)
    return reply

fresh()
v = inspect()
assert v['complete'] and v['reason'] == ''
assert v['summary'] == v['details'][1]['description'] == 'GUILDHALL tier 1 for MASON'
for practice, expected in [(0, 'Figure 55'), (1, 'Entity 55'), (9, 'Unknown religious practice')]:
    fresh(f'local d=rows[1].details[0].data.Location;d.type=2;d.deity_type={practice};d.deity_data.practice_id=55')
    v = inspect()
    assert v['details'][1]['description'] == 'TEMPLE tier 1 / ' + expected
    assert v['complete'] == (practice != 9)
    assert v['reason'] == (LIMIT if practice == 9 else '')
# :53-57: a recognized practice with a missing target retains complete=true.
# Pin this distinction from an unknown discriminator; 07-B must resolve it.
fresh('local d=rows[1].details[0].data.Location;d.type=2;d.deity_type=1;df.historical_entity.find=function(id)return nil end')
v = inspect()
assert v['details'][1]['description'] == 'TEMPLE tier 1 / Unknown religious practice'
assert v['complete'] and v['reason'] == ''
for kind, name in [(2, 'Residency'), (3, 'Citizenship'), (4, 'Parley')]:
    for pending in [False, True]:
        fresh(f'''local d=rows[1].details[0];d.type={kind};d.data={{['{name}']={{site=7,
        applicant=8,government=12,asker=8,target=12,end_year=120,end_season_tick=300,reason=42}}}}''')
        if pending:
            lua.execute('df.global.plotinfo.petitions=vec({0})')
        v = inspect(); d = v['details'][1]
        assert d['kind'] == kind and d['site_id'] == 7 and d['applicant_party'] == 8 and d['government_party'] == 12
        assert d['description'] == v['summary'] == name and not v['complete']
        assert all(d[key] == -1 for key in ['location_type','tier','profession','deity_type','deity_id'])
        assert v['reason'] == PARTIAL + ('; ' + PENDING if pending else '')
fresh('rows[1].details=vec({});df.global.plotinfo.continuing_agreement_id=vec({0})')
assert inspect()['summary'] == 'Agreement without details'
# Membership overrides site relevance; Pending overrides both native flags.
fresh('rows={agr(0,12,900),agr(1,12,900),agr(2),agr(3),agr(4,12,900)};rows[1].flags={petition_not_accepted=true,convicted_accepted=true};rows[3].flags.petition_not_accepted=true;rows[4].flags.convicted_accepted=true;rows[4].flags.petition_not_accepted=true;df.global.world.agreements.all=vec(rows);df.global.plotinfo.petitions=vec({0});df.global.plotinfo.continuing_agreement_id=vec({1})')
reply = listed(); values = list(reply['agreements'].values())
assert [v['id'] for v in values] == [3,2,1,0]
assert [v['status'] for v in values] == [3,2,1,0]
assert values[2]['continuing'] and not reply['pending_only']
reply = listed(pending=True)
assert reply['pending_only'] and [v['id'] for v in reply['agreements'].values()] == [0]
for query in ['0','GuIlDhAlL','entity 1001','MASON']:
    fresh()
    assert len(listed(query=query)['agreements']) == 1
assert len(listed(query='no-match')['agreements']) == 0
for count in [16,17]:
    fresh(f'rows={{}};for id=0,{count-1} do rows[#rows+1]=agr(id)end;df.global.world.agreements.all=vec(rows)')
    reply = listed()
    assert len(reply['agreements']) == 16 and reply['next_before_id'] == (-1 if count == 16 else 1)
    if count == 17:
        tail = listed(before=reply['next_before_id'])
        assert len(tail['agreements']) == 1 and tail['agreements'][1]['id'] == 0 and tail['next_before_id'] == -1
for field in ['details','parties']:
    for count in [8,9]:
        fresh(f'''local values={{}};for i=0,{count-1} do
        local v=agr(0).{field}[0];v.id=i;values[#values+1]=v end
        rows[1].{field}=vec(values)''')
        v = inspect()
        assert len(v[field]) == 8 and v['complete'] == (count == 8)
        assert v['reason'] == ('' if count == 8 else LIMIT)
for field in ['entity_ids','histfig_ids']:
    for count in [32,33]:
        fresh(f'local ids={{}};for i=1,{count} do ids[#ids+1]=i end;rows[1].parties=vec({{{{id=8,entity_ids=vec({{}}),histfig_ids=vec({{}})}}}});rows[1].parties[0].{field}=vec(ids)')
        v = inspect()
        assert len(v['parties'][1][field]) == 32
        # 32 members retained, only eight names displayed (:64-83).
        assert not v['complete'] and v['reason'] == LIMIT
for count in [8,9]:
    fresh(f'local ids={{}};for i=1,{count} do ids[#ids+1]=i end;rows[1].parties=vec({{{{id=8,entity_ids=vec(ids),histfig_ids=vec({{}})}}}})')
    v = inspect()
    assert v['parties'][1]['name'] == ', '.join('Entity '+str(i) for i in range(1,9))
    assert v['complete'] == (count == 8) and v['reason'] == ('' if count == 8 else LIMIT)
for length in [256,257]:
    fresh(f"dfhack.translation.translateName=function(n)return string.rep('x',{length})end")
    v = inspect()
    assert len(v['parties'][1]['name']) == 256
    assert v['complete'] == (length == 256) and v['reason'] == ('' if length == 256 else LIMIT)
for length in [2048,2049]:
    fresh(f"local d=rows[1].details[0].data.Location;d.type=2;d.deity_type=1;df.historical_entity.find=function(id)return {{name=string.rep('x',{length}-16)}}end;rows[1].parties=vec({{}})")
    v = inspect()
    assert v['details'][1]['description'] == 'TEMPLE tier 1 / ' + 'x'*2032
    assert v['complete'] == (length == 2048) and v['reason'] == ('' if length == 2048 else LIMIT)
fresh("local d=rows[1].details[0].data.Location;d.type=2;d.deity_type=1;df.historical_entity.find=function(id)return {name=string.rep('x',683)}end;rows[1].parties=vec({});dfhack.df2utf=function(s)return s:gsub('x',utf8.char(0x263a))end")
v = inspect()
assert len(v['details'][1]['description'].encode()) == 2047
assert v['details'][1]['description'] == 'TEMPLE tier 1 / ' + chr(0x263a)*677
assert not v['complete'] and v['reason'] == LIMIT
for field in ['petitions','continuing_agreement_id']:
    for count in [4096,4097]:
        fresh(f'local ids={{}};for i=1,{count} do ids[#ids+1]=i end;df.global.plotinfo.{field}=vec(ids)')
        reply = call(900+count, id=0)
        assert reply['ok'] == (count == 4096)
        assert reply['message'] == ('Native agreements' if count == 4096 else 'Agreement membership exceeds supported limit')
# :120-129: six rows cost 110640; seventh costs 9360, exactly 120000.
for over in [False, True]:
    fresh('''rows={};for id=100,107 do
      local a=agr(id);local ds={};a.parties=vec({})
      for j=0,7 do local d=agr(id).details[0];d.id=j;d.data.Location.type=2;
        d.data.Location.deity_type=1;d.data.Location.deity_data.practice_id=id;ds[#ds+1]=d end
      a.details=vec(ds);rows[#rows+1]=a
    end
    rows[2].parties=vec({{id=8,entity_ids=vec({}),histfig_ids=vec({})}})
    df.global.world.agreements.all=vec(rows)
    df.historical_entity.find=function(id)return {name=string.rep('x',(id==101 and 1039 or 2048)-16)}end
    ''')
    if over:
        lua.execute("rows[2].parties[0].histfig_ids=vec({55});df.historical_figure.find=function(id)return {name='x'}end")
    reply = listed()
    assert len(reply['agreements']) == (6 if over else 7)
    assert reply['next_before_id'] == (102 if over else 101)
    if not over:
        def search_bytes(row):
            search = row['summary']
            for party in row['parties'].values(): search += ' ' + party['name']
            for detail in row['details'].values(): search += ' ' + detail['description']
            return len(search.encode()) + len(row['reason'].encode())
        assert sum(search_bytes(row) for row in reply['agreements'].values()) == 120000
    tail = listed(before=reply['next_before_id'])
    assert tail['agreements'][1]['id'] == (101 if over else 100)
print('AGREEMENTS_ADAPTER_PASS')
