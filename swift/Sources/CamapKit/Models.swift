import Foundation

public struct Binding: Codable, Sendable, Equatable {
  public var longitude: Double
  public var latitude: Double
  public var rotation: Double
  public init(longitude: Double, latitude: Double, rotation: Double = 0) {
    self.longitude = longitude
    self.latitude = latitude
    self.rotation = rotation
  }
}

public struct SpatialFrame: Codable, Sendable, Equatable {
  public var id: String
  public var revision: Int
  public var name: String
  public var unit: String
  public var bindings: [String: Binding]
  public init(
    id: String = UUID().uuidString.lowercased(), revision: Int = 1, name: String,
    unit: String = "m", bindings: [String: Binding] = [:]
  ) {
    self.id = id
    self.revision = revision
    self.name = name
    self.unit = unit
    self.bindings = bindings
  }
}

public struct BuildingLevel: Codable, Sendable, Equatable {
  public var id: String
  public var label: String
  public var ordinal: Double
  public init(id: String = UUID().uuidString.lowercased(), label: String, ordinal: Double) {
    self.id = id
    self.label = label
    self.ordinal = ordinal
  }
}

public struct Source: Codable, Sendable, Equatable {
  public var method: String
  public var observedAt: String?
  public var accuracyMeters: Double?
  public init(method: String = "manual", observedAt: String? = nil, accuracyMeters: Double? = nil) {
    self.method = method
    self.observedAt = observedAt
    self.accuracyMeters = accuracyMeters
  }
}

public struct Feature: Codable, Sendable, Equatable {
  public var id: String
  public var revision: Int
  public var frameId: String
  public var kind: String
  public var name: String
  public var geometry: Geometry
  public var buildingId: String?
  public var parentId: String?
  public var levelId: String?
  public var levels: [BuildingLevel]?
  public var servedLevelIds: [String]?
  public var exterior: Bool?
  public var accessible: Bool?
  public var width: Double?
  public var hours: String?
  public var description: String?
  public var aliases: [String]?
  public var tags: [String]?
  public var source: Source?
  public init(
    id: String = UUID().uuidString.lowercased(), revision: Int = 1, frameId: String, kind: String,
    name: String, geometry: Geometry, buildingId: String? = nil, parentId: String? = nil,
    levelId: String? = nil, levels: [BuildingLevel]? = nil, servedLevelIds: [String]? = nil,
    exterior: Bool? = nil, accessible: Bool? = nil, width: Double? = nil, hours: String? = nil,
    description: String? = nil, aliases: [String]? = nil, tags: [String]? = nil,
    source: Source? = nil
  ) {
    self.id = id
    self.revision = revision
    self.frameId = frameId
    self.kind = kind
    self.name = name
    self.geometry = geometry
    self.buildingId = buildingId
    self.parentId = parentId
    self.levelId = levelId
    self.levels = levels
    self.servedLevelIds = servedLevelIds
    self.exterior = exterior
    self.accessible = accessible
    self.width = width
    self.hours = hours
    self.description = description
    self.aliases = aliases
    self.tags = tags
    self.source = source
  }
}

public struct RouteNode: Codable, Sendable, Equatable {
  public var id: String
  public var revision: Int
  public var frameId: String
  public var position: Point
  public var name: String
  public var entranceId: String?
  public init(
    id: String = UUID().uuidString.lowercased(), revision: Int = 1, frameId: String,
    position: Point, name: String, entranceId: String? = nil
  ) {
    self.id = id
    self.revision = revision
    self.frameId = frameId
    self.position = position
    self.name = name
    self.entranceId = entranceId
  }
}

public struct RouteEdge: Codable, Sendable, Equatable {
  public var id: String
  public var revision: Int
  public var frameId: String
  public var from: String
  public var to: String
  public var name: String
  public var oneWay: Bool
  public var accessible: Bool
  public var covered: Bool
  public var closed: Bool
  public var points: [Point]
  public init(
    id: String = UUID().uuidString.lowercased(), revision: Int = 1, frameId: String, from: String,
    to: String, name: String = "", oneWay: Bool = false, accessible: Bool = true,
    covered: Bool = false, closed: Bool = false, points: [Point] = []
  ) {
    self.id = id
    self.revision = revision
    self.frameId = frameId
    self.from = from
    self.to = to
    self.name = name
    self.oneWay = oneWay
    self.accessible = accessible
    self.covered = covered
    self.closed = closed
    self.points = points
  }
}

public struct Tombstone: Codable, Sendable, Equatable {
  public var collection: String
  public var id: String
  public init(collection: String, id: String) {
    self.collection = collection
    self.id = id
  }
}

public struct CamapDocument: Codable, Sendable, Equatable {
  public var formatVersion: String
  public var id: String
  public var title: String
  public var masterId: String?
  public var baseRevision: Int?
  public var frames: [SpatialFrame]
  public var features: [Feature]
  public var nodes: [RouteNode]
  public var edges: [RouteEdge]
  public var tombstones: [Tombstone]
  public init(
    formatVersion: String = "0.1.0", id: String = UUID().uuidString.lowercased(),
    title: String = "校园地图", masterId: String? = nil, baseRevision: Int? = nil,
    frames: [SpatialFrame] = [], features: [Feature] = [], nodes: [RouteNode] = [],
    edges: [RouteEdge] = [], tombstones: [Tombstone] = []
  ) {
    self.formatVersion = formatVersion
    self.id = id
    self.title = title
    self.masterId = masterId
    self.baseRevision = baseRevision
    self.frames = frames
    self.features = features
    self.nodes = nodes
    self.edges = edges
    self.tombstones = tombstones
  }
}
