#pragma once
#include "work_order_details_native.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"

namespace df3d_production {
struct JobSettingsObservation {
    int32_t jobId=-1,buildingId=-1,selected=-1;
    uint64_t revision=0,choicesRevision=0;
    df::coord search;
    std::string caption;
    std::optional<std::string> currentValue;
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
            {0x2198df,0xcc,UINT64_C(0x0835284909b8e4cc)},
            {0x21bd53,0x28,UINT64_C(0x33033347c20397f2)},
            {0x219386,0x37,UINT64_C(0x5648d69c12ce8e22)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
struct JobSettingsTarget {int32_t jobId=-1,buildingId=-1;};
// Native1423130 uses d15ef0 for the row button. Evaluate it on independently
// owned job/requirement storage; do not populate the material catalog per row.
inline std::optional<JobSettingsTarget> jobSettingsTarget(const df::job* source) {
    if(!source || !jobSettingsReady() || source->id<0 || source->job_items.elements.size()>64)return std::nullopt;
    std::vector<df::job_item> inputs;inputs.reserve(source->job_items.elements.size());
    for(const auto* item:source->job_items.elements){if(!item)return std::nullopt;inputs.push_back(*item);}
    df::job job=*source;job.job_items.elements.clear();
    for(auto& item:inputs)job.job_items.elements.push_back(&item);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!reinterpret_cast<bool(*)(df::job*)>(base+0xd15ef0)(&job))return std::nullopt;
    for(auto* ref:job.general_refs)if(ref && ref->getType()==df::general_ref_type::BUILDING_HOLDER) {
        const auto* holder=ref->getBuilding();
        return holder && holder->id>=0?std::optional<JobSettingsTarget>({job.id,holder->id}):std::nullopt;
    }
    return std::nullopt;
}
// Staged read adapter. Never invokes the global opener213420, widgets, or their
// callbacks. The job and requirement containers are owned; holder/item/raw
// records are read-only simulation inputs. No job is linked or reserved here.
inline std::optional<JobSettingsObservation> nativeJobSettings(const df::job& source,int32_t selected=-1,const std::string& query={}) {
    if(!jobSettingsReady() || !df::global::world || !df::global::plotinfo || source.job_items.elements.size()>64 || query.size()>128)return std::nullopt;
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
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    const auto mix=[&](auto... values){(add(uint64_t(values)),...);};
    const auto text=[&](const std::string& value){add(value.size());for(unsigned char ch:value){hash^=ch;hash*=UINT64_C(1099511628211);}};
    mix(job.id,holder->id,result.search.x,result.search.y,result.search.z,int(job.job_type),job.mat_type,job.mat_index,
        int(job.item_type),job.item_subtype,job.specflag.whole,job.specdata.hist_figure_id,job.material_category.whole,
        int(job.art_spec.type),job.art_spec.id,job.art_spec.subid);
    text(job.reaction_name);add(inputs.size());
    for(const auto& item:inputs) {
        mix(int(item.item_type),item.item_subtype,item.mat_type,item.mat_index,item.flags1.whole,item.quantity,int(item.vector_id),
            item.flags2.whole,item.flags3.whole,item.flags4,item.flags5,item.metal_ore,item.min_dimension,item.reagent_index,
            item.reaction_id,int(item.has_tool_use),item.dye_color,item.job_details_flags.whole,item.job_details_mat_type,
            item.job_details_mat_index,item.job_details_item_flags2.whole);
        text(item.reaction_class);text(item.has_material_reaction_product);add(item.contains.size());for(auto id:item.contains)add(id);
    }
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
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
    if(selected==-1)return query.empty()?std::optional<JobSettingsObservation>(result):std::nullopt;
    if(selected<0 || size_t(selected)>=result.options.size())return std::nullopt;
    const auto option=result.options[size_t(selected)];
    // Clothing shares native inline enumeration, not a manager-order proxy.
    if(option.kind==2) {
        auto sizes=nativeClothingSizes(job.specdata.hist_figure_id,result.revision,query);if(!sizes)return std::nullopt;
        result.selected=selected;result.currentValue=std::move(sizes->currentValue);
        result.choicesRevision=sizes->revision;result.materials=std::move(sizes->materials);return result;
    }
    // Artwork still needs its job-specific adapter.
    if(option.kind!=0 && option.kind!=3 && option.kind!=6)return std::nullopt;
    if(option.kind==3 && !query.empty())return std::nullopt;
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
    hash=result.revision;mix(option.kind,option.index);
    if(option.kind==3) {
        constexpr size_t captions[]={0x16157d4,0x16157f0,0x16157e0,0x16157cc,0x161580c};
        if(context.improvement_type.size()>5)return std::nullopt;
        for(auto kind:context.improvement_type) {
            if(int(kind)<0 || int(kind)>=int(std::size(captions)))return std::nullopt;
            WorkOrderDetailMaterial row;row.id=int32_t(result.materials.size());row.index=int(kind);
            row.caption=reinterpret_cast<const char*>(base+captions[int(kind)]);result.materials.push_back(std::move(row));
            add(int(kind));
        }
        result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
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
        if(row.count>0) {
            const auto amount=reinterpret_cast<int32_t(*)(int32_t,int32_t,int32_t,bool*)>(base+0x74f430)(row.count,df::global::plotinfo->nobles.bookkeeper_precision,0,&row.estimated);
            row.countCaption.emplace();reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(amount,&*row.countCaption);
            if(row.estimated)row.countCaption->append(reinterpret_cast<const char*>(base+0x1614d50),1);
        }
        mix(row.type,row.index,row.count,row.estimated);text(row.caption);if(row.countCaption)text(*row.countCaption);
        result.materials.push_back(std::move(row));
    }
    result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    if(!query.empty()) {
        if(option.kind==0)context.material_filter=query;else context.plant_filter=query;
        {
            df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
            reinterpret_cast<void(*)(df::job_details_interfacest*)>(base+(option.kind==0?0x2230f0:0x2239e0))(&context);
        }
        if(types.size()!=indices.size() || types.size()>result.materials.size())return std::nullopt;
        std::map<std::pair<int16_t,int32_t>,size_t> identities;
        for(size_t i=0;i<result.materials.size();++i)if(!identities.emplace(std::make_pair(result.materials[i].type,result.materials[i].index),i).second)return std::nullopt;
        std::vector<WorkOrderDetailMaterial> filtered;
        for(size_t i=0;i<types.size();++i) {
            const auto found=identities.find({types[i],indices[i]});if(found==identities.end())return std::nullopt;
            filtered.push_back(std::move(result.materials[found->second]));
        }
        result.materials=std::move(filtered);
    }
    return result;
}
// Material and clothing effects are inline in native218900, with pinned spans. The
// input handler also reads menu state and cannot be called. Use fresh native
// eligibility/catalog observations, then reproduce only its job field writes.
// Caller resolves membership at a safe point; this function verifies identity
// and both displayed receipts before the first write. No operation can fail or
// allocate once mutation starts. Artwork and other option families remain separate work.
enum class JobSettingsOutcome {Rejected,Stale,Applied};
inline JobSettingsOutcome applyJobSetting(df::job& job,const JobSettingsTarget& target,
    uint64_t revision,int32_t option,uint64_t choicesRevision,int32_t choice) {
    if(!revision || revision>INT64_MAX || !choicesRevision || choicesRevision>INT64_MAX || option<0 || choice<0)
        return JobSettingsOutcome::Rejected;
    if(job.id!=target.jobId)return JobSettingsOutcome::Stale;
    const auto observed=nativeJobSettings(job,option);
    if(!observed || observed->buildingId!=target.buildingId || observed->revision!=revision || observed->choicesRevision!=choicesRevision)
        return JobSettingsOutcome::Stale;
    if(size_t(option)>=observed->options.size())return JobSettingsOutcome::Rejected;
    const auto kind=observed->options[size_t(option)].kind;
    if(kind!=0 && kind!=2 && kind!=3)return JobSettingsOutcome::Rejected;
    const auto found=std::find_if(observed->materials.begin(),observed->materials.end(),[&](const auto& row){return row.id==choice;});
    if(found==observed->materials.end())return JobSettingsOutcome::Rejected;
    if(kind==3) {
        // Native21931f writes the chosen kind. Image opens its own editor;
        // only non-image kinds take219386's job artwork-reset/close branch.
        if(found->index<1 || found->index>4)return JobSettingsOutcome::Rejected;
        job.specdata.improvement=df::improvement_type(found->index);
        job.art_spec.type=df::job_art_specifier_type(-1);job.art_spec.id=-1;job.art_spec.subid=-1;
        return JobSettingsOutcome::Applied;
    }
    if(kind==2) {
        // Native21bd73 updates the job's size-race union and closes Details.
        // Requirement rebuilding at21bd7b belongs only to manager orders.
        job.specdata.hist_figure_id=found->index;return JobSettingsOutcome::Applied;
    }
    const auto index=observed->options[size_t(option)].index;
    if(index<0 || size_t(index)>=job.job_items.elements.size() || !job.job_items.elements[size_t(index)])return JobSettingsOutcome::Rejected;
    auto& item=*job.job_items.elements[size_t(index)];
    if(!item.job_details_flags.bits.have_set_job_details) {
        item.job_details_flags.bits.have_set_job_details=true;
        item.job_details_mat_type=item.mat_type;item.job_details_mat_index=item.mat_index;
        item.job_details_item_flags2=item.flags2;
    }
    item.mat_type=found->type;item.mat_index=found->index;
    if(index==0){job.mat_type=found->type;job.mat_index=found->index;}
    return JobSettingsOutcome::Applied;
}
}
