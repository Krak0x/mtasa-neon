#!/usr/bin/env python3
"""Source-level guards for the publish-only static-world-v3 runtime boundary."""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[3]


class NativeWorldV3RuntimeContractTest(unittest.TestCase):
    def test_v3_returns_before_legacy_registrar_policy_state(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CNativeWorldPackSA.cpp").read_text(encoding="utf-8")
        publication = source[source.index("SNativeWorldTransportPublishResult CNativeWorldPackManagerSA::PublishTransportOffer") :]
        route = publication.index("offer.format == STATIC_WORLD_V3_FORMAT")
        legacy_policy = publication.index("FindNativeWorldPackPolicy(offer.format)")
        self.assertLess(route, legacy_policy)
        v3 = source[source.index("PublishStaticWorldV3TransportOffer") : source.index("}  // namespace", source.index("PublishStaticWorldV3TransportOffer"))]
        self.assertNotIn("g_policy =", v3)
        self.assertNotIn("g_pack =", v3)
        self.assertNotIn("AcquireExistingNativeWorldCacheLease", v3)
        self.assertIn("static-world-v3-transport-envelope-v1", source)

    def test_v3_spatial_ownership_and_hash_guards_are_derived(self) -> None:
        source = (REPOSITORY / "Client/game_sa/CNativeWorldPackSA.cpp").read_text(encoding="utf-8")
        self.assertIn("colModelIds", source)
        self.assertIn("iplModelIds", source)
        self.assertIn("generated model is shared by multiple spatial IPLs", source)
        self.assertIn("COL model is not placed by its paired spatial IPL", source)
        self.assertIn("StaticWorldV3UppercaseKey", source)
        self.assertIn("generated model names collide in GTA uppercase key space", source)
        self.assertIn("generated TXD names collide in GTA uppercase key space", source)
        self.assertIn("ValidateStaticWorldV3Cols(const SStaticWorldV3Ide& ide, SStaticWorldV3Inventory& inventory", source)

    def test_v3_is_protocol_capability_gated_and_has_no_startup_form(self) -> None:
        bitstream = (REPOSITORY / "Shared/sdk/net/bitstream.h").read_text(encoding="utf-8")
        server = (REPOSITORY / "Server/mods/deathmatch/logic/CResource.cpp").read_text(encoding="utf-8")
        packet = (REPOSITORY / "Server/mods/deathmatch/logic/packets/CResourceStartPacket.cpp").read_text(encoding="utf-8")
        authorization = (REPOSITORY / "Client/sdk/core/CNativeWorldAuthorization.h").read_text(encoding="utf-8")
        meta = (REPOSITORY / "test-resources/native-world-v3-transport-test/meta.xml").read_text(encoding="utf-8")
        self.assertIn("NativeWorldStaticWorldV3Transport", bitstream)
        self.assertIn("staticWorldV3PublishOnly", server)
        self.assertIn("!startupAttribute", server)
        self.assertIn("NativeWorldStaticWorldV3Transport", packet)
        self.assertNotIn("NATIVE_WORLD_STATIC_V3", authorization)
        self.assertNotIn("startup=", meta)

    def test_v3_payload_and_disk_accounting_use_separate_u64_budgets(self) -> None:
        cache = (REPOSITORY / "Client/game_sa/CNativeWorldCacheSA.cpp").read_text(encoding="utf-8")
        client = (REPOSITORY / "Client/mods/deathmatch/logic/CResource.cpp").read_text(encoding="utf-8")
        self.assertIn("std::uint64_t payloadBytes", cache)
        self.assertIn("const std::uint64_t requestedDiskBytes", cache)
        self.assertIn("MAX_V3_TOTAL_BYTES - image.bytes", cache)
        self.assertIn("V3_MAXIMUM_MANIFEST_BYTES + V3_MAXIMUM_TOTAL_BYTES", client)
        self.assertIn("v3PayloadBytes = 0", client)
        self.assertGreaterEqual(client.count("V3_MAXIMUM_TOTAL_BYTES - v3PayloadBytes"), 2)


if __name__ == "__main__":
    unittest.main()
