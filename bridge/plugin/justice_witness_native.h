#pragma once
#include "justice_native.h"
#include "df/language_name.h"

namespace df3d_justice {
struct WitnessText {std::string witness,description,date,reported;};
// Resolve the report's recorded identity with DF's semantic helper, then format
// a copied name. The widget builder's equivalent inline branches are pinned.
inline std::optional<std::vector<WitnessText>> witnessText(const df::crime* crime) {
    auto* world=df::global::world;
    if(!crime || !world || crime->witnesses.size()>1048576 || !df3d_creature::inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<uint8_t*>(&world->history)!=base+0x24f9cb8 ||
       reinterpret_cast<uint8_t*>(&world->units.all)!=base+0x23e50b0)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xb92a80,0x6d,UINT64_C(0x8063e49eb1a20af4)},
            {0x67dc0,0x70,UINT64_C(0x17c7b286d4141624)},
            {0x72570,0x98,UINT64_C(0xa69932c0f279084a)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x4731dc,0x876,UINT64_C(0x8bf1482890d57da7)},
            {0x4866b0,0x206,UINT64_C(0xe43e52acf0a1a746)},
            {0x4872b0,0x21f,UINT64_C(0x4cfbec5fcaf552be)},
            {0x4874d0,0xec,UINT64_C(0xe47e4df06ec6f85f)},
            {0x4875c0,0x1eb,UINT64_C(0x208e45b2ed261669)},
            {0x474fe0,0xf8,UINT64_C(0x27c3bb17e2f3dd5d)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    auto ordered=crime->witnesses;
    for(const auto* report:ordered)if(!report || report->witness_ihf.all_witnessed_ident.size()>1048576 || report->accused_ihf.all_witnessed_ident.size()>1048576)return std::nullopt;
    // Native introsort changes only this owned pointer array. The comparator
    // reads report type and presence of an accused; ties use native sort order.
    if(!ordered.empty())reinterpret_cast<void(*)(df::witness_reportst**,df::witness_reportst**,ptrdiff_t,uint8_t)>(base+0x4866b0)(ordered.data(),ordered.data()+ordered.size(),ordered.size(),0);
    df3d_creature::InventoryRandomRestore restore(base);
    const auto name=[base,world](int32_t unitId,const df::incident_hfid& source,const char* fallback)->std::optional<std::string> {
        auto incident=source;std::string text;
        const auto* recorded=reinterpret_cast<df::language_name*(*)(void*,const df::incident_hfid*)>(base+0xb92a80)(&world->history,&incident);
        if(recorded) {
            auto owned=*recorded;
            reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&text,true,false);
        }else if(auto* unit=df::unit::find(unitId)) {
            if(unit->inventory.size()>10000)return std::nullopt;
            for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
            df3d_creature::InventoryDescriptionContext owned(*unit);
            reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&text,false);
        }else text=fallback;
        if(text.size()>16384)return std::nullopt;
        return text;
    };
    std::vector<WitnessText> result;result.reserve(ordered.size());
    for(const auto* report:ordered) {
        const auto witness=name(report->witness_id,report->witness_ihf,"unknown");if(!witness)return std::nullopt;
        const auto dates=witnessDates(*report);if(!dates)return std::nullopt;
        WitnessText row{"Witness: "+*witness+".",{},dates->date,dates->reported};
        if(report->accused_id!=-1) {
            const auto accused=name(report->accused_id,report->accused_ihf,"somebody");if(!accused)return std::nullopt;
            row.description=(int(report->type)==6?"Implicates: ":"Accuses: ")+*accused+".";
        }else switch(int(report->type)) {
            case 1:row.description="Found the body.";break;
            case 2:row.description="Saw that the object was missing.";break;
            case 3:row.description="Saw that the object was disturbed.";break;
            case 4:{const auto subject=name(report->accused_id,report->accused_ihf,"somebody");if(!subject)return std::nullopt;
                row.description="Saw "+*subject+" admire the object.";break;}
            default:break;
        }
        result.push_back(std::move(row));
    }
    return result;
}
}

