-- What Wandering Hordes' WH_Server.lua registers when it loads (Workshop 3759920384, B42.21 version: the
-- Events.*.Add lines at its end), as closures "defined in" that file; plus handlers of other files that must
-- pass straight through. Loaded after the add-on's shared file, like the game does (shared before server).
local WH_FILE = "G:/Steam/steamapps/workshop/content/108600/3759920384/mods/WanderingHordes_Core/42/media/lua/server/WH_Server.lua"
local CFG_FILE = "G:/Steam/steamapps/workshop/content/108600/3759920384/mods/WanderingHordes_Core/42/media/lua/shared/WH_Config.lua"

T.wh = { calls = {} }
local function counter(name)
    return function() T.wh.calls[name] = (T.wh.calls[name] or 0) + 1 end
end
function T.whCalls(name) return T.wh.calls[name] or 0 end

WanderingHordes = WanderingHordes or {}
WanderingHordes.Server = WanderingHordes.Server or {}
WanderingHordes.StepAsyncMigrationUpdate = T.fn(CFG_FILE, counter("migr"))   -- WH_Config.lua, registered by WH_Server
WanderingHordes.Server.OnClientCommand = T.fn(WH_FILE, counter("cmd"))
T.wh.mgr = T.fn(WH_FILE, counter("mgr"))
T.wh.scan = T.fn(WH_FILE, counter("scan"))
T.wh.min = T.fn(WH_FILE, counter("min"))
T.wh.ten = T.fn(WH_FILE, counter("ten"))
T.wh.start = T.fn(WH_FILE, counter("start"))
T.wh.zdead = T.fn(WH_FILE, counter("zdead"))
T.wh.zupd = T.fn(WH_FILE, counter("zupd"))

Events.OnClientCommand.Add(WanderingHordes.Server.OnClientCommand)
Events.OnTick.Add(T.wh.mgr)
Events.OnTick.Add(T.wh.scan)
Events.OnTick.Add(WanderingHordes.StepAsyncMigrationUpdate)
Events.EveryOneMinute.Add(T.wh.min)
Events.EveryTenMinutes.Add(T.wh.ten)
Events.OnGameStart.Add(T.wh.start)
Events.OnServerStarted.Add(T.wh.start)
Events.OnZombieDead.Add(T.wh.zdead)
Events.OnZombieUpdate.Add(T.wh.zupd)
T.wh.count = 10

-- other files: another mod's server file, a client file, a file only named like WH's, a WH_Config function
-- that WH_Server does not register, and a closure without a known file
T.other = {
    T.fn("G:/x/mods/Other/42/media/lua/server/Other_Server.lua", counter("o1")),
    T.fn("G:/x/mods/Other/42/media/lua/client/WH_Server.lua", counter("o2")),
    T.fn("G:/x/mods/Other/42/media/lua/server/MyWH_Server.lua", counter("o3")),
    T.fn(CFG_FILE, counter("o4")),
    counter("o5"),
}
for _, f in ipairs(T.other) do Events.OnTick.Add(f) end
T.otherZ = T.fn("G:/x/mods/Other/42/media/lua/client/Other.lua", counter("oz"))
Events.OnZombieUpdate.Add(T.otherZ)

-- every WH handler listed in its event, and how many
function T.whListed()
    local n = 0
    for _, pair in ipairs({ { "OnClientCommand", WanderingHordes.Server.OnClientCommand }, { "OnTick", T.wh.mgr },
        { "OnTick", T.wh.scan }, { "OnTick", WanderingHordes.StepAsyncMigrationUpdate }, { "EveryOneMinute", T.wh.min },
        { "EveryTenMinutes", T.wh.ten }, { "OnGameStart", T.wh.start }, { "OnServerStarted", T.wh.start },
        { "OnZombieDead", T.wh.zdead }, { "OnZombieUpdate", T.wh.zupd } }) do
        if T.listed(pair[1], pair[2]) then n = n + 1 end
    end
    return n
end

function T.otherListed()
    local n = 0
    for _, f in ipairs(T.other) do
        if T.listed("OnTick", f) then n = n + 1 end
    end
    if T.listed("OnZombieUpdate", T.otherZ) then n = n + 1 end
    return n
end
