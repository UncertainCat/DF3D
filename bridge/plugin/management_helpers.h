#pragma once
#include "Core.h"
#include "management_helper_owners.h"
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
static_assert(int(A::ConstructionMaterials)==63, "construction materials action number");
static_assert(int(A::Catalog)==0 && int(A::Place)==2 && int(A::Inspect)==3 && int(A::Remove)==4 && int(A::InspectAtTile)==5 && int(A::RemoveConstruction)==6, "construction.lua action numbers");
static_assert(int(A::AreaCatalog)==7 && int(A::AreaInspectAtTile)==8 && int(A::AreaInspect)==9 && int(A::AreaCreate)==10 && int(A::AreaUpdate)==11 && int(A::AreaDelete)==12 && int(A::AreaLink)==13 && int(A::AreaCandidates)==14, "areas.lua action numbers");
static_assert(int(A::ProductionList)==15 && int(A::ProductionInspect)==16 && int(A::ProductionQueue)==17 && int(A::ProductionJobEdit)==18 && int(A::FarmSetCrop)==19, "production.lua action numbers");
static_assert(int(A::WorkOrderList)==20 && int(A::WorkOrderInspect)==21 && int(A::WorkOrderCreate)==22 && int(A::WorkOrderUpdate)==23 && int(A::WorkOrderDelete)==24 && int(A::WorkOrderCondition)==25 && int(A::WorkOrderCandidates)==26 && int(A::WorkOrderCatalog)==27, "work_orders.lua action numbers");
static_assert(int(A::CitizenList)==28 && int(A::CitizenInspect)==29 && int(A::WorkDetailList)==30 && int(A::WorkDetailInspect)==31 && int(A::WorkDetailMembership)==32 && int(A::WorkDetailMode)==33, "citizens.lua action numbers");
static_assert(int(A::WorkDetailCreate)==64 && int(A::WorkDetailDelete)==65 && int(A::WorkDetailEdit)==66 && int(A::CitizenWorkScope)==67, "citizens.lua appended action numbers");
static_assert(int(A::ReportInspect)==35 && int(A::AgreementInspect)==37, "reports.lua / agreements.lua action numbers");
static_assert(int(A::TradeList)==38 && int(A::TradeInspect)==39 && int(A::TradeUpdate)==40 && int(A::TradeGoods)==41 && int(A::TradeBring)==42 && int(A::TradeExchangeOpen)==43, "trade.lua action numbers");
}
// Each live domain owns one cached Lua closure. Retirement is structural: no
// retired source or registry entry is compiled into the plugin.
class ManagementHelpers : public ManagementHelperOwners {
    struct Helper {
        df3d::mirror::ManagementAction first,last;
        std::string_view source;
        int reference=LUA_NOREF;
    };
    using Action=df3d::mirror::ManagementAction;
    std::array<Helper,9> entries_{{
        {ranges_[0].first,ranges_[0].last,kConstructionScript},
        {ranges_[1].first,ranges_[1].last,kAreasScript},
        {ranges_[2].first,ranges_[2].last,kProductionScript},
        {ranges_[3].first,ranges_[3].last,kWorkOrdersScript},
        {ranges_[4].first,ranges_[4].last,kCitizensScript},
        {ranges_[5].first,ranges_[5].last,kReportsScript},
        {ranges_[6].first,ranges_[6].last,kAgreementsScript},
        {ranges_[7].first,ranges_[7].last,kTradeScript},
        {ranges_[8].first,ranges_[8].last,kCreatureScript}
    }};
    uint64_t generation_=0;
public:
    uint64_t generation() const { return generation_; }
    ManagementHelpers()=default;
    ManagementHelpers(const ManagementHelpers&)=delete;
    ManagementHelpers& operator=(const ManagementHelpers&)=delete;
    ~ManagementHelpers(){reset();}
    void reset() {
        ++generation_;
        for(auto& helper:entries_) if(helper.reference!=LUA_NOREF) {
            auto* state=DFHack::Core::getInstance().getLuaState();
            if(helper.first==Action::WorkOrderList || helper.first==Action::Catalog) {
                // Release synthesized estimate filters before discarding the closure.
                const int top=lua_gettop(state);
                lua_rawgeti(state,LUA_REGISTRYINDEX,helper.reference);lua_newtable(state);
                lua_pushboolean(state,true);lua_setfield(state,-2,"cancel_builders");
                DFHack::Lua::SafeCall(DFHack::Core::getInstance().getConsole(),state,1,0);
                lua_settop(state,top);
            }
            luaL_unref(state,LUA_REGISTRYINDEX,helper.reference);
            helper.reference=LUA_NOREF;
        }
    }
    bool sameOwner(Action a,Action b) const {
        if(a>=Action::WorkDetailCreate && a<=Action::CitizenWorkScope)a=Action::CitizenList;
        if(b>=Action::WorkDetailCreate && b<=Action::CitizenWorkScope)b=Action::CitizenList;
        if(a==Action::ConstructionMaterials)a=Action::Catalog;
        if(b==Action::ConstructionMaterials)b=Action::Catalog;
        return ManagementHelperOwners::sameOwner(a,b);
    }
    int acquire(Action action,DFHack::color_ostream& out,lua_State* state) {
        if(action>=Action::WorkDetailCreate && action<=Action::CitizenWorkScope)action=Action::CitizenList;
        if(action==Action::ConstructionMaterials)action=Action::Catalog;
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
