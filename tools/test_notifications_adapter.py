from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
lua.execute('''
local stdipairs=ipairs
function report(id,text)
 return {id=id,text=text or 'Report '..id,type=0,year=106,time=139200,repeat_count=2,flags={continuation=id%2==1},zoom_type=0,zoom_type2=1,pos={x=2,y=3,z=4},pos2={x=2,y=3,z=4}}
end
rows={};for i=0,1099 do rows[#rows+1]=report(i)end
df={announcement_type={[0]='CANCEL_JOB',[1]='MOOD_BUILDING_CLAIMED',[2]='CITIZEN_DEATH'},report_zoom_type={NONE=-1,Generic=0,Item=1,Unit=2},global={world={status={reports=vec(rows),announcements=vec(rows)}}}}
df.report={find=function(id)for _,r in stdipairs(rows)do if r.id==id then return r end end end}
dfhack={df2utf=function(s)return s end,maps={isValidTilePos=function(p)return p.x>=0 and p.x<100 end,getTileFlags=function(p)return {hidden=p.y==99}end}}
function request(seq,id,before,query,only)
 return {seq=seq,action=id>=0 and 35 or 34,report={id=id,before_id=before,query=query or '',announcements_only=only~=false}}
end
''')
# The shared native-vector mock must reject both read and write bounds violations.
lua.execute('''
local v=vec({report(0)})
assert(v[0].id==0)
for _,index in ipairs({-1,1}) do
 assert(not pcall(function() return v[index] end))
 assert(not pcall(function() v[index]=report(99) end))
end
''')
helper=lua.execute(Path('bridge/plugin/reports.lua').read_text(),
    lua.execute(Path('bridge/plugin/report_tabs.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_tab_page.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_unit_profession.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_unit_page.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_unit_snapshot.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_entries.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_tab_snapshot.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_text_snapshot.lua').read_text()),
    lua.execute(Path('bridge/plugin/report_group_snapshot.lua').read_text()))
def call(seq=1,id=-1,before=-1,query='',only=True):
    return helper(lua.globals().request(seq,id,before,query,only))
page=call()
assert len(page['reports'])==16 and page['reports'][1]['id']==1099
assert page['next_before_id']==1084
second=call(seq=2,before=page['next_before_id'])
assert second['reports'][1]['id']==1083
zero=call(seq=3,id=0)['reports'][1]
assert zero['id']==0 and zero['repeat_count']==2 and zero['position_visible']
assert zero['position2_visible'] and zero['x2']==2
assert call(seq=4,id=1)['reports'][1]['continuation']
lua.execute('rows[1].pos.y=99')
assert call(seq=5,id=0)['reports'][1]['position_visible']
pending=call(seq=6,query='Report 0')
assert pending['pending'] and pending['message']=='Searching native reports' and pending['reports'] is None
# Expire old native rows between bounded continuation calls.
lua.execute("table.remove(rows,1);df.global.world.status.announcements=vec(rows)")
pending=call(seq=6,query='Report 0')
while pending['pending']:
    pending=call(seq=6,query='Report 0')
assert len(pending['reports'])==0
lua.execute("rows={};for i=0,19 do rows[#rows+1]=report(i,string.rep('x',20000))end;df.global.world.status.announcements=vec(rows)")
large=call(seq=7)
assert len(large['reports'])==8
assert sum(len(large['reports'][i]['text']) for i in range(1,9))==131072
assert not large['reports'][1]['text_complete']
missing=call(seq=8,id=999999)
assert not missing['ok'] and missing['message']=='Report no longer exists'
lua.execute("dfhack.df2utf=function(s)return s:gsub('x',utf8.char(0x263a))end")
unicode=call(seq=9,id=0)['reports'][1]
assert len(unicode['text'].encode('utf-8'))==16383
assert unicode['text'].endswith('\u263a') and not unicode['text_complete']

