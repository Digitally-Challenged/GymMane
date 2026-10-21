import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { parsePush } from "../src/protocol.js";
import { Pool } from "pg";
import { migrate } from "../src/migrate.js";
import { SyncStore } from "../src/store.js";

const definition = {
  id: "c123-0",
  n: "Custom hold",
  p: "abdomen",
  e: "Bodyweight",
  d: "Beginner",
  k: "time",
  s: [],
  st: ["Hold"],
  a: [],
  ty: "strength",
};
function parse(exerciseDefinitions?: unknown, ex = ["EIeI8Vf", "c123-0"]) {
  const id = randomUUID();
  return parsePush({
    schemaVersion: 1,
    operations: [
      {
        operationId: randomUUID(),
        entityType: "routine",
        entityId: id,
        baseRevision: 0,
        deleted: false,
        payload: {
          id,
          n: "Portable",
          ex,
          ...(exerciseDefinitions === undefined ? {} : { exerciseDefinitions }),
        },
      },
    ],
  });
}

test("routines accept legacy payloads and preserve typed custom definitions", () => {
  assert.equal(parse().length, 1);
  assert.deepEqual(
    parse({ "c123-0": definition })[0].payload?.exerciseDefinitions,
    { "c123-0": definition },
  );
});

test("malformed or unreferenced custom definitions are rejected", () => {
  for (const invalid of [
    [],
    "invalid",
    { "c123-0": null },
    { "c123-0": { ...definition, id: "other" } },
    { "c123-0": { ...definition, n: " " } },
    { "c123-0": { ...definition, p: 1 } },
    { "c123-0": { ...definition, s: [2] } },
    { "c123-0": { ...definition, st: "hold" } },
    { "c123-0": { ...definition, k: "unknown" } },
    { "c123-0": { ...definition, ty: "unknown" } },
    { unreferenced: { ...definition, id: "unreferenced" } },
  ])
    assert.throws(() => parse(invalid), { status: 400 });
});

test("every built-in catalog ID is protected against dependency overrides", () => {
  const catalog = new URL("../../lib/catalog/", import.meta.url);
  const ids = readdirSync(catalog)
    .filter((name) => name.endsWith(".dart"))
    .flatMap((name) =>
      [
        ...readFileSync(new URL(name, catalog), "utf8").matchAll(
          /\bid:\s*'([^']+)'/g,
        ),
      ].map((match) => match[1]),
    );
  assert.ok(ids.length > 200);
  for (const id of ids)
    assert.throws(() => parse({ [id]: { ...definition, id } }, [id]), {
      status: 400,
    });
});

test(
  "PostgreSQL preserves routine definitions, replay, account isolation and tombstones",
  { skip: !process.env.TEST_DATABASE_URL },
  async () => {
    const url = new URL(process.env.TEST_DATABASE_URL!);
    assert.ok(
      ["localhost", "127.0.0.1"].includes(url.hostname) &&
        url.pathname.endsWith("_test"),
    );
    const pool = new Pool({ connectionString: url.toString() });
    try {
      await migrate(pool);
      const store = new SyncStore(pool);
      const accountA = randomUUID(),
        accountB = randomUUID();
      const operations = parse({ "c123-0": definition });
      const first = await store.push(accountA, operations);
      assert.equal(first.results[0].status, "accepted");
      assert.deepEqual(await store.push(accountA, operations), first);
      const pulled = await store.pull(accountA, "0", 100);
      assert.deepEqual(pulled.entities[0].payload?.exerciseDefinitions, {
        "c123-0": definition,
      });
      assert.deepEqual((await store.pull(accountB, "0", 100)).entities, []);
      const otherDefinition = { ...definition, n: "Account B private name" };
      await store.push(accountB, [
        {
          ...operations[0],
          operationId: randomUUID(),
          payload: {
            ...operations[0].payload!,
            exerciseDefinitions: { "c123-0": otherDefinition },
          },
        },
      ]);
      assert.deepEqual(
        (await store.pull(accountA, "0", 100)).entities[0].payload
          ?.exerciseDefinitions,
        { "c123-0": definition },
      );
      await store.push(accountA, [
        {
          ...operations[0],
          operationId: randomUUID(),
          baseRevision: 1,
          deleted: true,
          payload: null,
        },
      ]);
      const deleted = (await store.pull(accountA, pulled.nextCursor, 100))
        .entities[0];
      assert.equal(deleted.deleted, true);
      assert.equal(deleted.payload, null);
    } finally {
      await pool.end();
    }
  },
);
