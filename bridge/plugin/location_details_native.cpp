#include "location_details_native.h"
#include "location_dance_native.h"
#include "location_value_native.h"
#include "modules/Maps.h"
#include "modules/Items.h"
#include "df/world.h"
#include "df/language_word_table.h"
#include "df/language_name.h"
#include "df/language_translation.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "modules/Translation.h"
#include "modules/Units.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/histfig_entity_link.h"
#include "df/historical_figure_info.h"
#include "df/metaphysical_profilest.h"
#include "df/language_word.h"
#include "df/entity_position_assignment.h"
#include "df/entity_site_link.h"
#include "df/entity_site_ab_profilest.h"
#include "df/entity_position_responsibility.h"
#include "df/unit.h"
#include "df/job_skill.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/building_type.h"
#include "df/civzone_type.h"
#include "MiscUtils.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/plotinfost.h"
#include "df/world_site.h"
#include "df/abstract_building_templest.h"
#include "df/entity_position.h"
#include "df/agreement.h"
#include "df/agreement_party.h"
#include "df/agreement_details.h"
#include "df/agreement_details_data_location.h"
#include "df/agreement_details_type.h"
#include "df/religious_practice_type.h"
#include "df/historical_entity_type.h"
#include <algorithm>
#include <numeric>

namespace df3d_area {
static std::unique_ptr<df::entity_position> prepareNativeLocationRecognitionPositionImpl(const LocationRecognitionFacts& observed) {
  const auto* facts=&observed;
  const auto state=locationRecognitionState(*facts);
  if(state!=LocationRecognitionState::RecognizePriesthood && state!=LocationRecognitionState::RecognizeHighPriest)return {};
  const bool high=state==LocationRecognitionState::RecognizeHighPriest;
  auto* religion=df::historical_entity::find(facts->religionId);
  if(!religion || !religion->entity_raw || religion->positions.next_position_id<0 ||
      religion->positions.next_position_id==INT32_MAX)return {};
  const df::entity_position* priest=nullptr;
  for(const auto* position:religion->positions.own) {
    if(!position)return {};
    if(position->code==(high?"HIGH_PRIEST":"PRIEST"))return {};
    if(position->code=="PRIEST")priest=position;
  }
  if(high && !priest)return {};
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0x9909a0,0x326)==UINT64_C(0xe38c7959ebcf3e23) &&
      hash(0x71f30,0x53)==UINT64_C(0x5eb4fcfbdedb7745) &&
      hash(0x76d4e0,0x5ea4)==UINT64_C(0x9fd8c4a763ca6e3f);
  }();
  if(!compatible)return {};
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  const auto random=reinterpret_cast<int32_t (*)(int32_t)>(base+0x71f30);
  const auto colors=reinterpret_cast<void (*)(int16_t,std::vector<int16_t>*,std::vector<int16_t>*,std::vector<int16_t>*)>(base+0x76d4e0);
  const auto generate=reinterpret_cast<void (*)(df::historical_entity*,df::language_name*,int16_t,df::historical_entity*,int32_t)>(base+0x9909a0);
  auto position=std::make_unique<df::entity_position>();
  position->id=religion->positions.next_position_id;
  position->code=high?"HIGH_PRIEST":"PRIEST";
  // Native32e861..32eb29 chooses a deity, accumulates its sphere colors in
  // reverse order through76d4e0, then chooses a parallel color triple.
  position->color={7,0,1};
  if(high)position->color=priest->color;
  else {
    df::historical_figure* deity=nullptr;
    const auto& deities=religion->relations.deities;
    if(!deities.empty())deity=df::historical_figure::find(deities[random(int32_t(deities.size()))]);
    if(deity) {
      std::vector<int16_t> foreground,background,bright;
      if(deity->info && deity->info->metaphysical) {
        const auto& spheres=deity->info->metaphysical->spheres;
        for(auto it=spheres.rbegin();it!=spheres.rend();++it)colors(int16_t(*it),&foreground,&background,&bright);
      }
      if(foreground.empty()){foreground.push_back(7);background.push_back(0);bright.push_back(1);}
      if(foreground.size()!=background.size() || foreground.size()!=bright.size())return {};
      const auto index=random(int32_t(foreground.size()));
      position->color={foreground[index],background[index],bright[index]};
    }
  }
  df::language_name name;
  generate(religion,&name,0x24,religion,-1);
  // Native32df9d..32e28a /32ed28..32efb5 use the generated THE word,
  // with native prefixes/fallbacks at1629b28..1629bc0 and15e9088.
  if(name.words[5]!=-1) {
    const auto* word=df::language_word::find(name.words[5]);if(!word)return {};
    const char* prefixesHigh[]={"high ","first ","exalted "};
    const char* prefixesPriest[]={"holy ","sacred "};
    const auto choice=random(high?3:2);
    const std::string prefix=high?prefixesHigh[choice]:prefixesPriest[choice];
    position->name[0]=prefix+word->forms[word->flags.bits.the_noun_sing?0:1];
    position->name[1]=prefix+word->forms[1];
  } else position->name=high?std::array<std::string,2>{"high priest","high priests"}:
                            std::array<std::string,2>{"priest","priests"};
  // Template setup is inline in native recognition; naming/color selection
  // above delegates to semantic routines with independently owned scratch.
  for(int flag:{1,2,7,10,11,13,14,17,21,22,25,26,27})
    position->flags.set(static_cast<df::entity_position_flags>(flag),true);
  position->responsibilities[15]=true;
  position->number=-1;position->precedence=high?50:200;
  if(high) {
    for(int flag:{0,8,9,12,15,16,28,29})position->flags.set(static_cast<df::entity_position_flags>(flag),true);
    for(int responsibility:{0,2,10})position->responsibilities[responsibility]=true;
    position->mandate_max=2;position->demand_max=3;
  }
  return position;
}
namespace {
// Shared native first-subject/applicant test used by rendering and recognition.
// Missing IDs/empty agreements are skipped; malformed owned pointers reject.
std::optional<bool> recognitionAgreementMatches(const df::agreement* agreement,int32_t religionId) {
  if(!agreement || agreement->details.empty())return false;
  const auto* subject=agreement->details.front();if(!subject)return std::nullopt;
  if(subject->type!=df::agreement_details_type::Location)return false;
  const auto* data=subject->data.Location;if(!data)return std::nullopt;
  const auto* applicant=binsearch_in_vector(agreement->parties,data->applicant);
  return applicant && std::binary_search(applicant->entity_ids.begin(),applicant->entity_ids.end(),religionId);
}
}
static std::optional<std::vector<int32_t>> concludeNativeLocationRecognitionAgreementsImpl(const LocationRecognitionFacts& observed) {
  const auto* facts=&observed;
  const auto state=locationRecognitionState(*facts);
  if(state!=LocationRecognitionState::RecognizePriesthood && state!=LocationRecognitionState::RecognizeHighPriest)
    return std::nullopt;
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0xba150,0x44)==UINT64_C(0xc8bc8a24a03e77ba) &&
      hash(0xbabe0,0xab)==UINT64_C(0x1bd318997a061458);
  }();
  if(!compatible)return std::nullopt;
  auto* plot=df::global::plotinfo;
  const std::array<std::vector<int32_t>*,2> lists{&plot->petitions,&plot->continuing_agreement_id};
  std::array<df::agreement*,2> selected{};
  std::vector<int32_t> ids;ids.reserve(2);
  // Native32d371..32d6b8 concludes only the first matching agreement per list.
  // Resolve both before publication; do not remove/delete the world agreements.
  for(size_t i=0;i<lists.size();++i)for(auto id:*lists[i]) {
    auto* agreement=df::agreement::find(id);
    const auto matches=recognitionAgreementMatches(agreement,facts->religionId);
    if(!matches)return std::nullopt;
    if(*matches){selected[i]=agreement;ids.push_back(id);break;}
  }
  const auto remove=reinterpret_cast<void (*)(int32_t,std::vector<int32_t>*)>(
    reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0xba150);
  for(size_t i=0;i<lists.size();++i)if(auto* agreement=selected[i]) {
    agreement->flags.bits.convicted_accepted=true;
    remove(agreement->id,lists[i]);
  }
  return ids;
}
static std::optional<std::vector<df::unit*>> collectNativeLocationRecognitionUnits(const LocationRecognitionFacts& observed) {
  const auto* facts=&observed;
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0x138ed20,0xff)==UINT64_C(0x430951f9f3e403c2) &&
      hash(0x13b3090,0x19)==UINT64_C(0x901cd2f6d41c1657) &&
      hash(0xb973c0,0x79)==UINT64_C(0xe30c0166fa2e4d2a) &&
      hash(0x72510,0x24)==UINT64_C(0xb716fcb94e763c8b) &&
      hash(0x13eff80,0xa0)==UINT64_C(0xb66acd69c2fb79b5) &&
      hash(0xe198e0,0xafb6)==UINT64_C(0x69508c275f046381);
  }();
  if(!compatible)return std::nullopt;
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  const auto eligible=reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20);
  const auto figure=reinterpret_cast<df::historical_figure* (*)(df::unit*)>(base+0x13b3090);
  const auto strength=reinterpret_cast<int16_t (*)(df::historical_figure*,int16_t,int32_t)>(base+0xb973c0);
  std::vector<df::unit*> units;
  for(auto* unit:df::global::world->units.active) {
    if(!unit || (unit->flags1.bits.inactive && !unit->flags1.bits.incoming) || !eligible(unit))continue;
    auto* hf=figure(unit);
    if(hf && strength(hf,0,facts->religionId)!=0)units.push_back(unit);
  }
  return units;
}
static std::optional<std::vector<int32_t>> applyNativeLocationRecognitionThoughtsImpl(const LocationRecognitionFacts& observed) {
  const auto* facts=&observed;
  const auto state=locationRecognitionState(*facts);
  if(state!=LocationRecognitionState::RecognizePriesthood && state!=LocationRecognitionState::RecognizeHighPriest)return std::nullopt;
  const auto units=collectNativeLocationRecognitionUnits(observed);if(!units)return std::nullopt;
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  // Native72510 initializes this 0x30-byte semantic thought input. Recognition
  // writes circumstance253, religion ID and strength100 at offsets0,4,12.
  // It contains no retained pointers or menu state; zero unused padding too.
  struct alignas(8) Thought { std::array<int32_t,12> fields{}; };
  static_assert(sizeof(Thought)==0x30);
  const auto initialize=reinterpret_cast<Thought* (*)(Thought*)>(base+0x72510);
  const auto apply=reinterpret_cast<void (*)(df::unit*,Thought*)>(base+0x13eff80);
  std::vector<int32_t> ids;ids.reserve(units->size());
  for(auto* unit:*units)ids.push_back(unit->id);
  for(auto* unit:*units) {
    Thought thought;initialize(&thought);
    thought.fields[0]=253;thought.fields[1]=facts->religionId;thought.fields[3]=100;
    apply(unit,&thought);
  }
  return ids;
}
std::unique_ptr<df::entity_position> prepareNativeLocationRecognitionPosition(int32_t siteId,int32_t locationId) {
  const auto facts=observeNativeLocationRecognition(siteId,locationId);
  if(!facts)return {};
  return prepareNativeLocationRecognitionPositionImpl(*facts);
}
std::optional<std::vector<int32_t>> concludeNativeLocationRecognitionAgreements(int32_t siteId,int32_t locationId) {
  const auto facts=observeNativeLocationRecognition(siteId,locationId);
  if(!facts)return std::nullopt;
  return concludeNativeLocationRecognitionAgreementsImpl(*facts);
}
std::optional<std::vector<int32_t>> applyNativeLocationRecognitionThoughts(int32_t siteId,int32_t locationId) {
  const auto facts=observeNativeLocationRecognition(siteId,locationId);
  if(!facts)return std::nullopt;
  return applyNativeLocationRecognitionThoughtsImpl(*facts);
}
LocationRecognitionOutcome recognizeNativeLocation(int32_t siteId,int32_t locationId,uint64_t expectedRevision) {
  if(!expectedRevision || expectedRevision>uint64_t(INT64_MAX))return LocationRecognitionOutcome::Rejected;
  const auto receipt=observeNativeLocationRecognitionReceipt(siteId,locationId);
  if(!receipt)return LocationRecognitionOutcome::Rejected;
  if(receipt->revision!=expectedRevision)return LocationRecognitionOutcome::Stale;
  const auto* facts=&receipt->facts;
  const auto state=locationRecognitionState(*facts);
  if(state!=LocationRecognitionState::RecognizePriesthood && state!=LocationRecognitionState::RecognizeHighPriest)
    return LocationRecognitionOutcome::Rejected;
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0xb96300,0xce)==UINT64_C(0x718bdbff364f1818) &&
      hash(0xb97610,0x8d8)==UINT64_C(0xe3c18f2100d8cb4a) &&
      hash(0xe1450,0x101)==UINT64_C(0xe9db8d770dfaf694) &&
      hash(0xc30000,0x1f0)==UINT64_C(0x4e448b8aaad2fd47) &&
      hash(0x9364d0,0x1da)==UINT64_C(0x65231f4d74787177) &&
      hash(0x30ffb0,0x19a)==UINT64_C(0x0e9cc013df4012c2) &&
      hash(0xbbe40,0xad)==UINT64_C(0x062a266340f9bf38);
  }();
  if(!compatible)return LocationRecognitionOutcome::Rejected;
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  auto* religion=df::historical_entity::find(facts->religionId);
  if(!religion || !religion->entity_raw || religion->positions.next_assignment_id<0 ||
      religion->positions.next_assignment_id==INT32_MAX)return LocationRecognitionOutcome::Rejected;
  auto& positions=religion->positions;
  const bool high=state==LocationRecognitionState::RecognizeHighPriest;
  df::entity_position* target=nullptr;
  df::entity_position_assignment* previous=nullptr;
  for(auto* position:positions.own) {
    if(!position)return LocationRecognitionOutcome::Rejected;
    if(position->code==(high?"HIGH_PRIEST":"PRIEST"))target=position;
    if(high && position->code=="PRIEST")for(auto* assignment:positions.assignments) {
      if(!assignment)return LocationRecognitionOutcome::Rejected;
      if(assignment->position_id==position->id && assignment->st_id==siteId)previous=assignment;
    }
  }
  for(auto* assignment:positions.assignments)
    if(!assignment || assignment->id>=positions.next_assignment_id)return LocationRecognitionOutcome::Rejected;
  if(high && !previous)return LocationRecognitionOutcome::Rejected;
  df::historical_figure* holder=previous && previous->histfig>=0?df::historical_figure::find(previous->histfig):nullptr;
  if(previous && previous->histfig>=0 && !holder)return LocationRecognitionOutcome::Rejected;
  if(!target && (positions.next_position_id<0 || positions.next_position_id==INT32_MAX))return LocationRecognitionOutcome::Rejected;
  if(!target)for(auto* position:positions.own)if(position->id>=positions.next_position_id)return LocationRecognitionOutcome::Rejected;
  // Native HF helpers operate on this semantic global container, never UI state.
  static_assert(offsetof(df::world_history,hf_civ_actors)==0x360);
  if(reinterpret_cast<uintptr_t>(&df::global::world->history)!=base+0x24f9cb8)return LocationRecognitionOutcome::Rejected;
  bool begun=false;
  try {
    auto assignment=std::make_unique<df::entity_position_assignment>();
    positions.own.reserve(positions.own.size()+(target?0:1));
    positions.assignments.reserve(positions.assignments.size()+1);
    // Preserve native effect/RNG order with the original eligibility snapshot.
    // Removing the only continuing agreement must not revoke this same intent.
    begun=true;
    if(!concludeNativeLocationRecognitionAgreementsImpl(*facts) ||
       !applyNativeLocationRecognitionThoughtsImpl(*facts))return LocationRecognitionOutcome::Unknown;
    if(!target) {
      auto prepared=prepareNativeLocationRecognitionPositionImpl(*facts);
      if(!prepared)return LocationRecognitionOutcome::Unknown;
      target=prepared.get();++positions.next_position_id;
      positions.own.push_back(prepared.release());
    }
    if(high) {
      target->flags.set(df::entity_position_flags::HAS_RECEIVED_POSITIONS,true);
      target->flags.set(df::entity_position_flags::ACTIVE,true);
    }
    assignment->id=positions.next_assignment_id++;
    assignment->position_id=target->id;assignment->st_id=siteId;
    assignment->flags.set(df::entity_position_profile_flags::active,true);
    auto* added=assignment.get();positions.assignments.push_back(assignment.release());
    if(holder) {
      const auto remove=reinterpret_cast<void (*)(df::historical_figure*,int32_t,int32_t,bool,bool)>(base+0xb96300);
      const auto assign=reinterpret_cast<void (*)(df::historical_figure*,int32_t,int32_t,int16_t,bool,int32_t,int32_t)>(base+0xb97610);
      remove(holder,previous->id,religion->id,false,false);
      assign(holder,added->id,religion->id,100,true,-1,-1);
      const auto track=reinterpret_cast<void (*)(df::historical_figure*,std::vector<df::historical_figure*>*)>(base+0xe1450);
      track(holder,&df::global::world->history.hf_civ_actors);
      const auto effects=reinterpret_cast<void (*)(void*,df::historical_entity*,df::entity_position*,df::historical_figure*)>(base+0xc30000);
      effects(&df::global::world->history,religion,target,holder);
    }
    const auto siteLink=reinterpret_cast<df::entity_site_link* (*)(df::historical_entity*,int32_t,bool)>(base+0x9364d0);
    auto* link=siteLink(religion,siteId,true);if(!link)return LocationRecognitionOutcome::Unknown;
    link->type=df::entity_site_link_type::Local_Activity;link->flags.bits.base_of_operation=true;
    if(high) {
      const auto profile=reinterpret_cast<df::entity_site_ab_profilest* (*)(df::entity_site_link*,int32_t,bool)>(base+0x30ffb0);
      auto* entry=profile(link,locationId,true);if(!entry)return LocationRecognitionOutcome::Unknown;
      entry->purpose_flag.bits.place_of_worship=true;
    } else link->flags.bits.residence=true;
    // Native3ad8e0 mixes row construction with semantic cache resolution. Use
    // only its bbe40 position lookup; never supply a native Details UI object.
    const auto resolve=reinterpret_cast<df::entity_position* (*)(df::historical_entity*,df::entity_position_assignment*)>(base+0xbbe40);
    for(auto* current:positions.assignments)if(current->st_id==siteId)resolve(religion,current);
    if(!prepareNativeLocationStaff(siteId,locationId))return LocationRecognitionOutcome::Unknown;
    return LocationRecognitionOutcome::Applied;
  } catch(const std::exception&) {
    return begun?LocationRecognitionOutcome::Unknown:LocationRecognitionOutcome::Rejected;
  }
}
std::optional<LocationRecognitionFacts> observeNativeLocationRecognition(int32_t siteId,int32_t locationId) {
  if(siteId<0 || locationId<0 || !df::global::world || !df::global::plotinfo ||
     !DFHack::Maps::IsValid() || siteId!=df::global::plotinfo->site_id)return std::nullopt;
  auto* site=df::world_site::find(siteId);if(!site)return std::nullopt;
  df::abstract_building* location=nullptr;
  for(auto* candidate:site->buildings)if(candidate && candidate->id==locationId){location=candidate;break;}
  if(!location || location->getType()!=df::abstract_building_type::TEMPLE)return std::nullopt;
  if(location->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) ||
     location->flags.is_set(df::abstract_building_flags::WG_RUINED) ||
     location->flags.is_set(df::abstract_building_flags::PWG_RUINED))return std::nullopt;
  auto* temple=static_cast<df::abstract_building_templest*>(location);
  if(temple->deity_type!=df::religious_practice_type::RELIGION_ENID)return std::nullopt;
  auto* religion=df::historical_entity::find(temple->deity_data.Religion);
  const auto* contents=temple->getContents();
  if(!religion || religion->type!=df::historical_entity_type::Religion || !contents)return std::nullopt;
  // Native2a6e00 is the semantic worshipper counter used by recognition input.
  // Its first ABI argument is unused. It reads active units/HF relationships,
  // including native eligibility helpers, not location_details/gps scratch.
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    uint64_t hash=UINT64_C(14695981039346656037);
    for(size_t i=0;i<0xba;++i){hash^=base[0x2a6e00+i];hash*=UINT64_C(1099511628211);}
    return hash==UINT64_C(0x7ae7f14c285d7534);
  }();
  if(!compatible)return std::nullopt;
  LocationRecognitionFacts result;
  result.siteId=siteId;result.locationId=locationId;result.religionId=religion->id;result.tier=contents->location_tier;
  // Native3b6c18 scans position codes and current-site assignments, including
  // vacant slots. Holder and abstract-building assignment do not filter rank.
  for(const auto* position:religion->positions.own) {
    if(!position)return std::nullopt;
    const int rank=position->code=="HIGH_PRIEST"?2:position->code=="PRIEST"?1:0;
    if(rank<=result.rank)continue;
    for(const auto* assignment:religion->positions.assignments) {
      if(!assignment)return std::nullopt;
      if(assignment->position_id==position->id && assignment->st_id==siteId){result.rank=rank;break;}
    }
  }
  const auto& difficulty=df::global::plotinfo->main.custom_difficulty;
  result.priestThreshold=difficulty.priesthood_unit_count;result.highPriestThreshold=difficulty.high_priesthood_unit_count;
  using Count=int32_t (*)(void*,int32_t,int32_t);
  const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
  result.worshippers=reinterpret_cast<Count>(const_cast<uint8_t*>(base)+0x2a6e00)(nullptr,1,religion->id);
  // Native3b6e76 checks the first subject and its applicant party. Preserve
  // continuing-agreement order; do not invent extra site/tier filters.
  for(auto id:df::global::plotinfo->continuing_agreement_id) {
    const auto matches=recognitionAgreementMatches(df::agreement::find(id),religion->id);
    if(!matches)return std::nullopt;
    if(*matches)result.continuingAgreements.push_back(id);
  }
  return result;
}
std::optional<LocationRecognitionReceipt> observeNativeLocationRecognitionReceipt(int32_t siteId,int32_t locationId) {
  auto facts=observeNativeLocationRecognition(siteId,locationId);if(!facts)return std::nullopt;
  auto* religion=df::historical_entity::find(facts->religionId);if(!religion)return std::nullopt;
  uint64_t hash=UINT64_C(14695981039346656037);
  const auto number=[&](uint64_t value) {
    for(unsigned i=0;i<8;++i){hash^=value&255;hash*=UINT64_C(1099511628211);value>>=8;}
  };
  const auto text=[&](const std::string& value) {
    number(value.size());for(unsigned char ch:value){hash^=ch;hash*=UINT64_C(1099511628211);}
  };
  const auto numbers=[&](const auto& values){number(values.size());for(auto value:values)number(uint64_t(value));};
  number(siteId);number(locationId);number(facts->religionId);number(facts->tier);number(facts->rank);
  number(facts->worshippers);number(facts->priestThreshold);number(facts->highPriestThreshold);
  number(religion->positions.next_position_id);number(religion->positions.next_assignment_id);
  // Hash semantic fields, never padding, addresses or lookup-cache indices.
  number(religion->positions.own.size());
  for(const auto* p:religion->positions.own) {
    if(!p)return std::nullopt;
    number(p->id);text(p->code);
    for(int i=0;i<=int(df::enum_traits<df::entity_position_flags>::last_item_value);++i)
      number(p->flags.is_set(static_cast<df::entity_position_flags>(i)));
    for(const auto* forms:{&p->name,&p->name_female,&p->name_male,&p->spouse,&p->spouse_female,&p->spouse_male,&p->squad})
      for(const auto& name:*forms)text(name);
    text(p->land_name);text(p->description);
    numbers(p->allowed_creature);numbers(p->rejected_creature);numbers(p->commander_id);numbers(p->commander_civ);
    numbers(p->commander_types);numbers(p->appointed_by);numbers(p->appointed_by_civ);numbers(p->succession_by_position);
    numbers(p->responsibilities);numbers(p->color);
    for(const auto* classes:{&p->allowed_class,&p->rejected_class}) {
      number(classes->size());for(const auto* value:*classes){if(!value)return std::nullopt;text(*value);}
    }
    for(int value:{int(p->squad_size),int(p->land_holder),int(p->requires_population),int(p->execution_skill),p->precedence,
        p->replaced_by,int(p->number),p->required_boxes,p->required_cabinets,p->required_racks,p->required_stands,
        p->required_office,p->required_bedroom,p->required_dining,p->required_tomb,p->mandate_max,p->demand_max,p->best_appointment_precedence})number(value);
  }
  number(religion->positions.assignments.size());
  for(const auto* a:religion->positions.assignments) {
    if(!a)return std::nullopt;
    for(int value:{a->id,a->position_id,a->histfig,a->histfig2,a->st_id,a->ab_id,a->squad_id,a->vassal_of_entity_id,a->vassal_of_position_profile_id})number(value);
    for(int i=0;i<=int(df::enum_traits<df::entity_position_profile_flags>::last_item_value);++i)
      number(a->flags.is_set(static_cast<df::entity_position_profile_flags>(i)));
    auto* holder=a->histfig>=0?df::historical_figure::find(a->histfig):nullptr;number(holder!=nullptr);
    if(holder) {
      number(holder->entity_links.size());
      for(const auto* link:holder->entity_links) {
        if(!link)return std::nullopt;
        number(link->entity_id);number(link->link_strength);
        // These virtual semantic getters do not populate UI or lookup caches.
        auto* current=const_cast<df::histfig_entity_link*>(link);
        number(int(current->getType()));number(current->getPosition());
        number(current->getPositionStartYear());number(current->getPositionEndYear());
      }
    }
  }
  // Include list order and each predicate result, even currently nonmatching
  // entries: edits can change which agreement the native first-match scan uses.
  for(const auto* list:{&df::global::plotinfo->petitions,&df::global::plotinfo->continuing_agreement_id}) {
    number(list->size());for(auto id:*list) {
      number(id);auto* agreement=df::agreement::find(id);number(agreement!=nullptr);
      const auto matches=recognitionAgreementMatches(agreement,religion->id);if(!matches)return std::nullopt;
      number(*matches);if(agreement)number(agreement->flags.whole);
    }
  }
  const auto recipients=collectNativeLocationRecognitionUnits(*facts);if(!recipients)return std::nullopt;
  number(recipients->size());
  for(const auto* unit:*recipients){number(unit->id);number(unit->hist_figure_id);}
  numbers(religion->relations.deities);
  for(auto id:religion->relations.deities) {
    const auto* deity=df::historical_figure::find(id);number(deity!=nullptr);
    const auto* metaphysical=deity && deity->info?deity->info->metaphysical:nullptr;
    number(metaphysical!=nullptr);if(metaphysical)numbers(metaphysical->spheres);
  }
  number(religion->site_links.size());
  for(const auto* link:religion->site_links) {
    if(!link)return std::nullopt;
    number(link->target);number(link->entity_id);number(int(link->type));number(link->flags.whole);number(link->former_flag.whole);
    number(link->ab_profile.size());for(const auto* profile:link->ab_profile) {
      if(!profile)return std::nullopt;number(profile->id);number(profile->purpose_flag.whole);
    }
  }
  // Time, RNG and personality/emotion state are execution-time native inputs,
  // not an observed outcome promise. Epoch ownership belongs to the transport.
  hash&=uint64_t(INT64_MAX);return LocationRecognitionReceipt{std::move(*facts),hash?hash:1};
}
std::optional<std::vector<LocationNameWord>> observeNativeLocationNameWords(uint8_t component,const std::string& queryCp437,int32_t language) {
  if(component>6 || !df::global::world || !DFHack::Maps::IsValid())return std::nullopt;
  // Native name-editor initialization calls this semantic selector builder,
  // passing all raw word IDs. It reads raw language words and writes only the
  // supplied vectors; its two callees are vector insertion/allocation helpers.
  // No name_creator object, menu, filter, cursor or cached choices are borrowed.
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0xd35530,0x9a4)==UINT64_C(0x77bd9190661f5681) &&
        hash(0xd2cb50,0xf0)==UINT64_C(0xf7ab8eceaadda09f) &&
        hash(0x52cee0,0x19e)==UINT64_C(0xc25c2d8a6eb9fcac) &&
        hash(0x1fc330,0x28c)==UINT64_C(0xc8d8335c19ae0818) &&
        hash(0x1fdf5f,0x83)==UINT64_C(0xbae5c91a8beb8614);
  }();
  if(!compatible)return std::nullopt;
  const auto& words=df::global::world->raws.language.words;
  if(words.size()>size_t(INT32_MAX) || std::any_of(words.begin(),words.end(),[](auto* v){return v==nullptr;}))return std::nullopt;
  std::vector<int32_t> ids(words.size());std::iota(ids.begin(),ids.end(),0);
  df::language_word_table table;
  static_assert(sizeof(table)==0x120);
  using Build=void(__fastcall*)(df::language_word_table*,std::vector<int32_t>*);
  const auto build=reinterpret_cast<Build>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0xd35530);
  build(&table,&ids);
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  using Form=void(__fastcall*)(void*,int32_t,std::string*,int32_t,int32_t);
  using Lower=void(__fastcall*)(std::string*);
  const auto form=reinterpret_cast<Form>(base+0xd2cb50);
  const auto lower=reinterpret_cast<Lower>(base+0x52cee0);
  std::string query=queryCp437;lower(&query);
  // Audited name component -> semantic selector table mapping at1fc387..1fc3b8.
  constexpr int slots[]={0,1,3,3,4,2,5};
  const auto slot=static_cast<df::language_word_table_index>(slots[component]);
  const auto& selected=table.words[slot];const auto& parts=table.parts[slot];
  if(selected.size()!=parts.size())return std::nullopt;
  std::vector<LocationNameWord> result;result.reserve(selected.size());
  const auto& translations=df::global::world->raws.language.translations;
  const auto* translation=language>=0 && size_t(language)<translations.size()?translations[language]:nullptr;
  static_assert(offsetof(df::language_translation,words)==0x50);
  for(size_t i=0;i<selected.size();++i) {
    if(selected[i]<0 || size_t(selected[i])>=words.size() || int(parts[i])<0 || int(parts[i])>8)return std::nullopt;
    std::string english;form(nullptr,selected[i],&english,0,int32_t(parts[i]));
    // Native1fc330 has no independent filter helper: it normalizes an owned
    // query with52cee0 and retains substring matches in native English forms.
    // Reproduce that audited string operation without a name_creator object.
    if(!query.empty() && english.find(query)==std::string::npos)continue;
    // Native draw1fdf5f..1fdfe2 reads the stored name language and raw word
    // translation directly, independently of part of speech. Missing language
    // displays blank. Do not borrow name_creator or reproduce its text clipping.
    std::string translated;
    if(translation && size_t(selected[i])<translation->words.size() && translation->words[selected[i]])
      translated=DF2UTF(*translation->words[selected[i]]);
    result.push_back({selected[i],int32_t(parts[i]),DF2UTF(english),std::move(translated)});
  }
  return result;
}
std::optional<LocationNameWord> chooseNativeLocationNameWord(uint8_t displayedComponent,const std::string& queryCp437) {
  const auto choices=observeNativeLocationNameWords(displayedComponent,queryCp437);
  if(!choices || choices->empty())return std::nullopt;
  static const bool compatible=[] {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    uint64_t h=UINT64_C(14695981039346656037);
    for(size_t i=0;i<0x163;++i){h^=base[0xd35ee0+i];h*=UINT64_C(1099511628211);}
    return h==UINT64_C(0xc1e4fe91eb73c848);
  }();
  if(!compatible)return std::nullopt;
  df::language_word_table table;
  const auto slot=static_cast<df::language_word_table_index>(0);
  for(const auto& choice:*choices) {
    table.words[slot].push_back(choice.word);
    table.parts[slot].push_back(static_cast<df::part_of_speech>(choice.partOfSpeech));
  }
  // Native nonempty selector uses the same eb68b0 RNG/bucket calculation as
  // name-editor Random1ff79c..1ff82b. Own both vectors and outputs; the helper's
  // empty-table fallback is intentionally unreachable. A singleton draws no RNG.
  using Choose=void(__fastcall*)(df::language_word_table*,int32_t*,int16_t*,int32_t);
  const auto choose=reinterpret_cast<Choose>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0xd35ee0);
  int32_t word=-1;int16_t part=-1;choose(&table,&word,&part,0);
  const auto found=std::find_if(choices->begin(),choices->end(),[&](const auto& row) {
    return row.word==word && row.partOfSpeech==part;
  });
  if(found==choices->end())return std::nullopt;
  return *found;
}
namespace {
LocationNameValue copyLocationName(const df::language_name& name) {
  LocationNameValue value;value.firstNameCp437=name.first_name;value.nicknameCp437=name.nickname;
  value.words=name.words;
  for(size_t i=0;i<7;++i)value.parts[i]=int16_t(name.parts_of_speech[i]);
  value.language=name.language;value.type=int16_t(name.type);value.hasName=name.has_name;
  return value;
}
}
std::optional<LocationNameSnapshot> observeNativeLocationName(int32_t siteId,int32_t id) {
  const auto details=observeNativeLocationDetailsCore(siteId,id);
  if(!details || !locationRefreshFunction())return std::nullopt;
  auto* entity=df::historical_entity::find(df::global::plotinfo->civ_id);
  auto* site=df::world_site::find(siteId);
  if(!entity || !entity->entity_raw || !site)return std::nullopt;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id || !(*found)->getName())return std::nullopt;
  LocationNameSnapshot value;value.siteId=siteId;value.id=id;value.kind=details->kind;
  value.namerId=entity->id;value.namerRace=entity->race;value.name=copyLocationName(*(*found)->getName());
  const auto text=formatNativeLocationName(value.name);if(!text)return std::nullopt;
  value.nativeHeader=text->native;value.englishHeader=text->english;
  return value;
}
std::optional<LocationNameText> formatNativeLocationName(const LocationNameValue& value) {
  if(!df::global::world || !DFHack::Maps::IsValid() || !locationRefreshFunction())return std::nullopt;
  static const bool compatible=[] {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t count) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0xa94030,0x6a1)==UINT64_C(0xd81db68b3c9b33d2) &&
        hash(0xa946e0,0x7c2)==UINT64_C(0xdbc3db5f052419ee) &&
        hash(0x52d3c0,0x288)==UINT64_C(0x6e1fbc2416fba9fc) &&
        hash(0xd2cb50,0xf0)==UINT64_C(0xf7ab8eceaadda09f);
  }();
  if(!compatible)return std::nullopt;
  const auto& words=df::global::world->raws.language.words;
  const auto& translations=df::global::world->raws.language.translations;
  if(value.language< -1 || (value.language>=0 && (size_t(value.language)>=translations.size() || !translations[value.language])))return std::nullopt;
  for(size_t i=0;i<7;++i) {
    if(value.words[i]< -1 || value.parts[i]<0 || value.parts[i]>8)return std::nullopt;
    if(value.words[i]>=0 && (size_t(value.words[i])>=words.size() || !words[value.words[i]]))return std::nullopt;
  }
  df::language_name name;
  name.first_name=value.firstNameCp437;name.nickname=value.nicknameCp437;name.words=value.words;
  for(size_t i=0;i<7;++i)name.parts_of_speech[i]=static_cast<df::part_of_speech>(value.parts[i]);
  name.language=value.language;name.type=static_cast<df::language_name_type>(value.type);name.has_name=value.hasName;
  static_assert(sizeof(df::language_name)==0x78);
  // Native editor draw1fcce7/1fcd85 uses these semantic formatters. Both write
  // owned output strings; they read raw language data and nickname settings.
  // Capitalization52d3c0 edits only supplied temporary strings. No UI scratch,
  // RNG, authoritative-name writes, or DFHack formatting reconstruction.
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  using Native=void(__fastcall*)(const df::language_name*,std::string*);
  using English=void(__fastcall*)(const df::language_name*,std::string*,bool,bool);
  std::string native,english;
  reinterpret_cast<Native>(base+0xa94030)(&name,&native);
  reinterpret_cast<English>(base+0xa946e0)(&name,&english,true,false);
  return LocationNameText{DF2UTF(native),DF2UTF(english)};
}
std::optional<LocationNameValue> generateNativeLocationName(int32_t siteId,int32_t id) {
  const auto observed=observeNativeLocationDetailsCore(siteId,id);
  if(!observed || !locationRefreshFunction())return std::nullopt;
  static const bool compatible=[] {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t count) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0x931860,0x2f9)==UINT64_C(0x3f40974d82863764) &&
        hash(0xa92860,0x17cb)==UINT64_C(0x627504395969e689) &&
        hash(0x930be0,0xc7c)==UINT64_C(0x300195a029c0e420) &&
        hash(0x65ff0,0x63)==UINT64_C(0x6f20abe9b56596f8) &&
        hash(0x1fa3e0,0x9b)==UINT64_C(0x1e0d5c1bd19aa9f2) &&
        hash(0xeb68b0,0x1e3)==UINT64_C(0x4bcd46a418e7a7bb) &&
        hash(0xd35ee0,0x163)==UINT64_C(0xc1e4fe91eb73c848);
  }();
  if(!compatible)return std::nullopt;
  auto* entity=df::historical_entity::find(df::global::plotinfo->civ_id);
  auto* site=df::world_site::find(siteId);
  if(!entity || !entity->entity_raw || !site)return std::nullopt;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id || !(*found)->getName())return std::nullopt;
  // Native32c051 resolves the fortress civilization;32c097..32c1c8 selects
  // category from location kind, independently of the name's stored type.
  constexpr int16_t types[]={-1,28,21,43,52,54};
  static_assert(offsetof(df::plotinfost,civ_id)==0x2440);
  static_assert(offsetof(df::historical_entity,entity_raw)==8);
  static_assert(offsetof(df::historical_entity,race)==0x98);
  static_assert(sizeof(df::language_name)==0x78);
  df::language_name generated=*(*found)->getName();
  using Generate=void(__fastcall*)(df::historical_entity*,df::language_name*,int16_t);
  const auto generate=reinterpret_cast<Generate>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0x931860);
  // The entity wrapper reads raw word tables/language/race. Its ordinary and
  // special-race branches write only the supplied name and consume native RNG.
  // No name_creator input, native UI scratch or DFHack-generated substitute.
  generate(entity,&generated,types[observed->kind]);
  return copyLocationName(generated);
}
LocationAccessOutcome editNativeLocationName(int32_t siteId,int32_t id,uint64_t expectedRevision,
    LocationNameEdit edit,int32_t target,int32_t displayed,int32_t word,int32_t part,
    const std::string& queryCp437) {
  if(!expectedRevision || expectedRevision>uint64_t(INT64_MAX) || uint8_t(edit)>3)return LocationAccessOutcome::Rejected;
  const bool whole=edit==LocationNameEdit::RandomWhole;
  if(whole ? (target!=-1 || displayed!=-1 || word!=-1 || part!=-1 || !queryCp437.empty()) :
      (target<0 || target>6 || displayed<0 || displayed>6))return LocationAccessOutcome::Rejected;
  if(edit==LocationNameEdit::SelectWord ? (target!=displayed || word<0 || part<0 || part>8) :
      (word!=-1 || part!=-1))return LocationAccessOutcome::Rejected;
  const auto observed=observeNativeLocationName(siteId,id);
  if(!observed)return LocationAccessOutcome::Rejected;
  if(locationNameRevision(*observed)!=expectedRevision)return LocationAccessOutcome::Stale;
  static const bool compatible=[] {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    uint64_t h=UINT64_C(14695981039346656037);
    for(size_t i=0;i<0x1382;++i){h^=base[0x1fe5c0+i];h*=UINT64_C(1099511628211);}
    return h==UINT64_C(0x3326cd7614642632);
  }();
  if(!compatible)return LocationAccessOutcome::Rejected;
  auto* site=df::world_site::find(siteId);if(!site)return LocationAccessOutcome::Rejected;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id || !(*found)->getName())return LocationAccessOutcome::Rejected;
  auto* name=(*found)->getName();
  // Everything above, including stale rejection, precedes RNG and mutations.
  // Native writes are inline: preserve their exact field scope and use semantic
  // native providers for choices/randomization, never the UI input handler.
  if(whole) {
    const auto generated=generateNativeLocationName(siteId,id);
    if(!generated)return LocationAccessOutcome::Rejected;
    name->first_name=generated->firstNameCp437;name->nickname=generated->nicknameCp437;
    name->words=generated->words;
    for(size_t i=0;i<7;++i)name->parts_of_speech[i]=static_cast<df::part_of_speech>(generated->parts[i]);
    name->language=generated->language;name->type=static_cast<df::language_name_type>(generated->type);
    name->has_name=generated->hasName;
  } else {
    if(edit==LocationNameEdit::SelectWord) {
      const auto choices=observeNativeLocationNameWords(uint8_t(displayed),queryCp437);
      if(!choices || std::none_of(choices->begin(),choices->end(),[&](const auto& row) {
        return row.word==word && row.partOfSpeech==part;
      }))return LocationAccessOutcome::Rejected;
    } else if(edit==LocationNameEdit::RandomComponent) {
      const auto picked=chooseNativeLocationNameWord(uint8_t(displayed),queryCp437);
      if(!picked)return LocationAccessOutcome::Rejected;
      word=picked->word;part=picked->partOfSpeech;
    } else {word=-1;part=0;}
    name->words[target]=word;name->parts_of_speech[target]=static_cast<df::part_of_speech>(part);
  }
  return LocationAccessOutcome::Completed;
}
std::optional<LocationDetailsCore> observeNativeLocationDetailsCore(int32_t siteId,int32_t id) {
  if(siteId<0 || id<0 || !df::global::plotinfo || !DFHack::Maps::IsValid() ||
      siteId!=df::global::plotinfo->site_id)return std::nullopt;
  auto* site=df::world_site::find(siteId);
  if(!site)return std::nullopt;
  auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return std::nullopt;
  auto* location=*found;
  if(location->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) ||
      location->flags.is_set(df::abstract_building_flags::WG_RUINED) ||
      location->flags.is_set(df::abstract_building_flags::PWG_RUINED))return std::nullopt;
  LocationDetailsCore result;result.siteId=siteId;result.id=id;
  switch(location->getType()) {
    case df::abstract_building_type::INN_TAVERN:result.kind=1;break;
    case df::abstract_building_type::TEMPLE:result.kind=2;break;
    case df::abstract_building_type::LIBRARY:result.kind=3;break;
    case df::abstract_building_type::GUILDHALL:result.kind=4;break;
    case df::abstract_building_type::HOSPITAL:result.kind=5;break;
    default:return std::nullopt;
  }
  const auto* contents=location->getContents();
  if(!contents)return std::nullopt;
  auto name=DFHack::Translation::translateName(location->getName(),true);
  if(!name.empty())name[0]=toupper_cp437(name[0]);
  result.name=DF2UTF(name);
  result.accessFlags={location->flags.is_set(df::abstract_building_flags::VISITORS_ALLOWED),
      location->flags.is_set(df::abstract_building_flags::NON_CITIZENS_ALLOWED),
      location->flags.is_set(df::abstract_building_flags::MEMBERS_ONLY)};
  result.access=locationAccess(result.accessFlags);
  result.profession=int32_t(contents->profession);result.tier=contents->location_tier;
  result.value=contents->location_value;result.desiredCopies=contents->desired_copies;
  result.recognized=contents->need_more.bits.entity_recognized;
  // Native165005 resolves TRADE assignments in reverse order, skipping missing
  // historical figures/units. No citizenship or activity filter in this lookup.
  result.appraisal=-1;
  if(const auto* entity=df::global::plotinfo->main.fortress_entity) {
    const auto& assignments=entity->assignments_by_type[df::entity_position_responsibility::TRADE];
    for(auto it=assignments.rbegin();it!=assignments.rend();++it) {
      if(!*it)continue;
      auto* figure=df::historical_figure::find((*it)->histfig);
      auto* unit=figure?df::unit::find(figure->unit_id):nullptr;
      if(!unit)continue;
      result.appraisal=std::max(0,DFHack::Units::getEffectiveSkill(unit,df::job_skill::APPRAISAL));
      break;
    }
  }
  // Preserve native internal units. Presentation conversion is separately
  // evidenced by155506; exposing raw value does not establish visibility.
  result.supplies={{{contents->count_goblets,contents->desired_goblets},
      {contents->count_instruments,contents->desired_instruments},
      {contents->count_paper,contents->desired_paper},
      {contents->count_splints,contents->desired_splints},
      {contents->count_thread,contents->desired_thread},
      {contents->count_cloth,contents->desired_cloth},
      {contents->count_crutches,contents->desired_crutches},
      {contents->count_powder,contents->desired_powder},
      {contents->count_buckets,contents->desired_buckets},
      {contents->count_soap,contents->desired_soap}}};
  result.zoneIds.assign(contents->building_ids.begin(),contents->building_ids.end());
  // Native170942: membership order/multiplicity is authoritative. Only Bedroom
  // zones are excluded from common furniture; stage/flags/ownership do not filter.
  int64_t counts[8]={};
  for(auto id:contents->building_ids) {
    auto* building=df::building::find(id);
    if(!building || building->getType()!=df::building_type::Civzone)continue;
    auto* zone=static_cast<df::building_civzonest*>(building);
    if(zone->type==df::civzone_type::Bedroom) {
      ++counts[6];if(zone->assigned_unit_id!=-1)++counts[7];continue;
    }
    for(auto* furniture:zone->contained_buildings) {
      if(!furniture)return std::nullopt; // No fabricated zero for a corrupt pointer.
      switch(furniture->getType()) {
        case df::building_type::Box:++counts[0];break;
        case df::building_type::Bed:++counts[1];break;
        case df::building_type::Table:++counts[2];break;
        case df::building_type::TractionBench:++counts[3];break;
        case df::building_type::Bookcase:++counts[4];break;
        case df::building_type::Chair:++counts[5];break;
        default:break;
      }
    }
  }
  for(auto count:counts)if(count>INT32_MAX)return std::nullopt;
  result.facilities={int32_t(counts[0]),int32_t(counts[1]),int32_t(counts[2]),int32_t(counts[3]),
      int32_t(counts[4]),int32_t(counts[5]),int32_t(counts[6]),int32_t(counts[7])};

  // Native173749: BOOK entries count even without writing; TOOL entries require
  // writing. Use effective item position (including carried/container contents),
  // non-Bedroom painted footprints, and count each vector occurrence once across
  // overlapping/repeated zones. Stack size and other item/zone flags do not filter.
  int64_t written=0;
  for(auto kind:{df::items_other_id::BOOK,df::items_other_id::TOOL}) {
    for(auto* item:df::global::world->items.other[kind]) {
      if(!item)return std::nullopt;
      if(kind==df::items_other_id::TOOL && !item->hasWriting())continue;
      const auto pos=DFHack::Items::getPosition(item);
      if(!pos.isValid())continue;
      for(auto id:contents->building_ids) {
        auto* building=df::building::find(id);
        if(!building || building->getType()!=df::building_type::Civzone)continue;
        const auto* zone=static_cast<df::building_civzonest*>(building);
        // Native175331: require room extents; building bounds are not inputs.
        if(zone->type==df::civzone_type::Bedroom || pos.z!=zone->z || !zone->room.extents)continue;
        const int64_t x=int64_t(pos.x)-zone->room.x,y=int64_t(pos.y)-zone->room.y;
        if(x<0 || y<0 || x>=zone->room.width || y>=zone->room.height ||
            !int(zone->room.extents[y*zone->room.width+x]))continue;
        ++written;break;
      }
    }
  }
  if(written>INT32_MAX)return std::nullopt;
  result.writtenObjects=int32_t(written);
  const auto dance=locationDanceFunction();
  if(!dance)return std::nullopt;
  result.danceFloorX=0;result.danceFloorY=0;
  int bestRank=-1;
  for(auto id:contents->building_ids) {
    auto* building=df::building::find(id);
    if(!building || building->getSubtype()==int(df::civzone_type::Bedroom) || !building->room.extents)continue;
    const auto& room=building->room;
    if(room.width<=0 || room.height<=0)continue;
    // Geometry/storage guard; never truncate a native footprint.
    if(int64_t(room.width)*room.height>32768)return std::nullopt;
    int32_t x=0,y=0;
    dance(room.extents,room.x,room.y,building->z,room.width,room.height,&x,&y);
    if(x<0 || y<0 || x>room.width || y>room.height)return std::nullopt;
    // Native3ad230 chooses tier first, then area; exact ties keep membership order.
    const int rank=std::clamp(std::min(x,y)-4,0,4);
    if(rank>bestRank || (rank==bestRank && int64_t(x)*y>int64_t(result.danceFloorX)*result.danceFloorY)) {
      bestRank=rank;result.danceFloorX=x;result.danceFloorY=y;
    }
  }
  if(result.kind==2 || result.kind==4) {
    result.affiliation=observeNativeLocationAffiliation(siteId,id);
    if(!result.affiliation)return std::nullopt;
  }
  result.staff=observeNativeLocationStaff(siteId,id);
  if(!result.staff)return std::nullopt;
  return result;
}
LocationAccessOutcome setNativeLocationAccess(int32_t siteId,int32_t id,
    uint64_t expectedRevision,LocationAccess mode) {
  if(!expectedRevision || expectedRevision>uint64_t(INT64_MAX))return LocationAccessOutcome::Rejected;
  const auto observed=observeNativeLocationDetailsCore(siteId,id);
  if(!observed)return LocationAccessOutcome::Rejected;
  const auto selected=locationAccessSelection(observed->kind,mode);
  if(!selected)return LocationAccessOutcome::Rejected;
  if(locationDetailsRevision(*observed)!=expectedRevision)return LocationAccessOutcome::Stale;
  auto* site=df::world_site::find(siteId);
  if(!site)return LocationAccessOutcome::Rejected;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return LocationAccessOutcome::Rejected;
  auto& flags=(*found)->flags;
  flags.set(df::abstract_building_flags::VISITORS_ALLOWED,selected->visitors);
  flags.set(df::abstract_building_flags::NON_CITIZENS_ALLOWED,selected->residents);
  flags.set(df::abstract_building_flags::MEMBERS_ONLY,selected->members);
  return LocationAccessOutcome::Completed;
}
LocationAccessOutcome editNativeLocationQuantity(int32_t siteId,int32_t id,
    uint64_t expectedRevision,uint8_t quantity,LocationQuantityEdit edit,int32_t value) {
  // Native writes are inline in the input handlers, not a callable semantic
  // routine. Pin those instructions; never call/borrow the global number editor.
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false; // Supported PE/layout identity.
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t count) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0x311c10,0x4d664)==UINT64_C(0x0bb5d255b4bd6863) &&
        hash(0x8baa33,0x121)==UINT64_C(0x0aff370e58e7681f);
  }();
  if(!compatible || !expectedRevision || expectedRevision>uint64_t(INT64_MAX) || quantity>10 ||
      static_cast<uint8_t>(edit)>2 || (edit==LocationQuantityEdit::Set ? value<0 || value>999 : value!=0))
    return LocationAccessOutcome::Rejected;
  const auto observed=observeNativeLocationDetailsCore(siteId,id);
  if(!observed)return LocationAccessOutcome::Rejected;
  const auto kind=observed->kind;
  const bool offered=(kind==1 && (quantity==0 || quantity==1)) || (kind==2 && quantity==1) ||
      (kind==3 && (quantity==2 || quantity==10)) || (kind==5 && quantity>=3 && quantity<=9);
  if(!offered)return LocationAccessOutcome::Rejected;
  if(locationDetailsRevision(*observed)!=expectedRevision)return LocationAccessOutcome::Stale;
  auto* site=df::world_site::find(siteId);
  if(!site)return LocationAccessOutcome::Rejected;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return LocationAccessOutcome::Rejected;
  auto* c=(*found)->getContents();if(!c)return LocationAccessOutcome::Rejected;
  int32_t* fields[]={&c->desired_goblets,&c->desired_instruments,&c->desired_paper,&c->desired_splints,
      &c->desired_thread,&c->desired_cloth,&c->desired_crutches,&c->desired_powder,
      &c->desired_buckets,&c->desired_soap,&c->desired_copies};
  static_assert(offsetof(df::abstract_building_contents,desired_goblets)==8);
  static_assert(offsetof(df::abstract_building_contents,desired_copies)==48);
  const int32_t scale=quantity==4?15000:quantity==5?10000:(quantity==7 || quantity==9)?150:1;
  auto& target=*fields[quantity];
  // Native checks the bound BEFORE adding/subtracting one raw unit. Preserve
  // partial raw quantities, including a step across the bound; do not clamp.
  if(edit==LocationQuantityEdit::Set)target=value*scale;
  else if(edit==LocationQuantityEdit::Increase && target<999*scale)target+=scale;
  else if(edit==LocationQuantityEdit::Decrease && target>0)target-=scale;
  return LocationAccessOutcome::Completed;
}

bool refreshNativeLocationDetailsCaches(int32_t siteId,int32_t id) {
  // Preflight all existing identity/availability/geometry guards before cache writes.
  // No pointers outlive this safe point; no native viewscreen state is involved.
  if(!observeNativeLocationDetailsCore(siteId,id))return false;
  const auto refresh=locationRefreshFunction();
  if(!refresh)return false;
  auto* site=df::world_site::find(siteId);
  if(!site)return false;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return false;
  auto* contents=(*found)->getContents();
  if(!contents)return false;
  // Native181042: refresh on entry/reentry only, retaining requested quantities
  // and recognition. Native initializer resets these scheduler fields afterward.
  refresh(contents,id,true);
  contents->update_timer=100;contents->update_count=0;
  return true;
}

}
