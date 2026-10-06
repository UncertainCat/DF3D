#pragma once
#include "mirror_generated.h"
#include <optional>
#include <string>
#include <cstdint>

namespace df3d::mirror {
inline std::optional<std::string> validateLocationDetails(const LocationDetails& d) {
  if(d.site_id()<0 || d.id()<0 || d.kind()<1 || d.kind()>5 || !d.revision() || d.revision()>INT64_MAX ||
      !d.name() || d.name()->size()>512 || d.access()>3 || d.profession()<-1 || d.profession()>511 || d.tier()<0 || d.appraisal()<-2 || d.written_objects()<-1)
    return "invalid location details identity";
  const auto x=d.dance_floor_x(),y=d.dance_floor_y();
  if(x<-1 || y<-1 || (x==-1)!=(y==-1) || (x==0)!=(y==0))return "invalid location dance floor";
  if(const auto* f=d.facilities()) {
    if(f->chests()<0 || f->beds()<0 || f->tables()<0 || f->traction_benches()<0 || f->bookcases()<0 || f->chairs()<0 || f->rooms()<0 || f->rented_rooms()<0 || f->rented_rooms()>f->rooms())
      return "invalid location facilities";
  }
  const auto mode=d.members()?3:d.visitors()?0:d.residents()?1:2;
  if(d.access()!=mode)return "invalid location access";
  if(!d.supplies() || d.supplies()->size()!=10)return "invalid location supplies";
  for(uint32_t i=0;i<10;++i)if(!d.supplies()->Get(i) || d.supplies()->Get(i)->kind()!=i)
    return "invalid location supply order";
  // Byte budget, not a gameplay or per-step work ceiling. No truncated facts.
  uint64_t bytes=512+uint64_t(d.name()->size())+4*(d.zone_ids()?uint64_t(d.zone_ids()->size()):0);
  if(const auto* a=d.affiliation()) {
    if(!a->name() || a->name()->size()>512 || a->count()<0 || a->kind()<1 || a->kind()>4 ||
        (d.kind()==2?a->kind()==4:d.kind()!=4 || a->kind()!=4) ||
        (a->kind()==1?(a->id()!=-1 || a->count()!=0 || a->name()->size()!=0 || a->workers()!=-1):
         a->kind()==4?(a->id()<-1 || a->workers()<0 || (a->id()==-1 && (a->count()!=0 || a->name()->size()!=0))):
         (a->id()<0 || a->workers()!=-1)))return "invalid location affiliation";
    bytes+=64+a->name()->size();
  }
  if(const auto* staff=d.staff()) {
    bytes+=128*(staff->rows()?uint64_t(staff->rows()->size()):0)+4*(staff->missing_roles()?uint64_t(staff->missing_roles()->size()):0);
    const auto allowed=[&](int32_t role) {
      return d.kind()==1?(role==0 || role==1):d.kind()==2?role==1:d.kind()==3?(role==2 || role==5):d.kind()==5?(role>=7 && role<=10):false;
    };
    if(staff->rows())for(const auto* row:*staff->rows()) {
      if(!row || row->source()>1 || row->site_id()!=d.site_id() || row->location_id()!=d.id())return "invalid location staff identity";
      if(const auto* n=row->names()) {
        if(!n->position_name() || !n->holder_name() || n->position_name()->size()>512 || n->holder_name()->size()>512 ||
            n->holder_kind()>2 || (n->holder_kind()==0?(n->holder_id()!=-1 || n->holder_name()->size()!=0):n->holder_id()<0) ||
            (row->source()==0 && n->position_name()->size()!=0))return "invalid location staff names";
        bytes+=64+n->position_name()->size()+n->holder_name()->size();
      }
      if(row->source()==0) {
        if(row->occupation_id()<0 || !allowed(row->role()) || row->entity_id()!=-1 || row->position_id()!=-1 || row->assignment_id()!=-1)return "invalid location occupation";
      } else if(d.kind()!=2 || row->entity_id()<0 || row->position_id()<0 || row->assignment_id()<0 || row->occupation_id()!=-1 || row->role()!=-1 || row->unit_id()!=-1 || row->group_id()!=-1)return "invalid location religious position";
    }
    int32_t previous=-1;
    if(staff->missing_roles())for(auto role:*staff->missing_roles()) {
      if(!allowed(role) || role<=previous)return "invalid missing location role";
      previous=role;
    }
  }
  if(bytes>224*1024)return "location details payload too large";
  int32_t last=-1;
  if(d.zone_ids())for(auto id:*d.zone_ids()) {
    if(id<0 || id<=last)return "invalid location zone membership";
    last=id;
  }
  return std::nullopt;
}
}
