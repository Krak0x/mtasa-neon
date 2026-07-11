/*****************************************************************************
 *
 *  PROJECT:     MTA Neon
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CWorldSectorCodeMover.h
 *  PURPOSE:     Minimal Fastman92 WorldSectors bytecode planner
 *
 *****************************************************************************/

#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

class CWorldSectorCodeMover
{
public:
    using SourceReader = std::function<bool(std::uintptr_t, void*, std::size_t)>;
    using MemoryWriter = std::function<bool(std::uintptr_t, const void*, std::size_t)>;

    struct SRelocation
    {
        std::uintptr_t   sourceAddress{};
        std::vector<std::uint8_t> expectedSource;
        std::uintptr_t   movedAddress{};
        std::vector<std::uint8_t> movedCode;
        std::vector<std::uint8_t> sourceJump;
    };

    explicit CWorldSectorCodeMover(std::uintptr_t movedCodeBase, std::size_t capacity, SourceReader sourceReader);

    void SetVariable(std::string name, std::uint32_t value);

    bool Prepare(std::uintptr_t sourceAddress, std::size_t originalSize, const std::uint8_t* bytecode, std::size_t bytecodeSize,
                 std::uintptr_t continueAt);
    bool Commit(const MemoryWriter& memoryWriter);

    const std::vector<SRelocation>& GetRelocations() const { return m_relocations; }
    std::size_t                     GetMovedCodeSize() const { return m_movedCodeSize; }
    const std::string&              GetError() const { return m_error; }

private:
    bool Emit(SRelocation& relocation, const void* bytes, std::size_t size);
    bool EmitRelative32(SRelocation& relocation, std::uintptr_t target);
    bool Fail(std::string error);

    std::uintptr_t                                m_movedCodeBase{};
    std::size_t                                   m_capacity{};
    std::size_t                                   m_movedCodeSize{};
    SourceReader                                  m_sourceReader;
    std::unordered_map<std::string, std::uint32_t> m_variables;
    std::vector<SRelocation>                      m_relocations;
    std::string                                   m_error;
};
