#!/usr/bin/env bash
# Offline tests: syntax check with the game's Kahlua compiler, then the add-on against a mocked game API
# (test/offline) in the game's own Kahlua VM and stdlib: server, client and single-player sides.
# JDK=<jdk bin folder> GAME=<Project Zomboid folder> override the defaults. Works in the dev workspace
# (mod/WanderingHordesSaveTrim/42) and in the GitHub repo (42/ at the root).
set -euo pipefail
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
JDK="${JDK:-C:/Users/druid/.openclaw/workspace/_ext/jdk/jdk-25.0.4.1+1/bin}"
GAME="${GAME:-G:/Steam/steamapps/common/ProjectZomboid}"
CP="$HERE/build/luacheck;$GAME/projectzomboid.jar"
MOD="$HERE/mod/WanderingHordesSaveTrim"
[ -d "$MOD" ] || MOD="$HERE"
MODLUA="$MOD/42/media/lua/server/WanderingHordesSaveTrim/WHSaveTrim.lua"
T="$HERE/test/offline"

mkdir -p "$HERE/build/luacheck"
"$JDK/javac" -encoding UTF-8 -cp "$GAME/projectzomboid.jar" -d "$HERE/build/luacheck" "$HERE/tools/LuaCheck.java" "$HERE/tools/LuaRun.java"
"$JDK/java" -cp "$CP" LuaCheck "$MODLUA" "$HERE/test/WHTrimTest/42/media/lua/client/WHTrimTest.lua" "$HERE/test/WHTrimTest/42/media/lua/server/WHTrimTest_Server.lua"
# stdlib.lua is read from the working directory
cd "$GAME"
"$JDK/java" -cp "$CP" LuaRun "$T/mocks.lua" \
  "$T/reset_server.lua" "$MODLUA" "$T/tests_server.lua" \
  "$T/reset_client.lua" "$MODLUA" "$T/tests_client.lua" \
  "$T/reset_sp.lua" "$MODLUA" "$T/tests_sp.lua" \
  "$T/summary.lua"
