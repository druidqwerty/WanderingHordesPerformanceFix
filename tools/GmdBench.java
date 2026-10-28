import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.Reader;
import java.nio.BufferOverflowException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

/**
 * Offline bench on a COPY of a real global_mod_data.bin, in the game's own Kahlua VM (projectzomboid.jar):
 *  1. load it the way GlobalModData.load does (KahluaTableImpl tables, LinkedHashMap), timed;
 *  2. save it the way GlobalModData.save does (1 MB buffer + 512 KB steps on overflow, the element is
 *     written again after each step = the first save after a start; then with the final buffer size =
 *     every later save), timed;
 *  3. run WHSaveTrim.lua on it with a mocked game API (test/offline/bench_mocks.lua: players at the given
 *     positions), one tick at a time, timing every tick (System.nanoTime);
 *  4. save again (both ways), write the trimmed file, report sizes and times.
 * The save code mirrors GlobalModData.save / KahluaTableImpl.save byte for byte (strings: short length +
 * UTF-8), so sizes are exact and times comparable; the live tests measure the real thing.
 *
 *   java -cp build;projectzomboid.jar GmdBench IN.bin OUT.bin ADDON.lua MOCKS.lua "x,y;x,y" [radius]
 * (run from the game folder: stdlib.lua is read from the working directory)
 */
public final class GmdBench {
    static int lastBlockSize = -1;

    static KahluaTable loadTable(ByteBuffer in, J2SEPlatform pf) {
        int count = in.getInt();
        KahluaTable t = pf.newTable();
        for (int n = 0; n < count; n++) {
            Object k = loadValue(in, in.get(), pf);
            Object v = loadValue(in, in.get(), pf);
            t.rawset(k, v);
        }
        return t;
    }

    static Object loadValue(ByteBuffer in, byte type, J2SEPlatform pf) {
        switch (type) {
            case 0: return readString(in);
            case 1: return in.getDouble();
            case 2: return loadTable(in, pf);
            case 3: return in.get() != 0;
            default: throw new RuntimeException("bad type " + type);
        }
    }

    static String readString(ByteBuffer in) {
        int len = in.getShort();
        if (len <= 0) return "";
        byte[] b = new byte[len];
        in.get(b);
        return new String(b, StandardCharsets.UTF_8);
    }

    static void writeString(ByteBuffer out, String s) {
        byte[] b = s.getBytes(StandardCharsets.UTF_8);
        out.putShort((short) b.length);
        out.put(b);
    }

    static byte typeOf(Object o) {
        if (o instanceof String) return 0;
        if (o instanceof Double) return 1;
        if (o instanceof KahluaTableImpl) return 2;
        if (o instanceof Boolean) return 3;
        return -1;
    }

    // KahluaTableImpl.save(ByteBuffer): count savable entries, then write them (two iterator passes)
    static void saveTable(ByteBuffer out, KahluaTable t) {
        KahluaTableIterator it = t.iterator();
        int count = 0;
        while (it.advance()) if (typeOf(it.getKey()) >= 0 && typeOf(it.getValue()) >= 0) count++;
        it = t.iterator();
        out.putInt(count);
        while (it.advance()) {
            byte kb = typeOf(it.getKey()), vb = typeOf(it.getValue());
            if (kb < 0 || vb < 0) continue;
            saveValue(out, kb, it.getKey());
            saveValue(out, vb, it.getValue());
        }
    }

    static void saveValue(ByteBuffer out, byte type, Object o) {
        out.put(type);
        switch (type) {
            case 0: writeString(out, (String) o); break;
            case 1: out.putDouble((Double) o); break;
            case 2: saveTable(out, (KahluaTable) o); break;
            case 3: out.put((Boolean) o ? (byte) 1 : 0); break;
        }
    }

    static ByteBuffer ensureCapacity(ByteBuffer bb) {
        if (bb == null) {
            lastBlockSize = 0x100000;
            return ByteBuffer.allocate(lastBlockSize);
        }
        lastBlockSize = bb.capacity() + 524288;
        ByteBuffer n = ByteBuffer.allocate(lastBlockSize);
        return n.put(bb.array(), 0, bb.position());
    }

