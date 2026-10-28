-- Wandering Hordes' server handlers on a multiplayer client (shared part): held back by default, registered
-- again with ClientOffload=false (and WH's start-up run once, late), taken out again with true; nobody else's
-- handlers touched. Run after reset_offload_client + the shared file + wh_fake_server.lua.
T.say("-- multiplayer client: Wandering Hordes' server handlers")
local M = WHPerfFix
check(M and M.sharedLoaded and M.VERSION == "2.0.0", "shared part loaded, version")
check(T.logged("2.0.0 shared part loaded") ~= nil, "shared load line")
check(#M.handlers == T.wh.count, "all " .. T.wh.count .. " of WH_Server.lua's handlers recognized (got " .. #M.handlers .. ")")
check(T.whListed() == 0, "none of them registered on a multiplayer client")
check(T.otherListed() == #T.other + 1, "every other handler registered (other files, look-alike names, no file)")
local on, off = M.clientStatus()
check(on == 0 and off == T.wh.count, "status: 0 run, all held")

T.tick(100, 100)
T.fire("OnZombieUpdate", {})
T.fire("EveryOneMinute")
T.fire("EveryTenMinutes")
check(T.whCalls("mgr") + T.whCalls("scan") + T.whCalls("migr") + T.whCalls("zupd") + T.whCalls("min") + T.whCalls("ten") == 0,
    "WH's server handlers never run on the client")
check(T.whCalls("o1") == 100 and T.whCalls("o2") == 100 and T.whCalls("o3") == 100 and T.whCalls("o4") == 100
    and T.whCalls("o5") == 100 and T.whCalls("oz") == 1, "the other handlers run as usual")

T.fire("OnGameStart")
check(T.whCalls("start") == 0, "WH's start-up (migration map) does not run on the client")
check(T.logged("multiplayer client: 10 of Wandering Hordes' server handlers held back, 0 run here") ~= nil,
    "OnGameStart: the client logs what it holds back")

-- an admin switches ClientOffload off in the running game: WH runs on the client again, its start-up once
SandboxVars.WHPerfFix.ClientOffload = false
T.tick(31, 100)
check(T.whListed() == T.wh.count, "ClientOffload=false: all of them registered again (got " .. T.whListed() .. ")")
check(T.whCalls("start") == 1, "WH's start-up run once, late")
local mgr0 = T.whCalls("mgr")
T.tick(10, 100)
check(T.whCalls("mgr") - mgr0 == 10 and T.whCalls("scan") >= 10, "WH's tick handlers run every tick again")
T.fire("OnZombieUpdate", {})
check(T.whCalls("zupd") == 1, "and its zombie-update handler")
check(T.otherListed() == #T.other + 1, "other handlers still registered once")

-- on again: taken out again, the start-up is not repeated
SandboxVars.WHPerfFix.ClientOffload = true
T.tick(31, 100)
check(T.whListed() == 0, "ClientOffload=true: taken out again")
local mgr1, scan1 = T.whCalls("mgr"), T.whCalls("scan")
T.tick(50, 100)
check(T.whCalls("mgr") == mgr1 and T.whCalls("scan") == scan1, "and they stop running")
SandboxVars.WHPerfFix.ClientOffload = false
T.tick(31, 100)
check(T.whListed() == T.wh.count and T.whCalls("start") == 1, "off again: registered again, start-up not repeated")
SandboxVars.WHPerfFix.ClientOffload = nil
T.tick(31, 100)
check(T.whListed() == 0, "setting missing = default on: held back")
check(T.otherListed() == #T.other + 1, "other handlers never touched")
for _, list in pairs(T.ev) do
    local seen = {}
    for _, f in ipairs(list) do
        check(not seen[f], "no handler registered twice")
        seen[f] = true
    end
end
