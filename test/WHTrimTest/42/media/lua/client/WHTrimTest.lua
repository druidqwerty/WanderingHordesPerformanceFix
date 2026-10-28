-- Wandering Hordes Performance Fix live-test helper (test only, never shipped). Joins the test server, clicks
-- through character creation, then runs a scripted tour from Lua/WHTrimTest.txt (script=step;step;...):
--   wait:SEC        tp:X,Y (admin /teleportto)        spawn (Wandering Hordes ForceSpawn near the player)
--   enc             the server probes WH's own spawn-safety check (isSquareSafeForSpawn) around the player
--   sh:X,Y,W,H      the server adds a safehouse there   sb:Key=Value  admin sandbox change WHPerfFix.Key
--   done            writes WHTrimTest_done.txt
-- Every 10 s it logs the size of THIS client's own copy of WH's grid (B42 would run WH's scanners on clients
-- too), how many of WH's server handlers run here, and how many loaded zombies carry WH's modData flags.

local function log(msg) print("[WHTrimTest] " .. tostring(msg)) end
local GRID = "WH_PassabilityGrid_v2"

local cfg
local function readCfg()
    if cfg then return cfg end
    cfg = {}
    local r = getFileReader("WHTrimTest.txt", false)
    if not r then return cfg end
    local line = r:readLine()
    while line do
        local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then cfg[k] = v end
        line = r:readLine()
    end
    r:close()
    return cfg
end

local done = {}
local function once(key)
    if done[key] then return false end
    done[key] = true
    return true
end

local menuStart
Events.OnFETick.Add(function()
    local c = readCfg()
    if not c.ip then return end
    local now = getTimestampMs()
    menuStart = menuStart or now
    local ms = MainScreen and MainScreen.instance
    if ms and ms.charCreationProfession and ms.charCreationProfession:isVisible() then
        if once("prof") then
            log("character creation: profession -> next")
            ms.charCreationProfession:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
        end
        return
    end
    if ms and ms.charCreationMain and ms.charCreationMain:isVisible() then
        if once("main") then
            log("character creation: appearance -> play")
            ms.charCreationMain:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
        end
        return
    end
    if isClient() then return end
    if now - menuStart < 5000 then return end
    if not (ConnectToServer and ConnectToServer.instance) then return end
    if once("connect") then
        log("connecting to " .. c.ip .. ":" .. c.port .. " as " .. c.user)
        local dummy = { setVisible = function() end }
        ConnectToServer.instance:connect(dummy, "", c.user, c.pass, c.ip, "", c.port, "", false, true, 1)
    end
end)

local function gridStats(p)
    local g = ModData.get(GRID)
    if not g then return 0, 0 end
    local n = 0
    for _ in pairs(g) do n = n + 1 end
    local near = 0
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    for x = px - 30, px + 30 do
        for y = py - 30, py + 30 do
            local b = g[math.floor(x / 10) * 100000 + math.floor(y / 10)]
            if b and b[x * 100000 + y] then near = near + 1 end
        end
    end
    return n, near
end

