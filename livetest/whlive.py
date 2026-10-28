"""Wandering Hordes Save Trim live test: a local dedicated server + one client (no Steam), Wandering Hordes
[Core] + Vanilla+ preset (the user's PRALIFE settings) + the add-on + the test helper (test/WHTrimTest).

  python -I whlive.py start NAME [--addon on|off|none] [--sandbox "Key=V,..."] [--world WORLD] [--gmd FILE]
                                 [--script "wait:20;enc;tp:X,Y;..."] [--save-every MIN] [--addon-dir DIR]
      prepares env/ (own cache dirs; the user's Zomboid folder is never touched), copies the saved test world
      WORLD (env/worlds/WORLD; default: a fresh world), puts FILE in as global_mod_data.bin, starts the
      server, then the client (which runs the script), and returns
  python -I whlive.py wait [SECONDS]       follow the logs until the script is done (default 900 s)
  python -I whlive.py finish [--keep-world WORLD]
                                           RCON quit (the server saves and exits), stop the client, collect
                                           logs + the saved global_mod_data.bin into results/<stamp>_<NAME>,
                                           optionally keep the saved world as env/worlds/WORLD; then analyze
  python -I whlive.py analyze [DIR]        numbers from a results dir (default: the latest)
  python -I whlive.py kill                 stop the test processes

Before a launch: take workspace/.pz-game.lock and make sure the user is not playing.
"""
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
GAME = r"G:\Steam\steamapps\common\ProjectZomboid"
JAVA = os.path.join(GAME, "jre64", "bin", "java.exe")
ENV = os.path.join(HERE, "env")
SRV = os.path.join(ENV, "srv")
CLI = os.path.join(ENV, "cli")
WORLDS = os.path.join(ENV, "worlds")
RESULTS = os.path.join(HERE, "results")
NAME = "WHTEST"
SAVE = os.path.join(SRV, "Saves", "Multiplayer", NAME)
PORT = 17371
RCON_PORT = 17375
RCON_PASS = "whtest"
WS = r"G:\Steam\steamapps\workshop\content\108600\3759920384\mods"
BASE = "8296,12159,0"   # the PRALIFE players' spot (players.db), in the densest part of their WH grid
PIDS = os.path.join(ENV, "pids.json")
STATE = os.path.join(ENV, "run.json")


def mods(addon, addon_dir=None):
    m = {"WanderingHordesCore": os.path.join(WS, "WanderingHordes_Core"),
         "WanderingHordesVanillaPlus": os.path.join(WS, "WanderingHordesVanillaPlus")}
    if addon != "none":
        m["WanderingHordesSaveTrim"] = addon_dir or os.path.join(PROJ, "mod", "WanderingHordesSaveTrim")
    m["WHTrimTest"] = os.path.join(PROJ, "test", "WHTrimTest")
    return m


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def copy_mods(dest, mm):
    md = os.path.join(dest, "mods")
    if os.path.isdir(md):
        shutil.rmtree(md)
    os.makedirs(md)
    for name, src in mm.items():
        shutil.copytree(src, os.path.join(md, name))
        os.makedirs(os.path.join(md, name, "common"), exist_ok=True)
    write(os.path.join(md, "default.txt"),
          "VERSION = 1,\n\nmods\n{\n" + "".join(f"    mod = {m},\n" for m in mm) + "}\n\nmaps\n{\n}\n")
    write(os.path.join(md, "reset-mods-42_00.txt"),
          "If this file does not exist, default.txt will be reset to empty (no mods active).")


def options_ini():
    src = os.path.join(os.path.expanduser("~"), "Zomboid", "options.ini")
    lines = open(src, encoding="utf-8", errors="replace").read().splitlines() if os.path.isfile(src) else []
    over = {"fullScreen": "false", "borderless": "false", "width": "1280", "height": "720", "vsync": "false",
            "frameRate": "60", "soundVolume": "0", "musicVolume": "0", "ambientVolume": "0", "jumpScareVolume": "0",
            "vehicleEngineVolume": "0", "voiceVolumeMic": "0", "voiceVolumePlayers": "0",
            "doneNewSaveFolder": "true", "tutorialDone": "true"}
    out, seen = [], set()
    for ln in lines:
        k = ln.split("=", 1)[0]
        if k in over:
            out.append(f"{k}={over[k]}")
            seen.add(k)
        else:
            out.append(ln)
    out += [f"{k}={v}" for k, v in over.items() if k not in seen]
    return "\n".join(out) + "\n"


