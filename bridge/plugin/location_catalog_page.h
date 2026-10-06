#pragma once
#include "location_catalog.h"
#include <algorithm>
#include <limits>

namespace df3d_area {
enum class LocationPageStatus { Ready, Unavailable, Stale, InvalidCursor };

template<class Row> struct LocationCatalogPage {
  LocationPageStatus status=LocationPageStatus::Unavailable;
  uint64_t revision=0;
  uint32_t nextCursor=0,total=0;
  std::vector<Row> rows;
};

// A safe-point observation must precede paging. Copies cross the publication
// boundary; neither pages nor callers retain references into mutable snapshots.
// The transport must separately validate encoded byte size and row contents.
template<class Row> class LocationCatalogSnapshot {
public:
  static constexpr uint32_t pageRows=128;

  void observe(uint64_t epoch,std::optional<std::vector<Row>> rows) {
    if(epoch==0 || !rows || rows->size()>std::numeric_limits<uint32_t>::max()) {
      invalidate();epoch_=epoch;return;
    }
    if(valid_ && epoch_==epoch && rows_==*rows)return;
    epoch_=epoch;
    if(serial_==uint64_t(std::numeric_limits<int64_t>::max())) {
      // Never wrap a receipt into one a stale client could still hold.
      invalidate();return;
    }
    ++serial_;revision_=serial_;rows_=std::move(*rows);valid_=true;
  }

  void invalidate() {
    valid_=false;revision_=0;rows_.clear();
    // Keep serial across invalidation and epoch changes to prevent ABA receipts.
  }

  LocationCatalogPage<Row> page(uint64_t epoch,uint32_t cursor,uint64_t expectedRevision=0) const {
    LocationCatalogPage<Row> result;
    if(!valid_ || epoch==0 || epoch!=epoch_)return result;
    if((cursor && !expectedRevision) || (expectedRevision && expectedRevision!=revision_)) {
      result.status=LocationPageStatus::Stale;return result;
    }
    if((cursor && cursor>=rows_.size()) || cursor%pageRows) {
      result.status=LocationPageStatus::InvalidCursor;return result;
    }
    result.status=LocationPageStatus::Ready;result.revision=revision_;
    result.total=uint32_t(rows_.size());
    const auto end=cursor+std::min(pageRows,result.total-cursor);
    result.rows.assign(rows_.begin()+cursor,rows_.begin()+end);
    result.nextCursor=end<result.total?end:0;
    return result;
  }
private:
  bool valid_=false;
  uint64_t epoch_=0,serial_=0,revision_=0;
  std::vector<Row> rows_;
};
}
