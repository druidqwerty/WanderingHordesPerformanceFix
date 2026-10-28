"""Summarize [WHPerfProbe] windows from server.out.log / client.out.log: one row per 10 s window with
ticks/s, zombies, and ms/tick of each timed handler (short names)."""
import re, sys, os
NAMES = {"OnTick WH_Server.lua:3697": "mgr", "OnTick WH_Server.lua:4676": "scan", "OnTick WH_Config.lua:320": "migr",
         "OnZombieUpdate WH_Server.lua:4407": "zupd", "OnZombieUpdate probe-empty:0": "zupd0",
         "EveryTenMinutes WH_Server.lua:4702": "10min", "OnClientCommand WH_Server.lua:4157": "cmd",
         "EveryOneMinute WH_Server.lua:1234": "1min", "OnZombieDead WH_Server.lua:4282": "zdead",
         "OnGameStart WH_Server.lua:4199": "start", "OnServerStarted WH_Server.lua:4199": "srvstart"}
WIN = re.compile(r"\[WHPerfProbe\] (srv|cli) window ([\d.]+) s: (\d+) ticks \(([\d.]+)/s\), max tick gap (\d+) ms, zombies (-?\d+)")
ROW = re.compile(r"\[WHPerfProbe\] (srv|cli)  (\S+ \S+)\s+calls\s+(\d+) \(\s*([\d.]+)/s\) ms/tick\s+([\d.]+) us/call\s+([\d.]+) max\s+(\d+) ms")
TOT = re.compile(r"\[WHPerfProbe\] (srv|cli)  total timed ([\d.]+) ms in ([\d.]+) s = ([\d.]+) ms/tick")
def run(path, tag):
    rows, cur = [], None
    for ln in open(path, encoding="utf-8", errors="replace"):
        m = WIN.search(ln)
        if m:
            cur = {"n": len(rows), "tps": float(m.group(4)), "gap": int(m.group(5)), "zom": int(m.group(6))}
            rows.append(cur)
            continue
        m = ROW.search(ln)
        if m and cur is not None:
            key = NAMES.get(m.group(2), m.group(2).split()[-1])
            cur[key] = (float(m.group(5)), int(m.group(7)), float(m.group(6)))
            continue
        m = TOT.search(ln)
        if m and cur is not None:
            cur["tot"] = float(m.group(4))
    cols = ["mgr", "scan", "migr", "zupd", "zupd0", "cmd", "10min", "zdead", "WHSaveTrim.lua:405"]
    print(f"== {tag}: {len(rows)} windows   (ms/tick avg / max ms in window)")
    print("win  t/s  gap  zomb | " + " | ".join(f"{c[:8]:>13s}" for c in cols) + " |  total")
    for r in rows:
        cells = []
        for c in cols:
            v = r.get(c)
            cells.append(f"{v[0]:7.3f}/{v[1]:4d}" if v else " " * 13)
        print(f"{r['n']:3d} {r['tps']:5.1f} {r['gap']:4d} {r['zom']:5d} | " + " | ".join(cells) + f" | {r.get('tot', 0):6.3f}")
for p, t in ((sys.argv[1], "server"), (sys.argv[2], "client")):
    if os.path.isfile(p):
        run(p, t)
