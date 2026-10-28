T.say(string.format("offline tests: %d passed, %d failed", T.passed, T.failed))
if T.failed > 0 then error("offline tests failed") end
