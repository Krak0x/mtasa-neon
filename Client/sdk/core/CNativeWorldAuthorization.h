/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        sdk/core/CNativeWorldAuthorization.h
 *  PURPOSE:     Inert native-world startup authorization value types
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#pragma once

#include <array>
#include <string>

struct SNativeWorldStartupAuthorization
{
    bool                          present{};
    unsigned char                 wireVersion{};
    unsigned char                 startupMode{};
    unsigned char                 policy{};
    unsigned char                 packFormat{};
    std::array<unsigned char, 32> serverIdDigest{};
    std::array<unsigned char, 4>  serverIpv4{};
    unsigned short                serverPort{};
    unsigned short                resourceNetId{};
    unsigned int                  resourceStartCounter{};
    unsigned short                bitstreamVersion{};
    unsigned long long            connectionGeneration{};
    unsigned long long            authorizationEpoch{};
    std::string                   resourceName;
};

struct SNativeWorldAuthorizationPublication
{
    bool        success{};
    std::string offerId;
    std::string contentId;
};

struct SNativeWorldAuthorizationRecordResult
{
    bool               success{};
    bool               found{};
    bool               idempotent{};
    bool               attached{};
    bool               publicationAmbiguous{};
    unsigned long long issuedAt{};
    unsigned long long expiresAt{};
    std::string        ticketId;
    std::string        diagnostic;
    std::string        error;
};
