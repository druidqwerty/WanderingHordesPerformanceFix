-- single player: the same as WH's own logic (local players); a safehouse is kept too if there is one
T.say("-- single player")
check(T.logged("1.0.0 loaded %(sp%)") ~= nil, "load line names the side")
local g = T.fill(0, 0, 1999, 1999, 3)
T.local_players = { T.player("me", 1500, 1500) }
T.houses = { T.safehouse(100, 100, 5, 5) }
check(T.untilPass(600), "sp pass")
check(T.has(1500, 1500) and T.has(1100, 1100) and not T.has(1090, 1500), "player square kept")
check(T.has(100, 100) and T.has(504, 504) and not T.has(510, 100), "safehouse square kept")
check(T.gmd.WHSaveTrim == nil, "no own table in single player")
local last = WHSaveTrim.status().last
check(last.players == 1 and last.houses == 1 and last.spots == 0 and last.homes == 1, "sp counters")
-- a second local player (split screen) is kept around too
T.local_players[2] = T.player("p2", 100, 1900)
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.untilPass(600)
check(T.has(100, 1900) and T.has(1500, 1500), "both local players kept")
-- a long trip: the spot where the game was loaded (usually the base) stays kept
T.local_players = { T.player("me", 300, 300) }
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.untilPass(600)
check(T.has(300, 300) and T.has(1500, 1500), "sp: load spot kept during a trip")
check(not T.has(1000, 1000) and not T.has(1999, 300), "sp: rest removed")
