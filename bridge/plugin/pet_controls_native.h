#pragma once
#include "creature_lists_native.h"
#include "df/widget_unit_name.h"

namespace df3d_residents {
struct PetActionHelp {std::string text;int32_t hover=-1,instruction=-1;bool observed=false;};
struct PetOwnerDisplay {int32_t id,columns;bool showGender,showProfession,oneLineOnly;df3d_area::ZoneOwnerDisplayText text;df3d_area::ZoneOwnerNameColor color;};
struct PetControls {
    std::vector<std::string> captions;
    std::vector<std::array<int16_t,3>> captionColors; // foreground, background, bright
    std::vector<int32_t> owners;
    std::vector<PetOwnerDisplay> ownerDisplay;
    std::vector<int32_t> actions; // 0 slaughter, 1 adoption, 2 gelding, 3 trainer, 4 war, 5 hunting
    std::vector<PetActionHelp> actionHelp;
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
        if(auto* text=virtual_cast<df::widget_text>(widget)) {
            result.captions.push_back(text->str);
            result.captionColors.push_back({text->fg,text->bg,int16_t(text->bright)});
        }
        if(auto* name=virtual_cast<df::widget_unit_name>(widget);name && name->u) {
            // The owned postprocessor creates fixed-width owner widgets. Read
            // their flags/minimum, without arranging or rendering native widgets.
            const auto text=df3d_area::nativeUnitNameDisplayText(*name->u,name->min_w,name->show_gender,name->show_profession,name->one_line_only);
            const auto color=df3d_area::nativeZoneOwnerNameColor(*name->u);
            if(!text || !color){valid=false;return;}
            result.owners.push_back(name->u->id);
            result.ownerDisplay.push_back({name->u->id,name->min_w,name->show_gender,name->show_profession,name->one_line_only,*text,*color});
        }
        for(const auto& callback:widget->custom_activated) {
            const auto oldCount=result.actions.size();
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
            if(result.actions.size()!=oldCount) {
                static_assert(offsetof(df::widget,tooltip)==0xd0);
                PetActionHelp help;
                if(const auto* literal=std::get_if<std::string>(&widget->tooltip)){help.text=*literal;help.observed=true;}
                else if(const auto* function=std::get_if<std::function<void()>>(&widget->tooltip)) {
                    uintptr_t captured=0;std::memcpy(&captured,reinterpret_cast<const std::byte*>(function)+56,8);
                    if(captured) {
                        const auto rva=(*reinterpret_cast<const uintptr_t* const*>(captured))[2]-reinterpret_cast<uintptr_t>(base);
                        struct HelpPin {size_t rva;uint64_t hash;};
                        constexpr HelpPin pins[]={
                            {0x3d39d0,UINT64_C(0xe8b19fc3adb81ece)},
                            {0x3d3a20,UINT64_C(0xdf4bbc35a6c159fc)},
                            {0x3d3a70,UINT64_C(0x78d5626c40e47a5e)},
                            {0x3d3b30,UINT64_C(0xf0c32cfc6af00fb8)},
                            {0x3d3b80,UINT64_C(0xcc8310fbe8872634)},
                            {0x3d3c10,UINT64_C(0xb6580eadffce4407)},
                        };
                        for(const auto& pin:pins)if(pin.rva==rva) {
                            uint64_t hash=UINT64_C(14695981039346656037);
                            for(size_t i=0;i<0x25;++i){hash^=base[rva+i];hash*=UINT64_C(1099511628211);}
                            if(hash!=pin.hash){valid=false;return;}
                            // These callbacks only select native help entries. Read their
                            // pinned immediate IDs without changing global hover state.
                            std::memcpy(&help.hover,base+rva+8,4);
                            std::memcpy(&help.instruction,base+rva+0x19,4);
                            help.observed=true;break;
                        }
                    }
                }
                result.actionHelp.push_back(std::move(help));
            }
        }
        if(auto* container=virtual_cast<df::widget_container>(widget))for(const auto& child:container->children)self(self,child.get());
    };
    visit(visit,row.get());
    return valid?std::optional<PetControls>(std::move(result)):std::nullopt;
}
}
