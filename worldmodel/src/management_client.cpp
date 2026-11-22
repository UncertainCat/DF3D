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
  df3d::stocks_pages::Assembly assembly;
  std::vector<uint8_t> assembled;
  uint64_t transportSeq=0;
  ManagementAction logicalAction=ManagementAction::Catalog;
  bool paging=false;
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
    pending_ = 0;i.assembly.reset();i.assembled.clear();i.paging=false;
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
      pending_ = 0;i.assembly.reset();i.assembled.clear();i.paging=false;
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
  const auto failTransfer=[&](const char* why) {
    const auto epoch=state_.worldEpoch;state_={};state_.worldEpoch=epoch;state_.revision=s->revision();
    state_.requestSeq=pending_;state_.action=i.logicalAction;state_.status=ManagementStatus::Rejected;
    if(i.logicalAction==ManagementAction::StocksGroupApply || i.logicalAction==ManagementAction::StocksItemApply) {
      state_.stocksMenu.emplace();state_.stocksMenu->outcome=StocksMenuOutcome::Unknown;
    }
    if(i.logicalAction==ManagementAction::DisplayCommit || i.logicalAction==ManagementAction::DisplayRemove) {
      state_.display.emplace();state_.display->outcome=DisplayOutcome::Unknown;
    }
    error_=why;pending_=0;i.assembly.reset();i.assembled.clear();i.paging=false;return true;
  };
  if(s->stocks_page() || s->production_page() || s->display_page()) {
    if(!pending_ || s->request_seq()!=i.transportSeq)return false;
    const bool production=i.logicalAction==ManagementAction::ProductionInspect ||
        i.logicalAction==ManagementAction::ProductionQueue || i.logicalAction==ManagementAction::ProductionJobEdit;
    const bool display=i.logicalAction>=ManagementAction::DisplayRead && i.logicalAction<=ManagementAction::DisplayRemove;
    const bool stocks=i.logicalAction==ManagementAction::StocksMenuRead ||
        i.logicalAction==ManagementAction::StocksGroupApply || i.logicalAction==ManagementAction::StocksItemApply;
    if((production && !s->production_page()) || (stocks && !s->stocks_page()) || (display && !s->display_page()) || (!production && !stocks && !display))
      return failTransfer("Mismatched reply family");
    const auto continuationAction=display?ManagementAction::DisplayRead:production?ManagementAction::ProductionInspect:ManagementAction::StocksMenuRead;
    df3d::stocks_pages::Page part;
    const auto copyPage=[&](const auto* page) {
      part={{s->world_epoch(),s->client_id(),page->request_seq()},page->total(),page->offset(),
        {page->bytes()->begin(),page->bytes()->end()}};
    };
    if(display)copyPage(s->display_page());else if(production)copyPage(s->production_page());else copyPage(s->stocks_page());
    if(part.identity.request!=pending_ || s->world_epoch()!=state_.worldEpoch ||
       s->action()!=m::ManagementAction(i.paging?continuationAction:i.logicalAction))return failTransfer("Mismatched reply page");
    if(!i.assembly.append(part))return failTransfer("Invalid reply sequence");
    i.paging=true;
    if(!i.assembly.complete()) {
      ManagementRequest continuation;continuation.action=continuationAction;
      if(display) {
        continuation.displayReplyRequest=pending_;continuation.displayReplyOffset=i.assembly.nextOffset();
      } else if(production) {
        continuation.productionReplyRequest=pending_;continuation.productionReplyOffset=i.assembly.nextOffset();
      } else {
        continuation.stocksMenu.pageRequest=pending_;continuation.stocksMenu.pageOffset=i.assembly.nextOffset();
      }
      flatbuffers::FlatBufferBuilder command;
      detail::management::encodeRequest(command,continuation,clientId_,seq_+1,state_.worldEpoch);
      if(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(command.GetBufferPointer())) ||
         !i.channel->push(command.GetBufferPointer(),command.GetSize()))return failTransfer("Reply continuation unavailable");
      i.transportSeq=++seq_;return false;
    }
    i.assembled=std::move(*i.assembly.take());
    flatbuffers::Verifier complete(i.assembled.data(),i.assembled.size());
    if(!complete.VerifyBuffer<m::ManagementState>(nullptr))return failTransfer("Malformed complete reply");
    s=flatbuffers::GetRoot<m::ManagementState>(i.assembled.data());
    if(s->stocks_page() || s->production_page() || s->display_page() || m::validateManagementState(*s) || s->client_id()!=clientId_ || s->world_epoch()!=state_.worldEpoch ||
       s->request_seq()!=pending_ || s->action()!=m::ManagementAction(i.logicalAction) ||
       (display?!s->display():production?!s->production():!s->stocks_menu()))return failTransfer("Mismatched complete reply");
    i.paging=false;
  }else if(i.paging) {
    if(s->request_seq()!=i.transportSeq)return false;
    return failTransfer("Reply capture unavailable");
  }
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
  if (!wm::isRuntimeAction(r.action)) {
    error_ = "Retired management action";
    return 0;
  }
  if (pending_) {
    error_ = "Wait for the current management request";
    return 0;
  }
  if (r.action != ManagementAction::Catalog && (!state_.worldEpoch || !catalogReady_)) {
    error_ = "Refresh the management catalog first";
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
    error_ = "Management queue full";
    return 0;
  }
  pending_ = ++seq_;
  impl_->transportSeq=pending_;impl_->logicalAction=r.action;impl_->paging=false;impl_->assembled.clear();
  impl_->assembly.begin({state_.worldEpoch,clientId_,pending_});
  state_.requestSeq = pending_;
  state_.status = ManagementStatus::Pending;
  error_.clear();
  return seq_;
#else
  return 0;
#endif
}
}  // namespace wm
