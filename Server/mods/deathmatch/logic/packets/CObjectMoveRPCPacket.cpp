/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        mods/deathmatch/logic/packets/CObjectMoveRPCPacket.cpp
 *  PURPOSE:     Version-aware object movement RPC packet class
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CObjectMoveRPCPacket.h"
#include "CObject.h"
#include <net/rpc_enums.h>

CObjectMoveRPCPacket::CObjectMoveRPCPacket(const CObject& object, const CPositionRotationAnimation& animation)
    : m_ObjectId(object.GetID()), m_Animation(animation)
{
}

bool CObjectMoveRPCPacket::Write(NetBitStreamInterface& bitStream) const
{
    bitStream.Write(static_cast<unsigned char>(MOVE_OBJECT));
    bitStream.Write(m_ObjectId);

    // CPlayerManager invokes Write once per recipient bitstream version. Keep
    // the animation semantic until here so its positions use that exact wire
    // format instead of the version-zero format of an intermediate stream.
    m_Animation.ToBitStream(bitStream, false);
    return true;
}
