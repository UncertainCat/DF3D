#pragma once
#include <filesystem>
#include <optional>

namespace df3d_session {
struct SavedWorldStamp {
    uintmax_t bytes;
    std::filesystem::file_time_type modified;
};
inline std::optional<SavedWorldStamp> savedWorldStamp(const std::filesystem::path& directory) {
    std::error_code error;
    const auto file=directory/"world.sav";
    if(!std::filesystem::is_regular_file(file,error) || error)return std::nullopt;
    const auto bytes=std::filesystem::file_size(file,error);
    if(error || !bytes)return std::nullopt;
    const auto modified=std::filesystem::last_write_time(file,error);
    if(error)return std::nullopt;
    return SavedWorldStamp{bytes,modified};
}
// A pre-existing file cannot establish an overwrite. Native writer progress and
// exact destination/timeline identity are checked separately by the session.
inline bool savedWorldChanged(const std::optional<SavedWorldStamp>& before,
                              const std::optional<SavedWorldStamp>& after) {
    return before && after && (before->bytes!=after->bytes || before->modified!=after->modified);
}
}