    // GlobalModData.save
    static ByteBuffer save(Map<String, KahluaTable> md) {
        ByteBuffer bb = ByteBuffer.allocate(lastBlockSize == -1 ? 0x100000 : lastBlockSize);
        bb.putInt(249);
        bb.putInt(md.size());
        for (Map.Entry<String, KahluaTable> e : md.entrySet()) {
            if (bb.capacity() - bb.position() < 4) {
                int p = bb.position();
                bb = ensureCapacity(bb);
                bb.position(p);
            }
            int p1 = bb.position();
            bb.putInt(0);
            int p2 = bb.position();
            int elem;
            while (true) {
                elem = bb.position();
                try {
                    writeString(bb, e.getKey());
                    saveTable(bb, e.getValue());
                } catch (BufferOverflowException ex) {
                    bb = ensureCapacity(bb);
                    bb.position(elem);
                    continue;
                }
                break;
            }
            int p3 = bb.position();
            bb.position(p1);
            bb.putInt(p3 - p2);
            bb.position(p3);
        }
        bb.flip();
        return bb;
    }

    static Map<String, KahluaTable> load(byte[] data, J2SEPlatform pf) {
        ByteBuffer bb = ByteBuffer.wrap(data);
        int ver = bb.getInt();
        int n = bb.getInt();
        Map<String, KahluaTable> md = new HashMap<>();
        for (int i = 0; i < n; i++) {
            bb.getInt();
            String tag = readString(bb);
            md.put(tag, loadTable(bb, pf));
        }
        return md;
    }

    static long usedHeap() {
        Runtime rt = Runtime.getRuntime();
        for (int i = 0; i < 3; i++) {
            System.gc();
            try { Thread.sleep(200); } catch (InterruptedException ignored) { }
        }
        return rt.totalMemory() - rt.freeMemory();
    }

    static String ms(long ns) { return String.format("%.1f ms", ns / 1e6); }

    static double[] timedSaves(Map<String, KahluaTable> md, String label) {
        lastBlockSize = -1;
        long t0 = System.nanoTime();
        ByteBuffer first = save(md);
        long t1 = System.nanoTime();
        // every later save starts with the final buffer size; take the median of 5
        List<Long> later = new ArrayList<>();
        int size = 0;
        for (int i = 0; i < 5; i++) {
            long a = System.nanoTime();
            ByteBuffer b = save(md);
            later.add(System.nanoTime() - a);
            size = b.limit();
        }
        Collections.sort(later);
        System.out.printf("%s: %d bytes; first save after a start %s, later saves %s (median of 5, min %s)%n",
                label, first.limit(), ms(t1 - t0), ms(later.get(2)), ms(later.get(0)));
        return new double[]{first.limit(), (t1 - t0) / 1e6, later.get(2) / 1e6};
    }

