from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
local stdipairs=ipairs
function vec(values)
 local t={};for i,v in stdipairs(values)do t[i-1]=v end
 return setmetatable(t,{__len=function()return #values end})
end
function report(id,text)
 return {id=id,text=text or 'Report '..id,type=0,year=106,time=139200,repeat_count=2,flags={continuation=id%2==1},zoom_type=0,zoom_type2=1,pos={x=2,y=3,z=4},pos2={x=2,y=3,z=4}}
end
rows={};for i=0,1099 do rows[#rows+1]=report(i)end
df={announcement_type={[0]='CANCEL_JOB',[1]='MOOD_BUILDING_CLAIMED',[2]='CITIZEN_DEATH'},report_zoom_type={Generic=0,Unit=1,Item=2},global={world={status={reports=vec(rows),announcements=vec(rows)}}}}
df.report={find=function(id)for _,r in stdipairs(rows)do if r.id==id then return r end end end}
dfhack={df2utf=function(s)return s end,maps={isValidTilePos=function(p)return p.x>=0 and p.x<100 end,getTileFlags=function(p)return {hidden=p.y==99}end}}
function request(seq,id,before,query,only)
 return {seq=seq,action=id>=0 and 35 or 34,report={id=id,before_id=before,query=query or '',announcements_only=only~=false}}
end
''')
helper=lua.execute(Path('bridge/plugin/reports.lua').read_text())
def call(seq=1,id=-1,before=-1,query='',only=True):
    return helper(lua.globals().request(seq,id,before,query,only))
page=call()
assert len(page['reports'])==16 and page['reports'][1]['id']==1099
assert page['next_before_id']==1084
second=call(seq=2,before=page['next_before_id'])
assert second['reports'][1]['id']==1083
zero=call(seq=3,id=0)['reports'][1]
assert zero['id']==0 and zero['repeat_count']==2 and zero['position_visible']
assert not zero['position2_visible'] and zero['x2']==-1
assert call(seq=4,id=1)['reports'][1]['continuation']
lua.execute('rows[1].pos.y=99')
assert not call(seq=5,id=0)['reports'][1]['position_visible']
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

# reports.lua:13-23. Current coordinate filtering differs from native:
# build/evidence/native/e7/findings.md:12-16; e11/findings.md:10-11,21-23
# (hidden and out-of-map positions still have native go-to buttons). Pin for 08-B.
lua.execute("dfhack.df2utf=function(s)return s end;rows={report(0),report(41)};df.global.world.status.announcements=vec(rows)")
for first, second in [(0,0),(1,0),(2,0),(0,1),(0,2)]:
    lua.execute(f"rows[1].zoom_type={first};rows[1].zoom_type2={second}")
    row=call(id=0)['reports'][1]
    for suffix,visible in [('',first==0),('2',second==0)]:
        assert row['position'+suffix+'_visible']==visible
        assert tuple(row[k+suffix] for k in ('x','y','z'))==((2,3,4) if visible else (-1,-1,-1))
for pos in ('pos','pos2'):
    for bad in ('{x=-1,y=3,z=4}', '{x=100,y=3,z=4}', '{x=2,y=99,z=4}', 'nil'):
        lua.execute(f"rows[1]=report(0);rows[1].zoom_type2=0;rows[1].{pos}={bad}")
        row=call(id=0)['reports'][1]
        suffix='2' if pos=='pos2' else ''
        assert not row['position'+suffix+'_visible']
        assert tuple(row[k+suffix] for k in ('x','y','z'))==(-1,-1,-1)
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
# build/evidence/native/e11/findings.md:6-9: native All excludes deaths by type. reports.lua does not
# apply tab membership; preserve its unfiltered announcement source for 08-B/E1.
lua.execute("rows={report(0)};rows[1].type=2;df.global.world.status.announcements=vec(rows)")
page=call(seq=800)
assert len(page['reports'])==1 and page['reports'][1]['category']=='CITIZEN_DEATH'
print('NOTIFICATIONS_ADAPTER_PASS')
