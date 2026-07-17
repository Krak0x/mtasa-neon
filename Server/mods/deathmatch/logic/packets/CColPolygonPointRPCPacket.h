/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        mods/deathmatch/logic/packets/CColPolygonPointRPCPacket.h
 *  PURPOSE:     Version-aware colpolygon point RPC packet class
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#pragma once

#include "CPacket.h"
#include <CVector2D.h>
#include <optional>

class CColPolygon;

class CColPolygonPointRPCPacket final : public CPacket
{
public:
    enum class Action
    {
        Update,
        Add,
    };

    CColPolygonPointRPCPacket(const CColPolygon& polygon, Action action, const CVector2D& point, std::optional<unsigned int> pointIndex = std::nullopt);

    ePacketID     GetPacketID() const { return PACKET_ID_LUA_ELEMENT_RPC; }
    unsigned long GetFlags() const { return PACKET_HIGH_PRIORITY | PACKET_RELIABLE | PACKET_SEQUENCED; }

    bool Write(NetBitStreamInterface& bitStream) const;

private:
    ElementID                   m_PolygonId;
    Action                      m_Action;
    CVector2D                   m_Point;
    std::optional<unsigned int> m_PointIndex;
};