    public static void main(String[] args) throws Exception {
        String in = args[0], out = args[1], addon = args[2], mocks = args[3], players = args[4];
        int radius = args.length > 5 ? Integer.parseInt(args[5]) : 400;
        byte[] data;
        try (FileInputStream f = new FileInputStream(in)) { data = f.readAllBytes(); }
        J2SEPlatform pf = new J2SEPlatform();

        // warm-up: one full load + trim run (the game's interpreter is long warm on a running server)
        for (int round = 0; round < 2; round++) {
            boolean measure = round == 1;
            long h0 = measure ? usedHeap() : 0;
            long t0 = System.nanoTime();
            Map<String, KahluaTable> md = load(data, pf);
            long t1 = System.nanoTime();
            long h1 = measure ? usedHeap() : 0;
            KahluaTable grid = md.get("WH_PassabilityGrid_v2");
            if (measure) {
                System.out.printf("load (GlobalModData.load): %s for %d bytes, %d tables; heap +%d MB%n",
                        ms(t1 - t0), data.length, md.size(), (h1 - h0) >> 20);
                timedSaves(md, "before");
            }

            KahluaTable env = pf.newEnvironment();
            KahluaThread thread = new KahluaThread(System.out, pf, env);
            thread.debugOwnerThread = Thread.currentThread();
            KahluaTable gmd = pf.newTable();
            for (Map.Entry<String, KahluaTable> e : md.entrySet()) gmd.rawset(e.getKey(), e.getValue());
            env.rawset("__GMD", gmd);
            env.rawset("__PLAYERS", players);
            env.rawset("__RADIUS", (double) radius);
            env.rawset("__QUIET", !measure);
            for (String path : new String[]{mocks, addon}) {
                LuaClosure c;
                try (Reader r = new FileReader(path, StandardCharsets.UTF_8)) { c = LuaCompiler.loadis(r, path, env); }
                Object[] res = thread.pcall(c, new Object[0]);
                if (res.length == 0 || res[0] != Boolean.TRUE) {
                    System.out.println("ERROR in " + path);
                    for (int i = 1; i < res.length; i++) System.out.println("  " + res[i]);
                    System.exit(1);
                }
            }
            Object tick = env.rawget("__benchTick");
            Object passes = env.rawget("__benchPasses");
            // ticks until the first pass is done; time each
            List<Long> times = new ArrayList<>();
            int before = ((Double) thread.pcall(passes, new Object[0])[1]).intValue();
            long total = 0;
            Object runningFn = env.rawget("__benchRunning");
            for (int i = 0; i < 100000; i++) {
                boolean wasRunning = thread.pcall(runningFn, new Object[0])[1] == Boolean.TRUE;
                long a = System.nanoTime();
                Object[] r = thread.pcall(tick, new Object[0]);
                long d = System.nanoTime() - a;
                if (r.length == 0 || r[0] != Boolean.TRUE) {
                    System.out.println("ERROR in tick");
                    for (int j = 1; j < r.length; j++) System.out.println("  " + r[j]);
                    System.exit(1);
                }
                boolean running = wasRunning || thread.pcall(runningFn, new Object[0])[1] == Boolean.TRUE;
                if (running) { times.add(d); total += d; }
                int now = ((Double) thread.pcall(passes, new Object[0])[1]).intValue();
                if (now > before) break;
            }
            if (!measure) continue;
            Collections.sort(times);
            System.out.printf("first pass: %d ticks with work, total %s, per tick median %s, p95 %s, max %s%n",
                    times.size(), ms(total), ms(times.get(times.size() / 2)),
                    ms(times.get((int) (times.size() * 0.95))), ms(times.get(times.size() - 1)));
            Object[] st = thread.pcall(env.rawget("__benchStatus"), new Object[0]);
            System.out.println("add-on: " + st[1]);
            long h2 = usedHeap();
            System.out.printf("heap after the trim: %d MB less than after the load%n", (h1 - h2) >> 20);
            double[] after = timedSaves(md, "after");
            // steady state: a pass over the trimmed table
            Object[] r0 = thread.pcall(env.rawget("__benchPassNow"), new Object[0]);
            times.clear();
            total = 0;
            before = ((Double) thread.pcall(passes, new Object[0])[1]).intValue();
            for (int i = 0; i < 100000; i++) {
                boolean wasRunning = thread.pcall(runningFn, new Object[0])[1] == Boolean.TRUE;
                long a = System.nanoTime();
                thread.pcall(tick, new Object[0]);
                long d = System.nanoTime() - a;
                boolean running = wasRunning || thread.pcall(runningFn, new Object[0])[1] == Boolean.TRUE;
                if (running) { times.add(d); total += d; }
                int now = ((Double) thread.pcall(passes, new Object[0])[1]).intValue();
                if (now > before) break;
            }
            Collections.sort(times);
            System.out.printf("next pass (trimmed table): %d ticks, total %s, per tick median %s, max %s%n",
                    times.size(), ms(total), ms(times.get(times.size() / 2)), ms(times.get(times.size() - 1)));
            // idle tick (between passes)
            long a = System.nanoTime();
            int idle = 1000;
            for (int i = 0; i < idle; i++) thread.pcall(tick, new Object[0]);
            System.out.printf("idle tick (between passes): %.4f ms%n", (System.nanoTime() - a) / 1e6 / idle);
            lastBlockSize = -1;
            ByteBuffer outBuf = save(md);
            try (FileOutputStream f = new FileOutputStream(out)) { f.write(outBuf.array(), 0, outBuf.limit()); }
            System.out.println("wrote " + out + " (" + outBuf.limit() + " bytes)");
            // load time of the trimmed file
            byte[] d2;
            try (FileInputStream f = new FileInputStream(out)) { d2 = f.readAllBytes(); }
            long l0 = System.nanoTime();
            Map<String, KahluaTable> md2 = load(d2, pf);
            System.out.printf("load of the trimmed file: %s (%d tables)%n", ms(System.nanoTime() - l0), md2.size());
        }
    }
}
