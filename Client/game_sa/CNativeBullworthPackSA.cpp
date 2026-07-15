/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CNativeBullworthPackSA.cpp
 *  PURPOSE:     Trusted Bullworth native world-pack policy
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CNativeBullworthPackSA.h"
#include "CNativeWorldPackSA.h"

namespace
{
    constexpr SNativeTxdPoolProfileSA BULLWORTH_TXD_POOL_PROFILES[] = {
        {"hoodlum-raw", "standalone-3607", 3607, 3606, -1, {true}},
        {"mta-programdata",
         "mta-runtime-3608",
         3608,
         3607,
         3607,
         {true, 0x01, 0x00000000, 0, 0xFFFF, 0xEA5A8E45, 0xFFFF, 0xFFFF, 0xFFFF, 0x00, 4, 13153, 5, 0}},
    };

    constexpr SNativeWorldPackPolicySA BULLWORTH_POLICY = {
        "bullworth",
        "Bullworth",
        "[NativeBW]",
        "MTA_NATIVE_BW_MODEL_STORES",
        "MTA\\data\\extended-world\\bullworth",
        "native-world.json",
        4096,
        1048576,
        131072,
        4096,
        8192,
        19999,
        2000,
        1000,
        10000,
        5000,
        252,
        255,
        191,
        256,
        6,
        {13984, 69, 160},
        {15000, 160, 200},
        BULLWORTH_TXD_POOL_PROFILES,
        static_cast<unsigned int>(std::size(BULLWORTH_TXD_POOL_PROFILES)),
    };
}  // namespace

const SNativeWorldPackPolicySA& GetNativeBullworthPackPolicy()
{
    return BULLWORTH_POLICY;
}
