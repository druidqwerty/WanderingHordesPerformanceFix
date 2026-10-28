import java.io.FileReader;
import java.io.Reader;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaCallFrame;
import se.krka.kahlua.vm.LuaClosure;

/**
 * LuaRun plus a high-resolution clock for offline benchmarks: Lua global nanoMs() = System.nanoTime() in ms.
 * Runs the given Lua files in order in one Kahlua environment (game folder as working directory).
 */
public final class LuaBench {
    public static void main(String[] args) throws Exception {
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        env.rawset("nanoMs", (JavaFunction) (LuaCallFrame cf, int n) -> {
            cf.push(System.nanoTime() / 1e6);
            return 1;
        });
        KahluaThread thread = new KahluaThread(System.out, platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        for (String path : args) {
            LuaClosure closure;
            try (Reader r = new FileReader(path, java.nio.charset.StandardCharsets.UTF_8)) {
                closure = LuaCompiler.loadis(r, path, env);
            }
            Object[] res = thread.pcall(closure, new Object[0]);
            if (res.length == 0 || res[0] != Boolean.TRUE) {
                System.out.println("ERROR in " + path + ":");
                for (int i = 1; i < res.length; i++) System.out.println("  " + res[i]);
                System.exit(1);
            }
        }
    }
}
