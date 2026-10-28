-- server side (dedicated / co-op host's server): online players, remembered spots, safehouses
local GRID = "WH_PassabilityGrid_v2"
T.say("-- server")
check(WHSaveTrim and WHSaveTrim.VERSION == "1.0.0", "loaded, version")
check(T.logged("1.0.0 loaded %(server%)") ~= nil, "load line names the side")

-- Kahlua's pairs(): a snapshot of the keys; a key removed meanwhile comes back with a nil value, a key
-- added meanwhile is not visited, an exhausted iterator keeps returning nil
do
    local t = { [1] = "a", [2] = "b", [3] = "c" }
    local it = pairs(t)
    local seen, nils = 0, 0
    t[4] = "d"
    local k, v = it()
    while k ~= nil do
        seen = seen + 1
        if seen == 1 then
            for kk = 1, 3 do if kk ~= k then t[kk] = nil break end end   -- remove one not yet visited
        end
        if v == nil then nils = nils + 1 end
        k, v = it()
    end
    check(seen == 3 and nils == 1, "pairs snapshot: 3 keys visited, the removed one with nil (seen " .. seen .. ", nils " .. nils .. ")")
    check(it() == nil and it() == nil, "exhausted iterator returns nil")
end

local g, n = T.fill(0, 0, 1999, 1999, 3)     -- 200 x 200 buckets
check(n == 40000, "fill 40000 buckets")
g["junk"] = { 1 }
g[0.5] = "not a table"   -- not a bucket key of the fill

-- nobody online and nothing remembered: never prune
T.tick(400, 100)
check(WHSaveTrim.status().passes == 0, "no pass without anyone to keep around")
check(T.count(g) == 40002, "nothing removed without players")

-- one player: square of 400 tiles around him, nothing else
T.players = { T.player("alice", 1000.5, 1000.5) }
check(T.untilPass(400), "pass 1 finished")
local last = WHSaveTrim.status().last
-- kept buckets: gx, gy in floor(600.5/10)=60 .. floor(1400.5/10)=140 -> 81 x 81
check(T.count(g) == 81 * 81 + 2, "pass 1 keeps 81x81 buckets + the 2 junk entries (got " .. T.count(g) .. ")")
check(last.checked == 40000 and last.removed == 40000 - 6561 and last.kept == 6561, "pass 1 counters")
check(last.ticks >= 100 and last.ticks <= 102, "budget 400 per tick: ~101 ticks (got " .. last.ticks .. ")")
check(T.has(1000, 1000) and T.has(600, 600) and T.has(1409, 1409) and T.has(600, 1409), "inside kept")
check(not T.has(599, 1000) and not T.has(1410, 1000) and not T.has(1000, 599) and not T.has(1000, 1410), "outside removed")
check(g["junk"] ~= nil and g[0.5] == "not a table", "junk entries untouched")
check(T.logged("pass 1: 40000 cells checked, 33439 removed") ~= nil, "first pass with removals is logged")
check(last.keptBytes > 0 and last.removedBytes > last.keptBytes, "size estimate")
check(T.gmd.WHSaveTrim and T.gmd.WHSaveTrim.spots.alice and T.gmd.WHSaveTrim.spots.alice.x == 1000, "alice's spot remembered")
check(T.gmd.WHSaveTrim.homes.alice and T.gmd.WHSaveTrim.homes.alice.y == 1000, "alice's join spot remembered")
check(last.players == 1 and last.homes == 1 and last.spots == 0, "pass 1: 1 player, 1 join spot")

-- interval: the next pass only after IntervalMinutes (default 2)
T.tick(600, 100)
check(WHSaveTrim.status().passes == 1, "no second pass within 1 min")
T.fill(0, 0, 1999, 1999, 3)
check(T.untilPass(1200), "pass 2 after the interval")
check(T.count(g) == 6561 + 2, "pass 2 trims the refill again")
check(T.logged("pass 2:") == nil, "later passes are quiet without Log")

-- alice logs off, bob comes: alice's spot stays kept
T.players = { T.player("bob", 1800, 200) }
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 3")
last = WHSaveTrim.status().last
check(T.has(1000, 1000) and T.has(1400, 1400), "offline alice's spot kept")
check(T.has(1800, 200) and T.has(1999, 0) and T.has(1400, 599), "bob's square kept")
check(not T.has(300, 300) and not T.has(1999, 1999), "rest removed")
check(last.players == 1 and last.spots == 1 and last.homes == 2, "1 player + 1 offline spot + 2 join spots")
check(T.gmd.WHSaveTrim.homes.bob and T.gmd.WHSaveTrim.homes.bob.x == 1800, "bob's join spot remembered")

-- KeepOfflinePlayers and KeepJoinSpots off: only bob
SandboxVars.WHSaveTrim.KeepOfflinePlayers = false
SandboxVars.WHSaveTrim.KeepJoinSpots = false
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 4")
check(not T.has(1000, 1000) and T.has(1800, 200), "offline and join spots not kept when switched off")
check(T.gmd.WHSaveTrim.spots.alice ~= nil and T.gmd.WHSaveTrim.spots.bob ~= nil, "spots still recorded")
SandboxVars.WHSaveTrim.KeepOfflinePlayers = true
SandboxVars.WHSaveTrim.KeepJoinSpots = nil

-- safehouse at (300,1700) 20x20: kept with KeepSafehouses (default on), removed with it off
T.houses = { T.safehouse(300, 1700, 20, 20) }
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 5")
check(T.has(300, 1700) and T.has(719, 1700) and T.has(0, 1999) and not T.has(730, 1700), "safehouse square kept")
check(WHSaveTrim.status().last.houses == 1, "1 safehouse")
SandboxVars.WHSaveTrim.KeepSafehouses = false
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 6")
check(not T.has(300, 1700), "safehouse not kept when switched off")
SandboxVars.WHSaveTrim.KeepSafehouses = true
T.houses = {}

-- radius setting, read live and clamped
SandboxVars.WHSaveTrim.KeepRadius = 50
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 7")
check(WHSaveTrim.status().last.radius == 100, "radius clamped to 100")
check(T.has(1700, 200) and not T.has(1690, 200), "radius 100 around bob")
SandboxVars.WHSaveTrim.KeepRadius = 1000
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass 8")
check(WHSaveTrim.status().last.radius == 1000 and WHSaveTrim.status().last.removed == 0, "radius 1000: alice's spot covers the whole grid")
SandboxVars.WHSaveTrim.KeepRadius = nil

-- switched off mid-pass: stops at once and removes nothing more
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.tick(5, 100)
check(WHSaveTrim.status().running, "pass running")
SandboxVars.WHSaveTrim.Enabled = false
local before = T.count(g)
T.tick(50, 100)
check(not WHSaveTrim.status().running and T.count(g) == before, "Enabled=false stops the pass, nothing more removed")
check(T.logged("stopped %(disabled%)") ~= nil, "stop logged")
T.tick(3000, 100)
check(T.count(g) == before, "nothing removed while switched off")
SandboxVars.WHSaveTrim.Enabled = true
check(T.untilPass(1200), "on again: pass resumes on schedule")
check(T.count(g) < before, "trimmed again after switching on")

-- buckets WH adds during a pass are left for the next pass; WH writing into a removed bucket is fine
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.tick(3, 100)
local far = T.bucketKey(5000, 5000)
g[far] = { [T.tileKey(5000, 5000)] = 8 }
T.untilPass(400)
check(g[far] ~= nil, "bucket added during the pass not touched")
local k0 = T.bucketKey(100, 1900)
check(g[k0] == nil, "far bucket removed")
-- WH's setTileModData on a removed bucket simply makes a new one
local b = g[k0]
if not b then b = {}; g[k0] = b end
b[T.tileKey(100, 1900)] = 9
check(g[k0][T.tileKey(100, 1900)] == 9, "WH can write a removed bucket again")
WHSaveTrim.passNow()
T.untilPass(400)
check(g[far] == nil and g[k0] == nil, "next pass removes them")

-- the table replaced mid-pass (e.g. removed by an admin tool): the pass stops, the new table is trimmed later
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.tick(5, 100)
ModData.remove(GRID)
local g2 = T.fill(0, 0, 999, 999, 3)
T.tick(1, 100)
check(T.logged("stopped %(table replaced%)") ~= nil, "replaced table detected")
check(T.count(g2) == 100 * 100, "new table untouched by the old pass")
check(T.untilPass(400), "new table trimmed on the next try")
check(not T.has(100, 100) and T.has(800, 800), "new table trimmed around alice's spot")
g = g2

-- a player moving during a pass: his current square is kept too
SandboxVars.WHSaveTrim.KeepOfflinePlayers = false
SandboxVars.WHSaveTrim.KeepJoinSpots = false
T.players = { T.player("bob", 100, 100) }
T.fill(0, 0, 999, 999, 3)
WHSaveTrim.passNow()
T.tick(2, 100)
T.players[1].x, T.players[1].y = 900, 900
T.untilPass(400)
check(T.has(900, 900) and T.has(100, 100), "start and current position kept")
check(not T.has(100, 900) and not T.has(900, 100), "rest removed")
SandboxVars.WHSaveTrim.KeepOfflinePlayers = true
SandboxVars.WHSaveTrim.KeepJoinSpots = nil

-- spots of players not seen for 30 days are dropped
T.gmd.WHSaveTrim.spots.alice.t = getTimestamp() - 31 * 24 * 3600
T.gmd.WHSaveTrim.homes.alice.t = getTimestamp() - 31 * 24 * 3600
WHSaveTrim.passNow()
T.untilPass(400)
check(T.gmd.WHSaveTrim.spots.alice == nil and T.gmd.WHSaveTrim.homes.alice == nil, "old spot and join spot dropped")
check(T.gmd.WHSaveTrim.spots.bob ~= nil and T.gmd.WHSaveTrim.homes.bob ~= nil, "bob's kept")

-- join spot: where a player came into the game (usually his base) stays kept while he is away on a trip
SandboxVars.WHSaveTrim.KeepOfflinePlayers = false
T.gmd.WHSaveTrim = nil
T.players = { T.player("carol", 300.5, 300.5) }
T.tick(30, 100)                                   -- players are looked at every 2 s
local own = T.gmd.WHSaveTrim
check(own and own.homes.carol and own.homes.carol.x == 300 and own.homes.carol.y == 300, "carol's join spot remembered")
check(own.homes.bob == nil, "no join spot for bob, who left")
T.players[1].x, T.players[1].y = 1700, 1700       -- a long trip
T.tick(30, 100)
check(own.homes.carol.x == 300 and own.spots.carol.x == 1700, "the join spot stays, the last seen spot follows")
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
check(T.untilPass(400), "pass with a player away from his join spot")
last = WHSaveTrim.status().last
check(T.has(300, 300) and T.has(1700, 1700), "join spot and current square kept")
check(not T.has(1000, 1000) and not T.has(300, 1700), "rest removed")
check(last.players == 1 and last.homes == 1, "1 player + 1 join spot")
-- he logs off and joins again somewhere else: that is his new join spot
T.players = {}
T.tick(30, 100)
T.players = { T.player("carol", 1700, 300) }
T.tick(30, 100)
check(own.homes.carol.x == 1700 and own.homes.carol.y == 300, "a new join moves the join spot")
-- a position of 0,0 (a player still being set up) is not taken as a join spot
T.players[2] = T.player("dave", 0, 0)
T.tick(30, 100)
check(own.homes.dave == nil, "no join spot at 0,0")
T.players[2].x, T.players[2].y = 1000, 1000
T.tick(30, 100)
check(own.homes.dave and own.homes.dave.x == 1000, "join spot once the position is known")
T.players[2] = nil
-- KeepJoinSpots off: only where he is now
SandboxVars.WHSaveTrim.KeepJoinSpots = false
T.players[1].x, T.players[1].y = 300, 1700
T.fill(0, 0, 1999, 1999, 3)
WHSaveTrim.passNow()
T.untilPass(400)
check(T.has(300, 1700) and not T.has(1700, 300) and not T.has(1000, 1000), "join spots not kept when switched off")
SandboxVars.WHSaveTrim.KeepJoinSpots = nil
SandboxVars.WHSaveTrim.KeepOfflinePlayers = true

-- Log on: every pass is logged
SandboxVars.WHSaveTrim.Log = true
WHSaveTrim.passNow()
T.untilPass(400)
check(T.logged("pass %d+: .*ms/tick") ~= nil, "Log: pass line")
SandboxVars.WHSaveTrim.Log = nil

-- no grid at all (WH never created it): no error, no pass
ModData.remove(GRID)
WHSaveTrim.passNow()
T.tick(100, 100)
check(ModData.get(GRID) == nil, "the add-on never creates WH's table")
