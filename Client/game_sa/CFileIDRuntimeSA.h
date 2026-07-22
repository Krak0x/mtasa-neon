/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CFileIDRuntimeSA.h
 *  PURPOSE:     Validated runtime view of GTA SA's FileID namespace
 *
 *****************************************************************************/

#pragma once

#include <game/CGame.h>
#include <game/CStreaming.h>

#include <cstdint>
#include <string>

class CFileIDRuntimeSA
{
public:
    bool CaptureStockLayout(eGameVersion gameVersion, std::string& error);
    bool InstallStockRelocation(std::string& error);

    const SFileIDLayout& GetLayout() const { return m_layout; }
    void*                GetModelInfoArray() const { return m_modelInfoArray; }
    CStreamingInfo*      GetStreamingInfoArray() const { return m_streamingInfoArray; }

    // GTA stores these two IDs in byte-sized legacy fields. The extended
    // accessors keep the ABI-sized structures intact while preserving the full
    // store index in process-lifetime side storage.
    static std::int32_t GetColModelSlot(const void* colModel);
    static void         SetColModelSlot(void* colModel, std::int32_t slot);
    static std::int32_t GetEntityIplIndex(const void* entity);
    static void         SetEntityIplIndex(void* entity, std::int32_t index);
    static void         ForgetEntityIplIndex(const void* entity);
    static bool         HasStoreExtensionOverflow();

    // The opt-in startup boundary harness creates and destroys real native
    // entities. Preserve the probe's temporary side-table entries without
    // exposing the table representation or affecting normal runtime access.
    static bool BeginStoreExtensionTestSnapshot(std::string& error);
    static bool RestoreStoreExtensionTestSnapshot(std::string& error);

private:
    SFileIDLayout   m_layout{};
    void*           m_modelInfoArray{};
    CStreamingInfo* m_streamingInfoArray{};
    std::uint32_t   m_imageSize{};
    bool            m_relocationPrepared{};
    bool            m_relocationInstalled{};
    bool            m_installStarted{};
};
