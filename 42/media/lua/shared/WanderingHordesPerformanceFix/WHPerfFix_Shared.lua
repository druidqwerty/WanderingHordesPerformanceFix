--*****************************************************************************
-- Wandering Hordes Performance Fix (WanderingHordesPerformanceFix) - add-on for Wandering Hordes [Core], B42.
-- Shared part: loads from media/lua/shared, so before every media/lua/server file of any mod.
--
-- Multiplayer clients: B42 loads media/lua/server on clients too, so Wandering Hordes' server logic
-- (WH_Server.lua) also runs on every client, for nothing: hordes are spawned, steered and saved by the
-- server, and nothing on a client reads what that code builds there. On a client it costs its wall scanners
-- every frame, its migration map at game start (a freeze) and again every game day (a step every 5th frame
-- for several seconds), its horde managers and a call on every zombie update.
-- Here the event handlers that WH_Server.lua registers are not registered on a multiplayer client (held
-- back); single player and the server keep every one of them. Sandbox ClientOffload=false registers them
-- again in a running game, true takes them out again.
-- Wandering Hordes itself is neither changed nor copied. Events.<E>.Add of a few events is wrapped only to
-- recognize WH_Server.lua's handlers; everybody else's handlers pass straight through.
--*****************************************************************************

WHPerfFix = WHPerfFix or {}
local M = WHPerfFix
if M.sharedLoaded then return end
M.sharedLoaded = true
M.VERSION = "2.0.0"

local function log(msg)
    print("[WHPerfFix] " .. msg)
end
M.log = log

-- settings: Sandbox page WHPerfFix (server-wide; a client sees the server's values)
function M.setting(key, default)
    local v = SandboxVars and SandboxVars.WHPerfFix or nil
    if type(v) ~= "table" or v[key] == nil then return default end
    return v[key]
end

function M.isMPClient()
    local c = false
    pcall(function() c = isClient() == true end)
    return c
end

local WH_SERVER_FILE = "/media/lua/server/WH_Server.lua"
local EVENTS = { "OnTick", "OnZombieUpdate", "OnZombieDead", "EveryOneMinute", "EveryTenMinutes", "EveryHours",
    "EveryDays", "OnGameStart", "OnServerStarted", "OnClientCommand", "OnPlayerUpdate", "OnLoad",
    "OnInitGlobalModData", "OnGameTimeLoaded", "OnCreatePlayer" }
local adds, removes = {}, {}   -- the game's Events.<E>.Add / Remove
M.handlers = {}                -- WH_Server.lua's handlers: { ev, fn, on = registered now, ran = started late }
local gameStarted = false

-- a handler from Wandering Hordes' server file (or the migration-map step of WH_Config.lua it registers)
local function fromWHServer(fn)
    if type(fn) ~= "function" then return false end
    local WH = WanderingHordes
    if type(WH) == "table" and fn == WH.StepAsyncMigrationUpdate then return true end
    local ok, file = pcall(getFilenameOfClosure, fn)
    if not ok or type(file) ~= "string" then return false end
    file = string.gsub(file, "\\", "/")
    return string.sub(file, -#WH_SERVER_FILE) == WH_SERVER_FILE
end

local function holdHere()
    return M.isMPClient() and M.setting("ClientOffload", true) ~= false
end

local function hook(ev)
    local e = Events and Events[ev]
    if type(e) ~= "table" or type(e.Add) ~= "function" then return end
    local add = e.Add
    adds[ev], removes[ev] = add, e.Remove
    e.Add = function(fn, ...)
        if fromWHServer(fn) then
            local h = { ev = ev, fn = fn, on = false }
            M.handlers[#M.handlers + 1] = h
            if holdHere() then return end
            h.on = true
        end
        return add(fn, ...)
    end
end

-- registers or takes out WH's server handlers as the setting says (multiplayer clients only; single player
-- and the server always keep them)
function M.applyClientOffload()
    if not M.isMPClient() then return end
    local hold = M.setting("ClientOffload", true) ~= false
    for i = 1, #M.handlers do
        local h = M.handlers[i]
        if hold and h.on and removes[h.ev] then
            removes[h.ev](h.fn)
            h.on = false
        elseif not hold and not h.on and adds[h.ev] then
            adds[h.ev](h.fn)
            h.on = true
            if h.ev == "OnGameStart" and gameStarted and not h.ran then
                h.ran = true   -- WH's start-up (initServerLogic) did not run on this client yet
                local ok, err = pcall(h.fn)
                if not ok then log("Wandering Hordes' start-up on this client failed: " .. tostring(err)) end
            end
        end
    end
end

-- for tests and admins: how many of WH's server handlers run here / are held back, and which
function M.clientStatus()
    local on, off, list = 0, 0, {}
    for i = 1, #M.handlers do
        local h = M.handlers[i]
        if h.on then on = on + 1 else off = off + 1 end
        list[#list + 1] = h.ev .. (h.on and "" or "(held)")
    end
    return on, off, table.concat(list, " ")
end

if type(Events) == "table" then
    for i = 1, #EVENTS do hook(EVENTS[i]) end
    -- our own handlers go through the game's Add (they are not WH's)
    if adds.OnGameStart then
        adds.OnGameStart(function()
            gameStarted = true
            M.applyClientOffload()
            if M.isMPClient() then
                local on, off, list = M.clientStatus()
                log(string.format("multiplayer client: %d of Wandering Hordes' server handlers held back, %d run "
                    .. "here: %s", off, on, list))
            end
        end)
    end
    if adds.OnTick then
        local lastCheck = 0
        adds.OnTick(function()
            local now = getTimestampMs()
            if now - lastCheck < 3000 then return end
            lastCheck = now
            M.applyClientOffload()   -- an admin's sandbox change in a running game
        end)
    end
end

log(M.VERSION .. " shared part loaded")
