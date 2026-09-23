"""Asset-free adapter regression: DF enums are metatable-backed, not iterable maps.

Run with Python + lupa (test tooling only; no DF or presentation dependencies).
"""
from pathlib import Path

from lupa import LuaRuntime


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        local function enum(names)
            local lookup = {}
            for i, name in ipairs(names) do
                lookup[i-1] = name
                lookup[name] = i-1
            end
            return setmetatable({_last_item=#names-1}, {__index=lookup})
        end
        df = {
            building_type=enum{'Chair','Workshop','Construction'},
            workshop_type=enum{'Carpenters'},
            construction_type=enum{'Wall','Floor'},
        }
        df.job_item = {
            new=function()
                return {
                    quantity=1,
                    assign=function(self, values)
                        for key, value in pairs(values) do self[key]=value end
                    end,
                    delete=function() end,
                }
            end,
        }
        dfhack = {buildings={}}
        dfhack.buildings.getCorrectSize=function(w,h,t)
            return false, t==df.building_type.Workshop and 3 or 1,
                          t==df.building_type.Workshop and 3 or 1
        end
        dfhack.buildings.getFiltersByType=function(_,t,st)
            -- Missing quantity must preserve job_item's native default of one.
            -- An explicit multi-input recipe must remain unavailable.
            if t==df.building_type.Construction and st==df.construction_type.Floor then
                return {{quantity=2}}
            end
            return {{new=true}}
        end
        """
    )
    source = Path(__file__).resolve().parents[1] / "bridge/plugin/construction.lua"
    adapter = lua.execute(source.read_text(encoding="utf-8"))
    result = adapter(lua.table_from({"action": 0}))
    assert result["ok"], result["message"]
    catalog = {entry["key"]: entry for entry in result["catalog"].values()}
    assert set(catalog) == {"Chair", "Workshop:Carpenters", "Construction:Wall", "Construction:Floor"}
    for key in ("Chair", "Workshop:Carpenters", "Construction:Wall"):
        assert catalog[key]["supported"], key
    assert catalog["Workshop:Carpenters"]["width"] == 3
    assert not catalog["Construction:Floor"]["supported"]
    lua.execute("df.building_type._last_item = -1")
    broken = lua.execute(source.read_text(encoding="utf-8"))
    result = broken(lua.table_from({"action": 0}))
    assert not result["ok"] and "catalog is incomplete" in result["message"]
    print("CONSTRUCTION_CATALOG PASS")


if __name__ == "__main__":
    main()
