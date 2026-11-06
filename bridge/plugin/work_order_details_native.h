#pragma once
#include "work_order_conditions_native.h"
#include "work_order_dye_native.h"
#include "df/plant_raw.h"
#include "df/job_details_interfacest.h"
#include "df/job_reqst.h"
#include "df/job_item.h"
#include "df/creature_raw.h"
#include "df/caste_raw.h"
#include <map>
#include <tuple>

namespace df3d_production {
struct WorkOrderDetailOption {int32_t kind=-1,index=-1;std::string caption;};
struct WorkOrderDetailMaterial {int16_t type=-1;int32_t index=-1,count=0;std::string caption;int32_t id=-1;std::optional<std::string> countCaption;bool estimated=false;int32_t dyeColor=-1,dyeFirst=-1,dyeSecond=-1;bool opensMenu=false;std::optional<std::array<float,3>> swatch;};
struct WorkOrderDetailsObservation {
    uint64_t revision=0,choicesRevision=0;
    std::string caption;
    std::optional<std::string> currentValue;
    std::optional<std::string> settingHeading;
    int32_t dyeTarget=-1;
    std::vector<WorkOrderDetailOption> options;
    std::vector<WorkOrderDetailMaterial> materials;
};
inline bool workOrderDetailsReady() {
    static const bool ready=[] {
        if(!workOrderRowsSupported() || !workshopInventoryReady() || !workOrderSuggestionsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x214ba4,0x18d,UINT64_C(0x102c5cc07df1d881)}, // input caption selection
            {0x215863,0x25e,UINT64_C(0x41f6aef5115dd21c)}, // material captions
            {0x218565,0xc4,UINT64_C(0x0f7660fb69bc1fe8)}, // plant captions
            {0x2198fe,0x6b,UINT64_C(0xf5db908387417145)}, // material requirement effect
            {0x219967,0x73,UINT64_C(0x7e8585ffa494649a)}, // first input effect
            {0x21afd4,0x41,UINT64_C(0xaf2f8581b53f027d)}, // rebuild requirements
            {0x21c23d,0xf8,UINT64_C(0x282e828b7cc40106)}, // plant effect
            {0x213552,0x4a6,UINT64_C(0x63bcd0e76a4e5af2)}, // inline option enumeration
            {0x213ea8,0xca,UINT64_C(0x20d1f62774cb088a)}, // native job-family dispatch data
            {0x21d190,0x42c0,UINT64_C(0x4e81bb00d071f6f9)}, // selected-option choices
            {0x21d050,0x13f,UINT64_C(0xa1141eef0dbe8cf1)}, // material amount
            {0x2230f0,0x8ec,UINT64_C(0xf7ba06a257bfe54c)}, // material sorting/filter
            {0x2239e0,0x706,UINT64_C(0x0cbc46c3d2089dc0)}, // plant sorting/filter
            {0x74f430,0x1d3,UINT64_C(0x79707f49e13c9401)}, // bookkeeper count estimate
            {0x21517c,0x274,UINT64_C(0x6901b2ef5ade89fb)}, // improvement captions
            {0x21931f,0x11,UINT64_C(0xfe95d347f9ba7430)}, // selected improvement effect
            {0x2193bd,0x94,UINT64_C(0xddbadbcbf283ad20)}, // non-image art reset/rebuild
            {0x2136b3,0x14c,UINT64_C(0xc35ac70a23517d3a)}, // clothing size eligibility/order
            {0x1fad50,0x99,UINT64_C(0x8dafb0b6ccf417bc)}, // native raw race identity
            {0x218077,0x6e,UINT64_C(0xe1f522b5885ed13e)}, // clothing row caption
            {0x21bd7b,0x3a,UINT64_C(0xd30ec4bc32a338c3)}, // order clothing size effect
            {0x8b9daf,0x164,UINT64_C(0x57661bca16adf222)}, // owned lowercase substring filtering
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0x217cce,0x31,UINT64_C(0x29d0e8ec616bdebc)}, // current clothing race caption
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)}, // native creature name
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Native214ba4 classifies the original requirement, including saved originals
// after a prior selection. Captions use the installed native literals.
inline std::string nativeDetailInputCaption(const df::job_item& item) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const bool saved=item.job_details_flags.bits.have_set_job_details;
    const auto type=saved?item.job_details_mat_type:item.mat_type;
    const auto index=saved?item.job_details_mat_index:item.mat_index;
    const auto flags=saved?item.job_details_item_flags2.whole:item.flags2.whole;
    size_t literal=0x16158f0;
    if(type==0 && index==-1)literal=0x16156b8;
    else if(type==-1 && int(item.item_type)==5)literal=0x16156d8;
    else if(type==-1 && int(item.item_type)==55)literal=0x16156d0;
    else if(type==-1 && int(item.item_type)==58)literal=0x16158a4;
    else if(type==-1 && int(item.item_type)==57)literal=0x161589c;
    else {
        constexpr unsigned bits[]={14,31,15,17,18,24,26,20,21};
        constexpr size_t words[]={0x1614d54,0x16158b4,0x16158ac,0x16158c4,0x16158bc,0x16158d4,0x16158cc,0x16158e4,0x16158dc};
        bool found=false;
        for(size_t i=0;i<std::size(bits);++i)if(flags&(uint32_t(1)<<bits[i])){literal=words[i];found=true;break;}
        if(!found) {
            if(item.flags1.whole&0x1000000)literal=0x1601078;
            else if(item.flags3.whole&0x100000)literal=0x16158fc;
            else if(item.flags3.whole&0x20000)literal=0x16156b8;
        }
    }
    return std::string(reinterpret_cast<const char*>(base+0x16156c0))+reinterpret_cast<const char*>(base+literal);
}

