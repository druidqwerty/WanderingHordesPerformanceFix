-- server (dedicated or the co-op host's server) and single player: WH keeps every handler, whatever the
-- setting says. Run after reset_offload_server / reset_offload_sp + the shared file + wh_fake_server.lua.
T.say("-- " .. T.side .. ": Wandering Hordes keeps its handlers")
local M = WHPerfFix
check(#M.handlers == T.wh.count, T.side .. ": all of WH's handlers recognized")
check(T.whListed() == T.wh.count, T.side .. ": all of them registered")
check(T.otherListed() == #T.other + 1, T.side .. ": other handlers registered")
T.tick(40, 100)
check(T.whCalls("mgr") == 40 and T.whCalls("scan") == 40 and T.whCalls("migr") == 40, T.side .. ": WH ticks")
SandboxVars.WHPerfFix.ClientOffload = true
T.tick(31, 100)
SandboxVars.WHPerfFix.ClientOffload = false
T.tick(31, 100)
check(T.whListed() == T.wh.count, T.side .. ": the setting never takes them out here")
T.fire(T.side == "server" and "OnServerStarted" or "OnGameStart")
check(T.whCalls("start") == 1, T.side .. ": WH's start-up runs by its own event, once")
check(T.logged("held back") == nil, T.side .. ": nothing held back, nothing logged about it")