# Native reports preserve stored positions for every zoom kind, including NONE.
# Evidence: fixtures/reports/recenter.json and e7/e11 hidden/item/unit captures.
lua.execute("dfhack.df2utf=function(s)return s end;rows={report(0),report(41)};df.global.world.status.announcements=vec(rows)")
for first in (-1,0,1,2):
    for second in (-1,0,1,2):
        lua.execute(f"rows[1].zoom_type={first};rows[1].zoom_type2={second}")
        row=call(id=0)['reports'][1]
        for suffix in ('','2'):
            assert row['position'+suffix+'_visible']
            assert tuple(row[k+suffix] for k in ('x','y','z'))==(2,3,4)
for pos in ('pos','pos2'):
    for source,expected in [('{x=-1,y=50,z=165}',(-1,50,165)),
                            ('{x=5000,y=5000,z=5000}',(5000,5000,5000)),
                            ('{x=2,y=99,z=4}',(2,99,4)),
                            ('{x=-30000,y=-30000,z=-30000}',None),('nil',None)]:
        lua.execute(f"rows[1]=report(0);rows[1].{pos}={source}")
        row=call(id=0)['reports'][1]
        suffix='2' if pos=='pos2' else ''
        assert row['position'+suffix+'_visible']==(expected is not None)
        assert tuple(row[k+suffix] for k in ('x','y','z'))==(expected or (-1,-1,-1))
        assert row['position'+('' if suffix else '2')+'_visible']
for kind,category in [(0,'CANCEL_JOB'),(1,'MOOD_BUILDING_CLAIMED'),(999,'Unknown')]:
    lua.execute(f"rows[1].type={kind}")
    row=call(id=0)['reports'][1]
    assert row['category']==category and row['year']==106 and row['year_tick']==139200

# build/evidence/native/e7/findings.md:36: pin bridge newest-first pending 08-B.
lua.execute("rows={report(0),report(41,'Doren cancels Store item')};for i=1083,1099 do rows[#rows+1]=report(i)end;df.global.world.status.announcements=vec(rows);df.global.world.status.reports=vec({report(12,'Combat line')})")
page=call(seq=20)
assert [r['id'] for r in page['reports'].values()]==list(range(1099,1083,-1))
assert page['next_before_id']==1084 and page['message']=='Native reports' and page['announcements_only']
page=call(seq=21,before=1084)
assert [r['id'] for r in page['reports'].values()]==[1083,41,0] and page['next_before_id']==-1
page=call(seq=22,only=False)
assert len(page['reports'])==1 and page['reports'][1]['id']==12 and not page['announcements_only']
for seq,query,expected in [(23,'dOrEn',[41]),(24,'41',[41]),(25,'absent',[])]:
    page=call(seq=seq,query=query)
    assert [r['id'] for r in page['reports'].values()]==expected and page['next_before_id']==-1
inspected=call(id=0)
assert inspected['message']=='Native report' and inspected['next_before_id']==-1 and len(inspected['reports'])==1
# Exactly 512 scanned rows finish; 513 need continuation under the same sequence.
for count in (512,513):
    lua.execute(f"rows={{}};for i=0,{count-1} do rows[#rows+1]=report(i)end;df.global.world.status.announcements=vec(rows)")
    page=call(seq=30+count,query='absent')
    if count==513:
        assert page['pending'] and page['message']=='Searching native reports' and page['reports'] is None
        page=call(seq=30+count,query='absent')
    assert not page['pending'] and len(page['reports'])==0 and page['message']=='Native reports'
# At each cap accept the limit, defer the next row, and preserve complete flags.
for count in (16,17):
    lua.execute(f"rows={{}};for i=0,{count-1} do rows[#rows+1]=report(i)end;df.global.world.status.announcements=vec(rows)")
    page=call(seq=600+count)
    assert len(page['reports'])==16 and page['next_before_id']==(-1 if count==16 else 1)
    if count==17:
        page=call(seq=618,before=page['next_before_id'])
        assert len(page['reports'])==1 and page['reports'][1]['id']==0 and page['next_before_id']==-1
