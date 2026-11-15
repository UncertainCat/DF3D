#pragma once
#include "depot_goods_native.h"
#include "knowledge_detail_native.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"
#include <array>

namespace df3d_production {
// Semantic world lookup used by native38ab20/38bc44, not picker state. It
// returns0 without a resolvable broker, otherwise effective Appraisal+1.
inline bool depotValuationReady() {
    if(!depotNativeReady() || !df::global::plotinfo || !df::global::world)return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0xe64560,0x18d,UINT64_C(0x3932842e403f9b33)},
            {0x77f920,0x2b0,UINT64_C(0x9ad2d1d0985ca611)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
inline std::optional<int32_t> depotAppraisal() {
    if(!depotValuationReady())return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto value=reinterpret_cast<int32_t(*)()>(base+0xe64560)();
    if(value<0)return {};return value;
}
inline std::optional<std::string> depotValueCaption(int32_t value,int32_t appraisal) {
    if(!depotValuationReady() || appraisal<0)return {};
    std::string result;if(!appraisal)return result;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    reinterpret_cast<void(*)(std::string*,int32_t,int32_t)>(base+0x77f920)(&result,value,appraisal-1);
    return result;
}
// The category initializer and filter contain inline projection logic around
// native description/matching leaves. Never call their menu/geometry tails.
inline std::optional<std::vector<int16_t>> depotCategories(const DepotGoods& goods,
    std::string query,bool excludeProhibited=false) {
    if(!depotNativeReady() || !df::global::world || query.size()>512 ||
       goods.rows.size()>1048576 || goods.groups.size()>1048576)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x36c9b8,0x3c1,UINT64_C(0xa7435a45e62032db)},
            {0x37ba00,0x665,UINT64_C(0xce207173b65aeff8)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    const auto describe=reinterpret_cast<Describe>(base+0xa82c10);
    const auto normalize=reinterpret_cast<void(*)(std::string*)>(base+0x52cee0);
    normalize(&query);
    const auto matches=[&](std::string caption){normalize(&caption);
        return reinterpret_cast<size_t(*)(const char*,size_t,size_t,const char*,size_t)>(base+0xe1990)
            (caption.data(),caption.size(),0,query.data(),query.size())!=size_t(-1);};
    const auto itemMatches=[&](df::item* item){std::string caption;
        reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(item,&caption,false,-1);
        return matches(std::move(caption));};
    std::array<bool,93> present{},eligible{},matched{};
    for(const auto& group:goods.groups){if(group.type<0 || group.type>=93)return {};present[group.type]=true;}
    for(const auto& row:goods.rows){
        if(excludeProhibited && row.prohibited)continue;
        auto* item=df::item::find(row.id);if(!item)return {};
        const auto type=int(item->getType());if(type<0 || type>=93)return {};
        eligible[type]=true;
        if(query.empty())continue;
        if(itemMatches(item))matched[type]=true;
        if(item->flags.bits.container){
            if(item->general_refs.size()>1048576)return {};
            for(auto* ref:item->general_refs){if(!ref)return {};
                if(ref->getType()==df::general_ref_type::CONTAINS_ITEM)
                    if(auto* child=ref->getItem())if(itemMatches(child))matched[type]=true;
            }
        }
    }
    if(!query.empty())for(const auto& group:goods.groups)if(eligible[group.type]){
        std::string caption;describe(&caption,group.type,group.subtype,group.subcat1,group.subcat2,group.amount,0,false,nullptr,-1,-1,true,0,0);
        if(matches(std::move(caption)))matched[group.type]=true;
    }
    std::array<std::string,93> captions;
    std::vector<int16_t> result;
    // Native first deduplicates types numerically, then inserts before equal names.
    for(int16_t type=0;type<93;++type)if(present[type]){
        describe(&captions[type],type,-1,-1,-1,-1,0,false,nullptr,-1,-1,true,0,0);
        normalize(&captions[type]);
        auto at=result.begin();while(at!=result.end() && captions[*at].compare(captions[type])<0)++at;
        result.insert(at,type);
    }
    result.erase(std::remove_if(result.begin(),result.end(),[&](int16_t type){return !(query.empty()?eligible[type]:matched[type]);}),result.end());
    return result;
}
struct DepotSelectedGroup {DepotGoodsGroup group;bool matches=false;uint32_t flags=0;std::string caption;std::vector<int32_t> ids;};
struct DepotGoodsChange {int32_t id=-1;bool desired=false;};
struct DepotSelection {std::vector<int32_t> ids;std::vector<int8_t> tags;std::vector<DepotSelectedGroup> groups;std::vector<std::string> itemCaptions;int32_t rowCells=0;};
// Local checkbox intent only. Eligibility/membership stay native; this changes
// tags in owned records, never jobs or game items. Native input31e449 uses1-tag.
inline std::optional<std::vector<int8_t>> depotDraftTags(const DepotGoods& goods,const std::vector<DepotGoodsChange>& changes) {
    if(goods.rows.size()>1048576 || changes.size()>1048576)return {};
    std::vector<std::pair<int32_t,size_t>> index;index.reserve(goods.rows.size());
    std::vector<int8_t> tags;tags.reserve(goods.rows.size());
    for(size_t i=0;i<goods.rows.size();++i){const auto& row=goods.rows[i];
        if(row.id<0 || (row.tag!=0 && row.tag!=2 && row.tag!=3))return {};
        if(!changes.empty())index.emplace_back(row.id,i);tags.push_back(row.tag);}
    if(changes.empty())return tags;
    std::sort(index.begin(),index.end());
    for(size_t i=1;i<index.size();++i)if(index[i-1].first==index[i].first)return {};
    std::vector<bool> seen(goods.rows.size(),false);
    for(const auto& change:changes){
        auto at=std::lower_bound(index.begin(),index.end(),std::pair<int32_t,size_t>{change.id,0});
        if(at==index.end() || at->first!=change.id || seen[at->second])return {};
        seen[at->second]=true;auto& tag=tags[at->second];
        if((tag>0)!=change.desired)tag=int8_t(1-tag);
    }
    return tags;
}
// Native strings are CP437. Preserve their bytes until the transport boundary.
inline std::optional<std::string> depotGroupCaption(int16_t type,int16_t subtype=-1,
    int16_t subcat1=-1,int16_t subcat2=-1,int32_t amount=-1) {
    if(!depotNativeReady() || !df::global::world || type<0 || type>=93)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x38a97d,0x50,UINT64_C(0xfb978fc53ec8137c)},
            {0x38b3c7,0x58,UINT64_C(0x22bfb81c86693c1f)},
            {0x38b857,0x15,UINT64_C(0x7d149f35ba3fb345)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string caption;
    using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    reinterpret_cast<Describe>(base+0xa82c10)(&caption,type,subtype,subcat1,subcat2,amount,0,false,nullptr,-1,-1,true,0,0);
    reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&caption);
    return caption;
}
// Native38be7b..38bebc displays direct resolved references in reference order.
// Count semantics at38c24b..38c29c are gated by the semantic container flag.
inline std::optional<std::vector<int32_t>> depotContainerIds(df::item* item) {
    if(!item || item->general_refs.size()>1048576)return {};
    std::vector<int32_t> ids;
    if(!item->flags.bits.container)return ids;
    for(auto* ref:item->general_refs){if(!ref)return {};
        if(ref->getType()==df::general_ref_type::CONTAINS_ITEM)
            if(auto* child=ref->getItem()){if(child->id<0)return {};ids.push_back(child->id);}
    }
    return ids;
}
struct DepotContainedItem {
    int32_t id=-1,type=-1,containedCount=0,value=0;bool prohibited=false;
    std::string caption,valueCaption;
};
struct DepotContainerPage {int32_t total=0;std::vector<DepotContainedItem> items;};
// Safe-point, pointer-free projection. The caller validates parent membership
// in the current depot goods source. No child is a separate hauling intent.
inline std::optional<DepotContainerPage> depotContainerPage(df::item* parent,int32_t offset,int32_t limit,int32_t appraisal) {
    if(!parent || offset<0 || limit<1 || limit>64 || appraisal<0 || !depotGoodsValuesReady() ||
        !df::global::world || df::global::world->mandates.all.size()>1048576 || !depotGroupCaption(int16_t(parent->getType())))return {};
    const auto ids=depotContainerIds(parent);if(!ids || size_t(offset)>ids->size())return {};
    DepotContainerPage result;result.total=int32_t(ids->size());
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    for(size_t i=size_t(offset);i<std::min(ids->size(),size_t(offset)+size_t(limit));++i){
        auto* child=df::item::find((*ids)[i]);if(!child)return {};
        const auto nested=depotContainerIds(child);if(!nested)return {};
        DepotContainedItem row;row.id=child->id;row.type=int32_t(child->getType());row.containedCount=int32_t(nested->size());
        reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(child,&row.caption,false,-1);
        row.value=reinterpret_cast<int32_t(*)(df::item*,void*,void*,bool,bool)>(base+0xc66020)(child,nullptr,nullptr,false,false);
        const auto caption=depotValueCaption(row.value,appraisal);if(!caption)return {};row.valueCaption=*caption;
        for(auto* mandate:df::global::world->mandates.all)if(mandate && int(mandate->mode)==0 &&
            reinterpret_cast<bool(*)(df::mandate*,df::item*)>(base+0xe5d5b0)(mandate,child)){row.prohibited=true;break;}
        result.items.push_back(std::move(row));
    }
    return result;
}
// Native37a0a0 selects/sorts a category,37cd50 searches owned group/item names,
//37d9c0 aggregates selection flags. None reads the global picker or window size.
// Do not substitute37ba00: its category-list scroll tail reads native geometry.
inline std::optional<DepotSelection> depotSelection(const DepotGoods& goods,int16_t type,
    std::string query,bool sortByDistance=true,bool pendingOnTop=true,bool excludeProhibited=false,
    const std::vector<DepotGoodsChange>& draft={},const std::vector<DepotGoodsChange>& sortDraft={}) {
    if(!depotNativeReady() || !df::global::world || type<0 || type>=93 || query.size()>512 ||
       goods.rows.size()>1048576 || goods.groups.size()>1048576)return {};
    const auto tags=depotDraftTags(goods,draft),sortTags=depotDraftTags(goods,sortDraft);
    if(!tags || !sortTags)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x37a060,0x40,UINT64_C(0x1f410ab43494a2fd)},
            {0x37a0a0,0x348,UINT64_C(0x69e51b5a2ce37ce6)},
            {0x37cd50,0x5f9,UINT64_C(0x16933f93fc2b62f5)},
            {0x37aeb0,0x1d4,UINT64_C(0x28424ba77803a9c7)},
            {0x37d9c0,0x200,UINT64_C(0x196754683223bd32)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    std::vector<df::tradegoodslistst> records(goods.rows.size());
    df::assign_trade_interfacest owned;owned.current_type=df::item_type(type);owned.item_filter=std::move(query);
    owned.sort_by_distance=sortByDistance;owned.pending_on_top=pendingOnTop;owned.exclude_prohib=excludeProhibited;
    static_assert(offsetof(df::assign_trade_interfacest,current_type_tgi)==0x160);
    static_assert(offsetof(df::assign_trade_interfacest,current_type_a_flag)==0x218);
    for(size_t i=0;i<records.size();++i){const auto& row=goods.rows[i];auto& record=records[i];
        record.it=df::item::find(row.id);if(!record.it)return {};
        record.dist=row.distance;record.tag=(*sortTags)[i];record.value=row.value;record.prohibited=row.prohibited;
        owned.master_i_list.tgi.push_back(&record);
    }
    for(const auto& group:goods.groups){
        owned.master_a_list.type.push_back(group.type);owned.master_a_list.subtype.push_back(group.subtype);
        owned.master_a_list.subcat1.push_back(group.subcat1);owned.master_a_list.subcat2.push_back(group.subcat2);
        owned.master_a_list.amount.push_back(group.amount);owned.master_a_list.expanded.push_back(group.expanded);
    }
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<void (*)(df::assign_trade_interfacest*)>(base+0x37a0a0)(&owned);
    // Checkbox clicks keep the current native order. Navigation supplies the
    // then-current draft as sortDraft; subsequent clicks only change draft.
    //37a0a0 sorts using tag*100000000 before37cd50, so applying the latest tags
    // before every sort would incorrectly move a newly checked row.
    for(size_t i=0;i<records.size();++i)records[i].tag=(*tags)[i];
    reinterpret_cast<void (*)(df::assign_trade_interfacest*)>(base+0x37d9c0)(&owned);
    DepotSelection result;
    result.rowCells=owned.i_height;
    // Validate the renderer's formatting leaves before obtaining item captions.
    if(!depotGroupCaption(type))return {};
    for(auto* row:owned.current_type_tgi){result.ids.push_back(row->it->id);result.tags.push_back(row->tag);
        std::string caption;
        reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(row->it,&caption,false,-1);
        result.itemCaptions.push_back(std::move(caption));
    }
    const auto count=owned.current_type_a_subtype.size();
    if(owned.current_type_a_subcat1.size()!=count || owned.current_type_a_subcat2.size()!=count ||
       owned.current_type_a_amount.size()!=count || owned.current_type_a_expanded.size()!=count ||
       owned.current_type_a_on.size()!=count || owned.current_type_a_flag.size()!=count)return {};
    for(size_t i=0;i<count;++i){auto caption=depotGroupCaption(type,int16_t(owned.current_type_a_subtype[i]),
        int16_t(owned.current_type_a_subcat1[i]),int16_t(owned.current_type_a_subcat2[i]),owned.current_type_a_amount[i]);
        if(!caption)return {};
        result.groups.push_back({{type,int16_t(owned.current_type_a_subtype[i]),
        int16_t(owned.current_type_a_subcat1[i]),int16_t(owned.current_type_a_subcat2[i]),
        owned.current_type_a_amount[i],owned.current_type_a_expanded[i]},owned.current_type_a_on[i],owned.current_type_a_flag[i].whole,std::move(*caption)});
        // Native row-height leaf37af95..37afcb and renderer38b569..38b5a5
        // use these exact virtual properties. Do not group by captions or
        // stack amounts: a group count can differ from its number of rows.
        auto& group=result.groups.back();
        for(auto* row:owned.current_type_tgi)if(row->it->getSubtype()==owned.current_type_a_subtype[i] &&
            row->it->getMaterial()==owned.current_type_a_subcat1[i] &&
            row->it->getMaterialIndex()==owned.current_type_a_subcat2[i])group.ids.push_back(row->it->id);
    }
    return result;
}
}
