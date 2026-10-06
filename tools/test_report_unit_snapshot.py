"""Retained unit-log history, explicit native refresh and immutable full text."""
from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
lua.execute("""
ids={};reports={};for i=0,139 do ids[#ids+1]=i;if i>=3 then reports[i]={id=i,text='Fixture '..i,color=3}end end
reports[5].text=string.rep('a',16383)..utf8.char(0x263a)..string.rep('b',18000)
unit={reports={log=vec({vec(ids),vec({}),vec({})})}}
df={unit={find=function(id)return id==17 and unit or nil end},report={find=function(id)return reports[id]end}}
dfhack={df2utf=function(s)return s end}
function mapped(r)return {id=r.id,text='mapped prefix',color=r.color,position={x=5}}end
""")
read,text,reset=lua.execute(Path('bridge/plugin/report_unit_snapshot.lua').read_text())(lua.globals().mapped)
def call(**kw):return read(lua.table_from(dict(unit_id=17,unit_category=0,**kw)))
def page_text(**kw):return text(lua.table_from(dict(unit_id=17,unit_category=0,id=5,**kw)))
def ids(page):return [r['id'] for r in page['reports'].values()]
initial=call();revision=initial['list_revision']
assert initial['ok'] and initial['total']==137 and initial['trimmed_through']==2
assert ids(initial)==list(range(3,67))
initial['reports'][1]['position']['x']=999
assert call(expected_list_revision=revision)['reports'][1]['position']['x']==5
assert not initial['reports'][3]['text_complete'] and len(initial['reports'][3]['text'].encode())==16383
expected=lua.globals().reports[5]['text']
# History and text requests do not consult native objects at all.
lua.execute("saved=df;df=nil")
assert ids(call(from_end=True,expected_list_revision=revision))==list(range(76,140))
assert ids(call(after_id=66,expected_list_revision=revision))==list(range(67,131))
first=page_text(expected_list_revision=revision);parts=[first['reports'][1]['text']]
while first['next_cursor']:
    first=page_text(cursor=first['next_cursor'],expected_list_revision=revision)
    assert first['ok'];parts.append(first['reports'][1]['text'])
assert ''.join(parts)==expected
assert not page_text(cursor=16384,expected_list_revision=revision)['ok']
assert not page_text(cursor='bad',expected_list_revision=revision)['ok']
assert not page_text(cursor=9223372036854775807,expected_list_revision=revision)['ok']
lua.execute("df=saved;reports[5].text='edited';reports[5].color=7;reports[4]=nil;unit.reports.log[0]:insert('#',140);reports[140]={id=140,text='new',color=2}")
# Source changes are invisible until explicit refresh. Existing metadata stays fixed.
assert call(expected_list_revision=revision)['total']==137
fresh=call(after_id=139,expected_list_revision=revision,refresh=True)
assert ids(fresh)==[140] and fresh['total']==138 and fresh['list_revision']==revision
retained=page_text(expected_list_revision=revision)
assert retained['reports'][1]['color']==3 and retained['reports'][1]['text']=='a'*16383
assert call(expected_list_revision=revision)['reports'][2]['id']==4
# Removal and same-length source replacement do not delete/replace captured rows.
lua.execute("unit.reports.log[0]:erase(0)")
assert call(after_id=140,expected_list_revision=revision,refresh=True)['total']==138
lua.execute("unit.reports.log[0][#unit.reports.log[0]-1]=141;reports[141]={id=141,text='same length',color=2}")
assert ids(call(after_id=140,expected_list_revision=revision,refresh=True))==[]
lua.execute("unit.reports.log[0]:insert('#',142);reports[142]={id=142,text='append',color=2}")
assert ids(call(after_id=140,expected_list_revision=revision,refresh=True))==[141,142]
# Failed refresh is atomic and preserves earlier text and revision.
lua.execute("unit.reports.log[0]:insert('#',143);reports[143]={id=143,text=string.rep('x',32*1024*1024),color=2}")
assert not call(after_id=142,expected_list_revision=revision,refresh=True)['ok']
assert call(expected_list_revision=revision)['total']==140
assert page_text(expected_list_revision=revision)['reports'][1]['color']==3
assert not call(refresh=True)['ok']
assert not call(from_end=True,refresh=True,expected_list_revision=revision)['ok']
assert not call(expected_list_revision=revision+1)['ok']
assert not read(lua.table_from(dict(unit_id=18,unit_category=0,expected_list_revision=revision)))['ok']
# Recapture sees native edits and expiration; reset invalidates retained handles.
lua.execute("unit.reports.log[0]:erase(#unit.reports.log[0]-1)")
reopened=call();assert reopened['list_revision']>revision
assert not page_text(expected_list_revision=revision)['ok']
assert page_text(expected_list_revision=reopened['list_revision'])['reports'][1]['text']=='edited'
reset();assert not call(expected_list_revision=reopened['list_revision'])['ok']
assert call()['list_revision']>reopened['list_revision']
print('REPORT_UNIT_SNAPSHOT_PASS')
