#pragma once
#include "workshop_job_native.h"
#include "workshop_catalog_native.h"
#include "workshop_orders_native.h"
#include "df/manager_order_template.h"
#include "df/cwo_buildingst.h"
#include "df/entity_raw.h"
#include "df/building_def.h"
#include <cstdlib>

namespace df3d_production {
inline bool workOrderCatalogSupported() {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8c812d,0x4d2,UINT64_C(0xa0bb18750d912459)}, // clothier fabric/task membership
            {0x8c571c,0x106,UINT64_C(0xe7e3ae7701fd626a)}, // jeweler job types + encrust targets
            {0x8c7d22,0x40b,UINT64_C(0xce7eea858978ebf4)}, // leather civ subtypes + LEATHER membership
            {0x8c6cf8,0x8f,UINT64_C(0xe02d6e399757e45f)}, // farmer task membership
            {0x8cb3ee,0xe,UINT64_C(0xcfbd210931f14f86)}, // tanner: reactions only
            {0x8cb44f,0x24,UINT64_C(0x8040656119a99b61)}, // millstone/quern builtin
            {0xa97150,0x5678,UINT64_C(0x87b9a46d78af72d7)},
            {0x3113b0,0x3a,UINT64_C(0x3a7d19574928cc99)},
            {0x8c03a0,0x17ad,UINT64_C(0xedd2766250590831)},
            {0x14d7f0,0xa0,UINT64_C(0x982df68a02e5f200)},
            {0x376300,0x82,UINT64_C(0x00a15ffdde597218)},
            {0x311580,0x68c,UINT64_C(0x47301c66334c61ee)},
            {0x3769cf,0x4d,UINT64_C(0x7e38a43365dc1161)},
            {0x37683f,0x4a,UINT64_C(0x659f0f1773728921)},
            {0x3c31a0,0x155,UINT64_C(0x2eafe9596f5d778c)}, // native picker search composition
            {0x30fe90,0xbe,UINT64_C(0x977bec31a3f05304)}, // allocate/register order
            {0x31f5cd,0x164,UINT64_C(0xe533c103b392863b)}, // selected-template effects
            {0xd15cf0,0x1f6,UINT64_C(0x00a3647b8c63120e)}, // details eligibility/requirements
            {0xd09ca0,0x2f52,UINT64_C(0x2e65a5a8b4f5a1c5)},
            {0xa676c0,0xa0,UINT64_C(0xcf5d67f71c5b901e)},
            {0xcc0110,0xa0,UINT64_C(0xdb71755904d0cf88)},
            {0x54d320,0x16b4,UINT64_C(0x13ca7481db9a2123)}, // category names
            {0x376270,0x82,UINT64_C(0x394e638a27d80d31)}, // category ordering
            {0x376b0a,0xedb,UINT64_C(0x2cf08d51d161f014)}, // category enumeration/membership
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return supported;
}

