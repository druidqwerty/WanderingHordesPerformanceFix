# Wandering Hordes Performance Fix [B42]

<p align="center"><img src="docs/preview.png" alt="Wandering Hordes Performance Fix" width="320"></p>

An add-on for [Wandering Hordes](https://steamcommunity.com/sharedfiles/filedetails/?id=3759920384) (by SpaceGamer_R):
removes what it costs in performance where it does nothing useful, and keeps what it does exactly the same.
Wandering Hordes itself is not changed and none of its code is copied; this is a separate Lua mod.
Formerly **Wandering Hordes Save Trim** (1.0.0): same Workshop item, new name and id.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3829140377 · **Source code (MIT):** https://github.com/druidqwerty/WanderingHordesPerformanceFix

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Free and open source. The code is written by an AI; the direction, the testing and the time are mine. If the mod made your game better: [support on Boosty](https://boosty.to/lrgpp).

Русская версия: [README_RU.md](README_RU.md)

## What it fixes

### 1. Every multiplayer client runs Wandering Hordes' server code, for nothing

Build 42 loads a mod's `media/lua/server` files on clients too, so Wandering Hordes' server logic (`WH_Server.lua`)
starts on every player's machine. Hordes are spawned, steered and saved by the server only, and zombies arrive on a
client without any of Wandering Hordes' data (checked: the same horde zombies carry its data on the server and
nothing on the client), so on a client all of that work is thrown away:

- its three wall scanners every frame (0.2-0.4 ms per frame on our test client, up to 4 ms);
- its migration map at game start: a **0.6 s freeze** when you join;
- the same map again once per game day: about 6 ms in every 5th frame for ~8 s (a stutter);
- its horde managers every frame and a Lua call on every zombie update (2,200 calls per second with 37 zombies
  around);
- its own wall map in the client's memory, growing with every tile you pass.

The add-on keeps those handlers from being registered on a multiplayer client. The server (and single player) keeps
all of them, so hordes appear, walk and behave as before.

### 2. Its wall map bloats the save

Wandering Hordes remembers walls, fences and water for every tile any player has ever been near: its scanners
fill a "passability grid" (the global ModData table `WH_PassabilityGrid_v2`) within 30 tiles of every player,
every tick, and nothing is ever removed. A long drive leaves a 61-tile-wide trail of it. The game writes all
global ModData into `global_mod_data.bin` at every world save, on the server's main thread, and reads all of it
at every start. On our two-player co-op save the wall map was **58 MB of a 76 MB** `global_mod_data.bin` (36,646
cells of 10x10 tiles): every world save froze the server for ~0.3 s, the **first save after a start took 6.3 s**
(the game paused every player for it), and loading it took **6.9 s** of every server start.

Wandering Hordes reads the map only to check whether the square where a horde is about to appear is fenced in
(it follows walls up to 300 tiles from that square, which is at most 75 tiles from a player) and as a water
shortcut. A missing tile simply means "not scanned yet": the scanners fill it again when a player comes near.
So every 2 minutes (setting) the add-on removes the 10x10 cells that are farther than 400 tiles (setting) from all
of these:

- every player;
- the spot where each player joined the game (usually the base he logged out at), also while he is away on a long
  trip;
- the spot where each offline player was last seen (multiplayer server, remembered for 30 days);
- every safehouse.

Near the players nothing changes: 400 tiles covers everything Wandering Hordes' fence check can reach from a horde
that appears near a player (75 + 300 tiles). Far away Wandering Hordes forgets its wall map; when somebody comes
back there, it scans the area again, as in a place nobody has visited yet. It never removes anything when there is
nobody to keep around, and never creates or replaces Wandering Hordes' table.

## Live tests

A local dedicated server and one client with Wandering Hordes [Core] + the Vanilla+ preset (our co-op settings),
vanilla zombies, forced hordes and teleports to unexplored places; the cost of every event handler of Wandering
Hordes timed on both sides by a test probe.

On the client (60 fps):

| | without the add-on | with the add-on |
|---|---|---|
| Wandering Hordes' Lua every frame (wall scanners, managers) | 0.2-0.4 ms | none |
| Freeze when joining (its migration map) | 0.6 s | none |
| Once per game day (the map again) | ~6 ms in every 5th frame for ~8 s | none |
| Calls on zombie updates | one per zombie per frame | none |
| Its wall map in the client's memory | grows with every tile | none |

- Switched off in the running game (admin, sandbox): the client registered Wandering Hordes' handlers within 3 s,
  froze for 0.6 s (its start-up, which the add-on saves) and scanned again; switched back on: gone again.
- The horde zombies the client had loaded (6-16 at a time, next to three forced hordes) had no Wandering Hordes
  data on the client, while the server had it on all 144 of them.

On the server, with our real 76 MB `global_mod_data.bin` (58 MB of it the wall map) and a world save every minute
(1.0.0, the same numbers again with 2.0.0):

| | without the add-on | with the add-on |
|---|---|---|
| Wall map | 36,646 cells, 58 MB | 4,221 cells, 7 MB |
| `global_mod_data.bin` | 76.1 MB | 25.0 MB |
| Server freeze for ModData at each save | 0.33-0.43 s (once 2.0 s) | 0.10-0.17 s |
| First save after a start (players paused) | 8.2 s | 0.53 s |

- The first check on the old 76 MB map: 9 s spread over 92 ticks, about 0.5 ms per tick (max 3-4 ms). Later checks:
  about 1 s, under 1 ms per tick. Between checks: nothing measurable.
- Offline bench with the game's own load/save code: about 433 MB less Java heap after the trim; first save
  4.9 s -> 0.23 s, later saves 125 -> 40 ms.
- Wandering Hordes' own check for where a horde may appear (`isSquareSafeForSpawn`, a 21x21 lattice around the
  base, 5 tiles apart) gives the same answers with and without the add-on, also after trips 1.8 km away when the
  base is not a safehouse (it is kept as the join spot). Hordes kept appearing as before. No Lua errors.
