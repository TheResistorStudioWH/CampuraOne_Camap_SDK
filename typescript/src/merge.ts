import {
  collections,
  type CamapDocument,
  type Entity,
  type Feature,
  type MergeConflict,
  type Duplicate,
  type Resolution,
} from "./types.js";
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object")
    return (
      "{" +
      Object.keys(value)
        .filter((k) => k !== "revision")
        .sort()
        .map(
          (k) =>
            JSON.stringify(k) +
            ":" +
            canonical((value as Record<string, unknown>)[k]),
        )
        .join(",") +
      "}"
    );
  return JSON.stringify(value);
}
const same = (a: unknown, b: unknown) => canonical(a) === canonical(b);
export function mergeDocuments(
  base: CamapDocument | null,
  server: CamapDocument,
  incoming: CamapDocument,
  resolutions: Resolution = {},
) {
  const document = structuredClone(server),
    conflicts: MergeConflict[] = [],
    duplicates: Duplicate[] = [];
  for (const c of collections) {
    const prior = new Map<string, Entity>(
        (base?.[c] || []).map((e) => [e.id, e]),
      ),
      current = new Map<string, Entity>(server[c].map((e) => [e.id, e])),
      out = new Map(current);
    const changes = new Map<string, Entity | null>(
      incoming[c].map((e) => [e.id, e]),
    );
    for (const t of incoming.tombstones)
      if (t.collection === c) changes.set(t.id, null);
    for (const [id, next] of changes) {
      const old = prior.get(id) || null,
        now = current.get(id) || null,
        key = c + ":" + id;
      let chosen = now;
      if (same(now, next) || same(old, next)) continue;
      if (same(old, now)) chosen = next;
      else {
        const choice = resolutions[key];
        conflicts.push({
          key,
          collection: c,
          id,
          base: old,
          server: now,
          incoming: next,
        });
        if (choice === "incoming") chosen = next;
        else if (choice !== "server") continue;
      }
      if (chosen)
        out.set(id, {
          ...structuredClone(chosen),
          revision: (now?.revision || 0) + 1,
        });
      else out.delete(id);
      if (c === "features" && !old && !now && chosen) {
        const f = chosen as Feature,
          center = (f: Feature) =>
            f.geometry.type === "point"
              ? f.geometry.coordinates
              : f.geometry.coordinates[0];
        const match = server.features.find(
          (s) =>
            s.kind === f.kind &&
            s.frameId === f.frameId &&
            s.levelId === f.levelId &&
            Math.hypot(
              center(s)[0] - center(f)[0],
              center(s)[1] - center(f)[1],
            ) < 2,
        );
        if (match) {
          const key = "duplicate:" + id;
          duplicates.push({ key, incomingId: id, serverId: match.id });
          if (resolutions[key] === "drop") out.delete(id);
        }
      }
    }
    (document[c] as Entity[]) = Array.from(out.values());
  }
  document.tombstones = [];
  return {
    document,
    conflicts,
    duplicates,
    unresolved: conflicts
      .filter((c) => !["incoming", "server"].includes(resolutions[c.key]))
      .map((c) => c.key),
  };
}
