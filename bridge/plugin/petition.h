#pragma once
#include "management_data.h"
#include "mirror_generated.h"
#include <cstdint>
#include <string>
namespace df3d_session {
struct PetitionInfo {
 int32_t id=-1,guildhallValue=0,grandGuildhallValue=0;
 uint64_t receipt=0,revision=0;
 bool canReview=false,canRespond=false,canClose=false,hasAgreement=false;
 std::string reason;
 df3d_management::AgreementInfo agreement;
};
const PetitionInfo& observePetition(uint64_t epoch,bool valid,bool busy);
bool actPetition(uint8_t action,uint64_t epoch,int32_t id,uint64_t receipt,std::string& error);
int petitionResult(std::string& message);
void resetPetition();
flatbuffers::Offset<df3d::mirror::PetitionReviewState> serializePetition(flatbuffers::FlatBufferBuilder& b,const PetitionInfo& info);
}
