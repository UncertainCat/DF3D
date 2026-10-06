#pragma once
#include "mirror_generated.h"
#include <algorithm>
#include <cstdint>
#include <optional>
#include <set>
#include <string>
namespace df3d::mirror {
inline std::optional<std::string> validateLocationCatalog(const LocationCatalog& c) {
  const auto count=[](const auto* rows)->size_t{return rows?rows->size():0;};
  const auto length=[](const flatbuffers::String* s)->size_t{return s?s->size():0;};
  const size_t size=count(c.religions())+count(c.guilds());
  if((c.kind()!=2 && c.kind()!=4) || !c.revision() || c.revision()>INT64_MAX || c.cursor()%128 ||
      c.total()>INT32_MAX || c.cursor()>c.total() || (c.cursor() && c.cursor()==c.total()) ||
      size>128 || size!=std::min(uint32_t(128),c.total()-c.cursor()) ||
      c.next_cursor()!=(c.cursor()+size<c.total()?c.cursor()+size:0) ||
      (c.kind()==2?count(c.guilds())!=0:count(c.religions())!=0))return "invalid location catalog page";
  size_t payload=64;
  std::set<std::pair<uint8_t,int32_t>> practices;
  size_t index=0;
  if(c.religions())for(const auto* r:*c.religions()) {
    if(!r || r->kind()<1 || r->kind()>3 || r->worshippers()<0 || length(r->name())>512 ||
        !practices.emplace(r->kind(),r->id()).second || count(r->deities())>256 ||
        (r->kind()==1 ? (r->id()!=-1 || length(r->name()) || count(r->deities()) || r->worshippers()) :
          (r->id()<0 || !length(r->name()))) ||
        (r->kind()==1 && c.cursor()+index!=0) ||
        (r->kind()==2 && (count(r->deities())!=1 || !r->deities()->Get(0) || r->deities()->Get(0)->id()!=r->id())))return "invalid religious choice";
    ++index;
    payload+=64+length(r->name());
    std::set<int32_t> deities;
    if(r->deities())for(const auto* d:*r->deities()) {
      if(!d || d->id()<0 || !deities.insert(d->id()).second || !length(d->name()) || length(d->name())>512 ||
          count(d->spheres())>130)return "invalid location deity";
      std::set<int32_t> spheres;
      if(d->spheres())for(auto id:*d->spheres())if(id<0 || id>=130 || !spheres.insert(id).second)return "invalid location sphere";
      payload+=48+length(d->name())+4*count(d->spheres());
    }
    if(payload>224*1024)return "location catalog payload too large";
  }
  if(c.kind()==2 && c.cursor()==0 && (!count(c.religions()) || c.religions()->Get(0)->kind()!=1))return "missing religious sentinel";
  std::set<int32_t> professions;
  if(c.guilds())for(const auto* g:*c.guilds()) {
    if(!g || g->profession()<0 || !professions.insert(g->profession()).second || g->workers()<0 || g->guild_id()<-1 ||
        g->members()<0 || length(g->guild_name())>512 ||
        (g->guild_id()==-1 ? (length(g->guild_name()) || g->members()) : !length(g->guild_name())))return "invalid guild choice";
    payload+=64+length(g->guild_name());
  }
  if(payload>224*1024)return "location catalog payload too large";
  return std::nullopt;
}
}
