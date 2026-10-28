-- Offline bench + equality check of the migration map (WH_Config.lua) with WH's own IsHighwayCell and with
-- the add-on's numeric one (WHPerfFix.installFastHighway, loaded before this file). Run by tools/LuaBench.java:
-- mig_mocks.lua, WH_Config.lua, <add-on file(s)>, migbench.lua.
local WH = WanderingHordes
local days = { 0, 3, 7, 14, 28, 60 }

local function snapshot()
    local s = {}
    for x = 0, 64 do
        for y = 0, 64 do
            s[x * 65 + y] = WH.GetCellMigrationChance(x, y)
        end
    end
    return s
end

local function timeInstant(day, reps)
    MOCK_HOURS = 24 + day * 24 + 1
    local best, sum = math.huge, 0
    for _ = 1, reps do
        local t0 = nanoMs()
        WH.UpdateMigrationMap(true)
        local dt = nanoMs() - t0
        sum = sum + dt
        if dt < best then best = dt end
    end
    return best, sum / reps, snapshot()
end

-- the daily background rebuild: UpdateMigrationMap() on a new day, then StepAsyncMigrationUpdate every tick
local function timeAsync(day)
    MOCK_HOURS = 24 + (day - 1) * 24 + 1
    WH.UpdateMigrationMap(true)
    MOCK_HOURS = 24 + day * 24 + 1
    WH.UpdateMigrationMap()
    local ticks, maxMs, sum, steps = 0, 0, 0, 0
    for _ = 1, 600 do
        local t0 = nanoMs()
        WH.StepAsyncMigrationUpdate()
        local dt = nanoMs() - t0
        ticks = ticks + 1
        sum = sum + dt
        if dt > 0.5 then steps = steps + 1 end
        if dt > maxMs then maxMs = dt end
    end
    return maxMs, sum, steps, snapshot()
end

local function run(tag, reps)
    local out = { instant = {}, async = {} }
    for _, d in ipairs(days) do
        local best, avg, snap = timeInstant(d, reps)
        out.instant[d] = snap
        print(string.format("%-8s day %3d: instant map (100 steps) best %7.1f ms, avg %7.1f ms (%.2f ms/step)",
            tag, d, best, avg, best / 100))
    end
    for _, d in ipairs({ 1, 15 }) do
        local maxMs, sum, steps, snap = timeAsync(d)
        out.async[d] = snap
        print(string.format("%-8s day %3d: daily rebuild over 600 ticks: %d steps > 0.5 ms, max %.1f ms/tick, total %.0f ms",
            tag, d, steps, maxMs, sum))
    end
    return out
end

local function same(a, b)
    local diff, n = 0, 0
    for k, v in pairs(a) do
        n = n + 1
        if b[k] ~= v then diff = diff + 1 end
    end
    return diff, n
end

-- warm-up (JIT)
for _ = 1, 3 do MOCK_HOURS = 25; WH.UpdateMigrationMap(true) end

-- the shared file was loaded with FastMigrationMap=false (mig_mocks): WH's own function is in place
local original = WH.IsHighwayCell
local before = run("original", 3)
SandboxVars.WHPerfFix.FastMigrationMap = true
local ok = WHPerfFix.applyFastHighway()
print("applyFastHighway: " .. tostring(ok) .. ", replaced: " .. tostring(WH.IsHighwayCell ~= original))
for _ = 1, 3 do MOCK_HOURS = 25; WH.UpdateMigrationMap(true) end
local after = run("fast", 3)

local bad = 0
for _, d in ipairs(days) do
    local diff, n = same(before.instant[d], after.instant[d])
    print(string.format("day %3d instant map: %d of %d cells differ", d, diff, n))
    bad = bad + diff
end
for _, d in ipairs({ 1, 15 }) do
    local diff, n = same(before.async[d], after.async[d])
    print(string.format("day %3d daily rebuild: %d of %d cells differ", d, diff, n))
    bad = bad + diff
end
-- the function itself on every cell of the grid and around it, and on odd arguments
local fnBad = 0
for x = -2, 66 do
    for y = -2, 66 do
        if original(x, y) ~= WH.IsHighwayCell(x, y) then fnBad = fnBad + 1 end
    end
end
for _, a in ipairs({ { 17.5, 39 }, { "17", "39" }, { "16", 38 }, { 0, 0 }, { -0, 0 } }) do
    if original(a[1], a[2]) ~= WH.IsHighwayCell(a[1], a[2]) then fnBad = fnBad + 1 end
end
print("IsHighwayCell answers that differ: " .. fnBad)
SandboxVars.WHPerfFix.FastMigrationMap = false
WHPerfFix.applyFastHighway()
local restored = WH.IsHighwayCell == original
SandboxVars.WHPerfFix.FastMigrationMap = true
WHPerfFix.applyFastHighway()
local again = WH.IsHighwayCell ~= original
print("setting off -> WH's own function back: " .. tostring(restored) .. "; on again -> fast: " .. tostring(again))
print((bad == 0 and fnBad == 0 and restored and again) and "MIGRATION MAP IDENTICAL" or "MIGRATION MAP DIFFERS")
