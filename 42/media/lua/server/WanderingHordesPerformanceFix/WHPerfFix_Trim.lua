--*****************************************************************************
-- Wandering Hordes Performance Fix (WanderingHordesPerformanceFix) - add-on for Wandering Hordes [Core], B42.
-- Server part: the wall-map trim (was the add-on "Wandering Hordes Save Trim" 1.0.0). The multiplayer-client
-- part is in shared/WanderingHordesPerformanceFix/WHPerfFix_Shared.lua.
--
-- The problem (B42.21, read from the game and WH code, measured on a real co-op save):
--  * Wandering Hordes keeps a wall map ("passability grid") in the global ModData table
--    WH_PassabilityGrid_v2: one entry per 1x1 tile, in buckets of 10x10 tiles (key gx*100000+gy).
--    Three scanners fill it every tick within 30 tiles of every player and never remove anything, so it
--    grows with every tile anybody has ever been near (a long drive leaves a 61-tile-wide trail).
--  * The game writes ALL global ModData into global_mod_data.bin at every world save, on the server's main
--    thread, and reads it all at start. On a real 2-player save the grid was 58 MB of a 76 MB file:
--    ~0.3 s server freeze every save (5 min), 6.3 s on the first save after a start (clients get paused),
--    6.9 s to load it at server start.
--  * WH reads the map only to check whether the square where a horde is about to appear is fenced in
--    (squareIsEnclosed: it follows walls up to 300 tiles from that square, which is at most 75 tiles
--    from a player) and as a water shortcut. A missing tile means "not scanned yet", and the scanners
--    scan it again when a player comes near.
--
-- What this add-on does (Lua only; Wandering Hordes itself is neither changed nor copied):
--  * Every few minutes it walks over the table, a few hundred buckets per tick, and removes the buckets
--    that are farther than KeepRadius tiles (square) from every player, from where each player joined the
--    game (usually the base he logged out at; kept while he is away on a trip), from where offline
--    players were last seen (server), and from every safehouse. So the table stays the size of the areas
--    around the players and their bases instead of the whole explored map.
--  * Near the players nothing changes: the default radius (400) covers every square WH's fence check can
--    reach from a horde that appears near a player (75 + 300 tiles). Far away, WH forgets its wall map;
--    when a player comes back there, WH scans the area again (as in a never-visited area).
--  * Runs wherever WH's scanners run: the server (or single player) - this is what the save contains - and
--    a multiplayer client where the shared part lets WH's server handlers run (ClientOffload=false; B42
--    loads media/lua/server on clients too): clients never save it, there it only saves memory.
--  * Nothing is removed when there is nobody to keep around (no player online and nothing remembered).
-- Settings: Sandbox page "Wandering Hordes: Performance Fix" (TrimWallMap, KeepRadius, KeepJoinSpots,
-- KeepOfflinePlayers, KeepSafehouses, TrimIntervalMinutes, Log); read live, so an admin change applies in
-- the running game.
--*****************************************************************************

WHPerfFix = WHPerfFix or {}
if WHPerfFix.Trim and WHPerfFix.Trim.loaded then return end
WHPerfFix.Trim = WHPerfFix.Trim or {}
local M = WHPerfFix.Trim
M.loaded = true
M.VERSION = WHPerfFix.VERSION or "2.0.0"

local GRID = "WH_PassabilityGrid_v2"   -- Wandering Hordes' table (WH_Server.lua getGridAndTileKeys)
local OWN = "WHPerfFix"                 -- our own small table: where players were last seen (server only)
local OLD_OWN = "WHSaveTrim"            -- the same table of the add-on's 1.0.0 (Wandering Hordes Save Trim)
local BUCKET = 10                       -- WH bucket = 10x10 tiles, key = gx * 100000 + gy
local KEY_MUL = 100000
local BUDGET = 400                      -- buckets checked per tick (measured: see MODLOG)
local SAMPLE_EVERY = 64                 -- count the tiles of every 64th bucket (for the size estimate)
local FIRST_DELAY_MS = 15000            -- first pass not before this long after the first tick
local RETRY_MS = 5000                   -- nobody to keep around yet: look again after this
local TRACK_MS = 2000                   -- how often the players are looked at (joins, last seen spots)
local SPOT_EXPIRE_S = 30 * 24 * 3600    -- forget a player's spots after 30 days without him (real time)
local BYTES_PER_BUCKET = 14             -- serialized: key 9 + type 1 + count 4
local BYTES_PER_TILE = 18               -- serialized: key 9 + value 9

