"""Native semantic classification, checked against independently captured widget rows."""
import json
from pathlib import Path
from lupa import LuaRuntime

fixture = json.loads(Path("fixtures/reports/tab_membership.json").read_text())
classify = LuaRuntime().execute(Path("bridge/plugin/report_tabs.lua").read_text())
assert len(fixture["rows"]) == 356
native_tabs = fixture["named_tab_capture"]["tabs"]
assert [t["native_index"] for t in native_tabs] == list(range(25))
by_type = {}
for tab in native_tabs[1:22]:
    for typ in tab["types"]:
        assert typ not in by_type, "Report type assigned to multiple native tabs"
        by_type[typ] = tab["native_index"] + 1
assert set(native_tabs[0]["types"]) == set(by_type)
for row in fixture["rows"]:
    expected = by_type.get(row["type"], 0)
    assert classify(row["name"]) == expected, row["name"]
    assert bool(expected) == row["native_all_visible"], row["name"]
assert classify("COMBAT_DODGE") == 0
assert classify("CITIZEN_DEATH") == 0
assert classify("FOOD_WARNING") == 17
assert classify("RESEARCH_BREAKTHROUGH") == 3
assert classify("UNRECOGNIZED_FUTURE_TYPE") is None
assert classify("") is None
print("REPORT_TABS_CLASSIFICATION_PASS")
