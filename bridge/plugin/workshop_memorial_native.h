#pragma once
#include "workshop_job_native.h"
#include "df/fort_death_profilest.h"
#include "df/incident.h"
#include "df/item_slabst.h"
#include "df/unit_ghost_info.h"
#include <array>

namespace df3d_production {
struct WorkshopMemorialRow {
    int32_t historicalFigureId=-1,priority=1000;
    std::string info;
};

// Native8c6da8..8c7347 composes the memorial list inline. Its five temporary
// buckets are owned here; no native category, button, search or menu is used.
// The placed-memorial, burial and pet-caste predicates are native semantic leaves.
inline std::optional<std::vector<WorkshopMemorialRow>> workshopMemorialRows(df::building* building) {
    if(!farmFunctions() || !building || int(building->getType())!=13 || building->getSubtype()!=2 ||
       !df::global::world || !df::global::plotinfo)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x16bed48,0x15,UINT64_C(0x70ca1a6997410b61)},
            {0x1615870,0xe,UINT64_C(0x8bbdc86cdb98b554)},
            {0x8c6da8,0x59f,UINT64_C(0xc16a9f84873118ec)},
            {0x13d50f0,0xbd,UINT64_C(0x0afaabee367aa435)},
            {0x13d51b0,0x170,UINT64_C(0xa9cf177035fcb56c)},
            {0x13765f0,0x27,UINT64_C(0x622520213ff0a937)},
            {0x1376500,0xf0,UINT64_C(0x2c5ca25b0abc0a79)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0x16beee8,0x1a,UINT64_C(0xa685a2110ed0ff4c)},
            {0x16becb0,0xd,UINT64_C(0xc518b0a742d75197)},
            {0x16becc0,0x9,UINT64_C(0xc5e98aa019830a47)},
            {0x16bec90,0x6,UINT64_C(0x8ba18e138c1f8f90)},
            {0x16bec98,0x11,UINT64_C(0x7b949fdd0572a20a)},
            {0x15e90d8,0x3,UINT64_C(0xe7305e17e30bba23)},
            {0x16bef08,0x10,UINT64_C(0x64633088ca7ea6dc)},
            {0x16bebf0,0xe,UINT64_C(0xc8ac11f237060ad1)},
            {0x16bec00,0x12,UINT64_C(0x9c1a04d032da98b7)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    static_assert(offsetof(df::unit,ghost_info)==0x380 && offsetof(df::unit,hist_figure_id)==0xc30);
    static_assert(offsetof(df::unit,counters)+offsetof(df::unit::T_counters,death_id)==0x7f8);
    static_assert(offsetof(df::incident,site)==0xd4 && offsetof(df::incident,entity)==0xe0 && offsetof(df::incident,flags)==0xec);
    static_assert(offsetof(df::plotinfost,main)+offsetof(df::plotinfost::T_main,dead_citizens)==0x8dd8);
    static_assert(offsetof(df::unit_ghost_info,flags)==0x1c);
    static_assert(offsetof(df::item_slabst,topic)==0x108 && offsetof(df::item_slabst,engraving_type)==0x10c);
    using Predicate=bool (*)(df::unit*);
    const auto memorialized=reinterpret_cast<Predicate>(base+0x13d50f0);
    const auto entombed=reinterpret_cast<Predicate>(base+0x13d51b0);
    const auto petCaste=reinterpret_cast<Predicate>(base+0x13765f0);
    auto* world=df::global::world;auto* plot=df::global::plotinfo;
    const auto deceasedCitizen=[&](int32_t id) {
        const auto& rows=plot->main.dead_citizens;
        const auto it=std::lower_bound(rows.begin(),rows.end(),id,[](const auto* row,int32_t key){return row->unit_id<key;});
        return it!=rows.end() && (*it)->unit_id==id;
    };
    const auto slabCount=[&](int32_t hfid) {
        int32_t count=0;
        for(const auto* slab:world->items.other.SLAB)
            if(slab && int(slab->engraving_type)==0 && slab->topic==hfid)++count;
        return count;
    };
    std::array<std::vector<int32_t>,5> buckets;
    for(auto* unit:world->units.active) {
        if(!unit || unit->hist_figure_id==-1 || (!unit->flags1.bits.inactive && !unit->flags3.bits.ghostly))continue;
        const auto* incident=df::incident::find(unit->counters.death_id);
        if(incident && incident->site==plot->site_id && incident->entity==plot->group_id && !(incident->flags.whole&3))continue;
        size_t bucket;
        if(deceasedCitizen(unit->id)) {
            if(slabCount(unit->hist_figure_id)>0 || memorialized(unit) || entombed(unit))bucket=2;
            else bucket=unit->ghost_info && unit->ghost_info->flags.bits.announced?0:1;
        } else bucket=unit->civ_id==plot->civ_id?3:4;
        buckets[bucket].push_back(unit->hist_figure_id);
    }
    const auto text=[base](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
    std::vector<WorkshopMemorialRow> result;
    for(const auto& bucket:buckets)for(const auto hfid:bucket) {
        WorkshopMemorialRow row;row.historicalFigureId=hfid;
        const auto* figure=df::historical_figure::find(hfid);
        auto* unit=figure?df::unit::find(figure->unit_id):nullptr;
        // Native leaves the constructor's empty info/default priority if the
        // historical figure or its unit no longer resolves.
        if(unit) {
            const auto count=slabCount(unit->hist_figure_id);
            const bool placed=memorialized(unit),buried=entombed(unit);
            const bool ghost=!placed && !buried && unit->ghost_info && unit->ghost_info->flags.bits.announced;
            row.info=text(placed?(buried?0x16beee8:0x16becb0):(buried?0x16becc0:(ghost?0x16bec90:0x16bec98)));
            row.info+=text(0x15e90d8);
            if(count>=2) {
                using Number=void (*)(int32_t,std::string*);
                reinterpret_cast<Number>(base+0x52c130)(count,&row.info);
                row.info+=text(0x16bef08);
            } else row.info+=text(count==1?0x16bebf0:0x16bec00);
            const int32_t group=petCaste(unit)?3000:(deceasedCitizen(unit->id)?1000:2000);
            row.priority=placed || buried?group+2:(ghost?1:group+int32_t(count!=0));
        }
        result.push_back(std::move(row));
    }
    return result;
}
}
