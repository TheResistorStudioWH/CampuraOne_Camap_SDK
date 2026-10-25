import { collections, type CamapDocument, type Issue } from "./types.js";
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const point = (p: unknown): boolean =>
  Array.isArray(p) &&
  p.length === 2 &&
  p.every(
    (n) => typeof n === "number" && Number.isFinite(n) && Math.abs(n) <= 100000,
  );
export function validateDocument(value: unknown): Issue[] {
  const issues: Issue[] = [],
    error = (path: string, message: string) =>
      issues.push({ path, message, severity: "error" });
  if (!value || typeof value !== "object" || Array.isArray(value))
    return [{ path: "$", message: "地图必须是对象", severity: "error" }];
  const d = value as CamapDocument;
  if (d.formatVersion !== "0.1.0") error("formatVersion", "不支持的格式版本");
  if (!uuid.test(d.id)) error("id", "文档 ID 必须为 UUID");
  if (typeof d.title !== "string" || !d.title.trim() || d.title.length > 200)
    error("title", "标题长度为 1–200 字");
  if (d.masterId !== null && !uuid.test(d.masterId))
    error("masterId", "无效主地图 ID");
  if (
    d.baseRevision !== null &&
    (!Number.isSafeInteger(d.baseRevision) || d.baseRevision < 0)
  )
    error("baseRevision", "无效基准版本");
  if ((d.masterId === null) !== (d.baseRevision === null))
    error("baseRevision", "主地图 ID 和版本需同时存在");
  const maps: Record<string, Map<string, any>> = {};
  for (const c of collections) {
    if (!Array.isArray(d[c]) || d[c].length > 50000) {
      error(c, "集合必须为不超过 50000 项的数组");
      maps[c] = new Map();
      continue;
    }
    maps[c] = new Map();
    for (const [i, e] of d[c].entries()) {
      if (!e || typeof e !== "object") {
        error(`${c}.${i}`, "无效对象");
        continue;
      }
      if (!uuid.test(e.id) || maps[c].has(e.id))
        error(`${c}.${i}.id`, "ID 必须为唯一 UUID");
      if (!Number.isSafeInteger(e.revision) || e.revision < 1)
        error(`${c}.${i}.revision`, "revision 必须为正整数");
      maps[c].set(e.id, e);
    }
  }
  for (const f of maps.frames.values()) {
    if (
      f.unit !== "m" ||
      typeof f.name !== "string" ||
      !f.bindings ||
      typeof f.bindings !== "object"
    )
      error(`frames.${f.id}`, "无效坐标框架");
    for (const [provider, b] of Object.entries(f.bindings || {}) as [
      string,
      any,
    ][]) {
      if (
        !["amap", "mapkit"].includes(provider) ||
        !b ||
        !Number.isFinite(b.longitude) ||
        Math.abs(b.longitude) > 180 ||
        !Number.isFinite(b.latitude) ||
        Math.abs(b.latitude) > 80 ||
        !Number.isFinite(b.rotation)
      )
        error(`frames.${f.id}.bindings`, "无效地图校准参数");
    }
  }
  const kinds = [
    "area",
    "building",
    "merchant",
    "room",
    "door",
    "gate",
    "stairs",
    "elevator",
    "poi",
    "text",
  ];
  for (const f of maps.features.values()) {
    const path = `features.${f.id}`;
    if (
      !maps.frames.has(f.frameId) ||
      !kinds.includes(f.kind) ||
      typeof f.name !== "string" ||
      f.name.length > 200
    )
      error(path, "无效地标或坐标框架");
    const g = f.geometry;
    if (
      !g ||
      !["point", "line", "polygon"].includes(g.type) ||
      (g.type === "point"
        ? !point(g.coordinates)
        : !Array.isArray(g.coordinates) ||
          g.coordinates.length < (g.type === "polygon" ? 3 : 2) ||
          !g.coordinates.every(point))
    )
      error(path + ".geometry", "无效几何坐标");
    if (
      f.levels !== undefined &&
      (!Array.isArray(f.levels) ||
        f.kind !== "building" ||
        f.levels.some(
          (l: any) =>
            !l ||
            !uuid.test(l.id) ||
            typeof l.label !== "string" ||
            !Number.isFinite(l.ordinal),
        ) ||
        new Set(f.levels.map((l: any) => l.id)).size !== f.levels.length)
    )
      error(path + ".levels", "无效楼层");
    if (f.buildingId) {
      const b = maps.features.get(f.buildingId);
      if (!b || b.kind !== "building" || b.frameId !== f.frameId)
        error(path + ".buildingId", "所属建筑不存在或跨坐标框架");
    }
    if (f.parentId) {
      const p = maps.features.get(f.parentId);
      if (!p || p.id === f.id || p.frameId !== f.frameId)
        error(path + ".parentId", "关联对象不存在");
    }
    const levels = maps.features.get(f.buildingId)?.levels || [];
    if (f.levelId && !levels.some((l: any) => l.id === f.levelId))
      error(path + ".levelId", "所属楼层不存在");
    if (
      f.servedLevelIds !== undefined &&
      (!Array.isArray(f.servedLevelIds) ||
        !["stairs", "elevator"].includes(f.kind) ||
        f.servedLevelIds.some(
          (id: string) => !levels.some((l: any) => l.id === id),
        ))
    )
      error(path + ".servedLevelIds", "通达楼层不存在");
    for (const k of ["exterior", "accessible"])
      if (f[k] !== undefined && typeof f[k] !== "boolean")
        error(path + "." + k, "必须为布尔值");
    if (f.width !== undefined && (!Number.isFinite(f.width) || f.width <= 0))
      error(path + ".width", "宽度必须为正数");
  }
  for (const n of maps.nodes.values()) {
    if (
      !point(n.position) ||
      !maps.frames.has(n.frameId) ||
      typeof n.name !== "string"
    )
      error(`nodes.${n.id}`, "无效路网节点");
    if (n.entranceId) {
      const f = maps.features.get(n.entranceId);
      if (
        !f ||
        !["door", "gate"].includes(f.kind) ||
        f.exterior !== true ||
        f.frameId !== n.frameId ||
        f.geometry.type !== "point" ||
        Math.hypot(
          f.geometry.coordinates[0] - n.position[0],
          f.geometry.coordinates[1] - n.position[1],
        ) > 0.01
      )
        error(`nodes.${n.id}.entranceId`, "路线只能连接位置一致的室外出入口");
    }
  }
  for (const e of maps.edges.values()) {
    const a = maps.nodes.get(e.from),
      b = maps.nodes.get(e.to);
    if (
      !a ||
      !b ||
      a.id === b.id ||
      a.frameId !== e.frameId ||
      b.frameId !== e.frameId ||
      !Array.isArray(e.points) ||
      !e.points.every(point) ||
      ["oneWay", "accessible", "covered", "closed"].some(
        (k) => typeof e[k] !== "boolean",
      )
    )
      error(`edges.${e.id}`, "无效路线端点或通行属性");
  }
  if (!Array.isArray(d.tombstones)) error("tombstones", "缺少删除记录");
  else {
    const seen = new Set<string>();
    for (const t of d.tombstones) {
      const key = t?.collection + ":" + t?.id;
      if (
        !t ||
        !collections.includes(t.collection) ||
        !uuid.test(t.id) ||
        maps[t.collection]?.has(t.id) ||
        seen.has(key)
      )
        error("tombstones", "删除记录无效、重复或与现有对象冲突");
      seen.add(key);
    }
  }
  return issues;
}
export function assertDocument(d: unknown): asserts d is CamapDocument {
  const errors = validateDocument(d).filter((i) => i.severity === "error");
  if (errors.length)
    throw new Error(errors.map((i) => i.path + ": " + i.message).join("\n"));
}
