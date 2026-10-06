"""Unit membership/order against native rows, plus paging and stale cursor safety."""
import json
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
fixture=json.loads(Path('fixtures/reports/unit_rows.json').read_text())
units={}
for row in fixture['rows']:
    u=units.setdefault(row['unit_id'],dict(row,counts=[0,0,0]))
    u['counts'][row['category']]=row['log_count']
lua.globals().facts=lua.table_from([lua.table_from(dict(u,counts=lua.table_from(u['counts']))) for u in units.values()])
lua.execute("""
units={}
for _,r in ipairs(facts)do
 local logs={};for c=1,3 do local ids={};for i=1,r.counts[c]do ids[i]=-1 end;logs[c]=vec(ids)end
 units[#units+1]={id=r.unit_id,name=r.name,profession=r.profession,dead=r.dead,reports={log=vec(logs)}}
end
df={global={world={units={all=vec(units)}}}}
dfhack={df2utf=function(s)return s end,translation={translateName=function(n)return n end},units={isDead=function(u)return u.dead end}}
function profession(u)return u.profession end
""")
read,mapper=lua.execute(Path('bridge/plugin/report_unit_page.lua').read_text())(lua.globals().profession)
def call(category=0,**kw):return read(lua.table_from(dict(unit_category=category,**kw)))
for category in range(3):
    expected=[r for r in fixture['rows'] if r['category']==category]
    actual=[];cursor=0;revision=0
    while True:
        page=call(category,cursor=cursor,expected_list_revision=revision)
        assert page['ok'];revision=page['list_revision'];assert revision>0
        assert page['total']==len(expected)
        assert list(page['unit_counts'].values())==fixture['counts']
        actual.extend(dict(r) for r in page['units'].values())
        cursor=page['next_cursor']
        if cursor==0:break
    assert [r['unit_id'] for r in actual]==[r['unit_id'] for r in expected]
    for row,fact in zip(actual,expected):
        for key in ('name','profession','dead','log_count'):assert row[key]==fact[key]
# Counts and membership use log references, not retained report IDs.
assert call()['total']==97
page=call();revision=page['list_revision'];cursor=page['next_cursor'];assert cursor==64
lua.execute('units[1].reports.log[0]:resize(0)')
assert not call(cursor=cursor,expected_list_revision=revision)['ok']
assert call()['total']==96
lua.execute("units[2].name=string.rep('x',513)")
row=call()['units'][1];assert row['name']=='' and row['error']=='Unit name exceeds 512 bytes'
assert not call(cursor=999)['ok'];assert not call(-1)['ok'];assert not call(3)['ok']
assert not call(cursor=0.5)['ok']
assert call(unit_id=1012)['total']==1
lua.execute("units[2].name=string.rep('x',512)")
assert len(call()['units'][1]['name'])==512
lua.execute("units={};for i=1,32769 do units[i]={}end;df.global.world.units.all=vec(units)")
assert call()['message']=='Unit list exceeds 32768 units'
lua.execute("units={};for i=1,16385 do units[i]={id=i,reports={log=vec({vec({-1}),vec({}),vec({})})}}end;df.global.world.units.all=vec(units)")
assert call()['message']=='Unit list exceeds 16384 rows'
print('REPORT_UNIT_PAGE_PASS')
