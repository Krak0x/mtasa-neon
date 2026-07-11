/*****************************************************************************
 *
 *  PROJECT:     MTA Neon
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CWorldSectorCodeMover.cpp
 *  PURPOSE:     Minimal Fastman92 WorldSectors bytecode planner
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CWorldSectorCodeMover.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <utility>

namespace
{
    constexpr std::uint8_t OPCODE_END = 0x00;
    constexpr std::uint8_t OPCODE_LITERAL = 0x01;
    constexpr std::uint8_t OPCODE_COPY_ADDRESS = 0x02;
    constexpr std::uint8_t OPCODE_RELATIVE_ADDRESS = 0x03;
    constexpr std::uint8_t OPCODE_VARIABLE = 0x05;

    bool ReadUint32(const std::uint8_t*& cursor, const std::uint8_t* end, std::uint32_t& value)
    {
        if (static_cast<std::size_t>(end - cursor) < sizeof(value))
            return false;

        std::memcpy(&value, cursor, sizeof(value));
        cursor += sizeof(value);
        return true;
    }
}

CWorldSectorCodeMover::CWorldSectorCodeMover(std::uintptr_t movedCodeBase, std::size_t capacity, SourceReader sourceReader)
    : m_movedCodeBase(movedCodeBase), m_capacity(capacity), m_sourceReader(std::move(sourceReader))
{
}

void CWorldSectorCodeMover::SetVariable(std::string name, std::uint32_t value)
{
    m_variables.insert_or_assign(std::move(name), value);
}

bool CWorldSectorCodeMover::Prepare(std::uintptr_t sourceAddress, std::size_t originalSize, const std::uint8_t* bytecode,
                                    std::size_t bytecodeSize, std::uintptr_t continueAt)
{
    if (!m_error.empty())
        return false;
    if (originalSize < 5)
        return Fail("A relocated source instruction must be at least five bytes");

    SRelocation relocation;
    relocation.sourceAddress = sourceAddress;
    relocation.movedAddress = m_movedCodeBase + m_movedCodeSize;
    relocation.expectedSource.resize(originalSize);
    if (!m_sourceReader(sourceAddress, relocation.expectedSource.data(), originalSize))
        return Fail("Could not read the original GTA instruction");

    const std::uint8_t* cursor = bytecode;
    const std::uint8_t* end = bytecode + bytecodeSize;
    bool                terminated = false;
    while (cursor < end && !terminated)
    {
        const std::uint8_t opcode = *cursor++;
        switch (opcode)
        {
            case OPCODE_END:
                terminated = true;
                break;

            case OPCODE_LITERAL:
            {
                if (cursor == end)
                    return Fail("Truncated literal opcode");
                const std::size_t size = *cursor++;
                if (static_cast<std::size_t>(end - cursor) < size || !Emit(relocation, cursor, size))
                    return Fail("Invalid literal opcode");
                cursor += size;
                break;
            }

            case OPCODE_COPY_ADDRESS:
            {
                if (cursor == end)
                    return Fail("Truncated copy-address opcode");
                const std::size_t size = *cursor++;
                std::uint32_t    address{};
                if (!ReadUint32(cursor, end, address))
                    return Fail("Truncated copy-address operand");
                std::vector<std::uint8_t> copiedBytes(size);
                if (!m_sourceReader(address, copiedBytes.data(), size) || !Emit(relocation, copiedBytes.data(), size))
                    return Fail("Could not copy bytes from a GTA address");
                break;
            }

            case OPCODE_RELATIVE_ADDRESS:
            {
                std::uint32_t target{};
                if (!ReadUint32(cursor, end, target) || !EmitRelative32(relocation, target))
                    return Fail("Invalid relative-address opcode");
                break;
            }

            case OPCODE_VARIABLE:
            {
                if (cursor == end)
                    return Fail("Truncated variable opcode");
                const std::size_t size = *cursor++;
                if (size == 0 || size > sizeof(std::uint32_t))
                    return Fail("Invalid WorldSectors variable size");

                const std::uint8_t* nameEnd = std::find(cursor, end, 0);
                if (nameEnd == end)
                    return Fail("Unterminated WorldSectors variable name");
                const std::string name(reinterpret_cast<const char*>(cursor), static_cast<std::size_t>(nameEnd - cursor));
                cursor = nameEnd + 1;

                const auto variable = m_variables.find(name);
                if (variable == m_variables.end() || !Emit(relocation, &variable->second, size))
                    return Fail("Unknown or invalid WorldSectors variable: " + name);
                break;
            }

            default:
                return Fail("Unsupported WorldSectors bytecode opcode");
        }
    }

    if (!terminated || cursor != end)
        return Fail("WorldSectors bytecode is truncated or has trailing data");
    if (continueAt != 0)
    {
        const std::uint8_t jumpOpcode = 0xE9;
        if (!Emit(relocation, &jumpOpcode, sizeof(jumpOpcode)) || !EmitRelative32(relocation, continueAt))
            return Fail("The continuation jump is out of range");
    }

    const std::uint32_t nops = 0x90909090;
    if (!Emit(relocation, &nops, sizeof(nops)))
        return Fail("The moved-code arena is full");

    relocation.sourceJump.assign(originalSize, 0x90);
    relocation.sourceJump[0] = 0xE9;
    const std::int64_t sourceDisplacement = static_cast<std::int64_t>(relocation.movedAddress) -
                                            static_cast<std::int64_t>(sourceAddress + 5);
    if (sourceDisplacement < std::numeric_limits<std::int32_t>::min() || sourceDisplacement > std::numeric_limits<std::int32_t>::max())
        return Fail("The source jump is out of range");
    const std::int32_t sourceRelative = static_cast<std::int32_t>(sourceDisplacement);
    std::memcpy(relocation.sourceJump.data() + 1, &sourceRelative, sizeof(sourceRelative));

    m_movedCodeSize += relocation.movedCode.size();
    m_relocations.push_back(std::move(relocation));
    return true;
}

bool CWorldSectorCodeMover::Commit(const MemoryWriter& memoryWriter)
{
    if (!m_error.empty() || m_relocations.empty())
        return false;

    // Complete the read-only preflight before writing either the code arena or
    // a GTA entry point. This prevents a version mismatch from leaving a
    // partially redirected executable.
    for (const SRelocation& relocation : m_relocations)
    {
        std::vector<std::uint8_t> currentSource(relocation.expectedSource.size());
        if (!m_sourceReader(relocation.sourceAddress, currentSource.data(), currentSource.size()) ||
            currentSource != relocation.expectedSource)
        {
            return Fail("A GTA instruction changed between prepare and commit");
        }
    }

    for (const SRelocation& relocation : m_relocations)
    {
        if (!memoryWriter(relocation.movedAddress, relocation.movedCode.data(), relocation.movedCode.size()))
            return Fail("Could not write the moved WorldSectors code");
    }

    for (const SRelocation& relocation : m_relocations)
    {
        if (!memoryWriter(relocation.sourceAddress, relocation.sourceJump.data(), relocation.sourceJump.size()))
            return Fail("Could not redirect a WorldSectors instruction");
    }
    return true;
}

bool CWorldSectorCodeMover::Emit(SRelocation& relocation, const void* bytes, std::size_t size)
{
    if (m_movedCodeSize + relocation.movedCode.size() + size > m_capacity)
        return false;
    const auto* source = static_cast<const std::uint8_t*>(bytes);
    relocation.movedCode.insert(relocation.movedCode.end(), source, source + size);
    return true;
}

bool CWorldSectorCodeMover::EmitRelative32(SRelocation& relocation, std::uintptr_t target)
{
    const std::uintptr_t operandEnd = relocation.movedAddress + relocation.movedCode.size() + sizeof(std::int32_t);
    const std::int64_t displacement = static_cast<std::int64_t>(target) - static_cast<std::int64_t>(operandEnd);
    if (displacement < std::numeric_limits<std::int32_t>::min() || displacement > std::numeric_limits<std::int32_t>::max())
        return false;
    const std::int32_t relative = static_cast<std::int32_t>(displacement);
    return Emit(relocation, &relative, sizeof(relative));
}

bool CWorldSectorCodeMover::Fail(std::string error)
{
    m_error = std::move(error);
    return false;
}
