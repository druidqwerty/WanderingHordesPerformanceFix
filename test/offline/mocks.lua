-- Offline test bench for the add-on (WHPerfFix_Shared.lua + WHPerfFix_Trim.lua): a mocked game API (only what
-- the add-on uses), run in the game's own Kahlua VM by tools/LuaRun (see tools/offline_test.sh). Not part of
-- the mod.

T = { passed = 0, failed = 0, clock = 1000000, side = "server", players = {}, local_players = {},
      houses = {}, gmd = {}, handlers = {}, printed = {}, files = {}, ev = {} }

local realPrint = print
print = function(s)
    T.printed[#T.printed + 1] = tostring(s)
    if T.echo then realPrint(s) end
end

function check(cond, msg)
    if cond then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        realPrint("FAIL " .. tostring(msg))
    end
end

function T.say(s) realPrint(s) end

-- a Java ArrayList stand-in
local function jlist(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

function T.player(name, x, y)
    local p = { name = name, x = x, y = y }
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getUsername() return self.name end
    return p
end

function T.safehouse(x, y, w, h)
    local s = { x = x, y = y, w = w, h = h }
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getW() return self.w end
    function s:getH() return self.h end
    return s
end

function getTimestampMs() return T.clock end
function getTimestamp() return math.floor(T.clock / 1000) end
function isServer() return T.side == "server" end
function isClient() return T.side == "client" end
function getOnlinePlayers()
    if T.side ~= "server" then error("getOnlinePlayers called off the server") end
    return jlist(T.players)
end
function getNumActivePlayers() return #T.local_players end
function getSpecificPlayer(i) return T.local_players[i + 1] end
SafeHouse = { getSafehouseList = function() return jlist(T.houses) end }

ModData = {
    get = function(tag) return T.gmd[tag] end,
    getOrCreate = function(tag)
        if T.gmd[tag] == nil then T.gmd[tag] = {} end
        return T.gmd[tag]
    end,
    remove = function(tag) local t = T.gmd[tag]; T.gmd[tag] = nil; return t end,
    exists = function(tag) return T.gmd[tag] ~= nil end,
}

-- Events.<E>.Add / Remove like the game's (a list per event, Remove takes out the first equal closure)
local EVENT_NAMES = { "OnTick", "OnZombieUpdate", "OnZombieDead", "EveryOneMinute", "EveryTenMinutes", "OnGameStart",
    "OnServerStarted", "OnClientCommand", "OnServerCommand", "OnFillWorldObjectContextMenu" }
function T.newEvents()
    T.ev = {}
    Events = {}
    for _, name in ipairs(EVENT_NAMES) do
        local list = {}
        T.ev[name] = list
        Events[name] = {
            Add = function(f) list[#list + 1] = f end,
            Remove = function(f)
                for i = 1, #list do
                    if list[i] == f then table.remove(list, i) return end
                end
            end,
        }
    end
    T.handlers = T.ev.OnTick
end
T.newEvents()

-- where a closure comes from (the game: the Lua file that defined it)
function getFilenameOfClosure(f) return T.files[f] end
function T.fn(file, body)
    local f = body or function() end
    T.files[f] = file
    return f
end

function T.fire(name, ...)
    local list = T.ev[name]
    local i = 1
    while i <= #list do
        list[i](...)
        i = i + 1
    end
end

function T.listed(name, f)
    for _, g in ipairs(T.ev[name]) do
        if g == f then return true end
    end
    return false
end

SandboxVars = { WHPerfFix = {} }

-- run n ticks, dt ms apart
-- like the game's Event.trigger: an index loop that re-reads the size (a handler may add or remove handlers)
function T.tick(n, dt)
    for _ = 1, n or 1 do
        T.clock = T.clock + (dt or 100)
        local list = T.ev.OnTick
        local i = 1
        while i <= #list do
            list[i]()
            i = i + 1
        end
    end
end

function T.reset(side)
    WHPerfFix = nil
    WanderingHordes = nil
    T.side = side
    T.players, T.local_players, T.houses, T.gmd, T.printed, T.files = {}, {}, {}, {}, {}, {}
    T.newEvents()
    SandboxVars = { WHPerfFix = {} }
end

-- WH's own key formulas (WH_Server.lua getGridAndTileKeys)
function T.bucketKey(x, y) return math.floor(x / 10) * 100000 + math.floor(y / 10) end
function T.tileKey(x, y) return x * 100000 + y end

-- WH-like grid: one bucket (with `tiles` tiles) for every 10x10 cell in [x0,x1] x [y0,y1] (tile coords)
function T.fill(x0, y0, x1, y1, tiles)
    local g = ModData.getOrCreate("WH_PassabilityGrid_v2")
    local n = 0
    for bx = math.floor(x0 / 10), math.floor(x1 / 10) do
        for by = math.floor(y0 / 10), math.floor(y1 / 10) do
            local b = {}
            for i = 0, (tiles or 3) - 1 do b[T.tileKey(bx * 10 + i % 10, by * 10 + math.floor(i / 10))] = 8 end
            g[bx * 100000 + by] = b
            n = n + 1
        end
    end
    return g, n
end

function T.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function T.has(x, y)
    local g = T.gmd["WH_PassabilityGrid_v2"]
    return g ~= nil and g[T.bucketKey(x, y)] ~= nil
end

function T.logged(pattern)
    for i = 1, #T.printed do
        if string.find(T.printed[i], pattern) then return T.printed[i] end
    end
    return nil
end

-- run ticks until the add-on reports a finished pass (or max ticks)
function T.untilPass(maxTicks, dt)
    local before = WHPerfFix.Trim.status().passes
    for _ = 1, maxTicks or 10000 do
        T.tick(1, dt)
        if WHPerfFix.Trim.status().passes > before then return true end
    end
    return false
end
