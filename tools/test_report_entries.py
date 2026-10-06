"""Explicit references preserve alert source order, expiry and UTF-8 boundaries."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
reports={[0]={id=0,text='Fixture zero'},[41]={id=41,text=string.rep(utf8.char(0x263a),1000)}}
units={[17]={id=17}}
df={report={find=function(id)return reports[id]end},unit={find=function(id)return units[id]end}}
function report_row(r)return {id=r.id,text=r.text,text_complete=true}end
function unit_row(u,c)return {unit_id=u.id,category=c,name='Fixture'}end
""")
read=lua.execute(Path('bridge/plugin/report_entries.lua').read_text())(lua.globals().report_row,lua.globals().unit_row)
def call(ids=(),units=()):return read(lua.table_from(dict(ids=lua.table_from(ids),units=lua.table_from([lua.table_from(dict(unit_id=u,category=c)) for u,c in units]))))
p=call([41,999,0],[(17,1),(17,0)])
assert p['ok'] and [r['id'] for r in p['reports'].values()]==[41,0]
assert list(p['missing_ids'].values())==[999]
assert [r['category'] for r in p['units'].values()]==[1,0]
assert len(p['reports'][1]['text'].encode())==3000 and p['reports'][1]['text_complete']
assert p['reports'][2]['text_complete']
assert not call()['ok'];assert [r['id'] for r in call([0,0])['reports'].values()]==[0,0]
assert len(call(units=[(17,0),(17,0)])['units'])==2
assert not call([-1])['ok'];assert not call(units=[(17,3)])['ok']
assert call(units=[(99,0)])['ok'] and len(call(units=[(99,0)])['units'])==0
assert call(range(64))['ok'];assert not call(range(65))['ok']
lua.execute("reports[41].text=string.rep('x',2048)")
assert call([41])['reports'][1]['text_complete']
lua.execute("reports[41].text=string.rep('x',2049)")
assert call([41])['reports'][1]['text_complete']
# Long native popup rows must survive a singleton read. Bulk requests remain
# bounded, with UTF-8-safe incomplete prefixes that can be resolved separately.
lua.execute("reports[41].text=string.rep('x',6408)")
assert len(call([41])['reports'][1]['text'])==6408 and call([41])['reports'][1]['text_complete']
lua.execute("reports[41].text=string.rep(utf8.char(0x263a),5462)")
assert len(call([41])['reports'][1]['text'].encode())==16383
assert not call([41])['reports'][1]['text_complete']
bulk=call([41]*64)
assert len(bulk['reports'])==64 and sum(len(r['text'].encode()) for r in bulk['reports'].values())==64*2046
assert all(not r['text_complete'] for r in bulk['reports'].values())
# Independent recorded popup ordering: sixteen reports, then one Sparring unit.
import json
fixture=json.loads(Path('fixtures/reports/alert_entries.json').read_text())
ids=[r['id'] for r in fixture['rows'] if r['kind']=='report']
refs=[(r['id'],fixture['unit_categories'][str(r['id'])]) for r in fixture['rows'] if r['kind']=='unit']
lua.globals().native_ids=lua.table_from(ids)
lua.execute("reports={};for _,id in ipairs(native_ids)do reports[id]={id=id,text='Synthetic row'}end;units[6837]={id=6837}")
p=call(ids,refs);assert p['ok']
actual=[('report',r['id']) for r in p['reports'].values()]+[('unit',r['unit_id']) for r in p['units'].values()]
assert actual==[(r['kind'],r['id']) for r in fixture['rows']]
capture=fixture['expiry_duplicate_capture']
ids=capture['source_refs']['report_ids']
refs=[(r['unit_id'],r['category']) for r in capture['source_refs']['units']]
lua.globals().native_ids=lua.table_from([r['report_id'] for r in capture['native_rows'] if r['report_id']>=0])
lua.execute("reports={};for _,id in ipairs(native_ids)do reports[id]={id=id,text='Synthetic row'}end")
p=call(ids,refs);assert p['ok']
actual=[dict(report_id=r['id'],unit_id=-1,category=-1) for r in p['reports'].values()]+[dict(report_id=-1,unit_id=r['unit_id'],category=r['category']) for r in p['units'].values()]
assert actual==capture['native_rows']
assert list(p['missing_ids'].values())==[2147483647]
print('REPORT_ENTRIES_PASS')
