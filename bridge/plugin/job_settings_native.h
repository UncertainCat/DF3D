#pragma once
#include "work_order_details_native.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"

namespace df3d_production {
struct JobSettingsObservation {
    int32_t jobId=-1,buildingId=-1,selected=-1;
    df::coord search;
    std::string caption;
    std::vector<WorkOrderDetailOption> options;
    std::vector<WorkOrderDetailMaterial> materials;
};
inline bool jobSettingsReady() {
    static const bool ready=[] {
        if(!workOrderDetailsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xd15ef0,0x1d0,UINT64_C(0x41e934528fc15d5a)},
            {0x213a63,0x3c3,UINT64_C(0xbbbfcafbc2f10658)},
            {0x213f74,0xac,UINT64_C(0xbc878cc2d1caf065)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
// Staged read adapter. Never invokes the global opener213420, widgets, or their
// callbacks. The job and requirement containers are owned; holder/item/raw
// records are read-only simulation inputs. No job is linked or reserved here.
inline std::optional<JobSettingsObservation> nativeJobSettings(const df::job& source,int32_t selected=-1) {
    if(!jobSettingsReady() || !df::global::world || source.job_items.elements.size()>64)return std::nullopt;
    std::vector<df::job_item> inputs;inputs.reserve(source.job_items.elements.size());
    for(const auto* item:source.job_items.elements){if(!item)return std::nullopt;inputs.push_back(*item);}
    df::job job=source;job.job_items.elements.clear();
    for(auto& item:inputs)job.job_items.elements.push_back(&item);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!reinterpret_cast<bool(*)(df::job*)>(base+0xd15ef0)(&job))return std::nullopt;
    df::building* holder=nullptr;
    for(auto* ref:job.general_refs)if(ref && ref->getType()==df::general_ref_type::BUILDING_HOLDER){holder=ref->getBuilding();break;}
    if(!holder)return std::nullopt;
    const auto caption=workshopJobCaption(job);if(!caption)return std::nullopt;
    JobSettingsObservation result;result.jobId=job.id;result.buildingId=holder->id;result.caption=*caption;
    result.search.x=holder->centerx;result.search.y=holder->centery;result.search.z=holder->z;
    // No separately callable enumeration leaf exists: these are the pinned
    // job-side opener's input predicates and dispatch data, not order families.
    for(size_t i=0;i<inputs.size();++i) {
        const auto& item=inputs[i];
        if(item.job_details_flags.bits.have_set_job_details ||
           (item.mat_type==0 && item.mat_index==-1) ||
           ((int(item.item_type)==5 || int(item.item_type)==55) && item.mat_type==-1) ||
           (item.flags1.whole&0x1000000) || (item.flags2.whole&0x8536c000) || (item.flags3.whole&0x120000))
            result.options.push_back({0,int32_t(i),nativeDetailInputCaption(item)});
    }
    const int family=int(job.job_type)-79;
    if(family>=0 && family<=151) {
        const uint8_t slot=base[0x213f88+family];
        if(slot>4)return std::nullopt;
        uint32_t target=0;std::memcpy(&target,base+0x213f74+slot*4,sizeof(target));
        switch(target) {
            case 0x213b8d:result.options.push_back({2,-1,reinterpret_cast<const char*>(base+0x1615910)});break;
            case 0x213d5e:result.options.push_back({1,-1,reinterpret_cast<const char*>(base+0x15fe1e8)});break;
            case 0x213dab:result.options.push_back({3,-1,reinterpret_cast<const char*>(base+0x1615690)});break;
            case 0x213dcd:result.options.push_back({6,int(job.job_type),reinterpret_cast<const char*>(base+0x1615930)});break;
            case 0x213e26:break;
            default:return std::nullopt;
        }
    }
    if(selected==-1 && result.options.size()==1)selected=0;
    if(selected==-1)return result;
    if(selected<0 || size_t(selected)>=result.options.size())return std::nullopt;
    const auto option=result.options[size_t(selected)];
    // Artwork/clothing and job effects still need their job-specific adapter.
    if(option.kind!=0 && option.kind!=3 && option.kind!=6)return std::nullopt;
    df::job_details_interfacest context;
    context.jb=&job;context.wq=nullptr;context.bld=holder;context.search=result.search;
    context.context=df::job_details_context_type::CREATURES_LIST_TASK;
    context.current_option=df::job_details_option_type(option.kind);context.current_option_index=option.index;
    {
        df3d_creature::InventoryRandomRestore random(const_cast<uint8_t*>(base));
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        reinterpret_cast<void(*)(df::job_details_interfacest*)>(base+0x21d190)(&context);
    }
    result.selected=selected;
    if(option.kind==3) {
        constexpr size_t captions[]={0x16157d4,0x16157f0,0x16157e0,0x16157cc,0x161580c};
        if(context.improvement_type.size()>5)return std::nullopt;
        for(auto kind:context.improvement_type) {
            if(int(kind)<0 || int(kind)>=int(std::size(captions)))return std::nullopt;
            WorkOrderDetailMaterial row;row.id=int32_t(result.materials.size());row.index=int(kind);
            row.caption=reinterpret_cast<const char*>(base+captions[int(kind)]);result.materials.push_back(std::move(row));
        }
        return result;
    }
    const auto& types=option.kind==0?context.material:context.plant_mat;
    const auto& indices=option.kind==0?context.matgloss:context.plant_matgloss;
    const auto& counts=option.kind==0?context.material_count:context.plant_count;
    if(types.size()>16384 || types.size()!=indices.size() || types.size()!=counts.size())return std::nullopt;
    for(size_t i=0;i<types.size();++i) {
        WorkOrderDetailMaterial row;row.id=int32_t(i);row.type=types[i];row.index=indices[i];row.count=counts[i];
        if(option.kind==0) {
            WorkOrderFilterChoice material;material.materialType=types[i];material.materialIndex=indices[i];material.materialState=0;
            const auto named=nativeWorkOrderFilterCaption(material,1);if(!named)return std::nullopt;row.caption=*named;
        } else {
            const auto& plants=df::global::world->raws.plants.all;
            if(indices[i]<0 || size_t(indices[i])>=plants.size() || !plants[size_t(indices[i])])return std::nullopt;
            row.caption=plants[size_t(indices[i])]->name;reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.caption);
        }
        if(row.caption.size()>512)return std::nullopt;
        result.materials.push_back(std::move(row));
    }
    return result;
}
}
