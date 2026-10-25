import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  decodeCamap,
  encodeCamap,
  validateDocument,
  mergeDocuments,
  newDocument,
  findRoute,
  toProvider,
  fromProvider,
} from "../dist/index.js";
import { zipStore, unzipStore } from "../dist/zip.js";
const bytes = new Uint8Array(
  await readFile(new URL("./fixtures/demo.camap", import.meta.url)),
);
const fixture = await decodeCamap(bytes);
test("portable package roundtrip preserves floors, doors, stairs and graph", async () => {
  assert.deepEqual(await decodeCamap(await encodeCamap(fixture)), fixture);
  assert.equal(fixture.features.length, 5);
});
test("CRC, checksum, oversized and path traversal packages are rejected", async () => {
  const bad = bytes.slice();
  bad[100] ^= 1;
  await assert.rejects(() => decodeCamap(bad));
  await assert.rejects(() => decodeCamap(new Uint8Array(21 * 1024 * 1024)));
  const files = unzipStore(bytes);
  await assert.rejects(() =>
    decodeCamap(
      zipStore({
        "../document.json": files["document.json"],
        "manifest.json": files["manifest.json"],
      }),
    ),
  );
  const json = JSON.parse(new TextDecoder().decode(files["document.json"]));
  json.title = "tampered";
  files["document.json"] = new TextEncoder().encode(JSON.stringify(json));
  await assert.rejects(() => decodeCamap(zipStore(files)), /校验和/);
});
test("unknown floor, dangling edge and indoor routing are invalid", () => {
  const d = structuredClone(fixture);
  d.features.find((f) => f.kind === "stairs").servedLevelIds = [
    crypto.randomUUID(),
  ];
  assert.ok(validateDocument(d).some((i) => i.path.includes("servedLevelIds")));
  d.nodes = [];
  assert.ok(validateDocument(d).some((i) => i.path.startsWith("edges.")));
  const e = structuredClone(fixture);
  e.features.find((f) => f.kind === "door").exterior = false;
  assert.ok(validateDocument(e).some((i) => i.path.includes("entranceId")));
});
test("three-way merge never interprets omitted objects as deletion", () => {
  const incoming = structuredClone(fixture);
  incoming.features = incoming.features.slice(0, 1);
  const result = mergeDocuments(fixture, fixture, incoming);
  assert.equal(result.document.features.length, 5);
  assert.equal(result.unresolved.length, 0);
});
test("independent field changes on different objects merge without conflict", () => {
  const server = structuredClone(fixture),
    incoming = structuredClone(fixture);
  server.features[0].name = "新版图书馆";
  incoming.features[1].name = "新咖啡馆";
  const result = mergeDocuments(fixture, server, incoming);
  assert.equal(result.conflicts.length, 0);
  assert.equal(result.document.features[0].name, "新版图书馆");
  assert.equal(result.document.features[1].name, "新咖啡馆");
});
test("concurrent edits require explicit choice", () => {
  const server = structuredClone(fixture),
    incoming = structuredClone(fixture);
  server.features[0].name = "甲";
  incoming.features[0].name = "乙";
  const r = mergeDocuments(fixture, server, incoming);
  assert.equal(r.unresolved.length, 1);
  const resolved = mergeDocuments(fixture, server, incoming, {
    [r.unresolved[0]]: "incoming",
  });
  assert.equal(resolved.unresolved.length, 0);
  assert.equal(resolved.document.features[0].name, "乙");
});
test("delete versus edit conflicts; deleted server object is not resurrected by unchanged client", () => {
  const server = structuredClone(fixture),
    incoming = structuredClone(fixture),
    id = fixture.features.at(-1).id;
  server.features.at(-1).name = "改名";
  incoming.features.pop();
  incoming.tombstones = [{ collection: "features", id }];
  assert.equal(mergeDocuments(fixture, server, incoming).unresolved.length, 1);
  server.features.pop();
  const unchanged = mergeDocuments(fixture, server, fixture);
  assert.ok(!unchanged.document.features.some((f) => f.id === id));
});
test("new overlapping IDs are only suspected duplicates, keep/drop works", () => {
  const incoming = structuredClone(fixture);
  const f = structuredClone(incoming.features.at(-1));
  f.id = crypto.randomUUID();
  incoming.features.push(f);
  const r = mergeDocuments(fixture, fixture, incoming);
  assert.equal(r.conflicts.length, 0);
  assert.equal(r.duplicates.length, 1);
  assert.equal(r.document.features.length, 6);
  assert.equal(
    mergeDocuments(fixture, fixture, incoming, {
      ["duplicate:" + f.id]: "drop",
    }).document.features.length,
    5,
  );
});
test("binding rotation roundtrip stays in local metres", () => {
  const b = { longitude: 114, latitude: 30, rotation: 37 },
    p = [50, -20],
    q = fromProvider(toProvider(p, b), b);
  assert.ok(Math.abs(p[0] - q[0]) < 0.0001 && Math.abs(p[1] - q[1]) < 0.0001);
});
test("outdoor routing respects one way, closed and accessible edges", () => {
  const [a, b] = fixture.nodes;
  assert.equal(findRoute(fixture, a.id, b.id).distanceMeters, 75);
  const d = structuredClone(fixture);
  d.edges[0].oneWay = true;
  assert.equal(findRoute(d, a.id, b.id), null);
  assert.ok(findRoute(d, b.id, a.id));
  d.edges[0].accessible = false;
  assert.equal(findRoute(d, b.id, a.id, { accessible: true }), null);
  d.edges[0].closed = true;
  assert.equal(findRoute(d, b.id, a.id), null);
});
test("new blank document is valid", () =>
  assert.deepEqual(validateDocument(newDocument()), []));
