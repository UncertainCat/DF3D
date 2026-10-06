#include "doctest.h"
#include "../bridge/plugin/room_undo.h"
#include <stdexcept>
#include <type_traits>

namespace {
using namespace df3d_area;
static_assert(!std::is_copy_constructible_v<RoomUndoReceipt>);
static_assert(!std::is_copy_assignable_v<RoomUndoReceipt>);
static_assert(!std::is_move_constructible_v<RoomUndoReceipt>);
static_assert(!std::is_move_assignable_v<RoomUndoReceipt>);
constexpr RoomUndoScope scope{31,47,59};
std::vector<RoomUndoTarget> targets(int count=3) {
  std::vector<RoomUndoTarget> out;
  for(int i=0;i<count;++i)out.push_back({100+i,uint64_t(200+i)});
  return out;
}
uint64_t revision(int32_t id) {return uint64_t(id+100);}
}

TEST_CASE("room Undo retains the whole created set and consumes authority before deletion") {
  RoomUndoReceipt receipt;
  const auto installed=receipt.replace(scope,targets(129));
  REQUIRE(installed.accepted);REQUIRE(installed.token!=0);
  std::vector<int32_t> observed,removed;
  const auto result=receipt.undo(scope,installed.token,[&](int32_t id) {
    CHECK(removed.empty());observed.push_back(id);return revision(id);
  },[&](int32_t id) {
    CHECK(observed.size()==129);
    CHECK_FALSE(receipt.matches(scope,installed.token));
    removed.push_back(id);return true;
  });
  CHECK(result.status==RoomUndoStatus::Completed);CHECK(result.removed==129);
  REQUIRE(removed.size()==129);
  for(int i=0;i<129;++i)CHECK(removed[i]==100+i);
  const auto replay=receipt.undo(scope,installed.token,[](int32_t) {
    FAIL("consumed receipt must not observe targets");return uint64_t(0);
  },[](int32_t) {FAIL("consumed receipt must not delete targets");return true;});
  CHECK(replay.status==RoomUndoStatus::Rejected);CHECK(replay.removed==0);
}

TEST_CASE("room Undo refuses foreign scope and token without discarding the current receipt") {
  RoomUndoReceipt receipt;
  const auto installed=receipt.replace(scope,targets());REQUIRE(installed.accepted);
  for(auto request:std::vector<RoomUndoScope>{{0,47,59},{32,47,59},{31,0,59},
      {31,48,59},{31,47,0},{31,47,60}}) {
    const auto result=receipt.undo(request,installed.token,[](int32_t) {
      FAIL("foreign request must not observe targets");return uint64_t(0);
    },[](int32_t) {FAIL("foreign request must not remove targets");return true;});
    CHECK(result.status==RoomUndoStatus::Rejected);
    CHECK(receipt.matches(scope,installed.token));
  }
  for(auto token:{uint64_t(0),installed.token+1}) {
    CHECK(receipt.undo(scope,token,revision,[](int32_t) {
      FAIL("wrong token must not remove targets");return true;
    }).status==RoomUndoStatus::Rejected);
    CHECK(receipt.matches(scope,installed.token));
  }
}

TEST_CASE("room Undo preflights every revision before deleting any room") {
  for(int failing=100;failing<103;++failing)for(int mode=0;mode<3;++mode) {
    RoomUndoReceipt receipt;
    const auto installed=receipt.replace(scope,targets());
    int removals=0;
    const auto result=receipt.undo(scope,installed.token,[&](int32_t id) {
      if(id!=failing)return revision(id);
      if(mode==2)throw std::runtime_error("injected observation failure");
      return mode==0?uint64_t(0):revision(id)+1;
    },[&](int32_t) {++removals;return true;});
    CHECK(result.status==RoomUndoStatus::Stale);CHECK(result.removed==0);
    CHECK(removals==0);CHECK_FALSE(receipt.matches(scope,installed.token));
  }
}

