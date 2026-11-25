-- ClientOffload=false from join: OnGameStart runs WH's initServerLogic natively, and a later
-- true -> false toggle must not run initServerLogic a second time. Also checks case-insensitive path matching.
T.say("-- client offload false at start + case-insensitive path")
SandboxVars.WHPerfFix.ClientOffload = false
local lowFn = T.fn("G:/x/mods/WanderingHordes_Core/42/media/lua/server/wh_server.lua", function() end)
Events.OnTick.Add(lowFn)
check(T.listed("OnTick", lowFn), "lowercase wh_server.lua registered when ClientOffload=false")

T.fire("OnGameStart")
check(T.whCalls("start") == 1, "ClientOffload=false at join: WH's OnGameStart runs natively once")

SandboxVars.WHPerfFix.ClientOffload = true
T.tick(31, 100)
check(T.whListed() == 0 and not T.listed("OnTick", lowFn), "toggled true: WH + lowercase wh_server.lua held")

SandboxVars.WHPerfFix.ClientOffload = false
T.tick(31, 100)
check(T.whListed() == T.wh.count and T.listed("OnTick", lowFn), "toggled false: re-registered")
check(T.whCalls("start") == 1, "toggled true->false: initServerLogic not repeated after native OnGameStart")