// A97150 builds the fortress-wide catalog in the supplied vector. It reads
// civilization resources, installed raws and acquired reaction permissions;
// no native picker/widget storage is supplied or borrowed. Native376390 uses
// this same builder before formatting, sorting and grouping the picker rows.
// This is the global catalog, not yet the workshop-filtered picker.
inline std::optional<std::vector<df::manager_order_template>> nativeWorkOrderCatalog() {
    if(!workOrderCatalogSupported() || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    static_assert(sizeof(df::manager_order_template)==0x98);
    static_assert(offsetof(df::manager_order_template,reaction_name)==8);
    static_assert(offsetof(df::manager_order_template,name)==0x50);
    static_assert(offsetof(df::manager_order_template,compare_str)==0x70);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Destroy=void (*)(df::manager_order_template*);
    struct Owned {
        std::vector<df::manager_order_template*> rows;
        Destroy destroy;
        ~Owned(){for(auto* row:rows)if(row)destroy(row);}
    } owned{{},reinterpret_cast<Destroy>(base+0x3113b0)};
    // Material resolution may populate a lookup cache. Restore that scratch
    // while retaining the templates allocated into our independent vector.
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Build=void (*)(std::vector<df::manager_order_template*>*);
    reinterpret_cast<Build>(base+0xa97150)(&owned.rows);
    if(owned.rows.size()>65536)return std::nullopt;
    const auto& text=df3d_area::staffOrderingFunctions();if(!text)return std::nullopt;
    for(auto* row:owned.rows) {
        if(!row || row->reaction_name.size()>128)return std::nullopt;
        df::job job;
        job.job_type=row->job_type;job.reaction_name=row->reaction_name;
        job.item_type=row->item_type;job.item_subtype=row->item_subtype;
        job.mat_type=row->mat_type;job.mat_index=row->mat_index;
        job.specflag=row->specflag;job.specdata=row->specdata;
        job.material_category=row->material_category;
        job.art_spec.type=row->art_specifier;job.art_spec.id=row->art_specifier_id1;job.art_spec.subid=row->art_specifier_id2;
        const auto caption=workshopJobCaption(job);
        if(!caption || caption->size()>8192)return std::nullopt;
        row->name=*caption;row->compare_str=*caption;text.normalize(&row->compare_str);
    }
    using Compare=int (*)(const void*,const void*);
    // Native376640 uses qsort with this pure caption comparator. Its arguments
    // point only into our vector of owned templates.
    if(!owned.rows.empty())std::qsort(owned.rows.data(),owned.rows.size(),sizeof(owned.rows[0]),reinterpret_cast<Compare>(base+0x376300));
    std::vector<df::manager_order_template> result;result.reserve(owned.rows.size());
    for(const auto* row:owned.rows)result.push_back(*row);
    return result;
}

inline std::optional<std::vector<df::manager_order_template>> nativeWorkshopOrderCatalog(df::building* building) {
    if(!building || (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace))return std::nullopt;
    const auto header=observeBuildingHeader(building);
    if(!header || header->removing || header->stage!=header->maxStage)return std::nullopt;
    auto catalog=nativeWorkOrderCatalog();if(!catalog)return std::nullopt;
    const int32_t type=int32_t(building->getType()),subtype=building->getSubtype(),custom=building->getCustomType();
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Classify=void (*)(int16_t,int16_t,int16_t,int32_t,uint32_t,int32_t*,int32_t*);
    const auto classify=reinterpret_cast<Classify>(base+0x311580);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<df::manager_order_template> result;
    for(auto& row:*catalog) {
        bool allowed=false;
        if(row.job_type==df::job_type::CustomReaction) {
            // Native3767aa finds the first exact reaction code, then checks its
            // parallel building restriction vectors. Use simulation raws only.
            const auto& reactions=df::global::world->raws.reactions.reactions;
            const auto found=std::find_if(reactions.begin(),reactions.end(),[&](const auto* r){return r && r->code==row.reaction_name;});
            if(found!=reactions.end()) {
                const auto& match=(*found)->building;
                if(match.type.size()!=match.subtype.size() || match.type.size()!=match.custom.size())return std::nullopt;
                for(size_t i=0;i<match.type.size();++i)
                    if(int32_t(match.type[i])==type && match.subtype[i]==subtype && match.custom[i]==custom){allowed=true;break;}
            }
        } else if(custom==-1) {
            int32_t expectedType=-1,expectedSubtype=-1;
            classify(int16_t(row.job_type),row.item_subtype,row.mat_type,row.mat_index,row.material_category.whole,&expectedType,&expectedSubtype);
            // Native3769cf maps magma forge/furnace variants for builtin jobs.
            int32_t builtinSubtype=subtype;
            if(type==13 && subtype==6)builtinSubtype=5;
            else if(type==5 && subtype>=4 && subtype<=6)builtinSubtype=subtype-3;
            allowed=expectedType==type && expectedSubtype==builtinSubtype;
        }
        if(allowed)result.push_back(std::move(row));
    }
    return result;
}

// These native task branches have the same builtin descriptor membership as
// the owned order catalog (Carpenter8c762d, Kitchen8cb3fc, WoodFurnace root,
// Farmer8c6cf8, Tanner8cb3ee, Millstone8cb44f Leather8c7d22, Jeweler8c571c and Clothier8c812d fabric pages).
// Reaction templates identify queued jobs across categories; visible reaction
// choices still use the separate native category/availability reader.
// Do not extend this to other families merely because classifier311580 matches:
// Mechanic, Craftsdwarf, Butcher, Stoneworker and Forge differ from task menus.
inline std::optional<std::vector<df::manager_order_template>> workshopTaskTemplates(df::building* building) {
    if(!building)return std::nullopt;
    const auto type=building->getType();const auto subtype=building->getSubtype();
    const bool forge=int(type)==13 && (subtype==5 || subtype==6);
    if(!forge && !((int(type)==13 && (subtype==0 || subtype==1 || subtype==4 || subtype==11 || subtype==12 || subtype==13 || subtype==22 || subtype==19 || subtype==15)) || (int(type)==5 && subtype==0)))return std::nullopt;
    auto rows=nativeWorkshopOrderCatalog(building);if(!rows)return std::nullopt;
    // These descriptors qualify existing queued jobs, never populate the forge
    // picker. The native task branches supply its choices independently.
    if(forge)for(const auto* job:building->jobs) {
        if(!job || job->mat_type!=0 || (int(job->job_type)!=133 && int(job->job_type)!=139))continue;
        const auto tasks=workshopForgeTasks(building,int(job->job_type)==133?3:4,job->mat_index);
        if(tasks)for(const auto& task:*tasks)if(task.job_type==job->job_type && task.item_subtype==job->item_subtype)rows->push_back(task);
    }
    return rows;
}

// Caption8c28f0 delegates to this semantic formatter; never construct its widget.
inline std::optional<std::vector<WorkshopForgeChoice>> workshopClothierFabrics(df::building* building) {
    if(!workOrderCatalogSupported() || !building || int(building->getType())!=13 || building->getSubtype()!=13)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
            {0x8c28f0,0x4a,UINT64_C(0xf75668c2b3daf60e)},
            {0x1615870,13,UINT64_C(0xcd56f05c0ea1035c)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned || !df::global::world)return std::nullopt;
    using Name=void (*)(void*,std::string*,int16_t,int32_t,int32_t,bool,int16_t);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<WorkshopForgeChoice> rows;
    for(int32_t fabric:{4,8,4096}){
        std::string caption;
        reinterpret_cast<Name>(base+0x14d1920)(df::global::world,&caption,-1,-1,fabric,false,0);
        caption.append(reinterpret_cast<const char*>(base+0x1615870),13);
        rows.push_back({fabric,-1,std::move(caption)});
    }
    return rows;
}

struct WorkshopOrderCatalog {
    uint64_t revision=0;
    std::vector<df::manager_order_template> rows;
};

struct NativeWorkOrderGroup {
    int32_t type=-1,subtype=-1,custom=-1;
    std::string name;
    std::vector<size_t> rows;
};
// Native376b0a..3779e5 groups a fresh catalog. The surrounding picker opener
// changes unrelated menus and must not be called, even with an owned context.
// Classification, naming and comparison use native semantic leaves; only the
// inline group enumeration/membership is composed here from simulation raws.
inline std::optional<std::vector<NativeWorkOrderGroup>> nativeWorkOrderGroups(const std::vector<df::manager_order_template>& catalog) {
    if(!workOrderCatalogSupported() || !df::global::world || !df::global::plotinfo)return std::nullopt;
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    if(!entity || !entity->entity_raw || catalog.size()>65536)return std::nullopt;
    static_assert(offsetof(df::entity_raw,workshops)+offsetof(df::entity_raw::T_workshops,permitted_building_id)==0x3cb8);
    static_assert(offsetof(df::cwo_buildingst,name)==0x28);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Classify=void (*)(int16_t,int16_t,int16_t,int32_t,uint32_t,int32_t*,int32_t*);
    using Name=void (*)(std::string*,int16_t,int16_t,int16_t,int32_t);
    const auto classify=reinterpret_cast<Classify>(base+0x311580);
    const auto name=reinterpret_cast<Name>(base+0x54d320);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<df::cwo_buildingst> groups;
    const auto& permitted=entity->entity_raw->workshops.permitted_building_id;
    if(permitted.size()>4096)return std::nullopt;
    groups.reserve(29+permitted.size());
    const auto append=[&](int32_t type,int32_t subtype,int32_t custom) {
        df::cwo_buildingst group;group.type=type;group.subtype=subtype;group.custom_id=custom;
        name(&group.name,int16_t(type),int16_t(subtype),df::global::plotinfo->race_id,custom);
        groups.push_back(std::move(group));
    };
    for(int32_t subtype=0;subtype<25;++subtype)if(subtype!=6 && subtype!=23)append(13,subtype,-1);
    for(int32_t subtype=0;subtype<4;++subtype)append(5,subtype,-1);
    for(auto id:permitted) {
        const auto* raw=df::building_def::find(id);
        if(raw && (raw->building_type==df::building_type::Workshop || raw->building_type==df::building_type::Furnace))
            append(int32_t(raw->building_type),raw->building_subtype,raw->id);
    }
    std::vector<df::cwo_buildingst*> sorted;sorted.reserve(groups.size());
    for(auto& group:groups)sorted.push_back(&group);
    using Compare=int (*)(const void*,const void*);
    if(!sorted.empty())std::qsort(sorted.data(),sorted.size(),sizeof(sorted[0]),reinterpret_cast<Compare>(base+0x376270));
    std::vector<std::pair<int32_t,int32_t>> builtin(catalog.size(),{-1,-1});
    for(size_t i=0;i<catalog.size();++i) {
        const auto& row=catalog[i];
        if(row.job_type!=df::job_type::CustomReaction)
            classify(int16_t(row.job_type),row.item_subtype,row.mat_type,row.mat_index,row.material_category.whole,&builtin[i].first,&builtin[i].second);
    }
    std::vector<NativeWorkOrderGroup> result;
    if(!catalog.empty()) {
        NativeWorkOrderGroup all;all.name="All tasks"; // Native literal162a138.
        for(size_t i=0;i<catalog.size();++i)all.rows.push_back(i);
        result.push_back(std::move(all));
    }
    for(const auto* group:sorted) {
        NativeWorkOrderGroup output{group->type,group->subtype,group->custom_id,group->name,{}};
        if(output.name.size()>512)return std::nullopt;
        for(size_t i=0;i<catalog.size();++i) {
            const auto& row=catalog[i];bool allowed=false;
            if(row.job_type==df::job_type::CustomReaction) {
                const auto& reactions=df::global::world->raws.reactions.reactions;
                const auto found=std::find_if(reactions.begin(),reactions.end(),[&](const auto* reaction){return reaction && reaction->code==row.reaction_name;});
                if(found!=reactions.end()) {
                    const auto& match=(*found)->building;
                    if(match.type.size()!=match.subtype.size() || match.type.size()!=match.custom.size())return std::nullopt;
                    for(size_t j=0;j<match.type.size();++j)
                        if(int32_t(match.type[j])==output.type && match.subtype[j]==output.subtype && match.custom[j]==output.custom){allowed=true;break;}
                }
            } else allowed=output.custom==-1 && builtin[i].first==output.type && builtin[i].second==output.subtype;
            if(allowed)output.rows.push_back(i);
        }
        if(!output.rows.empty())result.push_back(std::move(output));
    }
    return result;
}

// The receipt covers the current workshop and every ordered recipe value. A
// row index is meaningful only with this receipt; callers never supply recipes.
inline std::optional<WorkshopOrderCatalog> workshopOrderCatalog(df::building* building,bool global=false) {
    const auto profile=workshopOrdersProfile(building);
    if(global) {
        const auto* entity=df::global::plotinfo?df::global::plotinfo->main.fortress_entity:nullptr;
        if(!entity || entity->assignments_by_type[df::entity_position_responsibility::MANAGE_PRODUCTION].empty())return std::nullopt;
    } else if(!profile || !profile->managerAvailable)return std::nullopt;
    auto rows=global?nativeWorkOrderCatalog():nativeWorkshopOrderCatalog(building);if(!rows)return std::nullopt;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value) {
        for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    const auto text=[&](const std::string& value) {
        add(value.size());for(unsigned char c:value){hash^=c;hash*=UINT64_C(1099511628211);}
    };
    add(global?UINT64_MAX:profile->revision);add(rows->size());
    for(const auto& row:*rows) {
        add(int(row.job_type));text(row.reaction_name);add(int(row.item_type));add(row.item_subtype);
        add(row.mat_type);add(row.mat_index);add(row.specflag.whole);
        uint32_t data=0;static_assert(sizeof(row.specdata)==sizeof(data));
        std::memcpy(&data,&row.specdata,sizeof(data));add(data);add(row.material_category.whole);
        add(int(row.art_specifier));add(row.art_specifier_id1);add(row.art_specifier_id2);
        text(row.name);text(row.compare_str);
    }
    return WorkshopOrderCatalog{(hash&INT64_MAX)?(hash&INT64_MAX):1,std::move(*rows)};
}

struct WorkshopOrderCreateResult {
    WorkshopOrdersOutcome outcome=WorkshopOrdersOutcome::Rejected;
    int32_t orderId=-1;
    std::string caption;
    bool validated=false;
    std::optional<WorkshopOrdersProfile> profile;
};

inline WorkshopOrderCreateResult createWorkshopOrder(int32_t buildingId,uint64_t revision,int32_t choice) {
    WorkshopOrderCreateResult result;
    if(!workOrderCatalogSupported()){result.outcome=WorkshopOrdersOutcome::Unavailable;return result;}
    if(choice<0 || !revision)return result;
    auto* building=df::building::find(buildingId);
    const bool global=buildingId==-2;
    auto catalog=workshopOrderCatalog(building,global);if(!catalog)return result;
    if(catalog->revision!=revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(size_t(choice)>=catalog->rows.size())return result;
    auto& orders=df::global::world->manager_orders;
    if(orders.manager_order_next_id<0 || orders.manager_order_next_id==INT32_MAX || orders.all.size()>=65536)return result;
    static_assert(sizeof(df::manager_order)==0xa8);
    static_assert(offsetof(df::manager_order,reaction_name)==0x10);
    static_assert(offsetof(df::manager_order,amount_left)==0x50);
    static_assert(offsetof(df::manager_order,status)==0x54);
    static_assert(offsetof(df::plotinfost,tasks)+offsetof(df::entity_activity_statistics,population)==0x35c);
    static_assert(offsetof(df::plotinfost,nobles)+offsetof(df::plotinfo_positionst,manager_cooldown)==0x74);
    static_assert(offsetof(df::workquota_handlerst,manager_order_next_id)==0x18);
    const auto& recipe=catalog->rows[size_t(choice)];
    // Complete potentially throwing preparation before native registration.
    // The native allocator then appends into reserved capacity; string swap and
    // scalar writes below cannot leave a partially initialized registered order.
    std::string reaction=recipe.reaction_name;
    result.caption=recipe.name;
    orders.all.reserve(orders.all.size()+1);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Allocate=df::manager_order* (*)();
    result.outcome=WorkshopOrdersOutcome::Unknown;
    try {
        auto* order=reinterpret_cast<Allocate>(base+0x30fe90)();
        if(!order)return result;
        order->id=orders.manager_order_next_id++;
        order->workshop_id=global?-1:buildingId;
        order->job_type=recipe.job_type;order->reaction_name.swap(reaction);
        order->item_type=recipe.item_type;order->item_subtype=recipe.item_subtype;
        order->mat_type=recipe.mat_type;order->mat_index=recipe.mat_index;
        order->specflag=recipe.specflag;order->specdata=recipe.specdata;
        order->material_category=recipe.material_category;
        order->amount_left=10;order->amount_total=10;
        order->status.bits.validated=df::global::plotinfo->tasks.population<20;
        df::global::plotinfo->nobles.manager_cooldown=0;
        // Native leaves art_spec at the allocator defaults for this action.
        // Its first order-row observation (1896ca) calls this semantic helper
        // to populate the order's own requirements and determine whether it
        // offers Details. It accepts only the selected simulation record.
        using Details=bool (*)(df::manager_order*);
        {
            df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
            reinterpret_cast<Details>(base+0xd15cf0)(order);
        }
        result.orderId=order->id;
        result.validated=order->status.bits.validated;
        if(global) {
            if(std::find(orders.all.begin(),orders.all.end(),order)!=orders.all.end())result.outcome=WorkshopOrdersOutcome::Applied;
            return result;
        }
        auto after=workshopOrdersProfile(building);
        if(after && std::find(after->orderIds.begin(),after->orderIds.end(),order->id)!=after->orderIds.end()) {
            result.profile=std::move(after);result.outcome=WorkshopOrdersOutcome::Applied;
        }
    }catch(...) {} // A potentially registered effect must never be replayed.
    return result;
}
}
