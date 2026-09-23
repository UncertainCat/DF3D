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
// The embedded Lua adapters route on `request.action` by number (they are
// also loaded standalone by tools/test_*_adapter.py with numeric actions, so
// they cannot depend on a runtime-provided name table). Pin the numbering
// they use here: renumbering ManagementAction in schema/mirror.fbs fails
// this build instead of silently misrouting the scripts.
namespace lua_action_numbers {
using A=df3d::mirror::ManagementAction;
static_assert(int(A::Catalog)==0 && int(A::Place)==2 && int(A::Inspect)==3 && int(A::Remove)==4 && int(A::InspectAtTile)==5 && int(A::RemoveConstruction)==6, "construction.lua action numbers");
static_assert(int(A::AreaCatalog)==7 && int(A::AreaInspectAtTile)==8 && int(A::AreaInspect)==9 && int(A::AreaCreate)==10 && int(A::AreaUpdate)==11 && int(A::AreaDelete)==12 && int(A::AreaLink)==13 && int(A::AreaCandidates)==14, "areas.lua action numbers");
static_assert(int(A::ProductionList)==15 && int(A::ProductionInspect)==16 && int(A::ProductionQueue)==17 && int(A::ProductionJobEdit)==18 && int(A::FarmSetCrop)==19, "production.lua action numbers");
static_assert(int(A::WorkOrderList)==20 && int(A::WorkOrderInspect)==21 && int(A::WorkOrderCreate)==22 && int(A::WorkOrderUpdate)==23 && int(A::WorkOrderDelete)==24 && int(A::WorkOrderCondition)==25 && int(A::WorkOrderCandidates)==26 && int(A::WorkOrderCatalog)==27, "work_orders.lua action numbers");
static_assert(int(A::CitizenList)==28 && int(A::CitizenInspect)==29 && int(A::WorkDetailList)==30 && int(A::WorkDetailInspect)==31 && int(A::WorkDetailMembership)==32 && int(A::WorkDetailMode)==33, "citizens.lua action numbers");
static_assert(int(A::ReportInspect)==35 && int(A::AgreementInspect)==37, "reports.lua / agreements.lua action numbers");
static_assert(int(A::TradeList)==38 && int(A::TradeInspect)==39 && int(A::TradeUpdate)==40 && int(A::TradeGoods)==41 && int(A::TradeBring)==42 && int(A::TradeExchangeOpen)==43, "trade.lua action numbers");
}
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
