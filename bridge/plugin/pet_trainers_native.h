#pragma once
#include "pet_controls_native.h"
#include "df/unit_labor.h"

namespace df3d_residents {
struct TrainerChoice {int32_t id;std::vector<std::string> skills;};
inline bool petTrainersSupported() {
    static const bool ready=[] {
        if(!petControlsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3c7bf0,0x194,UINT64_C(0x8e2ddbf8beaba43b)},
            {0x36e720,0x71,UINT64_C(0x946299305fc7b64a)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x1429ef0,0x408,UINT64_C(0xb77385c5e0f54a56)},
            {0x36e9ec,0x17,UINT64_C(0x4ec8381f71dcf32e)},
            {0x36eab0,0xa,UINT64_C(0x45471637cae4ef45)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
inline std::optional<df3d_area::ZoneOwnerDisplayText> petTrainerName(df::unit* unit,int32_t columns) {
    if(!unit || columns<3 || columns>30 || !petTrainersSupported())return std::nullopt;
    static_assert(offsetof(df::widget_unit_name,show_gender)==0x158 &&
        offsetof(df::widget_unit_name,show_profession)==0x159 && offsetof(df::widget_unit_name,one_line_only)==0x15a);
    // Native36e9f3 writes gender=false/profession=true,36e9fc two-line output;
    //36eab0 fixes the nominal name width at30. Layout may reduce that width.
    return df3d_area::nativeUnitNameDisplayText(*unit,columns,false,true,false);
}
inline std::optional<std::vector<TrainerChoice>> petTrainers(int32_t animalId) {
    if(!df::global::world || !petTrainersSupported())return std::nullopt;
    auto* animal=df::unit::find(animalId);if(!animal)return std::nullopt;
    const auto controls=petControls(CreatureReference{animal});
    if(!controls || std::find(controls->actions.begin(),controls->actions.end(),3)==controls->actions.end())return std::nullopt;
    static_assert(offsetof(df::unit,status)+offsetof(df::unit::T_status,labors)+df::unit_labor::ANIMALTRAIN==0xac8);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto eligible=reinterpret_cast<bool (*)(df::unit*)>(const_cast<uint8_t*>(base+0x138ed20));
    std::vector<df::unit*> candidates;
    // Native36e720..36e78e has no separate selection API: retain its two field
    // gates around the native membership predicate. The native sorter receives
    // an owned vector and preserves its own skill ordering/tie behavior.
    for(auto* unit:df::global::world->units.active)
        if(unit && !unit->flags1.bits.inactive && eligible(unit) && unit->status.labors[df::unit_labor::ANIMALTRAIN])candidates.push_back(unit);
    using Sort=void (*)(void*,df::unit**,df::unit**);
    if(!candidates.empty())reinterpret_cast<Sort>(const_cast<uint8_t*>(base+0x3c7bf0))(nullptr,candidates.data(),candidates.data()+candidates.size());
    std::array<int32_t,149> weights{};weights[5]=1; // Native36e7f8..36e7fd: Animal Training only.
    using Skills=int (*)(std::shared_ptr<df::widget_container>,df::unit*,int32_t*);
    const auto build=reinterpret_cast<Skills>(const_cast<uint8_t*>(base+0x1429ef0));
    std::vector<TrainerChoice> result;result.reserve(candidates.size());
    for(auto* unit:candidates) {
        auto row=ownedRow();if(!row)return std::nullopt;
        build(row,unit,weights.data());
        TrainerChoice choice{unit->id,{}};size_t count=0;bool valid=true;
        const auto visit=[&](auto&& self,df::widget* widget)->void {
            if(!widget || !valid)return;
            if(++count>128){valid=false;return;}
            if(auto* text=virtual_cast<df::widget_text>(widget))choice.skills.push_back(text->str);
            if(auto* container=virtual_cast<df::widget_container>(widget))for(const auto& child:container->children)self(self,child.get());
        };
        visit(visit,row.get());if(!valid)return std::nullopt;
        result.push_back(std::move(choice));
    }
    return result;
}
}
