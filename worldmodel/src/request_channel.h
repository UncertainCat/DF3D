#pragma once

#include "client_mailbox.h"
#include "session_util.h"

#ifdef _WIN32
namespace wm::detail {

// Mechanical ownership only. Each typed client retains its own decoding,
// request sequencing, world reconciliation and reconnect policy.
class RequestChannel {
public:
  struct Configuration {
    uint32_t version, snapshotCapacity, commandCapacity;
    const char* unavailable;
    const char* mappingFailed;
    const char* capacityMismatch;
    const char* ownerEnded;
    const char* transportFailed;
  };

  RequestChannel() = default;
  RequestChannel(const RequestChannel&) = delete;
  RequestChannel& operator=(const RequestChannel&) = delete;
  ~RequestChannel() {
    reply_.reset();
    if (owner_) CloseHandle(owner_);
    if (region_) UnmapViewOfFile(region_);
    if (mapping_) CloseHandle(mapping_);
  }

  static std::unique_ptr<RequestChannel> open(const std::string& name,
      const Configuration& config, std::string& error) {
    auto channel = std::make_unique<RequestChannel>();
    auto& c = *channel;
    c.mapping_ = OpenFileMappingA(FILE_MAP_ALL_ACCESS, FALSE, name.c_str());
    if (!c.mapping_) { error = config.unavailable; return {}; }
    c.region_ = static_cast<df3d::shm::RegionHeader*>(
        MapViewOfFile(c.mapping_, FILE_MAP_ALL_ACCESS, 0, 0, 0));
    if (!c.region_) { error = config.mappingFailed; return {}; }
    if (const char* e = df3d::shm::checkRegion(c.region_, config.version)) {
      error = e; return {};
    }
    MEMORY_BASIC_INFORMATION view{};
    if (!VirtualQuery(c.region_, &view, sizeof(view)) ||
        df3d::shm::checkRegionSize(c.region_, static_cast<size_t>(view.RegionSize))) {
      error = config.mappingFailed; return {};
    }
    if (c.region_->snapshotCapacity != config.snapshotCapacity ||
        c.region_->commandCapacity != config.commandCapacity) {
      error = config.capacityMismatch; return {};
    }
    const auto* owner = df3d::mirror::sessionOwner(c.region_);
    c.pid_ = df3d::shm::atomicLoadAcquire(&owner->pid);
    c.created_ = df3d::shm::atomicLoadAcquire(&owner->created);
    c.generation_ = df3d::shm::atomicLoadAcquire(&owner->generation);
    c.owner_ = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE, static_cast<DWORD>(c.pid_));
    if (!c.created_ || !c.alive() ||
        df3d::shm::processCreated(c.owner_) != c.created_) {
      error = config.ownerEnded; return {};
    }
    c.reply_ = df3d::shm::ClientMailbox::create(name, c.generation_,
        config.version, config.snapshotCapacity);
    if (!c.reply_ || !c.writer_.open(name, c.generation_)) {
      error = config.transportFailed; return {};
    }
    // Initialization may race a producer restart. Never return an owner whose
    // mailbox and writer were established for a superseded generation.
    if (!c.alive()) { error = config.ownerEnded; return {}; }
    error.clear();
    return channel;
  }

  bool alive() const {
    if (!region_ || !owner_ || WaitForSingleObject(owner_, 0) != WAIT_TIMEOUT)
      return false;
    const auto* owner = df3d::mirror::sessionOwner(region_);
    return df3d::shm::atomicLoadAcquire(&owner->pid) == pid_ &&
        df3d::shm::atomicLoadAcquire(&owner->created) == created_ &&
        df3d::shm::atomicLoadAcquire(&owner->generation) == generation_;
  }
  uint64_t clientId() const { return reply_->id(); }
  size_t readPublic(uint8_t* bytes, size_t capacity) const {
    return df3d::shm::readLatestSnapshot(region_, bytes, capacity);
  }
  size_t readReply(uint8_t* bytes, size_t capacity) const {
    return df3d::shm::readLatestSnapshot(reply_->region(), bytes, capacity);
  }
  bool push(const uint8_t* bytes, size_t size) {
    return alive() && writer_.push(region_, bytes, size);
  }

private:
  HANDLE mapping_ = nullptr, owner_ = nullptr;
  df3d::shm::RegionHeader* region_ = nullptr;
  uint64_t pid_ = 0, created_ = 0, generation_ = 0;
  df3d::shm::CommandWriter writer_;
  std::unique_ptr<df3d::shm::ClientMailbox> reply_;
};

} // namespace wm::detail
#endif
