"""Report snapshot lifetime across mutable source changes, tabs and pagination."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path("tools/qa/lua_test_prelude.lua").read_text())
lua.execute("""
dfhack={df2utf=function(s)return s end}
rows={};for i=0,129 do rows[#rows+1]={id=i,type=i%2,text='before '..i}end
df={announcement_type={[0]='A',[1]='B'},global={world={status={reports=vec(rows),next_report_id=130},units={all=vec({})}}}}
function classify(name)return name=='A' and 2 or 3 end
function mapped(r)return {id=r.id,text=r.text,position={x=1,y=2,z=3}}end
""")
read,reset,read_text=lua.execute(Path("bridge/plugin/report_tab_snapshot.lua").read_text())(lua.globals().classify,lua.globals().mapped)
def call(**kw):return read(lua.table_from(dict(tab=kw.pop('tab',1),**kw)))
def ids(page):return [r['id'] for r in page['reports'].values()]
first=call();rev=first['list_revision'];assert rev>0 and ids(first)==list(range(64))
assert ids(call(from_end=True,expected_list_revision=rev))==list(range(66,130))
assert ids(call(before_id=66,expected_list_revision=rev))==list(range(2,66))
# Continuations consult no native world data, even for a never-visited category.
lua.execute("saved_world=df.global.world;df.global.world=nil")
assert ids(call(tab=2,expected_list_revision=rev))==list(range(0,128,2))
lua.execute("df.global.world=saved_world")
# Change existing contents and remove/append source rows while the screen is open.
lua.execute("rows[1].text='changed';table.remove(rows,2);rows[#rows+1]={id=130,type=1,text='added'};df.global.world.status.reports=vec(rows)")
page=call(after_id=63,expected_list_revision=rev);assert ids(page)==list(range(64,128)) and page['total']==130
named=call(tab=3,expected_list_revision=rev);assert ids(named)==list(range(1,128,2))
assert call(expected_list_revision=rev)['reports'][1]['text']=='before 0'
# Returned page edits cannot corrupt the retained snapshot, including nested data.
first['reports'][1]['position']['x']=900;first['tab_counts'][1]=0
assert call(expected_list_revision=rev)['reports'][1]['position']['x']==1
assert call(expected_list_revision=rev)['tab_counts'][1]==130
fresh=call();assert fresh['list_revision']>rev and fresh['reports'][1]['text']=='changed'
assert not call(expected_list_revision=rev)['ok']
rev=fresh['list_revision'];reset();assert not call(expected_list_revision=rev)['ok']
assert call()['list_revision']>rev
# Failed oversized captures do not retire the last valid snapshot.
valid=call();rev=valid['list_revision']
lua.execute("rows={};for i=0,2047 do rows[#rows+1]={id=i,type=0,text=string.rep('x',16384)}end;df.global.world.status.reports=vec(rows)")
assert call()['message']=='Report snapshot exceeds 32 MiB'
assert call(expected_list_revision=rev)['ok']
assert not call(after_id=0,before_id=1)['ok']
assert not call(expected_list_revision=-1)['ok']


# Full text belongs to the same tab snapshot, not to a fresh per-report capture.
lua.execute("rows={{id=7,type=0,text=string.rep('a',16383)..utf8.char(0x263a)..string.rep('z',30000)}};df.global.world.status.reports=vec(rows)")
opened=call();rev=opened['list_revision'];expected=lua.globals().rows[1]['text']
assert not opened['reports'][1]['text_complete'] and len(opened['reports'][1]['text'].encode())==16383
lua.execute("saved=df.global.world;df.global.world=nil;rows[1].text='new source text'")
def text_page(**kw):return read_text(lua.table_from(dict(id=kw.pop('id',7),tab=kw.pop('tab',1),expected_list_revision=kw.pop('expected_list_revision',rev),**kw)))
page=text_page();parts=[]
while True:
    assert page['ok'] and page['list_revision']==rev and page['total']==len(expected.encode())
    parts.append(page['reports'][1]['text'])
    if not page['next_cursor']:break
    page=text_page(cursor=page['next_cursor'])
assert ''.join(parts)==expected
assert text_page(tab=2)['ok'] and not text_page(tab=3)['ok']
assert not text_page(expected_list_revision=0)['ok'] and not text_page(id=999)['ok']
assert not text_page(cursor=16384)['ok']
assert not text_page(cursor=len(expected.encode()))['ok']
lua.execute("df.global.world=saved")
fresh=call();assert fresh['reports'][1]['text']=='new source text'
assert not text_page()['ok']
reset();assert not text_page(expected_list_revision=fresh['list_revision'])['ok']
print('REPORT_TAB_SNAPSHOT_PASS')
