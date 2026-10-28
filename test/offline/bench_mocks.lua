-- Mocked game API for tools/GmdBench.java: the server side with players at fixed positions
-- (__PLAYERS = "x,y;x,y"), WH's real table from the loaded save (__GMD), KeepRadius __RADIUS.
local clock = 1000000
local handlers = {}
local players = {}
local quiet = __QUIET == true

local realPrint = print
print = function(s) if not quiet then realPrint(s) end end

local i = 0
for x, y in string.gmatch(__PLAYERS, "(%-?[%d%.]+),(%-?[%d%.]+)") do
    i = i + 1
    local p = { x = tonumber(x), y = tonumber(y), name = "p" .. i }
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getUsername() return self.name end
    players[#players + 1] = p
end

local function jlist(t)
    return { size = function() return #t end, get = function(_, k) return t[k + 1] end }
end

function getTimestampMs() return clock end
function getTimestamp() return math.floor(clock / 1000) end
function isServer() return true end
function isClient() return false end
function getOnlinePlayers() return jlist(players) end
SafeHouse = { getSafehouseList = function() return jlist({}) end }
ModData = {
    get = function(tag) return __GMD[tag] end,
    getOrCreate = function(tag)
        if __GMD[tag] == nil then __GMD[tag] = {} end
        return __GMD[tag]
    end,
}
Events = { OnTick = { Add = function(f) handlers[#handlers + 1] = f end } }
SandboxVars = { WHSaveTrim = { KeepRadius = __RADIUS, Log = true } }

function __benchTick()
    clock = clock + 100
    for k = 1, #handlers do handlers[k]() end
end

function __benchRunning() return WHSaveTrim.status().running end
function __benchPasses() return WHSaveTrim.status().passes end
function __benchPassNow() WHSaveTrim.passNow() end
function __benchStatus()
    local l = WHSaveTrim.status().last
    return string.format("checked %d, removed %d (~%.1f MB), kept %d (~%.1f MB), %d ticks, %d players",
        l.checked, l.removed, l.removedBytes / 1048576, l.kept, l.keptBytes / 1048576, l.ticks, l.players)
end
