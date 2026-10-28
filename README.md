# Wandering Hordes Save Trim [B42]

<p align="center"><img src="docs/preview.png" alt="Wandering Hordes Save Trim" width="320"></p>

An add-on for [Wandering Hordes](https://steamcommunity.com/sharedfiles/filedetails/?id=3759920384) (by SpaceGamer_R):
stops its wall map from bloating the save and freezing the server at every world save.
Wandering Hordes itself is not changed and none of its code is copied; this is a separate Lua mod.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3829140377 · **Source code (MIT):** https://github.com/druidqwerty/WanderingHordesSaveTrim

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Free and open source. The code is written by an AI; the direction, the testing and the time are mine. If the mod made your game better: [support on Boosty](https://boosty.to/lrgpp).

Русская версия: [README_RU.md](README_RU.md)

## The problem

Wandering Hordes remembers walls, fences and water for every tile any player has ever been near: its scanners
fill a "passability grid" (the global ModData table `WH_PassabilityGrid_v2`) within 30 tiles of every player,
every tick, and nothing is ever removed. A long drive leaves a 61-tile-wide trail of it. The game writes all
global ModData into `global_mod_data.bin` at every world save, on the server's main thread, and reads all of it
at every start.

On our two-player co-op save:

- the wall map was **58 MB of a 76 MB** `global_mod_data.bin` (36,646 cells of 10x10 tiles), and it keeps
  growing with every trip;
- every world save (every 5 minutes) froze the server for ~0.3 s; the **first save after a start took 6.3 s**,
  and the game paused every player for it;
- loading it took **6.9 s** of every server start, and in memory it took over 400 MB of the server's Java heap.

Wandering Hordes reads the map only to check whether the square where a horde is about to appear is fenced in
(it follows walls up to 300 tiles from that square, which is at most 75 tiles from a player) and as a water
shortcut. A missing tile simply means "not scanned yet": the scanners fill it again when a player comes near.

## What the add-on does

- Every 2 minutes (setting) it walks over the map, a few hundred cells per tick, and removes the 10x10 cells that
  are farther than 400 tiles (setting) from all of these:
  - every player;
  - the spot where each player joined the game (usually the base he logged out at), also while he is away on a
    long trip;
  - the spot where each offline player was last seen (multiplayer server, remembered for 30 days);
  - every safehouse.
- Near the players nothing changes: 400 tiles covers everything Wandering Hordes' fence check can reach from a
  horde that appears near a player (75 + 300 tiles).
- Far away Wandering Hordes forgets its wall map; when somebody comes back there, it scans the area again, as in
  a place nobody has visited yet.
- It never removes anything when there is nobody to keep around, and never creates or replaces Wandering Hordes'
  table.
- It runs on the server (that is what the save contains) and in single player. On multiplayer clients it trims
  their own in-memory copy too: B42 runs Wandering Hordes' scanners there as well (clients never save it).

## Live test

A local dedicated server and one client with Wandering Hordes [Core] + the Vanilla+ preset (our co-op settings),
our real 76 MB `global_mod_data.bin` (58 MB of it the wall map), a world save every minute, a scripted tour
(base, 1.8 km, 3.4 km, base) with forced hordes:

| | without the add-on | with the add-on |
|---|---|---|
| Wall map | 36,646 cells, 58 MB | 4,221 cells, 7 MB |
| `global_mod_data.bin` | 76.1 MB | 25.0 MB |
| Server freeze for ModData at each save | 0.33-0.43 s (once 2.0 s) | 0.10-0.17 s |
| First save after a start (players paused) | 8.2 s | 0.55 s |

- The first check on the old 76 MB map: 9 s spread over 92 ticks, about 0.5 ms per tick (max 4 ms). Later checks:
  about 1 s, under 1 ms per tick. Between checks: nothing (0.006 ms per tick).
- Restarting from the trimmed save: loaded in 0.14 s on the test server (0.21-0.30 s for the old 76 MB file).
  The real co-op server took 6.9 s for the old file (it runs 300+ mods); its new time will show in the next session.
- Offline bench with the game's own load/save code: about 433 MB less Java heap after the trim; first save
  4.9 s -> 0.23 s, later saves 125 -> 40 ms.
- Wandering Hordes' own check for where a horde may appear (`isSquareSafeForSpawn`, a 21x21 lattice around the
  base, 5 tiles apart) gives the same answers with and without the add-on, also after trips 1.8 km away (2.5 and
  5 minutes, several checks each) when the base is not a safehouse: it is kept as the join spot. Hordes kept
  appearing as before. No Lua errors.
- An admin's sandbox change in the running game applied at the next check (radius 400 -> 150; switched off: no
  more checks).
- The other 18 MB of that file belong to other mods; this add-on touches only Wandering Hordes' table.

## Requirements and installation

