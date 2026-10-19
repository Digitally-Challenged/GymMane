import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "build" / "web"
excluded = {"gymmane-worker.js", "flutter_service_worker.js", ".last_build_id"}
files = sorted(
    path for path in root.rglob("*")
    if path.is_file() and path.name not in excluded and not path.name.endswith(".map")
)
digest = hashlib.sha256()
for path in files:
    digest.update(path.relative_to(root).as_posix().encode())
    digest.update(path.read_bytes())
worker = root / "gymmane-worker.js"
template = Path(__file__).resolve().parents[1] / "web" / worker.name
source = template.read_text().replace(
    "const CACHE = 'gymmane-trial';",
    f"const CACHE = 'gymmane-trial-{digest.hexdigest()[:16]}';",
).replace(
    "const PRECACHE = [];",
    "const PRECACHE = " + json.dumps([p.relative_to(root).as_posix() for p in files]) + ";",
)
worker.write_text(source)
print(f"Prepared offline cache: {len(files)} files")
