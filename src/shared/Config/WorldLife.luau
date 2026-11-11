--!strict
return {
	HOUSE_FIRES = true, -- Source visual roof fires; optional ignored city/fire data is required.
	FOREST_FIRES = true, -- Source tree fates/fire progression over the matching retained-tree map.
	-- APPROX owner-requested lively-world adaptation: refugee visuals on shelling also run in
	-- skirmishes, whose original events.on is false. Truck penalties still require events.on.
	REFUGEE_COLUMNS = true,
	REFUGEE_PACKET_ACTORS = 256, -- Port network/rendering cap, not an original gameplay value.
}