--=============================================================================
-- settings (Sandbox page WHPerfFix; read every tick / pass, so admin changes apply at once)
--=============================================================================
local function clamp(v, lo, hi, def)
    v = tonumber(v)
    if v == nil then return def end
    v = math.floor(v)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function readSettings()
    local v = SandboxVars and SandboxVars.WHPerfFix or nil
    if type(v) ~= "table" then v = {} end
    return {
        enabled = v.TrimWallMap ~= false,
        radius = clamp(v.KeepRadius, 100, 5000, 400),
        joinSpots = v.KeepJoinSpots ~= false,
        offline = v.KeepOfflinePlayers ~= false,
        safehouses = v.KeepSafehouses ~= false,
        intervalMs = clamp(v.TrimIntervalMinutes, 1, 60, 2) * 60000,
        log = v.Log == true,
    }
end

local function log(msg)
    print("[WHPerfFix] " .. msg)
end

local SIDE = nil
local function side()
    if SIDE then return SIDE end
    local srv, cli = false, false
    pcall(function() srv = isServer() == true end)
    pcall(function() cli = isClient() == true end)
    if srv then return "server" end
    if cli then return "client" end
    return "sp"
end

--=============================================================================
-- what to keep: squares of +-radius tiles, in bucket coordinates {gx0, gx1, gy0, gy1, ...}
--=============================================================================
local floor = math.floor

