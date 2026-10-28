"""Read Project Zomboid's global_mod_data.bin (B42 format, see GlobalModData.save/KahluaTableImpl.save) and
report the Wandering Hordes passability grid (WH_PassabilityGrid_v2).

  python -I gmd.py FILE                  tables and sizes, WH grid stats
  python -I gmd.py FILE --keep X,Y[;X,Y] [--radius R]
                                         what a trim around these points would keep (square radius R, default 500)

File: int version, int tableCount, then per table: int blockSize, string tag, table.
Table: int count, then count x (byte keyType, key, byte valueType, value); 0 string (short len + UTF-8),
1 double (8 bytes), 2 table, 3 boolean (1 byte). Big-endian.
"""
import struct
import sys

GRID = "WH_PassabilityGrid_v2"


def read_tables(data):
    """[(tag, offset_of_table, block_size)] without parsing the tables"""
    ver, n = struct.unpack_from(">ii", data, 0)
    pos = 8
    out = []
    for _ in range(n):
        (block,) = struct.unpack_from(">i", data, pos)
        pos += 4
        (ln,) = struct.unpack_from(">h", data, pos)
        tag = data[pos + 2:pos + 2 + ln].decode("utf-8", "replace")
        out.append((tag, pos + 2 + ln, block))
        pos += block
    return ver, out


def parse_grid(data, pos):
    """{bucketKey: {tileKey: mask}} for the WH grid table (all keys/values doubles)"""
    unpack = struct.unpack_from
    (nb,) = unpack(">i", data, pos)
    pos += 4
    grid = {}
    for _ in range(nb):
        kt = data[pos]
        if kt != 1:
            raise ValueError(f"bucket key type {kt} at {pos}")
        (bk,) = unpack(">d", data, pos + 1)
        vt = data[pos + 9]
        pos += 10
        if vt != 2:
            raise ValueError(f"bucket value type {vt} at {pos}")
        (nt,) = unpack(">i", data, pos)
        pos += 4
        # each tile entry: 1 + 8 + 1 + 8 bytes
        bucket = {}
        for i in range(nt):
            tk, mask = unpack(">xdxd", data, pos)
            bucket[tk] = mask
            pos += 18
        grid[bk] = bucket
    return grid, pos


def bucket_xy(key):
    gx = int(key // 100000)
    gy = int(key - gx * 100000)
    return gx, gy


def grid_bytes(grid):
    """serialized size of the grid table (as KahluaTableImpl.save writes it)"""
    return 4 + sum(10 + 4 + 18 * len(b) for b in grid.values())


def main():
    path = sys.argv[1]
    data = open(path, "rb").read()
    ver, tables = read_tables(data)
    print(f"{path}: {len(data)} bytes, version {ver}, {len(tables)} tables")
    for tag, off, block in sorted(tables, key=lambda t: -t[2])[:12]:
        print(f"  {block:>10}  {tag}")
    g = [t for t in tables if t[0] == GRID]
    if not g:
        print("no", GRID)
        return
    tag, off, block = g[0]
    grid, end = parse_grid(data, off)
    tiles = sum(len(b) for b in grid.values())
    xs = [bucket_xy(k)[0] for k in grid]
    ys = [bucket_xy(k)[1] for k in grid]
    print(f"{GRID}: {block} bytes, {len(grid)} buckets (10x10 cells), {tiles} tiles, "
          f"{tiles / max(1, len(grid)):.1f} tiles/bucket")
    if grid:
        print(f"  extent x {min(xs) * 10}..{max(xs) * 10 + 9}, y {min(ys) * 10}..{max(ys) * 10 + 9}")
    masks = {}
    for b in grid.values():
        for m in b.values():
            masks[m] = masks.get(m, 0) + 1
    print("  masks:", ", ".join(f"{int(m)}:{c}" for m, c in sorted(masks.items())))
    if "--keep" in sys.argv:
        pts = [tuple(float(v) for v in p.split(",")) for p in sys.argv[sys.argv.index("--keep") + 1].split(";")]
        radius = float(sys.argv[sys.argv.index("--radius") + 1]) if "--radius" in sys.argv else 500.0
        kept = {}
        for k, b in grid.items():
            gx, gy = bucket_xy(k)
            cx, cy = gx * 10 + 5, gy * 10 + 5
            if any(max(abs(cx - px), abs(cy - py)) <= radius + 5 for px, py in pts):
                kept[k] = b
        kt = sum(len(b) for b in kept.values())
        print(f"  keep r={radius:.0f} around {pts}: {len(kept)} buckets, {kt} tiles, {grid_bytes(kept)} bytes "
              f"({100.0 * grid_bytes(kept) / block:.1f} % of the grid); file would be about "
              f"{len(data) - block + grid_bytes(kept) + 2 + len(GRID)} bytes")


if __name__ == "__main__":
    main()
