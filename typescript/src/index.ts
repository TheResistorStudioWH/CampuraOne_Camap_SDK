export * from "./types.js";
export * from "./validate.js";
export * from "./merge.js";
export * from "./route.js";
export * from "./coordinates.js";
import type { CamapDocument } from "./types.js";
import { assertDocument } from "./validate.js";
import { zipStore, unzipStore, utf8, text } from "./zip.js";
export const FORMAT_VERSION = "0.1.0" as const;
export function newDocument(title = "未命名地图"): CamapDocument {
  return {
    formatVersion: FORMAT_VERSION,
    id: crypto.randomUUID(),
    title,
    masterId: null,
    baseRevision: null,
    frames: [],
    features: [],
    nodes: [],
    edges: [],
    tombstones: [],
  };
}
export async function sha256(data: Uint8Array): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(data).buffer),
    ),
  ]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export async function encodeCamap(doc: CamapDocument): Promise<Uint8Array> {
  assertDocument(doc);
  const data = utf8(JSON.stringify(doc));
  return zipStore({
    "manifest.json": utf8(
      JSON.stringify({
        format: "camap",
        version: FORMAT_VERSION,
        document: "document.json",
        sha256: await sha256(data),
      }),
    ),
    "document.json": data,
  });
}
export async function decodeCamap(bytes: Uint8Array): Promise<CamapDocument> {
  const files = unzipStore(bytes),
    manifest = JSON.parse(text(files["manifest.json"]));
  if (
    manifest.format !== "camap" ||
    manifest.version !== FORMAT_VERSION ||
    manifest.document !== "document.json" ||
    manifest.sha256 !== (await sha256(files["document.json"]))
  )
    throw new Error("文件版本不支持或校验和不一致");
  const doc = JSON.parse(text(files["document.json"]));
  assertDocument(doc);
  return doc;
}
