#pragma once
#include "creature_lists_native.h"
#include "df/widget_unit_name.h"

namespace df3d_residents {
struct PetControls {
    std::vector<std::string> captions;
    std::vector<int32_t> owners;
    std::vector<int32_t> actions; // 0 slaughter, 1 adoption, 2 gelding, 3 trainer, 4 war, 5 hunting
};
inline bool petControlsSupported() {
    static const bool ready=[] {
        if(!activitySupported() || !creatureListsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x370bf0,0x1c93,UINT64_C(0xce1da7bac00648af)},
            {0x3731a0,0x64d,UINT64_C(0x501bc4d7d03d520b)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
// Native postprocessors construct eligibility, ownership prose and controls
// into an independently allocated row. Two empty weak references replace the
// parent list/panel captures. Never arrange/render/feed this row or invoke its
// deferred callbacks: they are inspected only to identify semantic operations.
inline std::optional<PetControls> petControls(const CreatureReference& entry) {
    if((entry.kind!=0 && entry.kind!=1) || !petControlsSupported())return std::nullopt;
    if(entry.kind==0?!entry.unit:!entry.item)return std::nullopt;
    auto row=ownedRow();if(!row)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    alignas(16) std::array<std::byte,32> captures{};
    if(entry.kind==0) {
        using Build=void (*)(void*,std::shared_ptr<df::widget_container>,df::unit*);
        reinterpret_cast<Build>(const_cast<uint8_t*>(base+0x370bf0))(captures.data(),row,entry.unit);
    } else {
        using Build=void (*)(void*,std::shared_ptr<df::widget_container>,df::item*);
        reinterpret_cast<Build>(const_cast<uint8_t*>(base+0x3731a0))(captures.data(),row,entry.item);
    }
    PetControls result;size_t count=0;bool valid=true;
    const auto visit=[&](auto&& self,df::widget* widget)->void {
        if(!widget || !valid)return;
        if(++count>512){valid=false;return;}
        if(auto* text=virtual_cast<df::widget_text>(widget))result.captions.push_back(text->str);
        if(auto* name=virtual_cast<df::widget_unit_name>(widget);name && name->u)result.owners.push_back(name->u->id);
        for(const auto& callback:widget->custom_activated) {
            static_assert(sizeof(callback)==64);
            uintptr_t context=0;std::memcpy(&context,reinterpret_cast<const std::byte*>(&callback)+56,8);
            if(!context)continue;
            const auto* vtable=*reinterpret_cast<const uintptr_t* const*>(context);
            const auto target=vtable[2]-reinterpret_cast<uintptr_t>(base);
            if(target==0x3d0ca0)result.actions.push_back(0);
            else if(target==0x3d0e50 || target==0x3d0a90)result.actions.push_back(1);
            else if(target==0x3d0c40)result.actions.push_back(2);
            else if(target==0x3d1700)result.actions.push_back(3);
            else if(target==0x3d1460)result.actions.push_back(4);
            else if(target==0x3d1280)result.actions.push_back(5);
        }
        if(auto* container=virtual_cast<df::widget_container>(widget))for(const auto& child:container->children)self(self,child.get());
    };
    visit(visit,row.get());
    return valid?std::optional<PetControls>(std::move(result)):std::nullopt;
}
}
