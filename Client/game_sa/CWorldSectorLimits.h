/*****************************************************************************
 *
 *  PROJECT:     MTA Neon
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CWorldSectorLimits.h
 *  PURPOSE:     Extended GTA SA world-sector installation
 *
 *****************************************************************************/

#pragma once

bool InstallExtendedWorldSectorPatch();
void* GetActiveWorldSectorArray();
int   GetActiveWorldSectorCount();
int   GetActiveWorldSectorDimension();
void  EnsureVanillaWorldSectorsMigrated();
