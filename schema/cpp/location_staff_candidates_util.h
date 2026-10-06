#pragma once
#include "mirror_generated.h"
#include <algorithm>
#include <cstdint>
#include <optional>
#include <set>
#include <string>

namespace df3d::mirror {
inline std::optional<std::string> validateLocationStaffCandidates(const LocationStaffCandidates& c) {
  switch(c.role()) {case 0:case 1:case 2:case 5:case 7:case 8:case 9:case 10:break;
    default:return "invalid staff candidate role";}
  const size_t count=c.rows()?c.rows()->size():0;
  if(c.site_id()<0 || c.location_id()<0 || c.occupation_id()<0 || !c.revision() || c.revision()>INT64_MAX ||
      c.total()>INT32_MAX || c.cursor()%128 || c.cursor()>c.total() || (c.cursor() && c.cursor()==c.total()) ||
      count>128 || count!=std::min(uint32_t(128),c.total()-c.cursor()) ||
      c.next_cursor()!=(c.cursor()+count<c.total()?c.cursor()+count:0))return "invalid staff candidate page";
  size_t payload=128;
  std::set<int32_t> units;
  std::set<int32_t> sourceIndexes;
  int32_t previousScore=INT32_MAX;
  int32_t previousSource=-1;
  if(c.rows())for(const auto* r:*c.rows()) {
    if(!r || r->unit_id()<0 || r->histfig_id()<-1 || !units.insert(r->unit_id()).second ||
        !r->name() || r->name()->size()>2048 || !r->base_name() || r->base_name()->size()>2048 ||
        !r->profession_name() || r->profession_name()->size()>2048 ||
        r->profession_color()<0 || r->profession_color()>15 || r->score()<0 || r->score()>previousScore ||
        (r->skills() && r->skills()->size()>10))return "invalid staff candidate";
    if(r->source_index()<0 || uint32_t(r->source_index())>=c.total() || !sourceIndexes.insert(r->source_index()).second ||
        r->profession_order()<0 || r->status_order()<0 || !r->name_sort_key() || !r->profession_sort_key() ||
        r->name_sort_key()->size()>2048 || r->profession_sort_key()->size()>2048 ||
        (r->score()==previousScore && r->source_index()<=previousSource))return "invalid staff candidate ordering";
    previousSource=r->source_index();payload+=r->name_sort_key()->size()+r->profession_sort_key()->size();
    previousScore=r->score();payload+=128+r->name()->size()+r->base_name()->size()+r->profession_name()->size();
    std::set<int32_t> skills;int64_t score=0;
    if(r->skills())for(const auto* s:*r->skills()) {
      if(!s || s->id()<0 || s->id()>128 || !skills.insert(s->id()).second || s->rating()<0 ||
          s->experience()<0 || s->weight()<1 || s->weight()>5)return "invalid staff candidate skill";
      score+=int64_t(s->rating())*s->weight();payload+=48;
    }
    if(score!=r->score())return "invalid staff candidate score";
    if(payload>224*1024)return "staff candidate payload too large";
  }
  return std::nullopt;
}
}
