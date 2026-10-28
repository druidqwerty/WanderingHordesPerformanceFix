-- multiplayer client: WH's scanners fill the client's own in-memory copy around the local player;
-- the add-on trims it around the local players only, and never touches getOnlinePlayers or its own table
T.say("-- client")
check(T.logged("2.0.0 loaded %(client%)") ~= nil, "load line names the side")
local g = T.fill(0, 0, 1999, 1999, 3)
T.local_players = { T.player("me", 500, 500) }
T.tick(100, 100)        -- 10 s: first pass waits 15 s
check(WHPerfFix.Trim.status().passes == 0 and not WHPerfFix.Trim.status().running, "first pass waits 15 s")
check(T.untilPass(400), "client pass")
check(T.count(g) == 81 * 81, "client keeps the local player's square (got " .. T.count(g) .. ")")
check(T.has(500, 500) and T.has(100, 100) and T.has(909, 909) and not T.has(910, 500), "client square")
check(T.gmd.WHPerfFix == nil, "no own table on a client")
check(WHPerfFix.Trim.status().side == "client", "status side")
-- the spot where the client joined stays kept while the local player travels
T.local_players[1].x, T.local_players[1].y = 1500, 1500
T.fill(0, 0, 1999, 1999, 3)
WHPerfFix.Trim.passNow()
check(T.untilPass(400), "client pass during a trip")
check(T.has(500, 500) and T.has(1500, 1500) and not T.has(1000, 200), "client: join spot and current square kept")
check(WHPerfFix.Trim.status().last.homes == 1 and T.gmd.WHPerfFix == nil, "client: 1 join spot, still no own table")
-- no local player (e.g. dead, menu): nothing removed
T.local_players = {}
T.fill(0, 0, 1999, 1999, 3)
WHPerfFix.Trim.passNow()
T.tick(200, 100)
check(T.count(g) == 40000, "no local player: nothing removed")
