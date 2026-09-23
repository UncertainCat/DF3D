#pragma once
#include "Core.h"
#include "LuaTools.h"
#include "mirror_generated.h"
#include "construction_script.h"
#include "areas_script.h"
#include "production_script.h"
#include "work_orders_script.h"
#include "citizens_script.h"
#include "reports_script.h"
#include "agreements_script.h"
#include "trade_script.h"
#include "creature_script.h"
#include <array>
#include <string_view>

namespace df3d_management {
// Each live domain owns one cached Lua closure. Retirement is structural: no
// retired source or registry entry is compiled into the plugin.
class ManagementHelpers {
    struct Helper {
        df3d::mirror::ManagementAction first,last;
        std::string_view source;
        int reference=LUA_NOREF;
    };
    using Action=df3d::mirror::ManagementAction;
    std::array<Helper,9> entries_{{
        {Action::Catalog,Action::RemoveConstruction,kConstructionScript},
        {Action::AreaCatalog,Action::AreaCandidates,kAreasScript},
        {Action::ProductionList,Action::FarmSetCrop,kProductionScript},
        {Action::WorkOrderList,Action::WorkOrderCatalog,kWorkOrdersScript},
        {Action::CitizenList,Action::WorkDetailMode,kCitizensScript},
        {Action::ReportList,Action::ReportInspect,kReportsScript},
        {Action::AgreementList,Action::AgreementInspect,kAgreementsScript},
        {Action::TradeList,Action::TradeBring,kTradeScript},
        {Action::CreatureInspect,Action::CreatureInspect,kCreatureScript}
    }};
public:
    ManagementHelpers()=default;
    ManagementHelpers(const ManagementHelpers&)=delete;
    ManagementHelpers& operator=(const ManagementHelpers&)=delete;
    ~ManagementHelpers(){reset();}
    void reset() {
        for(auto& helper:entries_) if(helper.reference!=LUA_NOREF) {
            luaL_unref(DFHack::Core::getInstance().getLuaState(),LUA_REGISTRYINDEX,helper.reference);
            helper.reference=LUA_NOREF;
        }
    }
    int acquire(Action action,DFHack::color_ostream& out,lua_State* state) {
        for(auto& helper:entries_) if(action>=helper.first && action<=helper.last) {
            if(helper.reference==LUA_NOREF) {
                const int top=lua_gettop(state);
                if(!DFHack::Lua::SafeCallString(out,state,std::string(helper.source),0,1)) {
                    lua_settop(state,top); return LUA_NOREF;
                }
                helper.reference=luaL_ref(state,LUA_REGISTRYINDEX);
            }
            return helper.reference;
        }
        return LUA_NOREF;
    }
};
} // namespace df3d_management
