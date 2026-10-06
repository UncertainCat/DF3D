"""Full text pages preserve UTF-8 boundaries, revision and captured metadata."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
source={id=7,text=string.rep('a',16383)..utf8.char(0x263a)..string.rep('b',17000)..' TAIL',position={x=12}}
reads=0;conversions=0
df={report={find=function(id)reads=reads+1;return id==7 and source or nil end}}
dfhack={df2utf=function(raw)conversions=conversions+1;return raw end}
function mapped(r)return {id=r.id,text='prefix',position=r.position}end
""")
read, reset = lua.execute(Path('bridge/plugin/report_text_snapshot.lua').read_text())(lua.globals().mapped)

def call(**kw):
    return read(lua.table_from(dict(id=kw.pop('id', 7), **kw)))

first = call()
revision = first['list_revision']
assert first['ok'] and revision > 0 and first['view'] == 5
assert first['next_cursor'] == 16383 and not first['reports'][1]['text_complete']
expected = lua.globals().source['text'].encode()
first['reports'][1]['position']['x'] = 999
lua.execute("source.text='changed';source.position.x=88;df.report.find=function()error('Continuation touched native data')end")
chunks = [first['reports'][1]['text'].encode()]
cursor = first['next_cursor']
while cursor:
    page = call(cursor=cursor, expected_list_revision=revision)
    assert page['ok'] and page['list_revision'] == revision
    assert page['cursor'] == cursor and page['total'] == len(expected)
    row = page['reports'][1]
    assert row['position']['x'] == 12 and not row['text_complete']
    chunk = row['text'].encode()
    assert 0 < len(chunk) <= 16384
    chunks.append(chunk)
    assert page['next_cursor'] in (0, cursor + len(chunk))
    cursor = page['next_cursor']
assert b''.join(chunks) == expected and expected.endswith(b' TAIL')
assert lua.globals().reads == 1 and lua.globals().conversions == 1
for offset in (16384, 16385, len(expected)+1, -1):
    assert not call(cursor=offset, expected_list_revision=revision)['ok']
assert not call(id=8, expected_list_revision=revision)['ok']
assert not call(cursor=1)['ok']
assert not call(expected_list_revision=-1)['ok']
assert not call(id=-1)['ok']
# Failed captures leave the previous handle readable.
lua.execute("df.report.find=function(id)return id==7 and source or nil end")
assert not call(id=8)['ok']
lua.execute("source.text=string.rep('x',32*1024*1024+1)")
assert not call()['ok']
assert lua.globals().conversions == 1  # reject before native conversion
lua.execute("source.text='small';dfhack.df2utf=function()return string.rep('x',32*1024*1024+1)end")
assert not call()['ok']
lua.execute("dfhack.df2utf=function()return string.char(255)end")
assert not call()['ok']
assert call(expected_list_revision=revision)['reports'][1]['position']['x'] == 12
lua.execute("source.text='';dfhack.df2utf=function(s)return s end")
empty = call()
assert empty['ok'] and empty['total'] == 0 and empty['next_cursor'] == 0
assert empty['reports'][1]['text_complete'] and empty['list_revision'] > revision
assert not call(expected_list_revision=revision)['ok']
revision = empty['list_revision']
reset()
assert not call(expected_list_revision=revision)['ok']
lua.execute("source.text=string.rep('x',16384)")
exact = call()
assert exact['ok'] and exact['next_cursor'] == 0 and exact['reports'][1]['text_complete']
assert exact['list_revision'] > revision
# Maximum accepted payload is accounted in converted bytes. Reading a suffix at
# its boundary remains one bounded page, without remapping the native report.
lua.execute("source.text=string.rep('x',32*1024*1024)")
maximum = call()
assert maximum['ok'] and maximum['total'] == 32*1024*1024
last = call(cursor=maximum['total']-16384, expected_list_revision=maximum['list_revision'])
assert last['ok'] and last['next_cursor'] == 0 and len(last['reports'][1]['text']) == 16384
assert not last['reports'][1]['text_complete']
# Reject numeric coercion: IDs/cursors/revisions must be integers.
for fields in ({'id': '7'}, {'id': 7.5}, {'cursor': '0'}, {'expected_list_revision': '0'}):
    assert not call(**fields)['ok']
print('REPORT_TEXT_SNAPSHOT_PASS')