- Build 42.21+ and [Wandering Hordes](https://steamcommunity.com/sharedfiles/filedetails/?id=3759920384) [Core]
  (with one of its presets, as usual).
- Single player: enable it.
- Multiplayer: it must be in the server's mod list: add `WanderingHordesSaveTrim` to `Mods=` (after
  `WanderingHordesCore`) and `3829140377` to `WorkshopItems=`. Players who join get it from the Workshop
  automatically.
- It can be added to an existing save: the first check trims the old map (a few seconds, spread over ticks), the
  file shrinks at the next world save. Removing it later is safe: Wandering Hordes just grows its map again.
- No Java, no ZombieBuddy.

## Settings

The host sets them for everyone: Host > Manage settings > Edit > Sandbox > **Wandering Hordes: Save Trim**. An
admin can change them in a running game (Admin > Sandbox options); they apply at the next check.

- **Trim Wandering Hordes' wall map** (on). Off: as without this add-on.
- **Keep radius (tiles)** (400; 100-5000). Smaller = smaller save; a fenced place farther away is scanned again
  only when a player comes near it.
- **Keep around where players joined** (on).
- **Keep around offline players** (on; multiplayer server).
- **Keep around safehouses** (on).
- **Trim every (minutes)** (2; 1-60).
- **Debug log** (off): a line for every check in the console.

## Is it working?

The server console (`console.txt` in single player) has `[WHSaveTrim] 1.0.0 loaded (server)` (or `(sp)`), and
after the first check on an old save a line like
`[WHSaveTrim] pass 1: 36646 cells checked, 32425 removed (~48.4 MB), 4221 kept (~6.9 MB); keep radius 400 around 1 player(s), 1 join spot(s), 0 offline spot(s), 0 safehouse(s); 92 ticks, 0.50 ms/tick, max 3 ms, 9.1 s`.
`global_mod_data.bin` in the save folder shrinks at the next world save.

## Known limitations

- A trimmed place is, for Wandering Hordes, like a place nobody has visited: it scans 30 tiles around the player
  at once and the rest as players walk around. Until then its fence check there may let a horde appear inside a
  large fenced area it does not know yet (as in any new area). Your base is kept (join spot, offline spot,
  safehouse); for other fenced places you care about, make them a safehouse or raise the radius.
- The join spot is where a player came into the game; if you log out somewhere else, that is your next join spot.
  A safehouse is the sure way to keep a base.
- Only Wandering Hordes' table is touched; other mods' data in `global_mod_data.bin` stays as it is.

## How it works (for modders)

- Wandering Hordes' keys (`WH_Server.lua`): cell key `gx * 100000 + gy` with `gx = floor(x / 10)`, tile key
  `x * 100000 + y`, masks NORTH 1, WEST 2, WATER 4, SCANNED 8.
- A check iterates `pairs()` over the table across ticks (Kahlua's `pairs()` works on a snapshot of the keys, so
  removing entries meanwhile is safe; cells added meanwhile wait for the next check), 400 cells per tick, each
  cell tested against squares (in cell coordinates) around players, join spots, offline spots and safehouses;
  where the players are now is added every tick.
- Own data: global ModData `WHSaveTrim` on the server only: `spots[name]` (last seen) and `homes[name]` (join
  spot), refreshed every 2 s, dropped after 30 days without the player. Single player and clients keep the join
  spots of the session in memory.
- Settings are read from `SandboxVars.WHSaveTrim` at every check (Enabled: every tick).

## Source and tests

- `common/` and `42/` are the mod itself (`42/media/lua/server/WanderingHordesSaveTrim/WHSaveTrim.lua`); the release
  zip and the Workshop item contain the same files.
- `tools/offline_test.sh`: syntax check with the game's own Kahlua compiler, then 93 offline checks
  (`test/offline`: a mocked game API; server, client and single player) in the game's Lua VM. Needs a JDK and the
  game: `JDK=<jdk>/bin GAME=<ProjectZomboid folder> tools/offline_test.sh`.
- `tools/bench.sh` + `tools/GmdBench.java`: load/save times and the add-on's per-tick cost on a copy of a real
  `global_mod_data.bin`; `tools/gmd.py`: table sizes in a `global_mod_data.bin` and what a trim would keep.
- `livetest/whlive.py` + `test/WHTrimTest/`: the live test (a dedicated server and a client without Steam, a
  scripted tour) and its helper mod.
- `python tools/build.py --no-install --no-staging`: the offline tests, then the mod folder and the zip in `dist/`.

## My mods
- [SmoothRide MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827367565) — smooth multiplayer vehicles.
- [ZombieSync MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827946115) — smooth multiplayer zombies.
- [Tripping Zombies MP Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3829034899) — the same Tripping Zombies trips for every player.
- **Wandering Hordes Save Trim** — no more save freezes from Wandering Hordes' wall map (this mod).
- [Host Unstuck](https://steamcommunity.com/sharedfiles/filedetails/?id=3829163351) — un-sticks and speeds up the Workshop download when hosting from the menu.

## Credits and license

Wandering Hordes is by SpaceGamer_R; this add-on only works alongside it.
Add-on code: MIT.
