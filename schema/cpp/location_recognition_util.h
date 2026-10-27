#pragma once
#include "mirror_generated.h"
#include <optional>
#include <string>
#include <climits>
namespace df3d::mirror {
inline std::optional<std::string> validateLocationRecognition(const LocationRecognition& r) {
  if(r.site_id()<0 || r.location_id()<0 || r.religion_id()<0 || !r.revision() || r.revision()>INT64_MAX ||
      r.tier()<0 || r.tier()>2 || r.rank()<0 || r.rank()>2 || r.worshippers()<0 ||
      r.state()>LocationRecognitionState::RecognizeHighPriest || !r.continuing_agreements() ||
      r.continuing_agreements()->size()>4096)return "invalid recognition snapshot";
  for(auto id:*r.continuing_agreements())if(id<0)return "invalid recognition agreement";
  return std::nullopt;
}
}
