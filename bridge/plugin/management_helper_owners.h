#pragma once
#include "mirror_generated.h"
#include <array>

namespace df3d_management {
// Shared helper ranges: runtime dispatch and builder ownership use one table.
// Keep the ownership method independent of DFHack so offline tests execute it.
class ManagementHelperOwners {
protected:
    using Action=df3d::mirror::ManagementAction;
    struct Range { Action first,last; };
    inline static constexpr std::array<Range,10> ranges_{{
        {Action::Catalog,Action::RemoveConstruction},
        {Action::AreaCatalog,Action::AreaCandidates},
        {Action::ProductionList,Action::FarmSetCrop},
        {Action::WorkOrderList,Action::WorkOrderCatalog},
        {Action::CitizenList,Action::WorkDetailMode},
        {Action::ReportList,Action::ReportInspect},
        {Action::AgreementList,Action::AgreementInspect},
        {Action::TradeList,Action::TradeBring},
        {Action::CreatureInspect,Action::CreatureInspect},
        {Action::PrepareAlertDismissal,Action::DismissAlert}
    }};
public:
    bool sameOwner(Action a,Action b) const {
        for(const auto& helper:ranges_)
            if(a>=helper.first && a<=helper.last)
                return b>=helper.first && b<=helper.last;
        return false;
    }
};
} // namespace df3d_management
