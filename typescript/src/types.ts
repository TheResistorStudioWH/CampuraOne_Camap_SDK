export type Point = [number, number];
export type Geometry =
  | { type: "point"; coordinates: Point }
  | { type: "line" | "polygon"; coordinates: Point[] };
export interface Entity {
  id: string;
  revision: number;
}
export interface Binding {
  longitude: number;
  latitude: number;
  rotation: number;
}
export interface SpatialFrame extends Entity {
  name: string;
  unit: "m";
  bindings: Partial<Record<"amap" | "mapkit", Binding>>;
}
export interface Level {
  id: string;
  label: string;
  ordinal: number;
}
export type FeatureKind =
  | "area"
  | "building"
  | "merchant"
  | "room"
  | "door"
  | "gate"
  | "stairs"
  | "elevator"
  | "poi"
  | "text";
export interface Feature extends Entity {
  frameId: string;
  kind: FeatureKind;
  name: string;
  geometry: Geometry;
  buildingId?: string;
  parentId?: string;
  levelId?: string;
  levels?: Level[];
  servedLevelIds?: string[];
  exterior?: boolean;
  accessible?: boolean;
  width?: number;
  hours?: string;
  description?: string;
  aliases?: string[];
  tags?: string[];
  source?: {
    method: "manual" | "survey" | "import";
    observedAt?: string;
    accuracyMeters?: number;
  };
}
export interface RouteNode extends Entity {
  frameId: string;
  position: Point;
  name: string;
  entranceId?: string;
}
export interface RouteEdge extends Entity {
  frameId: string;
  from: string;
  to: string;
  name: string;
  oneWay: boolean;
  accessible: boolean;
  covered: boolean;
  closed: boolean;
  points: Point[];
}
export const collections = ["frames", "features", "nodes", "edges"] as const;
export type Collection = (typeof collections)[number];
export interface Tombstone {
  collection: Collection;
  id: string;
}
export interface CamapDocument {
  formatVersion: "0.1.0";
  id: string;
  title: string;
  masterId: string | null;
  baseRevision: number | null;
  frames: SpatialFrame[];
  features: Feature[];
  nodes: RouteNode[];
  edges: RouteEdge[];
  tombstones: Tombstone[];
}
export interface Issue {
  path: string;
  message: string;
  severity: "error" | "warning";
}
export interface MergeConflict {
  key: string;
  collection: Collection;
  id: string;
  base: Entity | null;
  server: Entity | null;
  incoming: Entity | null;
}
export interface Duplicate {
  key: string;
  incomingId: string;
  serverId: string;
}
export type Resolution = Record<
  string,
  "server" | "incoming" | "keep" | "drop"
>;
