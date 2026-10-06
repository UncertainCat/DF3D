"""Whole alert-group capture: >256 references, duplicates and retained full text."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
lua.execute("""
ids={};reports={};calls=0
for i=0,299 do ids[#ids+1]=i;reports[i]={id=i,text='before '..i,color=3}end
reports[75].text=string.rep('a',16383)..utf8.char(0x263a)..string.rep('z',18000)
ids[#ids+1]=75;ids[#ids+1]=999
group={type=20,announcement_id=vec(ids),report_unid=vec({17,999,17}),report_unit_announcement_category=vec({1,0,1})}
status={announcement_alert=vec({group}),alert_button_announcement_id=vec({3,3,999})}
df={global={world={status=status}},report={find=function(id) calls=calls+1;return reports[id] end},unit={find=function(id)return id==17 and {id=17,name='Before unit'}end}}
dfhack={df2utf=function(s)return s end}
function mapped(r)return {id=r.id,text='prefix',color=r.color,position={x=1}}end
function unit(u,cat)return {unit_id=u.id,category=cat,name=u.name,profession='Fixture',log_count=42}end
""")
read, text, reset = lua.execute(Path('bridge/plugin/report_group_snapshot.lua').read_text())(lua.globals().mapped, lua.globals().unit)

def call(**kw):
    return read(lua.table_from(dict(notification_category=kw.pop('notification_category', 20), **kw)))

def full(**kw):
    return text(lua.table_from(dict(notification_category=kw.pop('notification_category', 20), id=kw.pop('id', 75), **kw)))

first = call()
rev = first['list_revision']
assert first['ok'] and first['total'] == 303 and first['next_cursor'] == 64
assert lua.globals().calls == 301  # Every distinct reference resolved once.
expected = lua.globals().reports[75]['text']
first['reports'][1]['position']['x'] = 999
assert call(expected_list_revision=rev)['reports'][1]['position']['x'] == 1
# Paging and text cannot access source vectors, reports or units after capture.
lua.execute("saved=df;df=nil")
seen = []
units = []
page = call(expected_list_revision=rev)
while True:
    seen.extend(r['id'] for r in page['reports'].values())
    units.extend((r['unit_id'], r['category'], r['name']) for r in page['units'].values())
    if not page['next_cursor']:
        break
    page = call(expected_list_revision=rev, cursor=page['next_cursor'])
assert seen == list(range(300)) + [75]
assert units == [(17, 1, 'Before unit')] * 2
parts = []
page = full(expected_list_revision=rev)
assert len(page['reports'][1]['text'].encode()) == 16383
while True:
    parts.append(page['reports'][1]['text'])
    if not page['next_cursor']:
        break
    page = full(expected_list_revision=rev, cursor=page['next_cursor'])
assert ''.join(parts) == expected
assert not full(expected_list_revision=rev, cursor=16384)['ok']
assert not full(expected_list_revision=rev, cursor=9223372036854775807)['ok']
assert not full(expected_list_revision=rev, id=999)['ok']
assert not call(expected_list_revision=rev, notification_category=21)['ok']
assert not call(expected_list_revision=rev, notification_category=-1, alert_button=True)['ok']
assert not call(expected_list_revision=rev, cursor=303)['ok']
lua.execute("df=saved;reports[75].text='changed';reports[10]=nil;group.announcement_id:erase(0)")
assert full(expected_list_revision=rev)['reports'][1]['text'] == 'a' * 16383
fresh = call()
assert fresh['total'] == 301 and fresh['list_revision'] > rev
assert full(expected_list_revision=fresh['list_revision'])['reports'][1]['text'] == 'changed'
assert not full(expected_list_revision=rev)['ok']
rev = fresh['list_revision']
# Failed captures never retire the prior pointer-free snapshot.
lua.execute("group.report_unit_announcement_category:erase(0)")
assert not call()['ok']
assert full(expected_list_revision=rev)['ok']
lua.execute("group.report_unit_announcement_category=vec({1,0,1});status.announcement_alert:insert('#',group)")
assert not call()['ok']
lua.execute("status.announcement_alert:erase(1);reports[75].text=string.rep('x',32*1024*1024)")
assert not call()['ok']
assert full(expected_list_revision=rev)['reports'][1]['text'] == 'changed'
lua.execute("reports[75].text='small';group.announcement_id=vec({});for i=1,65537 do group.announcement_id:insert('#',75)end")
assert not call()['ok']
lua.execute("group.announcement_id:erase(0)")
assert not call()['ok']  # 65536 reports plus three unit references.
lua.execute("group.report_unid=vec({});group.report_unit_announcement_category=vec({})")
assert call()['total'] == 65536
# Red ALERT has its own source selector, preserving duplicates and omitting expiry.
button = call(notification_category=-1, alert_button=True)
assert button['total'] == 2 and [r['id'] for r in button['reports'].values()] == [3, 3]
assert full(notification_category=-1, alert_button=True, id=3, expected_list_revision=button['list_revision'])['reports'][1]['text'] == 'before 3'
assert not call(notification_category=20, alert_button=True)['ok']
assert not call(notification_category=37)['ok']
assert not call(notification_category=False, alert_button=True)['ok']
assert not call(alert_button=1)['ok']
assert not call(cursor=1)['ok']
reset()
assert not call(notification_category=-1, alert_button=True, expected_list_revision=button['list_revision'])['ok']
assert call(notification_category=-1, alert_button=True)['list_revision'] > button['list_revision']
# Payload pages stay bounded independently of the number of retained references.
lua.execute("group.announcement_id=vec({});reports[75].text=string.rep('a',16383)..utf8.char(0x263a)..'tail';for i=1,64 do group.announcement_id:insert('#',75)end")
bounded = call()
assert bounded['total'] == 64 and bounded['next_cursor'] == 8
assert len(bounded['reports']) == 8
assert all(not r['text_complete'] for r in bounded['reports'].values())
assert sum(len(r['text'].encode()) for r in bounded['reports'].values()) <= 131072
rev = bounded['list_revision']
lua.execute("reports[75].text=string.char(255)")
assert not call()['ok']
assert full(expected_list_revision=rev)['reports'][1]['text'] == 'a' * 16383
lua.execute("status.announcement_alert=vec({})")
assert not call()['ok']
assert full(expected_list_revision=rev)['ok']
lua.execute("status.announcement_alert=vec({group});group.announcement_id=vec({})")
empty = call()
assert empty['total'] == 0 and empty['next_cursor'] == 0
assert len(empty['reports']) == len(empty['units']) == 0
print('REPORT_GROUP_SNAPSHOT_PASS')