- An admin's sandbox change in the running game applied at the next check (radius 400 -> 150; trim off: no more
  checks).

## Requirements and installation

- Build 42.21+ and [Wandering Hordes](https://steamcommunity.com/sharedfiles/filedetails/?id=3759920384) [Core]
  (with one of its presets, as usual).
- Single player: enable it (the save trim works there; there is no client to unload).
- Multiplayer: it must be in the server's mod list: add `WanderingHordesPerformanceFix` to `Mods=` (after
  `WanderingHordesCore`) and `3829140377` to `WorkshopItems=`. Players who join get it from the Workshop
  automatically; the client part needs nothing else.
- Coming from Wandering Hordes Save Trim 1.0.0: replace `WanderingHordesSaveTrim` with
  `WanderingHordesPerformanceFix` in `Mods=` (the Workshop number stays). The settings page has a new name, so its
  values start from the defaults again; the remembered player spots are taken over.
- It can be added to an existing save: the first check trims the old map (a few seconds, spread over ticks), the
  file shrinks at the next world save. Removing it later is safe: Wandering Hordes just grows its map again and
  runs on clients again.
- No Java, no ZombieBuddy.

## Settings

The host sets them for everyone: Host > Manage settings > Edit > Sandbox > **Wandering Hordes: Performance Fix**.
An admin can change them in a running game (Admin > Sandbox options); they apply within seconds (the client part)
or at the next check (the trim).

- **Clients skip Wandering Hordes' server work** (on). Off: clients run it again, as without this add-on.
- **Trim Wandering Hordes' wall map** (on). Off: the map grows as without this add-on.
- **Keep radius (tiles)** (400; 100-5000). Smaller = smaller save; a fenced place farther away is scanned again
  only when a player comes near it.
- **Keep around where players joined** (on).
- **Keep around offline players** (on; multiplayer server).
- **Keep around safehouses** (on).
- **Trim every (minutes)** (2; 1-60).
- **Debug log** (off): a line for every check in the console.

## Is it working?