for length,complete in [(0,True),(16384,True),(16385,False)]:
    lua.execute(f"rows={{report(0,string.rep('x',{length}))}}")
    row=call(id=0)['reports'][1]
    assert len(row['text'].encode())==min(length,16384) and row['text_complete']==complete
for count in (8,9):
    lua.execute(f"rows={{}};for i=0,{count-1} do rows[#rows+1]=report(i,string.rep('x',16384))end;df.global.world.status.announcements=vec(rows)")
    page=call(seq=700+count)
    assert len(page['reports'])==8 and sum(len(r['text'].encode()) for r in page['reports'].values())==131072
    assert all(r['text_complete'] for r in page['reports'].values())
    assert page['next_before_id']==(-1 if count==8 else 1)
    if count==9:
        page=call(seq=710,before=page['next_before_id'])
        assert len(page['reports'])==1 and page['reports'][1]['id']==0
# Native All excludes deaths by type. Flat mode retains its legacy source and does not
# apply tab membership in Flat mode; Tab mode is checked below.
lua.execute("rows={report(0)};rows[1].type=2;df.global.world.status.announcements=vec(rows)")
page=call(seq=800)
assert len(page['reports'])==1 and page['reports'][1]['category']=='CITIZEN_DEATH'
# Exercise the integrated dispatcher and mapper against native tab evidence.
import json
fixture=json.loads(Path('fixtures/reports/tab_membership.json').read_text())
lua.globals().native_names=lua.table_from({r['type']:r['name'] for r in fixture['rows']})
lua.execute("""
df.announcement_type=native_names
rows={};for i=0,355 do
 local r=report(i);r.type=i;r.color=i%16;r.bright=i%2==1;r.speaker_id=17
 r.zoom_type=i%4-1;r.zoom_type2=-1;r.pos.y=99
 rows[#rows+1]=r
end
df.global.world.status.reports=vec(rows)
df.global.world.status.announcements=vec({})
df.global.world.status.next_report_id=356
df.global.world.units={all=vec({})}
""")
for native in fixture['named_tab_capture']['tabs'][:22]:
    seen=[];cursor=-1;revision=0
    while True:
        req=lua.globals().request(900,-1,-1,'',True)
        req['report']['view']=1;req['report']['tab']=native['native_index']+1
        req['report']['after_id']=cursor;req['report']['expected_list_revision']=revision
        page=helper(req);revision=page['list_revision']
        assert page['ok'] and page['message']=='' and page['list_revision']>0 and page['total']==len(native['types'])
        for row in page['reports'].values():
            i=row['id'];seen.append(i)
            assert row['color']==i%16 and row['bright']==(i%2==1)
            assert row['speaker_id']==17 and row['zoom_type']==i%4+1
            assert row['zoom_type2']==1 and row['position_hidden']
            assert row['position_visible'] and row['y']==99
        cursor=page['next_after_id']
        if cursor<0:break
    assert seen==native['types'],native['name']
# Unit-view dispatcher supplies the required transport envelope as well as counts.
req=lua.globals().request(901,-1,-1,'',True)
req['report']['view']=2;req['report']['unit_category']=0
page=helper(req)
assert page['ok'] and page['message']=='' and page['view']==2 and len(page['units'])==0
lua.execute("df.unit={find=function(id)if id==17 then return {reports={log=vec({vec({0,1}),vec({}),vec({})})}}end end}")
req['report']['view']=3;req['report']['unit_id']=17
page=helper(req)
assert page['ok'] and page['message']=='' and [r['id'] for r in page['reports'].values()]==[0,1]
assert len(page['tab_counts'])==25
req=lua.globals().request(902,-1,-1,'',True)
req['action']=35;req['report']['view']=4;req['report']['ids']=lua.table_from([1,999999,0,1])
page=helper(req)
assert page['ok'] and page['message']=='' and [r['id'] for r in page['reports'].values()]==[1,0,1]
assert list(page['missing_ids'].values())==[999999]
# Fresh unit metadata and Entries reads must never retire the ordinary-tab snapshot.
req=lua.globals().request(903,-1,-1,'',True)
req['report']['view']=1;req['report']['tab']=1
saved=helper(req);revision=saved['list_revision'];expected=[r['id'] for r in saved['reports'].values()]
lua.execute("df.global.world.status.reports=vec({});df.global.world.status.next_report_id=356")
req['report']['view']=2;req['report']['tab']=0;req['report']['unit_category']=0
assert helper(req)['ok']
req['report']['view']=1;req['report']['tab']=1;req['report']['unit_category']=-1;req['report']['expected_list_revision']=revision
assert [r['id'] for r in helper(req)['reports'].values()]==expected

