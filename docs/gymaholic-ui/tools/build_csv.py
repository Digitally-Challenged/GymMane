"""Append second-pass AX dumps (tools/ax format) to ui-inventory.csv. Additive: first-pass rows are kept."""
import csv, re, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "ui-inventory.csv"
rows = list(csv.reader(out.open()))
header, existing = rows[0], rows[1:]
done = {r[0] for r in existing}
line = re.compile(r"^\s*(AX\w+)\s?(.*) \| (\S+),(\S+) (\S+)x(\S+)$")
field = lambda body, key: (re.search(rf"(?:^| ){key}='(.*?)'(?= (?:t|d|id|v)='|$)", body) or [None, ""])[1]
added = 0
with out.open("a", newline="") as fh:
    w = csv.writer(fh)
    for f in sorted((root / "ui").glob("*.txt")):
        if f.stem in done or not re.match(r"\d", f.stem) or int(re.match(r"\d+", f.stem)[0]) < 14:
            continue
        for raw in f.read_text().splitlines():
            m = line.match(raw)
            if not m:
                continue
            role, body, x, y, wd, ht = m.groups()
            vals = [field(body, k) for k in ("id", "d", "t", "v")]
            if role == "AXGroup" and not any(vals):
                continue
            w.writerow([f.stem, role, *vals, f"{x},{y}", f"{wd}x{ht}"])
            added += 1
print("added", added)
