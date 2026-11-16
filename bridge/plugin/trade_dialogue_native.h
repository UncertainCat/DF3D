#pragma once
#include "trade_entry_native.h"

namespace df3d_production {
// DF53.16 assembles these branches inline in384850. Only immutable literals
// and semantic naming/ethics leaves are reused; no renderer or menu is called.
inline bool tradeDialogueNativeReady() {
    if(!tradeEntryNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x385bc8,0x604,UINT64_C(0xcab8a7ac1eb5e22f)},
            {0x38a53c,0x74,UINT64_C(0xb9dcb4dcceecceb4)},
            {0x75cfd0,0x48,UINT64_C(0xffe52ee188ceda58)},
            {0x30cea0,0xc3,UINT64_C(0x47a07e027acb5ada)},
            {0x30cf70,0x174,UINT64_C(0x6f623c8eaf55f9c1)},
            {0x1bb330,0xcc,UINT64_C(0x22cd601a57c49cb0)},
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)},
            {0x162a5a0,0xaf2,UINT64_C(0xd17189672d5ed32f)},
            {0x15e9718,2,UINT64_C(0x07cc9407b494d11f)},
            {0x161b2a8,0x81,UINT64_C(0xccdca9bb9a9d73e1)},
            {0x161b428,0x28,UINT64_C(0x951979a934857a95)},
            {0x161b540,0x2d,UINT64_C(0x27bd7bd94e292f5d)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
// The owner supplies its dialogue state explicitly. -1 denotes an announcement,
// whose owned exchange result must be supplied separately (never big_announce).
inline std::optional<std::string> tradeDialogue(const df::historical_entity& civ,
    const df::caravan_state& caravan,df::unit* broker,int16_t line) {
    if(!tradeDialogueNativeReady() || line<0 || line>28)return {};
    static_assert(offsetof(df::plotinfost,king_arrived)==0xaa);
    static_assert(offsetof(df::plotinfost,civ_id)==0x2440);
    static_assert(offsetof(df::plotinfost,race_id)==0x244c);
    static_assert(offsetof(df::historical_entity,resources)+offsetof(df::historical_entity::T_resources,ethic)+3*sizeof(df::ethic_response)==0xcf2);
    static_assert(offsetof(df::caravan_state,flags)==0x20c0);
    static_assert(offsetof(df::world,raws)+offsetof(df::world::T_raws,creatures)==0x11b558);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto text=[&](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
    const auto forbids=reinterpret_cast<bool(*)(int16_t)>(base+0x75cfd0);
    const auto animal=int16_t(civ.resources.ethic[df::ethic_type::KILL_ANIMAL]);
    const bool ethical=forbids(animal) || animal==5 || animal==6 || forbids(int16_t(civ.resources.ethic[df::ethic_type::KILL_PLANT]));
    const auto& plot=*df::global::plotinfo;
    std::string result=text(0x15e9718);
    const auto append=[&](size_t a,size_t b=0){result+=text(a);if(b)result+=text(b);};
    switch(line) {
    case 0:
        if(civ.id==plot.civ_id)append(plot.king_arrived?0x162a7a0:0x162a778,0x162a7f0);
        else if(ethical)append(0x162a7c8,0x162a878);
        else if(civ.race==plot.race_id)append(0x162a820);
        else {
            append(0x162a8b8);std::string profession,race;
            auto* creatures=&df::global::world->raws.creatures;
            if(broker && reinterpret_cast<bool(*)(void*,int16_t,int16_t,int16_t)>(base+0x30cea0)(creatures,broker->race,broker->caste,25))
                reinterpret_cast<bool(*)(void*,std::string*,int16_t,int16_t,int16_t,bool,bool)>(base+0x30cf70)(creatures,&profession,broker->race,broker->caste,25,false,false);
            else profession=text(0x162a8a8);
            result+=profession;append(0x162a5c8);
            reinterpret_cast<void(*)(int16_t,std::string*,bool,int16_t)>(base+0xaa3bd0)(plot.race_id,&race,true,-1);
            result+=race;append(0x162a5a0);
        }break;
    case 1:append(0x162a698);break;
    case 2:append(0x161b2a8);break;
    case 3:append(0x162a650);break;
    case 4:append(0x161b2d8);break;
    case 5:append(0x162a738);break;
    case 6:append(0x161b308);break;
    case 7:append(0x161b540);break;
    case 8:append(ethical?0x162b080:0x162b050);break;
    case 9:append(0x162ad40);break;
    case 10:if(ethical)append(0x162ad10);else append(0x162ada0,0x162ad68);break;
    case 11:if(ethical)append(0x162adf8);else append(0x162add0,0x162ae70);break;
    case 12:append(0x162ae10);break;
    case 13:append(0x162ab98,0x162ab50);break;
    case 14:append(0x162abf8);break;
    case 15:append(0x162abc8,0x162ac90);break;
    case 16:append(0x162ac40);break;
    case 17:if(civ.id==plot.civ_id || civ.race==plot.race_id)append(0x162ace0,0x162aca8);else append(0x161b428);break;
    case 18:append(0x162aa50,0x162aa00);break;
    case 19:append(0x162aaf0,0x162aad0);break;
    case 20:append(0x162aaa8,0x162aa78);break;
    case 21:case 22:case 23:break; // Native switch falls straight to closing quote.
    case 24:append(0x162a6d0);break;
    case 25:append(0x162afa8,0x162af88);break;
    case 26:append(0x162b010,0x162afe0);break;
    case 27:append(ethical && caravan.flags.bits.greatly_offended?0x162a5f0:0x162a5d8);break;
    case 28:append(ethical?0x162af20:0x162aec0);break;
    }
    append(0x15e9718);if(result.size()>2048)return {};return result;
}
}
