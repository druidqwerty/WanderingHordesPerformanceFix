-- a server save that ran Wandering Hordes Save Trim 1.0.0: its own table (ModData WHSaveTrim: spots, homes)
-- is taken over once and removed. Run after reset_migrate (puts the old table in) + shared + trim files.
T.say("-- server: taking over the 1.0.0 table")
local now = getTimestamp()
check(T.gmd.WHSaveTrim ~= nil, "old table present before the first look")
T.players = { T.player("erin", 300, 300) }
T.tick(30, 100)
local own = T.gmd.WHPerfFix
check(T.gmd.WHSaveTrim == nil, "old table removed")
check(own and own.spots.zed and own.spots.zed.x == 1800 and own.spots.zed.t == now - 3600, "offline spot taken over")
check(own.homes.zed and own.homes.zed.y == 1850, "join spot taken over")
check(own.spots.erin and own.spots.erin.x == 300, "current player recorded as usual")
check(own.spots.bad == nil, "a broken entry is not taken over")
check(T.logged("took over 2 player spot%(s%) from Wandering Hordes Save Trim 1.0.0") ~= nil, "take-over logged")
local g = T.fill(0, 0, 1999, 1999, 1)
WHPerfFix.Trim.passNow()
check(T.untilPass(1000), "pass after the take-over")
check(T.has(1800, 1800) and T.has(300, 300) and not T.has(1000, 1000), "the old offline spot is kept around")
