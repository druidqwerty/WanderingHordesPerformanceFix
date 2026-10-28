-- WH's handlers were registered while the game was not (yet) a multiplayer client (a Lua state kept from
-- single player, or isClient() not set yet when WH_Server.lua loaded): the next check takes them out.
-- Run after reset_offload_sp + the shared file + wh_fake_server.lua.
T.say("-- registered before becoming a multiplayer client")
check(T.whListed() == T.wh.count, "registered while not a client")
T.side = "client"
T.tick(31, 100)
check(T.whListed() == 0, "taken out at the next check on the client")
check(T.otherListed() == #T.other + 1, "other handlers untouched")
local mgr = T.whCalls("mgr")
T.tick(20, 100)
check(T.whCalls("mgr") == mgr, "no longer run")
