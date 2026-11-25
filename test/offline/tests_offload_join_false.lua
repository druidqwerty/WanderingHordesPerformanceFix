-- ClientOffload=false already set before WH_Server.lua loads: all 10 handlers register immediately,
-- OnGameStart runs WH's initServerLogic natively once, and a later true -> false toggle must not repeat it.
T.say("-- client offload false before WH_Server.lua loads")
local M = WHPerfFix
check(#M.handlers == T.wh.count, "all WH handlers tracked")
check(T.whListed() == T.wh.count, "all WH handlers registered immediately when ClientOffload=false")
T.fire("OnGameStart")
check(T.whCalls("start") == 1, "native OnGameStart runs initServerLogic once")
SandboxVars.WHPerfFix.ClientOffload = true
T.tick(31, 100)
check(T.whListed() == 0, "toggled true: all WH handlers removed")
SandboxVars.WHPerfFix.ClientOffload = false
T.tick(31, 100)
check(T.whListed() == T.wh.count, "toggled false: all WH handlers re-registered")
check(T.whCalls("start") == 1, "toggled true->false: initServerLogic still ran only once")
