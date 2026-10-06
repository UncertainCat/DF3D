"""Reports tab paging against independently captured native membership."""
import json
from pathlib import Path
from lupa import LuaRuntime

lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path("tools/qa/lua_test_prelude.lua").read_text())
fixture=json.loads(Path("fixtures/reports/tab_membership.json").read_text())
lua.globals().names=lua.table_from({r["type"]:r["name"] for r in fixture["rows"]})
lua.execute("""
rows={};for i=0,355 do rows[#rows+1]={id=i,type=i,text='Fixture '..i}end
units={{reports={log=vec({vec({-1}),vec({}),vec({9})})}},{reports={log=vec({vec({}),vec({2}),vec({})})}}}
df={announcement_type=names,global={world={status={reports=vec(rows),next_report_id=356},units={all=vec(units)}}}}
function map_row(r)return {id=r.id,text=r.text}end
""")
classify=lua.execute(Path("bridge/plugin/report_tabs.lua").read_text())
read=lua.execute(Path("bridge/plugin/report_tab_page.lua").read_text())(classify,lua.globals().map_row)
def call(tab=1,**kw):return read(lua.table_from(dict(tab=tab,**kw)))
def ids(page):return [r['id']for r in page['reports'].values()]
for native in fixture['named_tab_capture']['tabs'][:22]:
    expected=native['types'];actual=[];cursor=-1
    while True:
        page=call(native['native_index']+1,after_id=cursor)
        assert page['ok']
        actual+=ids(page)
        assert page['total']==len(expected)
        assert page['tab_counts'][native['native_index']+1]==len(expected)
        assert [page['tab_counts'][i]for i in (23,24,25)]==[1,1,1]
        cursor=page['next_after_id']
        if cursor<0:break
    assert actual==expected,native['name']
    actual=[];page=call(native['native_index']+1,from_end=True)
    while True:
        actual=ids(page)+actual
        cursor=page['next_before_id']
        if cursor<0:break
        page=call(native['native_index']+1,before_id=cursor)
    assert actual==expected,native['name']
assert not call(23)['ok']
assert not call(after_id=0,before_id=20)['ok']
# Flags/display vectors never determine native tab membership; only globals/types.
lua.execute('df.global.world.status.announcements=vec({});for _,r in ipairs(rows)do r.flags={announcement=false}end')
assert call()['total']==233
# Paused changes are read fresh, with no stale index retained between pages.
first=call();cursor=first['next_after_id']
lua.execute('while rows[1].id<=100 do table.remove(rows,1)end;df.global.world.status.reports=vec(rows)')
page=call(after_id=0)
assert page['gap'] and page['trimmed_through']==100 and all(i>100 for i in ids(page))
page=call(after_id=100);assert not page['gap']
# Wire byte budget shortens a page without skipping rows in either direction.
lua.execute("rows={};for i=0,19 do rows[#rows+1]={id=i,type=0,text=string.rep('x',16384)}end;df.global.world.status.reports=vec(rows);df.global.world.status.next_report_id=20")
a=call();assert ids(a)==list(range(8)) and a['next_after_id']==7
b=call(after_id=a['next_after_id']);assert ids(b)==list(range(8,16))
c=call(from_end=True);assert ids(c)==list(range(12,20)) and c['next_before_id']==12
d=call(before_id=c['next_before_id']);assert ids(d)==list(range(4,12))
lua.execute('rows={};df.global.world.status.reports=vec(rows)')
assert call(after_id=0)['gap'] and call()['total']==0
# Unknown types are refused rather than silently classified as General.
lua.execute("rows={{id=20,type=999,text='Fixture'}};df.global.world.status.reports=vec(rows)")
assert not call()['ok']
print('REPORT_TAB_PAGE_PASS')
