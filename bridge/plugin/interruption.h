#pragma once
#include <cstdint>
#include <string>
namespace df3d_session {
struct InterruptionInfo { uint8_t kind=0;uint64_t receipt=0;uint32_t popupCount=0;bool canAcknowledge=false;std::string text,reason; };
const InterruptionInfo& observeInterruption(uint64_t epoch,bool valid,bool busy);
bool acknowledgeInterruption(uint64_t epoch,uint64_t receipt,std::string& error);
// 0=no pending acknowledgment, 1=pending, 2=verified success, 3=unverified/rejected.
int interruptionResult(std::string& message);
void resetInterruption();
}
