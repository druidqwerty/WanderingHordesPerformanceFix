-- WHPerfProbe (test only, never shipped): times every event handler that Wandering Hordes and the add-on
-- register, on the server and on the client. Loads from shared/ (before any server/ file), wraps
-- Events.<E>.Add / Remove so that closures from WH's / the add-on's files are timed; prints a line per handler
-- every 10 s: calls, ms per tick, us per call, max ms. getTimestampMs() has 1 ms resolution: the sums are
-- unbiased over many calls (a call adds 1 when it crosses a ms boundary).
if WHPerfProbe then return end
WHPerfProbe = { stats = {}, order = {}, wrapped = {}, files = {} }
local P = WHPerfProbe
local now = getTimestampMs

local function log(msg) print("[WHPerfProbe] " .. tostring(msg)) end

local EVENTS = { "OnTick", "OnZombieUpdate", "EveryOneMinute", "EveryTenMinutes", "EveryHours", "EveryDays",
    "OnGameStart", "OnServerStarted", "OnClientCommand", "OnServerCommand", "OnZombieDead", "OnPlayerUpdate",
    "OnFillWorldObjectContextMenu", "OnLoad", "OnInitGlobalModData", "OnReceiveGlobalModData" }

local function short(file)
    file = tostring(file):gsub("\\", "/")
    return file:match("([^/]+)$") or file
end

local function interesting(file)
    file = tostring(file)
    if file:find("WHPerfProbe") then return false end
    return file:find("WH_") or file:find("WanderingHordes") or file:find("WHSaveTrim") or file:find("WHPerf")
end

local function srcOf(fn)
    local ok, f = pcall(getFilenameOfClosure, fn)
    if not ok or type(f) ~= "string" then return nil, 0 end
    local ok2, line = pcall(getFirstLineOfClosure, fn)
    return f, (ok2 and tonumber(line)) or 0
end

local function wrap(ev, fn, file, line)
    local key = ev .. " " .. short(file) .. ":" .. tostring(line)
    local st = P.stats[key]
    if not st then
        st = { key = key, ev = ev, calls = 0, ms = 0, maxMs = 0, wCalls = 0, wMs = 0, wMax = 0 }
        P.stats[key] = st
        P.order[#P.order + 1] = st
    end
    local inner = fn
    local w = function(...)
        local t0 = now()
        inner(...)
        local dt = now() - t0
        st.wCalls = st.wCalls + 1
        st.wMs = st.wMs + dt
        if dt > st.wMax then st.wMax = dt end
    end
    P.wrapped[fn] = w
    return w
end

for _, ev in ipairs(EVENTS) do
    local e = Events[ev]
    if e and e.Add then
        local origAdd, origRemove = e.Add, e.Remove
        e.Add = function(fn, ...)
            if type(fn) == "function" then
                local file, line = srcOf(fn)
                if file then
                    local s = short(file)
                    if not P.files[s] then
                        P.files[s] = true
                        log("first handler from " .. tostring(file))
                    end
                    if interesting(file) then
                        log("timing " .. ev .. " " .. s .. ":" .. line)
                        return origAdd(wrap(ev, fn, file, line), ...)
                    end
                end
            end
            return origAdd(fn, ...)
        end
        if origRemove then
            e.Remove = function(fn, ...)
                return origRemove(P.wrapped[fn] or fn, ...)
            end
        end
    end
end

-- calibration: an empty OnZombieUpdate handler, timed the same way (the wrapper's own cost per call)
local calib = function(z) end
Events.OnZombieUpdate.Add(wrap("OnZombieUpdate", calib, "probe-empty", 0))

local function side()
    local s, c = false, false
    pcall(function() s = isServer() == true end)
    pcall(function() c = isClient() == true end)
    return s and "srv" or (c and "cli" or "sp")
end

local ticks, wTicks, wStart, lastTick = 0, 0, nil, nil
local wFrameMax = 0
Events.OnTick.Add(function()
    local t = now()
    ticks = ticks + 1
    wTicks = wTicks + 1
    if lastTick then
        local gap = t - lastTick
        if gap > wFrameMax then wFrameMax = gap end
    end
    lastTick = t
    wStart = wStart or t
    if t - wStart < 10000 then return end
    local secs = (t - wStart) / 1000
    local zombies = -1
    pcall(function() zombies = getCell():getZombieList():size() end)
    local players = 0
    pcall(function()
        if isServer() then players = getOnlinePlayers():size() else players = getNumActivePlayers() end
    end)
    log(string.format("%s window %.1f s: %d ticks (%.1f/s), max tick gap %d ms, zombies %d, players %d",
        side(), secs, wTicks, wTicks / secs, wFrameMax, zombies, players))
    local total = 0
    for _, st in ipairs(P.order) do
        if st.wCalls > 0 then
            total = total + st.wMs
            log(string.format("%s  %-48s calls %7d (%7.1f/s) ms/tick %7.4f us/call %8.2f max %4d ms",
                side(), st.key, st.wCalls, st.wCalls / secs, st.wMs / math.max(1, wTicks),
                st.wMs * 1000 / st.wCalls, st.wMax))
        end
        st.calls = st.calls + st.wCalls
        st.ms = st.ms + st.wMs
        if st.wMax > st.maxMs then st.maxMs = st.wMax end
        st.wCalls, st.wMs, st.wMax = 0, 0, 0
    end
    log(string.format("%s  total timed %.1f ms in %.1f s = %.3f ms/tick, %.2f%% of wall time", side(), total, secs,
        total / math.max(1, wTicks), total / (secs * 10)))
    wTicks, wStart, wFrameMax = 0, t, 0
end)

log("loaded (" .. side() .. ")")