def prepare(a):
    for d in (os.path.join(SRV, "mods"), os.path.join(SRV, "Server"), os.path.join(SRV, "Logs"), CLI):
        if os.path.isdir(d):
            shutil.rmtree(d)
    if os.path.isdir(SAVE):
        shutil.rmtree(SAVE)
    for f in ("server-console.txt",):
        if os.path.isfile(os.path.join(SRV, f)):
            os.remove(os.path.join(SRV, f))
    os.makedirs(SRV, exist_ok=True)
    mm = mods(a["addon"], a.get("addon_dir"))
    copy_mods(SRV, mm)
    write(os.path.join(SRV, "Server", NAME + ".ini"), "\n".join([
        "Mods=" + ";".join(mm), "WorkshopItems=", "Map=Muldraugh, KY", "Public=false", "Open=true", "PVP=false",
        "PauseEmpty=false", "SpawnPoint=" + BASE, "MaxPlayers=4", f"DefaultPort={PORT}", f"UDPPort={PORT + 1}",
        "DoLuaChecksum=false", "UPnP=false", "ServerWelcomeMessage=", "Password=", "AutoCreateUserInWhiteList=true",
        "SteamScoreboard=false", "SafetySystem=false", f"SaveWorldEveryMinutes={a['save_every']}",
        f"RCONPort={RCON_PORT}", f"RCONPassword={RCON_PASS}",
    ] + [f"{x}=3" for x in ("AntiCheatSafety", "AntiCheatSpeed", "AntiCheatNoClip", "AntiCheatPlayer")]) + "\n")
    trim = ""
    if a["addon"] != "none":
        items = [kv.split("=", 1) for kv in (a.get("sandbox") or "").split(",") if "=" in kv]
        if a["addon"] == "off":
            items = [i for i in items if i[0].strip() != "Enabled"] + [["Enabled", "false"]]
        trim = "    WHSaveTrim = {\n" + "".join(f"        {k.strip()} = {v.strip()},\n" for k, v in items) + "    },\n"
    wh = open(os.path.join(HERE, "wh_sandbox_pralife.lua"), encoding="utf-8").read().rstrip() + "\n"
    # no natural population (only Wandering Hordes' hordes); day length 1 h like a busy test
    write(os.path.join(SRV, "Server", NAME + "_SandboxVars.lua"),
          "SandboxVars = {\n    VERSION = 6,\n    Zombies = 4,\n    DayLength = 3,\n    StartTime = 2,\n"
          "    ZombieConfig = {\n        PopulationMultiplier = 0.0,\n        PopulationStartMultiplier = 0.0,\n"
          "        PopulationPeakMultiplier = 0.0,\n    },\n" + wh + trim + "}\n")
    write(os.path.join(SRV, "Server", NAME + "_spawnregions.lua"),
          'function SpawnRegions()\n\treturn {\n\t\t{ name = "Muldraugh, KY", file = "media/maps/Muldraugh, KY/spawnpoints.lua" },\n\t}\nend\n')
    if a.get("world"):
        src = os.path.join(WORLDS, a["world"])
        shutil.copytree(src, SAVE)
    if a.get("gmd"):
        os.makedirs(SAVE, exist_ok=True)
        shutil.copy(a["gmd"], os.path.join(SAVE, "global_mod_data.bin"))
    copy_mods(CLI, mm)
    write(os.path.join(CLI, "options.ini"), options_ini())
    write(os.path.join(CLI, "Lua", "WHTrimTest.txt"),
          f"user=admin\npass=whtest\nip=127.0.0.1\nport={PORT}\nscript={a.get('script') or 'wait:60;done'}\n")
    json.dump(a, open(STATE, "w"))


def popen(args, log):
    f = open(log, "w", encoding="utf-8", errors="replace")
    flags = subprocess.CREATE_NEW_PROCESS_GROUP | 0x00000008  # DETACHED_PROCESS
    try:
        return subprocess.Popen(args, cwd=GAME, stdout=f, stderr=subprocess.STDOUT, creationflags=flags | 0x01000000)
    except OSError:
        return subprocess.Popen(args, cwd=GAME, stdout=f, stderr=subprocess.STDOUT, creationflags=flags)


def alive(pid):
    out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH", "/FO", "CSV"], capture_output=True, text=True).stdout
    return f'"{pid}"' in out


def kill():
    if not os.path.isfile(PIDS):
        return
    pids = list(json.load(open(PIDS)).values())
    for pid in pids:
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    t0 = time.time()
    while time.time() - t0 < 30 and any(alive(p) for p in pids):
        time.sleep(1)
    os.remove(PIDS)


