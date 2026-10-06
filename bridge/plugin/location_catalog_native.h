#pragma once
#include "location_catalog.h"
namespace df3d_area {
// Caller holds a DF safe point. Observes current simulation facts only; no
// native selector, camera, widgets, staged edits or mutations.
std::optional<std::vector<ReligiousPractice>> observeNativeLocationReligions();
std::optional<std::vector<GuildWorkers>> observeNativeLocationGuilds();
struct LocationAffiliation {
  uint8_t kind=0; // 1 no dedication,2 deity,3 religion,4 guild (possibly absent).
  int32_t id=-1,count=0,workers=-1; // workers only applies to guilds.
  std::string name;
};
// Details-specific observation: works even when a practice has no eligible
// worshippers and is absent from the offered creation catalog.
std::optional<LocationAffiliation> observeNativeLocationAffiliation(int32_t siteId,int32_t locationId);
}