- A client's `console.txt` has `[WHPerfFix] multiplayer client: 10 of Wandering Hordes' server handlers held back,
  0 run here: ...`.
- The server console has `[WHPerfFix] 2.0.0 loaded (server)`, and after the first check on an old save a line like
  `[WHPerfFix] pass 1: 36646 cells checked, 32425 removed (~48.4 MB), 4221 kept (~6.9 MB); keep radius 400 around 1 player(s), 1 join spot(s), 0 offline spot(s), 0 safehouse(s); 92 ticks, 0.45 ms/tick, max 3 ms, 9.1 s`.
  `global_mod_data.bin` in the save folder shrinks at the next world save.

## Known limitations

- The server still does all of Wandering Hordes' own work: its scanners (0.2-0.5 ms per tick per player in our
  test), its horde managers, and its migration map (0.6-0.7 s at server start, ~6 ms steps for about a minute once
  per game day). That is what makes Wandering Hordes work; the add-on does not touch it.
- A trimmed place is, for Wandering Hordes, like a place nobody has visited: it scans 30 tiles around the player
  at once and the rest as players walk around. Until then its fence check there may let a horde appear inside a
  large fenced area it does not know yet (as in any new area). Your base is kept (join spot, offline spot,
  safehouse); for other fenced places you care about, make them a safehouse or raise the radius.
- The join spot is where a player came into the game; if you log out somewhere else, that is your next join spot.
  A safehouse is the sure way to keep a base.
- The client part recognizes Wandering Hordes' handlers by its file `media/lua/server/WH_Server.lua`. If an update
  of Wandering Hordes renames that file, the add-on simply holds nothing back (the client log line then says 0) and
  everything works as without it.
- Only Wandering Hordes' table is touched; other mods' data in `global_mod_data.bin` stays as it is.

## How it works (for modders)

- Client part (`42/media/lua/shared/WanderingHordesPerformanceFix/WHPerfFix_Shared.lua`): a `shared/` file runs
  before every `server/` file, so it wraps `Events.<E>.Add` of the events Wandering Hordes uses. A closure whose
  `getFilenameOfClosure()` ends in `/media/lua/server/WH_Server.lua` (plus `WanderingHordes.StepAsyncMigrationUpdate`,
  which that file registers) is recorded; on a multiplayer client (`isClient()`) it is not passed on to the game's
  `Add`. Everybody else's handlers go straight through. Every 3 s (and at `OnGameStart`) the setting is applied:
  off registers them with the game's `Add` (and calls Wandering Hordes' `OnGameStart` start-up once, late), on
  takes them out with the game's `Remove`. `Event.trigger` is an index loop that re-reads the list size, so adding
  or removing inside `OnTick` is safe. The game ignores `Add` only while it hot-reloads a Lua file (debug).
- Trim (`42/media/lua/server/WanderingHordesPerformanceFix/WHPerfFix_Trim.lua`): Wandering Hordes' keys
  (`WH_Server.lua`): cell key `gx * 100000 + gy` with `gx = floor(x / 10)`, tile key `x * 100000 + y`, masks NORTH 1,
  WEST 2, WATER 4, SCANNED 8. A check iterates `pairs()` over the table across ticks (Kahlua's `pairs()` works on a
  snapshot of the keys, so removing entries meanwhile is safe; cells added meanwhile wait for the next check), 400
  cells per tick, each cell tested against squares (in cell coordinates) around players, join spots, offline spots
  and safehouses; where the players are now is added every tick.
- Own data: global ModData `WHPerfFix` on the server only: `spots[name]` (last seen) and `homes[name]` (join spot),
  refreshed every 2 s, dropped after 30 days without the player; the 1.0.0 table `WHSaveTrim` is taken over once and
  removed. Single player and clients keep the join spots of the session in memory.
- Settings are read from `SandboxVars.WHPerfFix` at every check (TrimWallMap: every tick; ClientOffload: every 3 s).

## Source and tests

- `common/` and `42/` are the mod itself; the release zip and the Workshop item contain the same files.
- `tools/offline_test.sh`: syntax check with the game's own Kahlua compiler, then 148 offline checks
  (`test/offline`: a mocked game API; the trim on a server, a client and in single player, the take-over of the 1.0.0
  table, and Wandering Hordes' handlers on a client / the server / single player, including the live switch) in the
  game's Lua VM. Needs a JDK and the game: `JDK=<jdk>/bin GAME=<ProjectZomboid folder> tools/offline_test.sh`.
- `test/WHPerfProbe/`: the timing probe of the live tests (wraps `Events.<E>.Add` and times every handler of
  Wandering Hordes and the add-on, server and client); `tools/probe_report.py` turns its log into a table.
- `tools/LuaBench.java` + `test/offline/migbench.lua`: offline timing of Wandering Hordes' migration map.
- `tools/bench.sh` + `tools/GmdBench.java`: load/save times and the trim's per-tick cost on a copy of a real
  `global_mod_data.bin`; `tools/gmd.py`: table sizes in a `global_mod_data.bin` and what a trim would keep.
- `livetest/whlive.py` + `test/WHTrimTest/`: the live test (a dedicated server and a client without Steam, a
  scripted tour) and its helper mod.
- `python tools/build.py --no-install --no-staging`: the offline tests, then the mod folder and the zip in `dist/`.

## Changelog

- **2.0.0** (2026-10-29): renamed from Wandering Hordes Save Trim (`WanderingHordesSaveTrim` ->
  `WanderingHordesPerformanceFix`, same Workshop item). New: multiplayer clients no longer run Wandering Hordes'
  server code (wall scanners every frame, the 0.6 s freeze at join, the daily stutter, the zombie-update calls).
  Settings page `WHPerfFix` (TrimWallMap, TrimIntervalMinutes, new ClientOffload); the 1.0.0 player spots are taken
  over.
- **1.0.0** (2026-10-29): the wall-map trim.

## My mods
- [SmoothRide MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827367565) — smooth multiplayer vehicles.
- [ZombieSync MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827946115) — smooth multiplayer zombies.
- [Tripping Zombies MP Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3829034899) — the same Tripping Zombies trips for every player.
- **Wandering Hordes Performance Fix** — no save freezes and no client lag from Wandering Hordes (this mod).
- [Download Unstuck](https://steamcommunity.com/sharedfiles/filedetails/?id=3829163351) — un-sticks the Workshop download when hosting from the menu.

## Credits and license

Wandering Hordes is by SpaceGamer_R; this add-on only works alongside it.
Add-on code: MIT.
