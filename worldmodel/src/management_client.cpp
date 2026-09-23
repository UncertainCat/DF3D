#include "wm/management_client.h"

#include <algorithm>
#include <chrono>

#include "management_codecs.h"
#include "management_enum_checks.inc"
#include "request_channel.h"
namespace wm {
namespace m = df3d::mirror;
struct ManagementClient::Impl {
#ifdef _WIN32
  std::unique_ptr<detail::RequestChannel> channel;
  std::vector<uint8_t> publicScratch;
#endif
  std::vector<uint8_t> scratch;
};
ManagementClient::ManagementClient() : impl_(new Impl) {}
ManagementClient::~ManagementClient() = default;
bool ManagementClient::transportAlive() const {
#ifdef _WIN32
  return impl_->channel && impl_->channel->alive();
#else
  return false;
#endif
}
std::unique_ptr<ManagementClient> ManagementClient::open(std::string& error,
                                                         const std::string& name) {
#ifdef _WIN32
  std::unique_ptr<ManagementClient> c(new ManagementClient);
  auto& i = *c->impl_;
  i.channel = detail::RequestChannel::open(
      name.empty() ? m::kManagementRegionName : name,
      {m::kManagementVersion, m::kManagementCapacity, m::kManagementCommandCapacity,
       "Management bridge unavailable", "Cannot map management bridge",
       "Unexpected management capacity", "DF process ended",
       "Cannot create management client transport"},
      error);
  if (!i.channel)
    return {};
  c->clientId_ = i.channel->clientId();
  c->seq_ = 0;
  i.publicScratch.resize(m::kManagementCapacity);
  i.scratch.resize(m::kManagementCapacity);
  error.clear();
  return c;
#else
  error = "Management bridge requires Windows";
  return {};
#endif
}
bool ManagementClient::poll() {
#ifdef _WIN32
  auto& i = *impl_;
  if (!i.channel->alive()) {
    state_ = {};
    state_.status = ManagementStatus::Rejected;
    error_ = state_.message = "DF process or management bridge ended";
    pending_ = 0;
    return false;
  }
  // Public metadata announces world changes; private replies survive other clients.
  auto publicLen = i.channel->readPublic(i.publicScratch.data(), i.publicScratch.size());
  const m::ManagementState* broadcast = nullptr;
  if (publicLen) {
    flatbuffers::Verifier verify(i.publicScratch.data(), publicLen);
    if (verify.VerifyBuffer<m::ManagementState>(nullptr)) {
      auto* candidate = flatbuffers::GetRoot<m::ManagementState>(i.publicScratch.data());
      if (!m::validateManagementState(*candidate))
        broadcast = candidate;
    }
  }
  auto n = i.channel->readReply(i.scratch.data(), i.scratch.size());
  if (broadcast && (!n || state_.worldEpoch != broadcast->world_epoch())) {
    if (state_.worldEpoch != broadcast->world_epoch()) {
      pending_ = 0;
      catalogReady_ = false;
      state_ = {};
      state_.worldEpoch = broadcast->world_epoch();
      state_.status = ManagementStatus::Idle;
      state_.message = "World changed; refresh catalog";
      return true;
    }
    if (!n)
      return false;
  }
  if (!n)
    return false;
  flatbuffers::Verifier v(i.scratch.data(), n);
  if (!v.VerifyBuffer<m::ManagementState>(nullptr)) {
    error_ = "Malformed management state";
    return false;
  }
  auto* s = flatbuffers::GetRoot<m::ManagementState>(i.scratch.data());
  if (auto e = m::validateManagementState(*s)) {
    error_ = *e;
    return false;
  }
  if (s->client_id() != clientId_)
    return false;
  if (broadcast && s->world_epoch() != broadcast->world_epoch())
    return false;
  if (s->revision() == state_.revision)
    return false;
  if (state_.worldEpoch && state_.worldEpoch != s->world_epoch()) {
    pending_ = 0;
    catalogReady_ = false;
    state_ = {};
  }
  ManagementState next = detail::management::decodeState(s);
  if (pending_ && next.requestSeq < pending_) {
    next.requestSeq = pending_;
    next.status = ManagementStatus::Pending;
  } else if (pending_ && next.status != ManagementStatus::Pending)
    pending_ = 0;
  if (s->client_id() == clientId_ && next.action == ManagementAction::Catalog &&
      next.status == ManagementStatus::Ok)
    catalogReady_ = true;
  state_ = std::move(next);
  error_.clear();
  return true;
#else
  return false;
#endif
}
uint64_t ManagementClient::send(const ManagementRequest& r) {
#ifdef _WIN32
  if (!impl_->channel->alive()) {
    error_ = "DF process ended";
    return 0;
  }
  if (pending_) {
    error_ = "Wait for the current construction request";
    return 0;
  }
  if (r.action != ManagementAction::Catalog && (!state_.worldEpoch || !catalogReady_)) {
    error_ = "Refresh construction catalog first";
    return 0;
  }
  flatbuffers::FlatBufferBuilder b;
  detail::management::encodeRequest(b, r, clientId_, seq_ + 1, state_.worldEpoch);
  if (auto e = m::validateConstructionRequest(
          *flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer()))) {
    error_ = *e;
    return 0;
  }
  if (!impl_->channel->push(b.GetBufferPointer(), b.GetSize())) {
    error_ = "Construction queue full";
    return 0;
  }
  pending_ = ++seq_;
  state_.requestSeq = pending_;
  state_.status = ManagementStatus::Pending;
  error_.clear();
  return seq_;
#else
  return 0;
#endif
}
}  // namespace wm