def wait_for(path, pattern, timeout, pid=None):
    rx = re.compile(pattern)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if pid is not None and not alive(pid):
            return False
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                if rx.search(f.read()):
                    return True
        time.sleep(2)
    return False


COMMON = ["--enable-native-access=ALL-UNNAMED", "-XX:-CreateCoredumpOnCrash", "-XX:-OmitStackTraceInFastThrow",
          "-XX:+UseZGC"]


def windows_of(pid):
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    return found


def click(pid):
    """a left click in the middle of the client's window, posted to it (no focus, no real mouse): the game
    reads GLFW's button state, which the window procedure sets from WM_LBUTTONDOWN/UP"""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    n = 0
    for hwnd in windows_of(pid):
        r = wintypes.RECT()
        user32.GetClientRect(hwnd, ctypes.byref(r))
        lp = ((r.bottom // 2) << 16) | (r.right // 2)
        user32.PostMessageW(hwnd, 0x0200, 0, lp)          # WM_MOUSEMOVE
        user32.PostMessageW(hwnd, 0x0201, 0x0001, lp)     # WM_LBUTTONDOWN
        time.sleep(0.4)
        user32.PostMessageW(hwnd, 0x0202, 0, lp)          # WM_LBUTTONUP
        n += 1
    return n


def click_to_start(pid, timeout=900):
    """waits for the client's world to load, then clicks the "click to start" prompt until it is in the game"""
    log = os.path.join(ENV, "client.out.log")
    if not wait_for(log, r"game loading took", timeout, pid):
        print("client did not finish loading", flush=True)
        return False
    t0 = time.time()
    while time.time() - t0 < 180:
        if wait_for(log, r"\[WHTrimTest\] in game at", 1):
            print(f"client in game ({time.time() - t0:.0f} s after loading)", flush=True)
            return True
        print("click to start:", click(pid), "window(s)", flush=True)
        time.sleep(4)
    return False


def launch():
    srv = popen([JAVA] + COMMON + ["-Xmx3072m", "-Djava.awt.headless=true",
                                   "-Djava.library.path=./natives/;./natives/win64/;./",
                                   "-cp", "./;projectzomboid.jar", "zombie.network.GameServer", "-cachedir=" + SRV,
                                   "-servername", NAME, "-adminusername", "admin", "-adminpassword", "whtest",
                                   "-nosteam", "-port", str(PORT), "-udpport", str(PORT + 1)],
                os.path.join(ENV, "server.out.log"))
    pids = {"server": srv.pid}
    json.dump(pids, open(PIDS, "w"))
    print("server pid", srv.pid, "- waiting for SERVER STARTED", flush=True)
    t0 = time.time()
    if not wait_for(os.path.join(ENV, "server.out.log"), r"SERVER STARTED", 900, srv.pid):
        print("server did not start; see env/server.out.log", flush=True)
        return None
    print(f"server started after {time.time() - t0:.0f} s", flush=True)
    cli = popen([JAVA] + COMMON + ["-Djava.awt.headless=true", "-Dzomboid.steam=0", "-Dzomboid.znetlog=1", "-Xmx4096m",
                                   "-Djava.library.path=./win64/;./", "-cp", "./;projectzomboid.jar",
                                   "zombie.gameStates.MainScreenState", "-cachedir=" + CLI, "-nosteam"],
                os.path.join(ENV, "client.out.log"))
    pids["client"] = cli.pid
    json.dump(pids, open(PIDS, "w"))
    print("client pid", cli.pid, flush=True)
    if not click_to_start(cli.pid):
        print("client not in game; see env/client.out.log", flush=True)
    return pids


FOLLOW = re.compile(r"\[WHTrimTest\] (?!srv near)|\[WHSaveTrim\]|WANDERING HORDES LOG|Saving took|Saving GlobalModData|"
                    r"Pausing clients|GlobalModData.init|SERVER STARTED|[Kk]icked|ERROR|Exception|STACK TRACE")


class Follower:
    FSTATE = os.path.join(ENV, "follow.json")

    def __init__(self, resume=False):
        self.pos = json.load(open(self.FSTATE)) if resume and os.path.isfile(self.FSTATE) else {}

    def save(self):
        json.dump(self.pos, open(self.FSTATE, "w"))

    def poll(self):
        for name in ("server.out.log", "client.out.log"):
            path = os.path.join(ENV, name)
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8", errors="replace") as f:
                f.seek(self.pos.get(name, 0))
                chunk = f.read()
                self.pos[name] = f.tell()
            for ln in chunk.splitlines():
                if FOLLOW.search(ln):
                    print(f"  {name.split('.')[0]:6s} {ln.strip()[:260]}", flush=True)


def wait(max_s):
    done = os.path.join(CLI, "Lua", "WHTrimTest_done.txt")
    pids = json.load(open(PIDS)) if os.path.isfile(PIDS) else {}
    fol = Follower(resume=True)
    t0 = time.time()
    state = "running"
    while time.time() - t0 < max_s:
        fol.poll()
        if os.path.isfile(done):
            state = "done"
            break
        dead = [r for r, pid in pids.items() if not alive(pid)]
        if dead:
            state = "dead:" + ",".join(dead)
            break
        time.sleep(5)
    fol.poll()
    fol.save()
    print("state:", state, flush=True)
    return state


def rcon(cmd, timeout=10):
    def pkt(i, t, body):
        b = body.encode("utf-8") + b"\x00\x00"
        return struct.pack("<iii", len(b) + 8, i, t) + b

    def read(s):
        hdr = b""
        while len(hdr) < 4:
            c = s.recv(4 - len(hdr))
            if not c:
                raise ConnectionError("rcon closed")
            hdr += c
        (n,) = struct.unpack("<i", hdr)
        data = b""
        while len(data) < n:
            c = s.recv(n - len(data))
            if not c:
                raise ConnectionError("rcon closed")
            data += c
        i, t = struct.unpack("<ii", data[:8])
        return i, t, data[8:-2].decode("utf-8", "replace")

    s = socket.create_connection(("127.0.0.1", RCON_PORT), timeout=timeout)
    try:
        s.sendall(pkt(1, 3, RCON_PASS))
        i, t, _ = read(s)
        if t == 0:   # some servers send an empty response first
            i, t, _ = read(s)
        if i == -1:
            raise PermissionError("rcon auth failed")
        s.sendall(pkt(2, 2, cmd))
        try:
            _, _, body = read(s)
        except (socket.timeout, ConnectionError):
            body = ""
        return body
    finally:
        s.close()


def collect(name, keep_world=None):
    stamp = time.strftime("%Y%m%d_%H%M%S")
    res = os.path.join(RESULTS, f"{stamp}_{name}")
    os.makedirs(res, exist_ok=True)
    for d, tag in ((os.path.join(SRV, "Logs"), "srv"), (os.path.join(CLI, "Logs"), "cli")):
        if os.path.isdir(d):
            for f in os.listdir(d):
                if "DebugLog" in f or f.endswith("console.txt"):
                    shutil.copy(os.path.join(d, f), os.path.join(res, tag + "_" + f))
    for f in ("server.out.log", "client.out.log", "run.json"):
        if os.path.isfile(os.path.join(ENV, f)):
            shutil.copy(os.path.join(ENV, f), os.path.join(res, f))
    if os.path.isfile(os.path.join(CLI, "console.txt")):
        shutil.copy(os.path.join(CLI, "console.txt"), os.path.join(res, "cli_console.txt"))
    g = os.path.join(SAVE, "global_mod_data.bin")
    if os.path.isfile(g):
        shutil.copy(g, os.path.join(res, "global_mod_data.bin"))
    if keep_world:
        dst = os.path.join(WORLDS, keep_world)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.copytree(SAVE, dst)
        print("world kept:", dst, flush=True)
    return res


def finish(keep_world=None):
    st = json.load(open(STATE)) if os.path.isfile(STATE) else {}
    pids = json.load(open(PIDS)) if os.path.isfile(PIDS) else {}
    if pids.get("client"):
        subprocess.run(["taskkill", "/PID", str(pids["client"]), "/T", "/F"], capture_output=True)
    if pids.get("server") and alive(pids["server"]):
        try:
            print("rcon quit:", rcon("quit"), flush=True)
        except Exception as e:  # noqa: BLE001
            print("rcon failed:", e, flush=True)
        t0 = time.time()
        while time.time() - t0 < 240 and alive(pids["server"]):
            time.sleep(2)
        print(f"server exited after {time.time() - t0:.0f} s" if not alive(pids["server"]) else "server still alive",
              flush=True)
    kill()
    res = collect(st.get("name", "run"), keep_world)
    print("results:", res, flush=True)
    analyze(res)


# Lua errors (any mod) and errors naming Wandering Hordes / the add-on / the helper; vanilla start-up noise excluded
LUAERR = re.compile(r"ERROR|STACK TRACE|attempted index|KahluaException|Exception")
NOISE = re.compile(r"handleMannequinZone|AdvancedAnimator|NoSuchFile|FluidContainerScript|AngelCodeFont|"
                   r"Translator.reportMissing|Formatting \"Sandbox_|WANDERING HORDES LOG|mergeRoomsOntoMetaCell|"
                   r"not adding suspicious zone|CraftRecipeComponentScript|WindowsException|Missing ThumpSound|"
                   r"AntiCheatPacketException|IsoPropertyType")
TS = re.compile(r"^\[(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\.(\d\d\d)\]")


def ts(line):
    m = TS.match(line)
    if not m:
        return None
    d, mo, y, h, mi, s, ms = (int(x) for x in m.groups())
    return ((d * 24 + h) * 60 + mi) * 60 + s + ms / 1000.0


def analyze(res=None):
    if res is None:
        res = sorted(os.path.join(RESULTS, d) for d in os.listdir(RESULTS))[-1]
    out = []
    srv = [f for f in os.listdir(res) if f.startswith("srv_") and "DebugLog-server" in f]
    lines = []
    for f in sorted(srv):
        lines += open(os.path.join(res, f), encoding="utf-8", errors="replace").read().splitlines()
    gmd_load = None
    t_init = None
    saves = []
    for i, ln in enumerate(lines):
        if "GlobalModData.init() start" in ln:
            t_init = ts(ln)
        elif "GlobalModData.init() end" in ln and t_init is not None:
            gmd_load = ts(ln) - t_init
        elif "Saving GlobalModData" in ln:
            t = ts(ln)
            nxt = next((ts(x) for x in lines[i + 1:i + 6] if ts(x) is not None), None)
            took = next((float(re.search(r"Saving took ([\d.]+)", x).group(1)) for x in lines[i:i + 8]
                         if "Saving took" in x), None)
            paused = any("Pausing clients" in x for x in lines[i:i + 4])
            saves.append((t, (nxt - t) * 1000 if nxt else None, took, paused))
    started = next((ts(x) for x in lines if "SERVER STARTED" in x), None)
    first = ts(lines[0]) if lines else None
    out.append(f"results: {res}")
    out.append(f"server: GlobalModData.init {gmd_load * 1000:.0f} ms" if gmd_load is not None else "server: no GlobalModData.init lines")
    if started and first:
        out.append(f"server: log start -> SERVER STARTED {started - first:.1f} s")
    for t, gm, took, paused in saves:
        rel = t - started if (t and started) else 0
        out.append(f"  save at +{rel:6.0f} s: GlobalModData {gm:7.0f} ms, whole save {took if took else 0:7.0f} ms"
                   + (" (clients paused)" if paused else ""))
    for ln in lines:
        if "[WHSaveTrim]" in ln:
            out.append("  " + ln[ln.index("[WHSaveTrim]"):][:300])
    errs = [ln for ln in lines if LUAERR.search(ln) and not NOISE.search(ln)]
    out.append(f"server error lines: {len(errs)}")
    out += ["  " + e[:250] for e in errs[:12]]
    cli_files = [f for f in os.listdir(res) if f.startswith("cli_")]
    clines = []
    for f in sorted(cli_files):
        clines += open(os.path.join(res, f), encoding="utf-8", errors="replace").read().splitlines()
    cerrs = [ln for ln in clines if LUAERR.search(ln) and not NOISE.search(ln)]
    out.append(f"client error lines: {len(cerrs)}")
    out += ["  " + e[:250] for e in cerrs[:12]]
    g = os.path.join(res, "global_mod_data.bin")
    if os.path.isfile(g):
        out.append(f"saved global_mod_data.bin: {os.path.getsize(g)} bytes")
    text = "\n".join(out)
    print(text)
    write(os.path.join(res, "summary.txt"), text + "\n")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    args = sys.argv[2:]

    def opt(name, default=None):
        return args[args.index(name) + 1] if name in args else default

    if cmd == "start":
        kill()
        for f in (Follower.FSTATE,):
            if os.path.isfile(f):
                os.remove(f)
        a = {"name": args[0], "addon": opt("--addon", "on"), "sandbox": opt("--sandbox", ""), "world": opt("--world"),
             "gmd": opt("--gmd"), "script": opt("--script"), "save_every": int(opt("--save-every", "1")),
             "addon_dir": opt("--addon-dir")}
        prepare(a)
        if launch() is None:
            kill()
            sys.exit(1)
        Follower().save()
    elif cmd == "wait":
        wait(int(args[0]) if args else 900)
    elif cmd == "finish":
        finish(opt("--keep-world"))
    elif cmd == "analyze":
        analyze(args[0] if args else None)
    elif cmd == "kill":
        kill()
    elif cmd == "rcon":
        print(rcon(" ".join(args)))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
