-- Wandering Hordes Save Trim live-test helper, server side (test only, never shipped).
-- Logs the server's copy of WH's grid (buckets every 30 s, scanned tiles around each player every 2 s),
-- the add-on's status, zombies loaded; on request probes WH's own spawn-safety check around a player
-- and adds a safehouse.
if not (isServer and isServer()) then return end

local function log(msg) print("[WHTrimTest] " .. tostring(msg)) end
local GRID = "WH_PassabilityGrid_v2"

local function near(g, px, py, r)
    local n = 0
    for x = px - r, px + r do
        for y = py - r, py + r do
            local b = g[math.floor(x / 10) * 100000 + math.floor(y / 10)]
            if b and b[x * 100000 + y] then n = n + 1 end
        end
    end
    return n
end

local function players()
    local out = {}
    local list = getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    end
    return out
end

local t0, lastNear, lastGrid = nil, 0, 0
Events.OnTick.Add(function()
    local now = getTimestampMs()
    t0 = t0 or now
    local g = ModData.get(GRID)
    if now - lastNear >= 2000 then
        lastNear = now
        if g then
            for _, p in ipairs(players()) do
                local px, py = math.floor(p:getX()), math.floor(p:getY())
                log(string.format("srv near user=%s pos=%d,%d r30=%d/3721", tostring(p:getUsername()), px, py, near(g, px, py, 30)))
            end
        end
    end
    if now - lastGrid >= 30000 then
        lastGrid = now
        local n = 0
        local a = getTimestampMs()
        if g then for _ in pairs(g) do n = n + 1 end end
        local st = WHSaveTrim and WHSaveTrim.status and WHSaveTrim.status() or nil
        local l = st and st.last or nil
        local zombies = 0
        pcall(function() zombies = getCell():getZombieList():size() end)
        local sv = SandboxVars and SandboxVars.WHSaveTrim or {}
        log(string.format("srv grid=%d buckets (counted in %d ms) zombies=%d trim passes=%s running=%s last: checked=%s removed=%s kept=%s radius=%s ticks=%s ms=%s | sandbox Enabled=%s KeepRadius=%s Interval=%s Log=%s",
            n, getTimestampMs() - a, zombies, tostring(st and st.passes), tostring(st and st.running),
            tostring(l and l.checked), tostring(l and l.removed), tostring(l and l.kept), tostring(l and l.radius),
            tostring(l and l.ticks), tostring(l and l.ms), tostring(sv.Enabled), tostring(sv.KeepRadius),
            tostring(sv.IntervalMinutes), tostring(sv.Log)))
    end
end)

-- WH's own check for a square where a horde may appear (isSquareSafeForSpawn, global in WH_Server.lua):
-- water / safehouse / indoor / fenced in (squareIsEnclosed on the grid). A 21x21 lattice, 5 tiles apart.
local function probe(p)
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), 0
    local a = getTimestampMs()
    local rows, safe, unsafe, missing = {}, 0, 0, 0
    for j = -10, 10 do
        local row = {}
        for i = -10, 10 do
            local sq = cell:getGridSquare(px + i * 5, py + j * 5, pz)
            local c = " "
            if sq then
                local ok, res = pcall(isSquareSafeForSpawn, sq, false)
                if ok and res then c = "." safe = safe + 1 else c = "#" unsafe = unsafe + 1 end
            else
                missing = missing + 1
            end
            row[#row + 1] = c
        end
        rows[#rows + 1] = table.concat(row)
    end
    local g = ModData.get(GRID)
    log(string.format("enc pos=%d,%d safe=%d unsafe=%d noSquare=%d scanned r50=%d/10201 (%d ms) map=%s",
        px, py, safe, unsafe, missing, g and near(g, px, py, 50) or 0, getTimestampMs() - a, table.concat(rows, "/")))
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "WHTrimTest" then return end
    if command == "enc" then
        probe(player)
    elseif command == "sh" then
        local x, y, w, h = string.match(args and args.arg or "", "^(%d+),(%d+),(%d+),(%d+)$")
        if x then
            local s = SafeHouse.addSafeHouse(tonumber(x), tonumber(y), tonumber(w), tonumber(h), player:getUsername())
            log("safehouse added at " .. x .. "," .. y .. " " .. w .. "x" .. h .. ": " .. tostring(s ~= nil))
        end
    elseif command == "spot" then
        local x, y = string.match(args and args.arg or "", "^(%d+),(%d+)$")
        local g = ModData.get(GRID)
        if x and g then
            log(string.format("spot %s,%s scanned r50=%d/10201 (player at %d,%d)", x, y,
                near(g, tonumber(x), tonumber(y), 50), math.floor(player:getX()), math.floor(player:getY())))
        end
    elseif command == "probe" then
        lastGrid = 0
    end
end)

log("server helper loaded")
