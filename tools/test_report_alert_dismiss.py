"""Red ALERT dismissal preserves reports and rejects stale/replayed source receipts."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(Path('tools/qa/lua_test_prelude.lua').read_text())
lua.execute("""
status={alert_button_announcement_id=vec({0,7,7,2147483647})}
-- No report, category or native widget API exists in this fixture.
df={global={world={status=status}}}
""")
capture, dismiss, reset = lua.execute(Path('bridge/plugin/report_alert_dismiss.lua').read_text())
first = capture()
assert first['ok'] and first['count'] == 4
assert dismiss(first['receipt'])['count'] == 4
assert lua.eval('#status.alert_button_announcement_id') == 0
assert not dismiss(first['receipt'])['ok']
empty = capture()
assert empty['ok'] and dismiss(empty['receipt'])['count'] == 0

# Same length replacements and reordering are stale, not just appends/removals.
for change in (
    "status.alert_button_announcement_id:insert('#',8)",
    "status.alert_button_announcement_id:erase(0)",
    "status.alert_button_announcement_id[1]=8",
    "status.alert_button_announcement_id[0]=7;status.alert_button_announcement_id[1]=0",
):
    lua.execute('status.alert_button_announcement_id=vec({0,7,7,2147483647})')
    receipt = capture()['receipt']
    lua.execute(change)
    before = lua.eval('table.concat(status.alert_button_announcement_id._data,",")')
    assert not dismiss(receipt)['ok']
    assert lua.eval('table.concat(status.alert_button_announcement_id._data,",")') == before
    assert not dismiss(receipt)['ok']

receipt = capture()['receipt']
reset()
assert not dismiss(receipt)['ok']
new = capture()['receipt']
assert new > receipt
assert not dismiss(receipt)['ok']
assert dismiss(new)['ok']  # An unrelated stale request does not retire the current owner.
receipt = capture()['receipt']
new = capture()['receipt']
assert not dismiss(receipt)['ok'] and dismiss(new)['ok']
for value in (0, -1, 1.5, '1', None):
    assert not dismiss(value)['ok']

lua.execute("status.alert_button_announcement_id=vec({});for i=1,65536 do status.alert_button_announcement_id:insert('#',7)end")
receipt = capture()['receipt']
lua.execute("status.alert_button_announcement_id:insert('#',8)")
assert not capture()['ok']
assert not dismiss(receipt)['ok']
lua.execute('status.alert_button_announcement_id:erase(65536)')
assert dismiss(capture()['receipt'])['count'] == 65536
# Production wrapper binds the prepared receipt to its client and fortress epoch.
capture, dismiss, reset = lua.execute(Path('bridge/plugin/report_alert_dismiss.lua').read_text())
route = lua.execute(Path('bridge/plugin/report_dismissal.lua').read_text(), capture, dismiss, reset)
def command(action, client=11, epoch=7, receipt=0):
    return route(lua.table_from(dict(action=action, client_id=client, epoch=epoch,
        report=lua.table_from(dict(expected_list_revision=receipt)))))
lua.execute('status.alert_button_announcement_id=vec({0,7,7,2147483647})')
prepared = command(68)
assert prepared['ok'] and prepared['total'] == 4
receipt = prepared['list_revision']
assert not command(69, client=12, receipt=receipt)['ok']
assert not command(69, epoch=8, receipt=receipt)['ok']
assert command(69, receipt=receipt)['total'] == 4
assert not command(69, receipt=receipt)['ok']
print('REPORT_ALERT_DISMISS_PASS')
