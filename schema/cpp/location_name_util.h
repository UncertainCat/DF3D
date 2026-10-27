#pragma once
#include "mirror_generated.h"
#include <cstdint>
#include <optional>
#include <string>

namespace df3d::mirror {
// Transport storage bounds, not native naming rules. Never truncate a name or
// form to satisfy these limits; report an unavailable payload instead.
inline constexpr uint32_t kLocationNameBytes=4096;
inline constexpr uint32_t kLocationNameHeaderBytes=16384;
inline constexpr uint32_t kLocationNamePageRows=128;
inline constexpr uint32_t kLocationNamePageBytes=64*1024;
inline std::optional<std::string> validateLocationNameQuery(const LocationNameQuery& q) {
  if(q.component()>6 || !q.query_bytes() || q.query_bytes()->size()>kLocationNameBytes)
    return "invalid location name query";
  return std::nullopt;
}
inline std::optional<std::string> validateLocationNameEdit(const LocationNameEdit& e) {
  if(e.mode()>LocationNameMode::RandomWhole || !e.query_bytes() || e.query_bytes()->size()>kLocationNameBytes)
    return "invalid location name edit";
  if(e.mode()==LocationNameMode::RandomWhole) {
    if(e.target()!=-1 || e.displayed()!=-1 || e.word()!=-1 || e.part()!=-1 || e.query_bytes()->size())
      return "unrelated whole-name fields";
  } else {
    if(e.target()<0 || e.target()>6 || e.displayed()<0 || e.displayed()>6)return "invalid name component";
    if(e.mode()==LocationNameMode::SelectWord ?
        (e.target()!=e.displayed() || e.word()<0 || e.part()<0 || e.part()>8) : (e.word()!=-1 || e.part()!=-1))
      return "invalid name choice fields";
  }
  return std::nullopt;
}
inline std::optional<std::string> validateLocationNameSnapshot(const LocationNameSnapshot& s) {
  if(!s.native_header() || !s.english_header() || s.native_header()->size()>kLocationNameHeaderBytes ||
      s.english_header()->size()>kLocationNameHeaderBytes)return "invalid location name headers";
  if(s.site_id()<0 || s.id()<0 || s.kind()<1 || s.kind()>5 || s.namer_id()<0 || s.namer_race()<-1 ||
      !s.revision() || s.revision()>INT64_MAX || !s.value())return "invalid location name identity";
  const auto& v=*s.value();
  if(!v.first_name_bytes() || !v.nickname_bytes() || v.first_name_bytes()->size()>kLocationNameBytes ||
      v.nickname_bytes()->size()>kLocationNameBytes || !v.words() || v.words()->size()!=7 ||
      !v.parts() || v.parts()->size()!=7 || v.language()<-1 || v.type()<-1)
    return "invalid structured location name";
  for(auto word:*v.words())if(word<-1)return "invalid location name word";
  for(auto part:*v.parts())if(part<0 || part>8)return "invalid location name grammar";
  // Do not require unused components to have part0, or infer has_name/type from
  // the words. Native edits can retain those independent fields.
  return std::nullopt;
}
inline std::optional<std::string> validateLocationNamePage(const LocationNamePage& p) {
  if(!p.snapshot())return "missing location name snapshot";
  if(auto error=validateLocationNameSnapshot(*p.snapshot()))return error;
  if(p.component()>6 || !p.query_bytes() || p.query_bytes()->size()>kLocationNameBytes ||
      !p.choices() || p.choices()->size()>kLocationNamePageRows || p.cursor()>p.total())
    return "invalid location name page";
  const uint64_t end=uint64_t(p.cursor())+p.choices()->size();
  if(end>p.total() || p.truncated()!=(end<p.total()) ||
      p.next_cursor()!=(p.truncated()?end:0) || (p.truncated() && !p.choices()->size()))
    return "invalid location name pagination";
  const auto& value=*p.snapshot()->value();
  uint64_t bytes=512+p.query_bytes()->size()+value.first_name_bytes()->size()+value.nickname_bytes()->size()+
      p.snapshot()->native_header()->size()+p.snapshot()->english_header()->size();
  for(const auto* choice:*p.choices()) {
    if(!choice || choice->word()<0 || choice->part()<0 || choice->part()>8 ||
        !choice->english() || !choice->translated())return "invalid location name choice";
    bytes+=64+uint64_t(choice->english()->size())+choice->translated()->size();
    if(bytes>kLocationNamePageBytes)return "location name page too large";
  }
  return std::nullopt;
}
}