# Text view uses the same native row metadata without its mapped-prefix limit.
lua.execute("rows[1].text=string.rep('z',40000)..' LAST';rows[1].color=3")
request=lua.table_from(dict(action=35,report=lua.table_from(dict(view=5,id=0))))
first=helper(request);assert first['ok'] and first['total']==40005
revision=first['list_revision'];parts=[first['reports'][1]['text']]
while first['next_cursor']:
    request['report']['cursor']=first['next_cursor'];request['report']['expected_list_revision']=revision
    first=helper(request);assert first['ok'] and first['reports'][1]['color']==3
    parts.append(first['reports'][1]['text'])
assert ''.join(parts)=='z'*40000+' LAST'

assert [r['id'] for r in helper(req)['reports'].values()]==expected


# A retained tab's full text survives independent popup Text recapture and source mutation.
lua.execute("df.global.world.status.reports=vec({rows[1]})")
req=lua.table_from(dict(action=34,report=lua.table_from(dict(view=1,tab=1))))
tab=helper(req);tab_revision=tab['list_revision']
lua.execute("rows[1].text='mutated after tab capture'")
request['report']['cursor']=0;request['report']['expected_list_revision']=0
assert helper(request)['reports'][1]['text']=='mutated after tab capture'
request['report']['tab']=1;request['report']['expected_list_revision']=tab_revision
page=helper(request);assert page['ok'] and page['total']==40005
assert page['reports'][1]['text']=='z'*16384
request['report']['cursor']=32768
page=helper(request);assert page['ok'] and page['reports'][1]['text']=='z'*(40000-32768)+' LAST'


# The production factory routes unit-owned Text separately from ordinary tabs.
lua.execute("df.unit.find=function(id)return id==17 and {reports={log=vec({vec({0}),vec({}),vec({})})}} or nil end")
unit_request=lua.table_from(dict(action=34,report=lua.table_from(dict(view=3,unit_id=17,unit_category=0))))
unit_page=helper(unit_request);assert unit_page['ok'] and unit_page['list_revision']>0
unit_revision=unit_page['list_revision']
lua.execute("rows[1].text='edited after unit capture'")
unit_text=lua.table_from(dict(action=35,report=lua.table_from(dict(view=5,id=0,unit_id=17,unit_category=0,expected_list_revision=unit_revision))))
assert helper(unit_text)['reports'][1]['text']=='mutated after tab capture'
assert helper(request)['reports'][1]['text']=='z'*(40000-32768)+' LAST'
# Complete Group routing retains values independently of unit and tab owners.
lua.execute("df.global.world.status.announcement_alert=vec({{type=20,announcement_id=vec({75,75}),report_unid=vec({}),report_unit_announcement_category=vec({})}})")
group=helper(lua.table_from({'action':34,'report':lua.table_from({'view':6,'notification_category':20})}))
assert group['ok'] and group['view']==6 and group['total']==2
text=helper(lua.table_from({'action':35,'report':lua.table_from({'view':5,'notification_category':20,'id':75,'expected_list_revision':group['list_revision']})}))
assert text['ok'] and text['view']==5 and text['notification_category']==20
assert text['reports'][1]['text']==group['reports'][1]['text']
print('NOTIFICATIONS_ADAPTER_PASS')
