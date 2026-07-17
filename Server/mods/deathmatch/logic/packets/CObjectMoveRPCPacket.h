/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        mods/deathmatch/logic/packets/CObjectMoveRPCPacket.h
 *  PURPOSE:     Version-aware object movement RPC packet class
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#pragma once

#include "CPacket.h"
#include <CPositionRotationAnimation.h>

class CObject;

class CObjectMoveRPCPacket final : public CPacket
{
public:
    CObjectMoveRPCPacket(const CObject& object, const CPositionRotationAnimation& animation);

    ePacketID     GetPacketID() const { return PACKET_ID_LUA_ELEMENT_RPC; }
    unsigned long GetFlags() const { return PACKET_HIGH_PRIORITY | PACKET_RELIABLE | PACKET_SEQUENCED; }

    bool Write(NetBitStreamInterface& bitStream) const;

private:
    ElementID                  m_ObjectId;
    CPositionRotationAnimation m_Animation;
};