-- loaded zombies, and how many of them carry Wandering Hordes' modData flags (set by its server code);
-- also the modData keys seen on this client's zombies (anything at all synced from the server?)
local function zombieFlags()
    local n, flagged, keys = 0, 0, {}
    pcall(function()
        local list = getCell():getZombieList()
        n = list:size()
        for i = 0, n - 1 do
            local z = list:get(i)
            local md = z and z:getModData() or nil
            if md and (md.isWandering or md.whVirtualId ~= nil or md.isSprinter or md.wanderingdelete) then
                flagged = flagged + 1
            end
            if md then
                for k in pairs(md) do keys[tostring(k)] = true end
            end
        end
    end)
    local list = {}
    for k in pairs(keys) do list[#list + 1] = k end
    table.sort(list)
    return n, flagged, table.concat(list, ",")
end

local steps, idx, stepAt, t0, lastReport = nil, 1, nil, nil, 0
local tp = nil   -- {x, y, tries, at}: a teleport that has not arrived yet (the server sometimes ignores one)

local function teleport(p, x, y)
    SendCommandToServer("/teleportto " .. x .. "," .. y .. ",0")
    if tp.tries > 3 then   -- fallback: move the player ourselves
        p:setX(x + 0.5); p:setY(y + 0.5)
        pcall(function() p:setLastX(x + 0.5); p:setLastY(y + 0.5) end)
    end
end

local function checkTeleport(p, now)
    if not tp then return end
    if math.abs(p:getX() - tp.x) <= 3 and math.abs(p:getY() - tp.y) <= 3 then
        log(string.format("tp arrived at %d,%d (try %d)", tp.x, tp.y, tp.tries))
        tp = nil
    elseif now - tp.at > 5000 then
        if tp.tries >= 6 then
            log(string.format("tp FAILED to %d,%d (still at %d,%d)", tp.x, tp.y, math.floor(p:getX()), math.floor(p:getY())))
            tp = nil
            return
        end
        tp.tries = tp.tries + 1
        tp.at = now
        log(string.format("tp retry %d to %d,%d (at %d,%d)", tp.tries, tp.x, tp.y, math.floor(p:getX()), math.floor(p:getY())))
        teleport(p, tp.x, tp.y)
    end
end

local function parseScript(s)
    local out = {}
    for item in string.gmatch(s or "", "[^;]+") do
        out[#out + 1] = item
    end
    return out
end

local function sandboxChange(p, kv)
    local key, value = string.match(kv, "^([%w_]+)=([%w_.]+)$")
    if not key then return end
    local opts = SandboxOptions.new()
    opts:copyValuesFrom(getSandboxOptions())
    local o = opts:getOptionByName("WHPerfFix." .. key)
    if not o then
        log("sandbox option WHPerfFix." .. key .. " not found")
        return
    end
    if value == "true" then o:setValue(true)
    elseif value == "false" then o:setValue(false)
    else o:setValue(tonumber(value) or value) end
    opts:sendToServer()
    log("sent sandbox change WHPerfFix." .. key .. "=" .. value)
end

Events.OnTick.Add(function()
    local c = readCfg()
    local p = getPlayer()
    if not p or not c.script then return end
    local now = getTimestampMs()
    p:setInvulnerable(true)
    if not t0 then
        t0 = now
        steps = parseScript(c.script)
        stepAt = now + 8000      -- let the world settle after the join
        log("in game at " .. math.floor(p:getX()) .. "," .. math.floor(p:getY()) .. "; script " .. #steps .. " steps")
        if SandboxVars and SandboxVars.WHPerfFix then
            local s = SandboxVars.WHPerfFix
            log("client sees sandbox WHPerfFix ClientOffload=" .. tostring(s.ClientOffload) .. " TrimWallMap="
                .. tostring(s.TrimWallMap) .. " KeepRadius=" .. tostring(s.KeepRadius))
        end
    end
    if now - lastReport >= 10000 then
        lastReport = now
        local n, near = gridStats(p)
        local st = WHPerfFix and WHPerfFix.Trim and WHPerfFix.Trim.status() or nil
        local last = st and st.last or nil
        local on, off = -1, -1
        if WHPerfFix and WHPerfFix.clientStatus then on, off = WHPerfFix.clientStatus() end
        local zn, zflag, zkeys = zombieFlags()
        log(string.format("cli t=%.0f grid=%d near=%d/3721 pos=%d,%d step=%d trim passes=%s lastRemoved=%s lastKept=%s "
            .. "whHandlers run=%d held=%d zombies=%d withWHmodData=%d modDataKeys=[%s]",
            (now - t0) / 1000, n, near, math.floor(p:getX()), math.floor(p:getY()), idx,
            tostring(st and st.passes), tostring(last and last.removed), tostring(last and last.kept), on, off, zn, zflag,
            zkeys))
    end
    checkTeleport(p, now)
    if now < stepAt or idx > #steps then return end
    local s = steps[idx]
    idx = idx + 1
    local cmd, arg = string.match(s, "^(%w+):?(.*)$")
    log(string.format("step %d/%d %s at t=%.0f", idx - 1, #steps, s, (now - t0) / 1000))
    if cmd == "wait" then
        stepAt = now + (tonumber(arg) or 0) * 1000
        return
    elseif cmd == "tp" then
        local x, y = string.match(arg, "^(%d+),(%d+)$")
        tp = { x = tonumber(x), y = tonumber(y), tries = 1, at = now }
        teleport(p, tp.x, tp.y)
    elseif cmd == "spawn" then
        sendClientCommand(p, "WanderingHordes", "ForceSpawn", {})
    elseif cmd == "enc" or cmd == "sh" or cmd == "probe" or cmd == "spot" or cmd == "tpwh" then
        sendClientCommand(p, "WHTrimTest", cmd, { arg = arg })
    elseif cmd == "sb" then
        sandboxChange(p, arg)
    elseif cmd == "done" then
        local w = getFileWriter("WHTrimTest_done.txt", true, false)
        w:write("done\n")
        w:close()
        log("script done")
    end
    stepAt = now + 500
end)

-- tpwh: the server names where a Wandering Hordes zombie is; go there (to see it loaded on this client)
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "WHTrimTest" or command ~= "tpwh" then return end
    local p = getPlayer()
    if not p or not args or not args.x then
        log("tpwh: no Wandering Hordes zombie on the server")
        return
    end
    local x, y = math.floor(args.x) + 2, math.floor(args.y) + 2
    log(string.format("tpwh: %d WH zombie(s) on the server, going to %d,%d", args.n or 0, x, y))
    tp = { x = x, y = y, tries = 1, at = getTimestampMs() }
    teleport(p, x, y)
end)

log("client helper loaded")
