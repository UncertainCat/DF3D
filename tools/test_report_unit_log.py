"""Semantic unit logs: retained native IDs, cursor completeness and expiration."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
lua.execute("""
ids={};retained={}
for i=0,9999 do ids[#ids+1]=i;if i>=100 and i%7~=0 then retained[i]={id=i,text='Fixture '..i}end end
unit={id=17,reports={log=vec({vec(ids),vec({}),vec({})})}}
df={unit={find=function(id)if id==17 then return unit end end},report={find=function(id)return retained[id]end}}
function row(r)return {id=r.id,text=r.text}end
""")
read=lua.execute(Path('bridge/plugin/report_unit_log.lua').read_text())(lua.globals().row)
def call(**kw):return read(lua.table_from(dict(unit_id=17,unit_category=0,**kw)))
def rows(page):return [r['id'] for r in page['reports'].values()]
expected=[i for i in range(100,10000) if i%7!=0]
for backwards in (False,True):
    actual=[];cursor=-1;first=True
    while True:
        args={'from_end':True} if backwards and first else {('before_id' if backwards else 'after_id'):cursor}
        page=call(**args);assert page['ok'] and page['total']==len(expected)
        actual=rows(page)+actual if backwards else actual+rows(page)
        cursor=page['next_before_id' if backwards else 'next_after_id'];first=False
        if cursor<0:break
    assert actual==expected
assert call(after_id=0)['gap'] and call()['trimmed_through']==99
assert not call(after_id=99)['gap']
assert not call(after_id=1,before_id=500)['ok']
assert not call(after_id=0,from_end=True)['ok']
assert not read(lua.table_from(dict(unit_id=999,unit_category=0)))['ok']
# Trimming/expiry and later growth are observed on the next paused request.
p=call();cursor=p['next_after_id']
lua.execute('for i=0,1000 do retained[i]=nil end;unit.reports.log[0]:insert("#",10000);retained[10000]={id=10000,text="New"}')
p=call(after_id=cursor);assert p['gap'] and all(i>1000 for i in rows(p))
assert rows(call(from_end=True))[-1]==10000
# Payload-limited pages preserve progress in both directions.
lua.execute("ids={};retained={};for i=0,19 do ids[#ids+1]=i;retained[i]={id=i,text=string.rep('x',16384)}end;unit.reports.log[0]=vec(ids)")
a=call();assert rows(a)==list(range(8))
assert rows(call(after_id=a['next_after_id']))==list(range(8,16))
a=call(from_end=True);assert rows(a)==list(range(12,20))
assert rows(call(before_id=a['next_before_id']))==list(range(4,12))
lua.execute('retained={}')
assert call(after_id=0)['gap'] and call()['total']==0
lua.execute('unit.reports.log[0]=vec({})')
assert call()['total']==0 and call()['next_after_id']==-1
lua.execute('unit.reports.log[0]=vec({1,1})')
assert not call()['ok']
lua.execute('unit.reports.log[0]=vec({2,1})')
assert not call()['ok']
print('REPORT_UNIT_LOG_PASS')
