#!/usr/bin/env bash
# Offline tests: syntax check with the game's Kahlua compiler, then the add-on against a mocked game API
# (test/offline) in the game's own Kahlua VM and stdlib: the wall-map trim on the server, a client and in
# single player, the take-over of the 1.0.0 table, and Wandering Hordes' server handlers on a multiplayer
# client / the server / single player (shared part).
# JDK=<jdk bin folder> GAME=<Project Zomboid folder> override the defaults. Works in the dev workspace
# (mod/WanderingHordesPerformanceFix/42) and in the GitHub repo (42/ at the root).
set -euo pipefail
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
JDK="${JDK:-C:/Users/druid/.openclaw/workspace/_ext/jdk/jdk-25.0.4.1+1/bin}"
GAME="${GAME:-G:/Steam/steamapps/common/ProjectZomboid}"
CP="$HERE/build/luacheck;$GAME/projectzomboid.jar"
MOD="$HERE/mod/WanderingHordesPerformanceFix"
[ -d "$MOD" ] || MOD="$HERE"
SHARED="$MOD/42/media/lua/shared/WanderingHordesPerformanceFix/WHPerfFix_Shared.lua"
TRIM="$MOD/42/media/lua/server/WanderingHordesPerformanceFix/WHPerfFix_Trim.lua"
T="$HERE/test/offline"
TT="$HERE/test/WHTrimTest/42/media/lua"

mkdir -p "$HERE/build/luacheck"
"$JDK/javac" -encoding UTF-8 -cp "$GAME/projectzomboid.jar" -d "$HERE/build/luacheck" "$HERE/tools/LuaCheck.java" "$HERE/tools/LuaRun.java"
"$JDK/java" -cp "$CP" LuaCheck "$SHARED" "$TRIM" "$TT/client/WHTrimTest.lua" "$TT/server/WHTrimTest_Server.lua"
# stdlib.lua is read from the working directory
cd "$GAME"
"$JDK/java" -cp "$CP" LuaRun "$T/mocks.lua" \
  "$T/reset_server.lua" "$SHARED" "$TRIM" "$T/tests_server.lua" \
  "$T/reset_client.lua" "$SHARED" "$TRIM" "$T/tests_client.lua" \
  "$T/reset_sp.lua" "$SHARED" "$TRIM" "$T/tests_sp.lua" \
  "$T/reset_migrate.lua" "$SHARED" "$TRIM" "$T/tests_migrate.lua" \
  "$T/reset_offload_client.lua" "$SHARED" "$T/wh_fake_server.lua" "$T/tests_offload.lua" \
  "$T/reset_offload_server.lua" "$SHARED" "$T/wh_fake_server.lua" "$T/tests_offload_server.lua" \
  "$T/reset_offload_sp.lua" "$SHARED" "$T/wh_fake_server.lua" "$T/tests_offload_server.lua" \
  "$T/reset_offload_sp.lua" "$SHARED" "$T/wh_fake_server.lua" "$T/tests_offload_late.lua" \
  "$T/summary.lua"
