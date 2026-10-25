// CAMAP 0.1 uses the interoperable ZIP STORE profile: no compression, encryption,
// directories, descriptors or ZIP64. Readers never extract to the filesystem.
export const MAX_BYTES = 20 * 1024 * 1024;
const encoder = new TextEncoder(),
  decoder = new TextDecoder("utf-8", { fatal: true });
export const utf8 = (s: string) => encoder.encode(s);
export const text = (b: Uint8Array) => decoder.decode(b);
export function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}
export function zipStore(files: Record<string, Uint8Array>): Uint8Array {
  const entries = Object.entries(files),
    parts: Uint8Array[] = [],
    central: Uint8Array[] = [];
  let offset = 0;
  for (const [name, data] of entries) {
    const n = utf8(name),
      header = new Uint8Array(30 + n.length),
      h = new DataView(header.buffer),
      crc = crc32(data);
    h.setUint32(0, 0x04034b50, true);
    h.setUint16(4, 20, true);
    h.setUint32(14, crc, true);
    h.setUint32(18, data.length, true);
    h.setUint32(22, data.length, true);
    h.setUint16(26, n.length, true);
    header.set(n, 30);
    const c = new Uint8Array(46 + n.length),
      v = new DataView(c.buffer);
    v.setUint32(0, 0x02014b50, true);
    v.setUint16(4, 20, true);
    v.setUint16(6, 20, true);
    v.setUint32(16, crc, true);
    v.setUint32(20, data.length, true);
    v.setUint32(24, data.length, true);
    v.setUint16(28, n.length, true);
    v.setUint32(42, offset, true);
    c.set(n, 46);
    parts.push(header, data);
    central.push(c);
    offset += header.length + data.length;
  }
  const length = central.reduce((n, c) => n + c.length, 0),
    end = new Uint8Array(22),
    v = new DataView(end.buffer);
  v.setUint32(0, 0x06054b50, true);
  v.setUint16(8, entries.length, true);
  v.setUint16(10, entries.length, true);
  v.setUint32(12, length, true);
  v.setUint32(16, offset, true);
  const out = new Uint8Array(offset + length + 22);
  let p = 0;
  for (const b of [...parts, ...central, end]) {
    out.set(b, p);
    p += b.length;
  }
  if (out.length > MAX_BYTES) throw new Error("文件超过 20 MiB");
  return out;
}
export function unzipStore(bytes: Uint8Array): Record<string, Uint8Array> {
  const fail = (): never => {
    throw new Error("无效的 CAMAP ZIP STORE 包");
  };
  if (bytes.length < 22 || bytes.length > MAX_BYTES) fail();
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength),
    e = bytes.length - 22;
  if (
    v.getUint32(e, true) !== 0x06054b50 ||
    v.getUint16(e + 4, true) ||
    v.getUint16(e + 6, true) ||
    v.getUint16(e + 20, true)
  )
    fail();
  const count = v.getUint16(e + 10, true),
    start = v.getUint32(e + 16, true);
  if (
    count !== 2 ||
    v.getUint16(e + 8, true) !== count ||
    start + v.getUint32(e + 12, true) !== e
  )
    fail();
  let p = start,
    local = 0;
  const files: Record<string, Uint8Array> = {};
  for (let i = 0; i < count; i++) {
    if (p + 46 > e || v.getUint32(p, true) !== 0x02014b50) fail();
    const n = v.getUint16(p + 28, true),
      extra = v.getUint16(p + 30, true),
      comment = v.getUint16(p + 32, true),
      size = v.getUint32(p + 24, true),
      off = v.getUint32(p + 42, true),
      crc = v.getUint32(p + 16, true);
    if (
      v.getUint16(p + 8, true) ||
      v.getUint16(p + 10, true) ||
      v.getUint16(p + 34, true) ||
      extra ||
      comment ||
      size !== v.getUint32(p + 20, true) ||
      off !== local ||
      p + 46 + n > e
    )
      fail();
    const name = text(bytes.subarray(p + 46, p + 46 + n));
    if (
      !["manifest.json", "document.json"].includes(name) ||
      Object.hasOwn(files, name) ||
      off + 30 + n + size > start
    )
      fail();
    if (
      v.getUint32(off, true) !== 0x04034b50 ||
      v.getUint16(off + 6, true) ||
      v.getUint16(off + 8, true) ||
      v.getUint16(off + 26, true) !== n ||
      v.getUint16(off + 28, true) ||
      v.getUint32(off + 14, true) !== crc ||
      v.getUint32(off + 18, true) !== size ||
      v.getUint32(off + 22, true) !== size ||
      text(bytes.subarray(off + 30, off + 30 + n)) !== name
    )
      fail();
    const data = bytes.slice(off + 30 + n, off + 30 + n + size);
    if (crc32(data) !== crc) fail();
    files[name] = data;
    local = off + 30 + n + size;
    p += 46 + n;
  }
  if (p !== e || local !== start) fail();
  return files;
}
