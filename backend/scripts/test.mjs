import { readdirSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
const files = ["tests", "strava"].flatMap((directory) =>
  existsSync(directory)
    ? readdirSync(directory)
        .filter((name) => name.endsWith(".test.ts"))
        .map((name) => `${directory}/${name}`)
    : [],
);
const result = spawnSync(
  process.execPath,
  ["--import", "tsx", "--test", ...files],
  { stdio: "inherit" },
);
if (result.error) throw result.error;
process.exit(result.status ?? 1);
