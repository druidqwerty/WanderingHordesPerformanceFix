#!/usr/bin/env bash
# Offline bench on a COPY of a real global_mod_data.bin (tools/GmdBench.java): load/save times like
# GlobalModData, the add-on's per-tick cost on the real table, the trimmed file.
#   bash tools/bench.sh IN.bin OUT.bin "x,y;x,y" [radius]
# JDK=<jdk bin folder> GAME=<Project Zomboid folder> override the defaults; works in the dev workspace and the repo.
set -euo pipefail
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
JDK="${JDK:-C:/Users/druid/.openclaw/workspace/_ext/jdk/jdk-25.0.4.1+1/bin}"
GAME="${GAME:-G:/Steam/steamapps/common/ProjectZomboid}"
MOD="$HERE/mod/WanderingHordesSaveTrim"
[ -d "$MOD" ] || MOD="$HERE"
mkdir -p "$HERE/build/bench"
"$JDK/javac" -encoding UTF-8 -cp "$GAME/projectzomboid.jar" -d "$HERE/build/bench" "$HERE/tools/GmdBench.java"
cd "$GAME"
"$JDK/java" -Xmx6g -cp "$HERE/build/bench;$GAME/projectzomboid.jar" GmdBench "$1" "$2" \
  "$MOD/42/media/lua/server/WanderingHordesSaveTrim/WHSaveTrim.lua" \
  "$HERE/test/offline/bench_mocks.lua" "$3" "${4:-400}"