// The opener213420 changes global screen state and is never called. Compose its
// pinned semantic option enumeration over initialized simulation requirements.
// Choice population21d190 receives an independently owned context/order/inputs.
// IMAGE opens a separate global picker and is not called here. Improvement
// choices are observed, but their Image choice still needs an owned art editor.
struct ClothingSizeChoices {std::string currentValue;uint64_t revision=0;std::vector<WorkOrderDetailMaterial> materials;};
// Shared inline native clothing enumeration: manager2136b3 and job213bfa use
// the same simulation raws/predicates. Neither opener is invoked at runtime.
inline std::optional<ClothingSizeChoices> nativeClothingSizes(int32_t specifiedRace,uint64_t revision,const std::string& query) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    ClothingSizeChoices result;uint64_t hash=revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    // Native opener2136b3 inlines this enumeration; its whole UI handler is
    // not an eligible runtime API. Iterate authoritative alphabetic raws,
    // and use DF's identity leaf. No native menu vectors are borrowed.
    auto& creatures=df::global::world->raws.creatures;
    const int32_t playerRace=df::global::plotinfo->race_id;
    if(playerRace<0 || size_t(playerRace)>=creatures.all.size() || !creatures.all[size_t(playerRace)] || query.size()>128)return std::nullopt;
    const int32_t currentRace=specifiedRace==-1?playerRace:specifiedRace;
    if(currentRace<0 || size_t(currentRace)>=creatures.all.size() || !creatures.all[size_t(currentRace)])return std::nullopt;
    reinterpret_cast<void(*)(int16_t,std::string*,bool,int16_t)>(base+0xaa3bd0)(int16_t(currentRace),&result.currentValue,true,-1);
    if(result.currentValue.size()>512)return std::nullopt;
    std::vector<int32_t> races{playerRace};
    for(auto* raw:creatures.alphabetic) {
        if(!raw)return std::nullopt;
        if(!std::any_of(raw->caste.begin(),raw->caste.end(),[](const auto* caste){return caste && caste->flags.is_set(df::caste_raw_flags::EQUIPS);}))continue;
        if(!raw->flags.is_set(df::creature_raw_flags::HAS_ANY_INTELLIGENT_LEARNS))continue;
        if(raw!=creatures.all[size_t(playerRace)] && !raw->flags.is_set(df::creature_raw_flags::OCCURS_AS_ENTITY_RACE) &&
           !raw->flags.is_set(df::creature_raw_flags::HAS_ANY_LOCAL_POPS_CONTROLLABLE) && !raw->flags.is_set(df::creature_raw_flags::HAS_ANY_OUTSIDER_CONTROLLABLE) &&
           !raw->flags.is_set(df::creature_raw_flags::HAS_ANY_LOCAL_POPS_PRODUCE_HEROES))continue;
        const int32_t race=int16_t(reinterpret_cast<int16_t(*)(df::creature_handler*,df::creature_raw*)>(base+0x1fad50)(&creatures,raw));
        if(race>=0 && race!=playerRace)races.push_back(race);
    }
    if(races.size()>16384)return std::nullopt;
    hash=revision;add(2);add(races.size());
    for(size_t i=0;i<races.size();++i) {
        const auto race=races[i];if(size_t(race)>=creatures.all.size() || !creatures.all[size_t(race)])return std::nullopt;
        WorkOrderDetailMaterial row;row.id=int32_t(i);row.index=race;row.caption=creatures.all[size_t(race)]->name[1];
        if(row.caption.size()>512)return std::nullopt;
        add(race);result.materials.push_back(std::move(row));
    }
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    if(!query.empty()) {
        const auto lower=reinterpret_cast<void(*)(std::string*)>(base+0x52cee0);
        auto normalized=query;lower(&normalized);
        result.materials.erase(std::remove_if(result.materials.begin(),result.materials.end(),[&](const auto& row){auto caption=row.caption;lower(&caption);return caption.find(normalized)==std::string::npos;}),result.materials.end());
    }
    return result;
}
inline std::optional<WorkOrderDetailsObservation> nativeWorkOrderDetails(df::manager_order& source,int32_t selected=-1,const std::string& query={},int32_t dyeTarget=-1,bool dyeFilterApplied=false) {
    if(!workOrderDetailsReady() || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    const auto observation=nativeWorkOrderRow(source,-1,true);
    if(!observation || !observation->detailsAvailable || !source.items || source.items->elements.size()>64)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    WorkOrderDetailsObservation result;
    result.caption=observation->caption+" ("+std::to_string(source.amount_total)+")";
    uint64_t hash=observation->revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    add(source.items->elements.size());
    for(const auto* item:source.items->elements) {
        if(!item)return std::nullopt;
        add(int(item->item_type));add(item->item_subtype);add(item->mat_type);add(item->mat_index);
        add(item->flags1.whole);add(item->flags2.whole);add(item->flags3.whole);add(item->flags4);add(item->flags5);
        add(item->job_details_flags.whole);add(item->job_details_mat_type);add(item->job_details_mat_index);add(item->job_details_item_flags2.whole);
    }
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    for(size_t i=0;i<source.items->elements.size();++i) {
        const auto* item=source.items->elements[i];if(!item)return std::nullopt;
        if(item->job_details_flags.bits.have_set_job_details ||
           (item->mat_type==0 && item->mat_index==-1) ||
           ((int(item->item_type)==5 || int(item->item_type)==55) && item->mat_type==-1) ||
           (item->flags1.whole&0x1000000) || (item->flags2.whole&0x8536c000) || (item->flags3.whole&0x120000))
            result.options.push_back({0,int32_t(i)});
    }
    const int family=int(source.job_type)-79;
    if(family>=0 && family<=165) {
        const uint8_t slot=base[0x213ecc+family];
        uint32_t target=0;std::memcpy(&target,base+0x213ea8+slot*4,sizeof(target));
        switch(target) {
            case 0x21365d:result.options.push_back({2,-1});break;
            case 0x2137ff:result.options.push_back({1,-1});break;
            case 0x213828:result.options.push_back({6,int(source.job_type)});break;
            case 0x21387f:result.options.push_back({3,-1});break;
            case 0x2138a8:result.options.push_back({4,190});break;
            case 0x2138fc:result.options.push_back({4,191});break;
            case 0x213950:result.options.push_back({4,244});break;
            case 0x2139a4:result.options.push_back({5,-1});break;
            case 0x213e26:break;
            default:return std::nullopt;
        }
    }
    constexpr size_t optionNames[]={0,0x15fe1e8,0x1615910,0x1615690,0x1615900,0x1615900,0x1615930};
    for(auto& option:result.options)option.caption=option.kind==0?nativeDetailInputCaption(*source.items->elements[size_t(option.index)]):reinterpret_cast<const char*>(base+optionNames[option.kind]);
    if(selected==-1)return dyeTarget==-1 && !dyeFilterApplied?std::optional<WorkOrderDetailsObservation>(result):std::nullopt;
    if(selected<0 || size_t(selected)>=result.options.size())return std::nullopt;
    const auto option=result.options[size_t(selected)];
    if(option.kind!=4 && option.kind!=5 && (dyeTarget!=-1 || dyeFilterApplied))return std::nullopt;
    if(option.kind==4 || option.kind==5) {
        const auto catalog=nativeWorkOrderDyeCatalog(source,dyeTarget);if(!catalog)return std::nullopt;
        result.dyeTarget=dyeTarget;
        const auto literal=[&](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
        result.settingHeading=literal(dyeTarget>=0?0x1615820:option.kind==4?0x1615848:0x1615990);
        const auto& colors=df::global::world->raws.descriptors.colors;
        const auto name=[&](int32_t id)->std::optional<std::string>{if(id<0 || size_t(id)>=colors.size() || !colors[size_t(id)] || colors[size_t(id)]->name.size()>128)return std::nullopt;return colors[size_t(id)]->name;};
        const auto substrate=literal(int(source.job_type)==191?0x16158a4:int(source.job_type)==190?0x161589c:0x16156d0);
        hash=result.revision;add(option.kind);add(dyeTarget);add(catalog->rows.size());
        for(const auto& choice:catalog->rows) {
            const auto color=name(choice.color);if(!color)return std::nullopt;
            WorkOrderDetailMaterial row;row.id=int32_t(result.materials.size());row.index=row.dyeColor=choice.color;row.count=choice.available;
            row.dyeFirst=choice.first;row.dyeSecond=choice.second;row.opensMenu=choice.tint;
            if(dyeTarget<0) {
                if(option.kind==5)row.caption="Mix "+*color+literal(0x1615978);
                else row.caption=(choice.tint?literal(0x1615814):"Dye ")+substrate+" "+*color+(choice.tint?literal(0x1615870):"");
                const auto* raw=colors[size_t(choice.color)];row.swatch=std::array<float,3>{raw->red,raw->green,raw->blue};
            } else {
                const auto first=name(choice.first),second=name(choice.second);if(!first || !second)return std::nullopt;
                // Native2160f5/2161c7 repeats the source color in tint captions.
                if(option.kind==4)row.caption=literal(0x1615814)+*first+" "+substrate+" "+*first+literal(0x1615840)+*second+literal(0x1615838);
                else row.caption="Mix "+*color+literal(0x1615960)+*first+" and "+*second;
            }
            if(choice.available>0) {
                row.countCaption=dyeTarget<0?literal(0x1615890):std::string{};
                reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(choice.available,&*row.countCaption);
                if(dyeTarget<0 && option.kind==4 && choice.tint)row.countCaption->append(" "+literal(int(source.job_type)==191?0x1615880:int(source.job_type)==190?0x1615950:0x1615940));
                row.countCaption->append(literal(0x1615860));
            }
            if(row.caption.size()>512 || (row.countCaption && row.countCaption->size()>128))return std::nullopt;
            add(choice.color);add(choice.first);add(choice.second);add(choice.tint);add(choice.available);
            result.materials.push_back(std::move(row));
        }
        result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
        if(dyeFilterApplied || !query.empty()) {
            const auto filtered=nativeWorkOrderDyeCatalog(source,dyeTarget,query,true);if(!filtered)return std::nullopt;
            using Key=std::tuple<int32_t,int32_t,int32_t,bool>;
            std::map<Key,std::vector<size_t>> ids;std::map<Key,size_t> used;
            for(size_t i=0;i<catalog->rows.size();++i){const auto& r=catalog->rows[i];ids[{r.color,r.first,r.second,r.tint}].push_back(i);}
            std::vector<WorkOrderDetailMaterial> rows;
            for(const auto& r:filtered->rows) {
                const Key key{r.color,r.first,r.second,r.tint};const auto found=ids.find(key);auto& next=used[key];
                if(found==ids.end() || next>=found->second.size())return std::nullopt;
                rows.push_back(std::move(result.materials[found->second[next++]]));
            }
            result.materials=std::move(rows);
        }
        return result;
    }
    if(option.kind!=0 && option.kind!=2 && option.kind!=3 && option.kind!=6)return std::nullopt;
    if(option.kind==3 && !query.empty())return std::nullopt;
    if(option.kind==2) {
        auto sizes=nativeClothingSizes(source.specdata.hist_figure_id,result.revision,query);if(!sizes)return std::nullopt;
        result.currentValue=std::move(sizes->currentValue);result.choicesRevision=sizes->revision;result.materials=std::move(sizes->materials);return result;
    }
    std::vector<df::job_item> inputs;inputs.reserve(source.items->elements.size());
    for(const auto* item:source.items->elements)inputs.push_back(*item);
    df::job_reqst requirements;for(auto& item:inputs)requirements.elements.push_back(&item);
    df::manager_order order=source;order.items=&requirements;
    df::job_details_interfacest context;
    static_assert(offsetof(df::job_details_interfacest,current_option)==0x18);
    static_assert(offsetof(df::job_details_interfacest,plant_mat)==0x450);
    context.wq=&order;context.jb=nullptr;context.bld=nullptr;
    context.context=df::job_details_context_type::MANAGER_WORK_ORDER;
    context.search.x=context.search.y=context.search.z=-30000;
    context.current_option=df::job_details_option_type(option.kind);context.current_option_index=option.index;
    {
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        using Populate=void (*)(df::job_details_interfacest*);
        reinterpret_cast<Populate>(base+0x21d190)(&context);
    }
    if(option.kind==3) {
        constexpr size_t captions[]={0x16157d4,0x16157f0,0x16157e0,0x16157cc,0x161580c};
        if(context.improvement_type.size()>5)return std::nullopt;
        hash=result.revision;add(option.kind);add(option.index);add(context.improvement_type.size());
        for(const auto value:context.improvement_type) {
            const int type=int(value);if(type<0 || type>=int(std::size(captions)))return std::nullopt;
            WorkOrderDetailMaterial row;row.id=int32_t(result.materials.size());row.index=type;
            row.caption=reinterpret_cast<const char*>(base+captions[type]);
            add(type);result.materials.push_back(std::move(row));
        }
        result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
        return result;
    }
    const auto& types=option.kind==0?context.material:context.plant_mat;
    const auto& indices=option.kind==0?context.matgloss:context.plant_matgloss;
    const auto& counts=option.kind==0?context.material_count:context.plant_count;
    if(types.size()>16384 || types.size()!=indices.size() || types.size()!=counts.size())return std::nullopt;
    hash=result.revision;add(option.kind);add(option.index);add(types.size());
    for(size_t i=0;i<types.size();++i) {
        std::string caption;
        if(option.kind==0) {
            WorkOrderFilterChoice material;material.materialType=types[i];material.materialIndex=indices[i];material.materialState=0;
            const auto named=nativeWorkOrderFilterCaption(material,1);if(!named)return std::nullopt;caption=*named;
        } else {
            const auto& plants=df::global::world->raws.plants.all;
            if(indices[i]<0 || size_t(indices[i])>=plants.size() || !plants[size_t(indices[i])])return std::nullopt;
            caption=plants[size_t(indices[i])]->name;
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&caption);
        }
        if(caption.size()>512)return std::nullopt;
        add(types[i]);add(indices[i]);
        WorkOrderDetailMaterial row{types[i],indices[i],counts[i],std::move(caption)};
        row.id=int32_t(i);
        if(counts[i]>0) {
            const auto amount=reinterpret_cast<int32_t(*)(int32_t,int32_t,int32_t,bool*)>(base+0x74f430)(counts[i],df::global::plotinfo->nobles.bookkeeper_precision,0,&row.estimated);
            row.countCaption.emplace();
            reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(amount,&*row.countCaption);
            if(row.estimated)row.countCaption->append(reinterpret_cast<const char*>(base+0x1614d50),1);
        }
        result.materials.push_back(std::move(row));
    }
    result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    if(!query.empty()) {
        if(query.size()>128)return std::nullopt;
        if(option.kind==0)context.material_filter=query;else context.plant_filter=query;
        {
            df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
            reinterpret_cast<void(*)(df::job_details_interfacest*)>(base+(option.kind==0?0x2230f0:0x2239e0))(&context);
        }
        if(types.size()!=indices.size() || types.size()>result.materials.size())return std::nullopt;
        // Preserve unfiltered identities: selection rechecks the full native list.
        std::map<std::pair<int16_t,int32_t>,size_t> identities;
        for(size_t i=0;i<result.materials.size();++i) {
            const auto& row=result.materials[i];
            if(!identities.emplace(std::make_pair(row.type,row.index),i).second)return std::nullopt;
        }
        std::vector<WorkOrderDetailMaterial> filtered;filtered.reserve(types.size());
        for(size_t i=0;i<types.size();++i) {
            const auto found=identities.find({types[i],indices[i]});
            if(found==identities.end())return std::nullopt;
            filtered.push_back(std::move(result.materials[found->second]));
        }
        result.materials=std::move(filtered);
    }
    return result;
}

struct WorkOrderDetailEditResult {
    WorkshopOrdersOutcome outcome=WorkshopOrdersOutcome::Rejected;
    std::optional<WorkOrderDetailsObservation> observation;
};
inline void rebuildWorkOrderDetailRequirements(df::manager_order& order) {
    using Fill=void (*)(df::job_reqst*,int16_t,int16_t,int16_t,int16_t,int32_t,const std::string*,uint32_t,uint32_t,int32_t,df::building*,int32_t,int32_t,int32_t);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<Fill>(base+0xd09ca0)(order.items,int16_t(order.job_type),int16_t(order.item_type),order.item_subtype,order.mat_type,order.mat_index,&order.reaction_name,order.material_category.whole,order.specflag.whole,order.specdata.hist_figure_id,nullptr,int32_t(order.art_spec.type),order.art_spec.id,order.art_spec.subid);
}
inline WorkOrderDetailEditResult setWorkOrderDetailMaterial(df::manager_order& order,uint64_t revision,int32_t option,uint64_t choicesRevision,int32_t choice,int32_t dyeTarget=-1) {
    WorkOrderDetailEditResult result;
    const auto before=nativeWorkOrderDetails(order,option,{},dyeTarget);
    if(!before)return result;
    if(!revision || revision!=before->revision || !choicesRevision || choicesRevision!=before->choicesRevision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(choice<0 || size_t(choice)>=before->materials.size())return result;
    const auto selected=before->options[size_t(option)];
    const auto material=before->materials[size_t(choice)];
    if(selected.kind==4 || selected.kind==5) {
        if(material.opensMenu || (selected.kind==5 && dyeTarget<0))return result;
        result.outcome=WorkshopOrdersOutcome::Unknown;
        if(selected.kind==4)order.specdata.hist_figure_id=material.index;
        else order.mat_index=material.index;
        order.art_spec.id=material.dyeFirst;order.art_spec.subid=material.dyeSecond;
        if(order.items)rebuildWorkOrderDetailRequirements(order);
        result.observation=nativeWorkOrderDetails(order);
        if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
        return result;
    }
    if(selected.kind==2) {
        result.outcome=WorkshopOrdersOutcome::Unknown;
        order.specdata.hist_figure_id=material.index; // Native union field at order+0x3c.
        if(order.items)rebuildWorkOrderDetailRequirements(order);
        result.observation=nativeWorkOrderDetails(order);
        if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
        return result;
    }
    if(selected.kind==3) {
        // Image requires a further user selection; do not borrow its native UI.
        if(material.index<=0 || material.index>4)return result;
        result.outcome=WorkshopOrdersOutcome::Unknown;
        order.specdata.improvement=df::improvement_type(material.index);
        order.art_spec.type=df::job_art_specifier_type(-1);order.art_spec.id=-1;order.art_spec.subid=-1;
        if(order.items)rebuildWorkOrderDetailRequirements(order);
        result.observation=nativeWorkOrderDetails(order);
        if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
        return result;
    }
    const size_t index=selected.kind==6?0:size_t(selected.index);
    if(!order.items || index>=order.items->elements.size() || !order.items->elements[index])return result;
    auto& item=*order.items->elements[index];
    result.outcome=WorkshopOrdersOutcome::Unknown;
    if(!item.job_details_flags.bits.have_set_job_details) {
        item.job_details_flags.bits.have_set_job_details=true;
        item.job_details_mat_type=item.mat_type;item.job_details_mat_index=item.mat_index;
        if(selected.kind==0)item.job_details_item_flags2=item.flags2;
    }
    item.mat_type=material.type;item.mat_index=material.index;
    if(index==0) {
        order.mat_type=material.type;order.mat_index=material.index;
        rebuildWorkOrderDetailRequirements(order);
    }
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
}