local function addSquare(rects, x0, y0, x1, y1, r)
    rects[#rects + 1] = floor((x0 - r) / BUCKET)
    rects[#rects + 1] = floor((x1 + r) / BUCKET)
    rects[#rects + 1] = floor((y0 - r) / BUCKET)
    rects[#rects + 1] = floor((y1 + r) / BUCKET)
end

local function playerName(p)
    local name = nil
    pcall(function() name = p:getUsername() end)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- the players whose surroundings WH's scanners fill on this machine (as WH's getPlayerList: all online
-- players on the server, the local players elsewhere); dead ones too, they are still somewhere.
-- Also returns a key per player: the user name on the server, the local player number elsewhere.
local function players()
    local out, keys = {}, {}
    if side() == "server" then
        local list = getOnlinePlayers and getOnlinePlayers() or nil
        if list then
            for i = 0, list:size() - 1 do
                local p = list:get(i)
                if p then
                    out[#out + 1] = p
                    keys[#out] = playerName(p)
                end
            end
        end
    else
        local n = 1
        pcall(function() n = getNumActivePlayers() end)
        for i = 0, (n or 1) - 1 do
            local p = getSpecificPlayer(i)
            if p then
                out[#out + 1] = p
                keys[#out] = "local" .. i
            end
        end
    end
    return out, keys
end

local function playerSquares(rects, radius, list)
    for i = 1, #list do
        local p = list[i]
        local ok, x, y = pcall(function() return p:getX(), p:getY() end)
        if ok and x and y then
            addSquare(rects, x, y, x, y, radius)
        end
    end
end

-- a usable position (a player still being set up can be at 0,0)
local function position(p)
    local ok, x, y = pcall(function() return p:getX(), p:getY() end)
    if ok and type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
        return floor(x), floor(y)
    end
    return nil, nil
end

-- server: where each player was last seen (kept while he is offline) and where he joined the game
-- (kept while he is away), saved with the world; single player / client: where each local player was
-- first seen in this session (the game is loaded where it was left, usually the base)
local migrated = false

local function ownData()
    local t = ModData.getOrCreate(OWN)
    if type(t.spots) ~= "table" then t.spots = {} end
    if type(t.homes) ~= "table" then t.homes = {} end
    if not migrated then
        migrated = true
        -- a save that ran the add-on's 1.0.0 (Wandering Hordes Save Trim): take its spots over, once
        local old = ModData.get(OLD_OWN)
        if type(old) == "table" then
            local n = 0
            for _, key in ipairs({ "spots", "homes" }) do
                if type(old[key]) == "table" then
                    for name, s in pairs(old[key]) do
                        if t[key][name] == nil and type(s) == "table" then
                            t[key][name] = { x = s.x, y = s.y, t = s.t }
                            n = n + 1
                        end
                    end
                end
            end
            ModData.remove(OLD_OWN)
            log("took over " .. n .. " player spot(s) from Wandering Hordes Save Trim 1.0.0")
        end
    end
    return t
end

local onlineBefore = {}   -- server: who was online at the last look (a name not in it has just joined)
local localHomes = {}     -- single player / client

local function track(list, keys)
    if side() ~= "server" then
        for i = 1, #list do
            local k = keys[i]
            if k and not localHomes[k] then
                local x, y = position(list[i])
                if x then localHomes[k] = { x = x, y = y } end
            end
        end
        return
    end
    local data = ownData()
    local spots, homes = data.spots, data.homes
    local now = getTimestamp and getTimestamp() or 0
    local here = {}
    for i = 1, #list do
        local name = keys[i]
        if name then
            local x, y = position(list[i])
            if x then
                here[name] = true
                local s = spots[name]
                if type(s) ~= "table" then
                    s = {}
                    spots[name] = s
                end
                s.x, s.y, s.t = x, y, now
                local h = homes[name]
                if not onlineBefore[name] or type(h) ~= "table" then
                    homes[name] = { x = x, y = y, t = now }
                else
                    h.t = now
                end
            elseif onlineBefore[name] then
                here[name] = true
            end
        end
    end
    onlineBefore = here
end

-- drop the spots of players not seen for a long time
local function expire(t, now)
    local old = {}
    for name, s in pairs(t) do
        if type(s) ~= "table" or (tonumber(s.t) or 0) < now - SPOT_EXPIRE_S then
            old[#old + 1] = name
        end
    end
    for i = 1, #old do t[old[i]] = nil end
end

local function spotSquares(rects, radius, keys)
    local spots = ownData().spots
    local here = {}
    for _, name in pairs(keys) do here[name] = true end
    local count = 0
    for name, s in pairs(spots) do
        if not here[name] and type(s) == "table" and tonumber(s.x) and tonumber(s.y) then
            addSquare(rects, s.x, s.y, s.x, s.y, radius)
            count = count + 1
        end
    end
    return count
end

local function homeSquares(rects, radius)
    local homes = side() == "server" and ownData().homes or localHomes
    local count = 0
    for _, h in pairs(homes) do
        if type(h) == "table" and tonumber(h.x) and tonumber(h.y) then
            addSquare(rects, h.x, h.y, h.x, h.y, radius)
            count = count + 1
        end
    end
    return count
end

local function safehouseSquares(rects, radius)
    local count = 0
    pcall(function()
        local list = SafeHouse and SafeHouse.getSafehouseList and SafeHouse.getSafehouseList() or nil
        if not list then return end
        for i = 0, list:size() - 1 do
            local h = list:get(i)
            if h then
                local x, y, w, hh = h:getX(), h:getY(), h:getW(), h:getH()
                if x and y and w and hh then
                    addSquare(rects, x, y, x + math.max(w, 1) - 1, y + math.max(hh, 1) - 1, radius)
                    count = count + 1
                end
            end
        end
    end)
    return count
end

--=============================================================================
-- the pass: an iterator over a snapshot of the table's bucket keys (Kahlua's pairs() copies the key set,
-- so removing entries while it runs is safe; buckets WH adds meanwhile are left for the next pass)
--=============================================================================
local pass = nil        -- the running pass
local nextPassAt = nil  -- ms
local passCount = 0
local reported = false  -- the first pass that removed something is always logged

local function countTiles(b)
    local n = 0
    for _ in pairs(b) do n = n + 1 end
    return n
end

local function startPass(s, now)
    local grid = ModData.get(GRID)
    if type(grid) ~= "table" then return false end
    local srv = side() == "server"
    local list, keys = players()
    if not srv and #list == 0 then return false end   -- no local player (menu, dead): leave it alone
    track(list, keys)
    local rects = {}
    playerSquares(rects, s.radius, list)
    local nPlayers = #rects / 4
    local nSpots = 0
    if srv then
        local nowS = getTimestamp and getTimestamp() or 0
        local data = ownData()
        expire(data.spots, nowS)
        expire(data.homes, nowS)
        if s.offline then nSpots = spotSquares(rects, s.radius, keys) end
    end
    local nHomes = 0
    if s.joinSpots then nHomes = homeSquares(rects, s.radius) end
    local nHouses = 0
    if s.safehouses then nHouses = safehouseSquares(rects, s.radius) end
    if #rects == 0 then return false end      -- nobody to keep around: never prune everything
    pass = {
        grid = grid, iter = pairs(grid), rects = rects, radius = s.radius,
        players = nPlayers, homes = nHomes, spots = nSpots, houses = nHouses,
        checked = 0, removed = 0, sampled = 0, sampledTiles = 0, sampledRemoved = 0, sampledRemovedTiles = 0,
        ticks = 0, ms = 0, maxMs = 0, t0 = now,
    }
    return true
end

-- checks up to `budget` buckets against the squares `r` ({gx0, gx1, gy0, gy1, ...}); true when the pass is over
local function step(p, budget, r)
    local grid, iter = p.grid, p.iter
    local nr = #r
    local checked, removed = p.checked, p.removed
    local done = false
    for _ = 1, budget do
        local k, b = iter()
        if k == nil then
            done = true
            break
        end
        if b ~= nil and type(k) == "number" and type(b) == "table" then
            checked = checked + 1
            local gx = floor(k / KEY_MUL)
            local gy = k - gx * KEY_MUL
            local keep = false
            for j = 1, nr, 4 do
                if gx >= r[j] and gx <= r[j + 1] and gy >= r[j + 2] and gy <= r[j + 3] then
                    keep = true
                    break
                end
            end
            if checked % SAMPLE_EVERY == 0 then      -- a few buckets are counted for the size estimate
                local tiles = countTiles(b)
                p.sampled = p.sampled + 1
                p.sampledTiles = p.sampledTiles + tiles
                if not keep then
                    p.sampledRemoved = p.sampledRemoved + 1
                    p.sampledRemovedTiles = p.sampledRemovedTiles + tiles
                end
            end
            if not keep then
                grid[k] = nil
                removed = removed + 1
            end
        end
    end
    p.checked, p.removed = checked, removed
    return done
end

local function mb(bytes)
    return string.format("%.1f MB", bytes / 1048576)
end

local function finishPass(p, now, why)
    passCount = passCount + 1
    local avg = p.sampled > 0 and p.sampledTiles / p.sampled or 0
    local avgRemoved = p.sampledRemoved > 0 and p.sampledRemovedTiles / p.sampledRemoved or avg
    local kept = p.checked - p.removed
    local removedBytes = p.removed * (BYTES_PER_BUCKET + BYTES_PER_TILE * avgRemoved)
    local totalBytes = p.checked * (BYTES_PER_BUCKET + BYTES_PER_TILE * avg)
    local keptBytes = math.max(0, totalBytes - removedBytes)
    M.last = {
        pass = passCount, checked = p.checked, removed = p.removed, kept = kept, radius = p.radius,
        players = p.players, homes = p.homes, spots = p.spots, houses = p.houses, ticks = p.ticks, ms = p.ms,
        maxMs = p.maxMs,
        wallMs = now - p.t0, keptBytes = keptBytes, removedBytes = removedBytes, why = why,
    }
    if why then
        log(string.format("pass %d stopped (%s) after %d cells, %d removed", passCount, why, p.checked, p.removed))
        return
    end
    local s = readSettings()
    if s.log or (p.removed > 0 and not reported) then
        reported = reported or p.removed > 0
        log(string.format("pass %d: %d cells checked, %d removed (~%s), %d kept (~%s); keep radius %d around "
            .. "%d player(s), %d join spot(s), %d offline spot(s), %d safehouse(s); %d ticks, %.2f ms/tick, "
            .. "max %d ms, %.1f s",
            passCount, p.checked, p.removed, mb(removedBytes), kept, mb(keptBytes), p.radius, p.players,
            p.homes, p.spots, p.houses, p.ticks, p.ticks > 0 and p.ms / p.ticks or 0, p.maxMs,
            (now - p.t0) / 1000))
    end
end

local function enabledNow()
    local v = SandboxVars and SandboxVars.WHPerfFix or nil
    return not (type(v) == "table" and v.TrimWallMap == false)
end

local lastTrack = nil

local function onTick()
    local now = getTimestampMs()
    if SIDE == nil then SIDE = side() end   -- settled once the game runs
    if nextPassAt == nil then nextPassAt = now + FIRST_DELAY_MS end
    if (lastTrack == nil or now - lastTrack >= TRACK_MS) and enabledNow() then
        lastTrack = now
        track(players())
    end
    if pass == nil then
        if now < nextPassAt then return end   -- between passes: nothing else to do
        local s = readSettings()
        if not s.enabled or not startPass(s, now) then
            nextPassAt = now + RETRY_MS        -- off, no WH table yet, or nobody to keep around
            return
        end
    elseif not enabledNow() then
        finishPass(pass, now, "disabled")
        pass = nil
        nextPassAt = now + RETRY_MS
        return
    end
    local p = pass
    if ModData.get(GRID) ~= p.grid then      -- the table was replaced or removed: start over next time
        finishPass(p, now, "table replaced")
        pass = nil
        nextPassAt = now + RETRY_MS
        return
    end
    -- the squares of the pass start, plus where the players are now (a car covers a lot of ground)
    local r = {}
    local base = p.rects
    for i = 1, #base do r[i] = base[i] end
    playerSquares(r, p.radius, players())
    local done = step(p, BUDGET, r)
    local t1 = getTimestampMs()
    local dt = t1 - now
    p.ticks = p.ticks + 1
    p.ms = p.ms + dt
    if dt > p.maxMs then p.maxMs = dt end
    if done then
        pass = nil
        nextPassAt = t1 + readSettings().intervalMs
        finishPass(p, t1, nil)
    end
end

-- for tests and admins: what the last pass did, and whether one is running
function M.status()
    return { version = M.VERSION, side = side(), passes = passCount, running = pass ~= nil, last = M.last,
             nextPassInMs = nextPassAt and (nextPassAt - getTimestampMs()) or nil }
end

-- for tests: start a pass now (does not wait for the interval)
function M.passNow()
    nextPassAt = 0
end

Events.OnTick.Add(onTick)
log(M.VERSION .. " loaded (" .. side() .. ")")
