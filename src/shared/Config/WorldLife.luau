--!strict
return {
	-- APPROX owner-requested lively-world adaptation: refugee visuals on shelling also run in
	-- skirmishes, whose original events.on is false. Truck penalties still require events.on.
	REFUGEE_COLUMNS = true,
	REFUGEE_PACKET_ACTORS = 256, -- Port network/rendering cap, not an original gameplay value.
}
