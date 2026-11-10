"""Crawl a Gymaholic help sheet (already open) depth-first: capture every topic page, then go back."""
import subprocess, re, sys, time, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
T = ROOT / "tools"
pid = subprocess.run(["pgrep", "-x", "Gymaholic"], capture_output=True, text=True).stdout.split()[0]
prefix = sys.argv[1]
SKIP = {"Close", "Search", ""}
count = 0

def dump():
    return subprocess.run([str(T / "ax"), "dump", pid], capture_output=True, text=True).stdout

def topics(tree):
    out = []
    for line in tree.splitlines():
        m = re.match(r"\s*AXButton d='(.*?)'(?: id='(.*?)')? \|", line)
        if m and m.group(2) is None and m.group(1) not in SKIP:
            out.append(m.group(1))
    return out

def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:40]

def visit(path, depth):
    global count
    tree = dump()
    name = f"{prefix}-" + "--".join(slug(p) for p in path) if path else prefix
    subprocess.run([str(T / "step"), name], capture_output=True)
    subprocess.run([str(T / "scrollcap"), name, "6"], capture_output=True)
    for _ in range(7):
        subprocess.run([str(T / "ax"), "scroll", pid, "up"], capture_output=True)
    count += 1
    if depth >= 3:
        return
    for t in topics(tree):
        subprocess.run([str(T / "reveal"), t], capture_output=True)
        r = subprocess.run([str(T / "ax"), "press", pid, t], capture_output=True, text=True)
        if "NOT_FOUND" in r.stdout:
            print("skip", path, t); continue
        time.sleep(0.9)
        after = dump()
        if "BackButton" not in after or after == tree:
            print("no-nav", path, t); continue
        visit(path + [t], depth + 1)
        subprocess.run([str(T / "ax"), "press", pid, "BackButton"], capture_output=True)
        time.sleep(0.8)

visit([], 0)
print("pages", count)
