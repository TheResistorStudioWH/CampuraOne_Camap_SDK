import CryptoKit
import Foundation

public enum CamapError: Error, LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    if case .invalid(let s) = self { return s }
    return nil
  }
}
public enum Camap {
  public static let version = "0.1.0", maximumBytes = 20 * 1024 * 1024
  private static func require(_ condition: Bool, _ message: String = "Invalid CAMAP archive") throws
  { if !condition { throw CamapError.invalid(message) } }
  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private static func crc(_ bytes: Data) -> UInt32 {
    var c: UInt32 = 0xffff_ffff
    for b in bytes {
      c ^= UInt32(b)
      for _ in 0..<8 { c = (c >> 1) ^ ((c & 1) == 1 ? 0xedb8_8320 : 0) }
    }
    return c ^ 0xffff_ffff
  }
  public static func read(from url: URL) throws -> CamapDocument {
    let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
    try require(size <= maximumBytes, "Package exceeds 20 MiB")
    return try decode(Data(contentsOf: url))
  }
  public static func write(_ document: CamapDocument, to url: URL) throws {
    try encode(document).write(to: url, options: .atomic)
  }
  public static func decode(_ data: Data) throws -> CamapDocument {
    try require(data.count >= 22 && data.count <= maximumBytes)
    let b = Array(data)
    let e = b.count - 22
    func n(_ p: Int, _ width: Int) -> Int {
      guard p >= 0, p + width <= b.count else { return -1 }
      return (0..<width).reduce(0) { $0 | (Int(b[p + $1]) << ($1 * 8)) }
    }
    try require(
      n(e, 4) == 0x0605_4b50 && n(e + 4, 2) == 0 && n(e + 6, 2) == 0 && n(e + 8, 2) == 2
        && n(e + 10, 2) == 2 && n(e + 20, 2) == 0)
    let start = n(e + 16, 4)
    try require(start + n(e + 12, 4) == e)
    var p = start
    var local = 0
    var files: [String: Data] = [:]
    for _ in 0..<2 {
      try require(p + 46 <= e && n(p, 4) == 0x0201_4b50)
      let length = n(p + 28, 2)
      let size = n(p + 24, 4)
      let offset = n(p + 42, 4)
      let checksum = n(p + 16, 4)
      try require(
        n(p + 8, 2) == 0 && n(p + 10, 2) == 0 && n(p + 30, 2) == 0 && n(p + 32, 2) == 0
          && n(p + 34, 2) == 0 && size == n(p + 20, 4) && offset == local && p + 46 + length <= e)
      let name = String(decoding: b[(p + 46)..<(p + 46 + length)], as: UTF8.self)
      try require(
        ["manifest.json", "document.json"].contains(name) && files[name] == nil
          && offset + 30 + length + size <= start)
      try require(
        n(offset, 4) == 0x0403_4b50 && n(offset + 6, 2) == 0 && n(offset + 8, 2) == 0
          && n(offset + 26, 2) == length && n(offset + 28, 2) == 0 && n(offset + 14, 4) == checksum
          && n(offset + 18, 4) == size && n(offset + 22, 4) == size
          && String(decoding: b[(offset + 30)..<(offset + 30 + length)], as: UTF8.self) == name)
      let bytes = Data(b[(offset + 30 + length)..<(offset + 30 + length + size)])
      try require(Int(crc(bytes)) == checksum)
      files[name] = bytes
      local = offset + 30 + length + size
      p += 46 + length
    }
    try require(local == start && p == e)
    guard let manifest = files["manifest.json"], let document = files["document.json"],
      let m = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
    else { throw CamapError.invalid("Missing manifest") }
    try require(
      m["format"] as? String == "camap" && m["version"] as? String == version
        && m["document"] as? String == "document.json" && m["sha256"] as? String == hash(document),
      "Unsupported version or checksum mismatch")
    let decoded = try JSONDecoder().decode(CamapDocument.self, from: document)
    try validate(decoded)
    return decoded
  }
  public static func encode(_ document: CamapDocument) throws -> Data {
    try validate(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // Optional nil provenance fields are required JSON nulls in the interchange format.
    var object = try JSONSerialization.jsonObject(with: encoder.encode(document)) as! [String: Any]
    if document.masterId == nil { object["masterId"] = NSNull() }
    if document.baseRevision == nil { object["baseRevision"] = NSNull() }
    let payload = try JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    let manifest = try JSONSerialization.data(
      withJSONObject: [
        "format": "camap", "version": version, "document": "document.json", "sha256": hash(payload),
      ], options: [.sortedKeys])
    var out = Data()
    var central = Data()
    func put(_ n: Int, _ width: Int, _ target: inout Data) {
      for i in 0..<width { target.append(UInt8(truncatingIfNeeded: n >> (i * 8))) }
    }
    for (name, bytes) in [("manifest.json", manifest), ("document.json", payload)] {
      let offset = out.count
      let n = Array(name.utf8)
      let checksum = Int(crc(bytes))
      put(0x0403_4b50, 4, &out)
      for value in [20, 0, 0, 0, 0] { put(value, 2, &out) }
      for value in [checksum, bytes.count, bytes.count] { put(value, 4, &out) }
      put(n.count, 2, &out)
      put(0, 2, &out)
      out.append(contentsOf: n)
      out.append(bytes)
      put(0x0201_4b50, 4, &central)
      for value in [20, 20, 0, 0, 0, 0] { put(value, 2, &central) }
      for value in [checksum, bytes.count, bytes.count] { put(value, 4, &central) }
      for value in [n.count, 0, 0, 0, 0] { put(value, 2, &central) }
      put(0, 4, &central)
      put(offset, 4, &central)
      central.append(contentsOf: n)
    }
    let offset = out.count
    out.append(central)
    put(0x0605_4b50, 4, &out)
    for value in [0, 0, 2, 2] { put(value, 2, &out) }
    put(central.count, 4, &out)
    put(offset, 4, &out)
    put(0, 2, &out)
    try require(out.count <= maximumBytes)
    return out
  }
  public static func validate(_ d: CamapDocument) throws {
    func uuid(_ s: String) -> Bool { UUID(uuidString: s) != nil }
    func point(_ p: Point) -> Bool {
      p.x.isFinite && p.y.isFinite && abs(p.x) <= 100000 && abs(p.y) <= 100000
    }
    try require(
      d.formatVersion == version && uuid(d.id)
        && !d.title.trimmingCharacters(in: .whitespaces).isEmpty && d.title.count <= 200,
      "Invalid document")
    try require((d.masterId == nil) == (d.baseRevision == nil))
    if let id = d.masterId { try require(uuid(id) && (d.baseRevision ?? -1) >= 0) }
    let ids = [d.frames.map(\.id), d.features.map(\.id), d.nodes.map(\.id), d.edges.map(\.id)]
    for group in ids {
      try require(
        group.count <= 50000 && Set(group).count == group.count && group.allSatisfy(uuid),
        "Invalid or duplicate ID")
    }
    let frames = Dictionary(uniqueKeysWithValues: d.frames.map { ($0.id, $0) })
    let features = Dictionary(uniqueKeysWithValues: d.features.map { ($0.id, $0) })
    let nodes = Dictionary(uniqueKeysWithValues: d.nodes.map { ($0.id, $0) })
    for f in d.frames {
      try require(f.revision > 0 && f.unit == "m")
      for (k, b) in f.bindings {
        try require(
          ["amap", "mapkit"].contains(k) && b.longitude.isFinite && abs(b.longitude) <= 180
            && b.latitude.isFinite && abs(b.latitude) <= 80 && b.rotation.isFinite)
      }
    }
    for f in d.features {
      if let width = f.width { try require(width.isFinite && width > 0, "Invalid width") }
      try require(
        f.name.count <= 200 && f.revision > 0 && frames[f.frameId] != nil
          && [
            "area", "building", "merchant", "room", "door", "gate", "stairs", "elevator", "poi",
            "text",
          ].contains(f.kind) && f.geometry.points.allSatisfy(point))
      switch f.geometry {
      case .polygon(let p): try require(p.count >= 3)
      case .line(let p): try require(p.count >= 2)
      default: break
      }
      if let bid = f.buildingId {
        try require(
          features[bid]?.kind == "building" && features[bid]?.frameId == f.frameId,
          "Unknown building")
      }
      if let pid = f.parentId {
        try require(pid != f.id && features[pid]?.frameId == f.frameId, "Unknown parent")
      }
      let levels = features[f.buildingId ?? ""]?.levels ?? []
      if let lid = f.levelId { try require(levels.contains { $0.id == lid }, "Unknown floor") }
      if let served = f.servedLevelIds {
        try require(
          ["stairs", "elevator"].contains(f.kind)
            && served.allSatisfy { id in levels.contains { $0.id == id } }, "Unknown served floor")
      }
      if let own = f.levels {
        try require(
          f.kind == "building" && Set(own.map(\.id)).count == own.count
            && own.allSatisfy { uuid($0.id) && $0.ordinal.isFinite })
      }
    }
    for n in d.nodes {
      try require(n.revision > 0 && frames[n.frameId] != nil && point(n.position))
      if let id = n.entranceId {
        guard let f = features[id], case .point(let p) = f.geometry else {
          throw CamapError.invalid("Unknown entrance")
        }
        try require(
          ["door", "gate"].contains(f.kind) && f.exterior == true && f.frameId == n.frameId
            && hypot(p.x - n.position.x, p.y - n.position.y) <= 0.01,
          "Indoor entrance is not routable")
      }
    }
    for e in d.edges {
      try require(
        e.revision > 0 && e.from != e.to && nodes[e.from]?.frameId == e.frameId
          && nodes[e.to]?.frameId == e.frameId && e.points.allSatisfy(point),
        "Unknown route endpoint")
    }
    let names = ["frames", "features", "nodes", "edges"]
    var seen = Set<String>()
    for t in d.tombstones {
      guard let i = names.firstIndex(of: t.collection) else {
        throw CamapError.invalid("Unknown collection")
      }
      try require(
        uuid(t.id) && !ids[i].contains(t.id) && seen.insert(t.collection + ":" + t.id).inserted,
        "Invalid tombstone")
    }
  }
}