TEST_CASE("uncertain room Undo stops once and cannot replay a partially removed set") {
  for(int failing=100;failing<103;++failing)for(bool throws:{false,true}) {
    RoomUndoReceipt receipt;
    const auto installed=receipt.replace(scope,targets());
    std::vector<int32_t> attempts;
    const auto result=receipt.undo(scope,installed.token,revision,[&](int32_t id) {
      attempts.push_back(id); // deletion may already have occurred before failure
      CHECK_FALSE(receipt.matches(scope,installed.token));
      if(id!=failing)return true;
      if(throws)throw std::runtime_error("injected removal failure");
      return false;
    });
    CHECK(result.status==RoomUndoStatus::Unknown);
    CHECK(result.removed==size_t(failing-100));
    REQUIRE(attempts.size()==size_t(failing-99));CHECK(attempts.back()==failing);
    CHECK(receipt.undo(scope,installed.token,revision,[](int32_t) {
      FAIL("unknown outcome must not replay");return true;
    }).status==RoomUndoStatus::Rejected);
  }
}

TEST_CASE("empty native selections and interaction exit retire older room Undo history") {
  RoomUndoReceipt receipt;
  auto prior=receipt.replace(scope,targets());REQUIRE(prior.accepted);
  // Empty, all-in-use and all-unenclosed native results all have an empty set.
  for(int selection=0;selection<3;++selection) {
    const auto empty=receipt.replace(scope,{});
    CHECK(empty.accepted);CHECK(empty.token==0);
    CHECK_FALSE(receipt.matches(scope,prior.token));CHECK_FALSE(receipt.matches(scope,0));
    auto next=receipt.replace(scope,targets());REQUIRE(next.accepted);
    CHECK(next.token>prior.token);prior=next;
  }
  receipt.clear();CHECK_FALSE(receipt.matches(scope,prior.token));
  const auto next=receipt.replace(scope,targets());REQUIRE(next.accepted);
  CHECK(next.token>prior.token);
}

TEST_CASE("invalid replacement cannot retain older room Undo authority") {
  const std::vector<std::vector<RoomUndoTarget>> invalid{
    {{-1,200}},{{100,0}},{{100,uint64_t(INT64_MAX)+1}},
    {{100,200},{100,201}},{{101,201},{100,200}}};
  RoomUndoReceipt receipt;
  for(auto replacement:invalid) {
    const auto prior=receipt.replace(scope,targets());REQUIRE(prior.accepted);
    const auto result=receipt.replace(scope,std::move(replacement));
    CHECK_FALSE(result.accepted);CHECK(result.token==0);
    CHECK_FALSE(receipt.matches(scope,prior.token));
  }
  for(auto invalidScope:std::vector<RoomUndoScope>{{0,47,59},{31,0,59},{31,47,0}}) {
    const auto prior=receipt.replace(scope,targets());REQUIRE(prior.accepted);
    CHECK_FALSE(receipt.replace(invalidScope,targets()).accepted);
    CHECK_FALSE(receipt.matches(scope,prior.token));
  }
}

TEST_CASE("late Done only retires the matching room interaction") {
  RoomUndoReceipt receipt;
  const auto installed=receipt.replace(scope,targets());REQUIRE(installed.accepted);
  for(auto other:std::vector<RoomUndoScope>{{32,47,59},{31,48,59},{31,47,60},{0,0,0}}) {
    receipt.finish(other);CHECK(receipt.matches(scope,installed.token));
  }
  receipt.finish(scope);CHECK_FALSE(receipt.matches(scope,installed.token));
  const RoomUndoScope next{scope.epoch,scope.client,scope.interaction+1};
  const auto replacement=receipt.replace(next,targets());REQUIRE(replacement.accepted);
  receipt.finish(scope);CHECK(receipt.matches(next,replacement.token));
  receipt.finish(next);CHECK_FALSE(receipt.matches(next,replacement.token));
}
