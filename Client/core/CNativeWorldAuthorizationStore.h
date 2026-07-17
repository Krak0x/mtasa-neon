/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        core/CNativeWorldAuthorizationStore.h
 *  PURPOSE:     DPAPI-backed inert native-world authorization store
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#pragma once

#include <core/CNativeWorldAuthorization.h>

namespace NativeWorldAuthorizationStore
{
    SNativeWorldAuthorizationRecordResult Persist(const SNativeWorldStartupAuthorization&     authorization,
                                                  const SNativeWorldAuthorizationPublication& publication);
    SNativeWorldAuthorizationRecordResult Inspect();
    SNativeWorldAuthorizationRecordResult Clear();
    SNativeWorldAuthorizationRecordResult Revoke(const SNativeWorldStartupAuthorization& authorization, const std::string& contentId);
}
