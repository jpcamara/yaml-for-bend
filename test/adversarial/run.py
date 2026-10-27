"""Runs build/stress on each input in a directory and prints, for each,
its size, the wall time, the peak memory and what it loaded. Inputs named
v11-* are read with the YAML 1.1 types.

    python3 test/adversarial/run.py build/adversarial [timeout-seconds]
"""
import os, sys, tempfile, time

root = os.path.join(os.path.dirname(__file__), "..", "..")
folder = sys.argv[1]
timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 120
# ru_maxrss is in bytes on macOS and kilobytes on Linux.
unit = 1 if sys.platform == "darwin" else 1024

def run(path):
    with tempfile.TemporaryFile() as out:
        start = time.time()
        args = ["stress", path] + (["v11"] if os.path.basename(path).startswith("v11-") else [])
        pid = os.posix_spawn(os.path.join(root, "build", "stress"), args, os.environ,
                             file_actions=[(os.POSIX_SPAWN_DUP2, out.fileno(), 1), (os.POSIX_SPAWN_DUP2, out.fileno(), 2)])
        while True:
            done, status, usage = os.wait4(pid, os.WNOHANG)
            if done:
                break
            if time.time() - start > timeout:
                os.kill(pid, 9); os.wait4(pid, 0)
                return None, None, "TIMEOUT"
            time.sleep(0.01)
        took = time.time() - start
        out.seek(0)
        text = out.read().decode("utf-8", "replace").strip().replace("\n", " | ")
        code = os.waitstatus_to_exitcode(status)
        if code != 0:
            text = "CRASH (exit %d) %s" % (code, text)
        return took, usage.ru_maxrss * unit / 1e6, text

print("%-32s %9s %8s %7s  %s" % ("input", "bytes", "seconds", "MB", "result"))
for name in sorted(os.listdir(folder)):
    path = os.path.join(folder, name)
    took, mb, text = run(path)
    shown = ("%8.2f" % took) if took is not None else ">%7d" % timeout
    print("%-32s %9d %8s %7s  %s" % (name[:-5], os.path.getsize(path), shown, "%.0f" % mb if mb else "-", text[:80]))
    sys.stdout.flush()
