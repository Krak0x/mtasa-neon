/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        mods/deathmatch/logic/packets/CColPolygonPointRPCPacket.cpp
 *  PURPOSE:     Version-aware colpolygon point RPC packet class
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CColPolygonPointRPCPacket.h"
#include "CColPolygon.h"
#include <net/rpc_enums.h>
#include <net/SyncStructures.h>

CColPolygonPointRPCPacket::CColPolygonPointRPCPacket(const CColPolygon& polygon, Action action, const CVector2D& point, std::optional<unsigned int> pointIndex)
    : m_PolygonId(polygon.GetID()), m_Action(action), m_Point(point), m_PointIndex(pointIndex)
{
}

bool CColPolygonPointRPCPacket::Write(NetBitStreamInterface& bitStream) const
{
    if (m_Action == Action::Update && !m_PointIndex)
        return false;

    const unsigned char actionId = m_Action == Action::Update ? UPDATE_COLPOLYGON_POINT : ADD_COLPOLYGON_POINT;
    bitStream.Write(actionId);
    bitStream.Write(m_PolygonId);

    // The point width is negotiated per recipient. Serializing it directly
    // into this destination preserves both legacy and extended-world clients.
    SPosition2DSync position(false);
    position.data.vecPosition = m_Point;
    bitStream.Write(&position);

    if (m_PointIndex)
        bitStream.Write(*m_PointIndex);

    return true;
}
