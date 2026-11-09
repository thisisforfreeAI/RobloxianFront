--!strict
-- Development switches. The atlas test board only ever runs inside Studio.
return {
	ATLAS_TEST_BOARD = true, -- Phase 1A sprite check (docs/STUDIO_TESTS.md, test 6)
	FORCE_PART_GROUND = false, -- true draws the ground with Parts (orientation reference, test 2)
	OWNERSHIP_PROBE = true, -- K sends an order for enemy units; server must refuse (test 7)
}
