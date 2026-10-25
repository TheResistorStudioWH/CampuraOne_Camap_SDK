library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

const camapVersion = '0.1.0';
const maximumCamapBytes = 20 * 1024 * 1024;

/// Portable model. Unknown optional metadata is retained on a read/write cycle.
/// Coordinates remain provider-neutral metres; no implicit GCJ/WGS conversion.
class CamapDocument {
  final Map<String, dynamic> _json;
  CamapDocument.fromJson(Map<String, dynamic> json)
      : _json = jsonDecode(jsonEncode(json)) as Map<String, dynamic> {
    validateCamap(_json);
  }
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
  String get id => _json['id'];
  String get title => _json['title'];
  String? get masterId => _json['masterId'];
  int? get baseRevision => _json['baseRevision'];
  List<Map<String, dynamic>> _collection(String key) =>
      (toJson()[key] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get frames => _collection('frames');
  List<Map<String, dynamic>> get features => _collection('features');
  List<Map<String, dynamic>> get nodes => _collection('nodes');
  List<Map<String, dynamic>> get edges => _collection('edges');
  List<Map<String, dynamic>> get tombstones => _collection('tombstones');
}

void _require(bool value, [String reason = 'Invalid CAMAP package']) {
  if (!value) throw FormatException(reason);
}

int _crc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

CamapDocument decodeCamap(Uint8List bytes) {
  _require(bytes.length >= 22 && bytes.length <= maximumCamapBytes);
  final v = ByteData.sublistView(bytes), e = bytes.length - 22;
  int u16(int p) => v.getUint16(p, Endian.little);
  int u32(int p) => v.getUint32(p, Endian.little);
  _require(u32(e) == 0x06054b50 &&
      u16(e + 4) == 0 &&
      u16(e + 6) == 0 &&
      u16(e + 8) == 2 &&
      u16(e + 10) == 2 &&
      u16(e + 20) == 0);
  final start = u32(e + 16);
  _require(start + u32(e + 12) == e);
  var p = start, local = 0;
  final files = <String, Uint8List>{};
  for (var i = 0; i < 2; i++) {
    _require(p + 46 <= e && u32(p) == 0x02014b50);
    final n = u16(p + 28),
        size = u32(p + 24),
        off = u32(p + 42),
        crc = u32(p + 16);
    _require(u16(p + 8) == 0 &&
        u16(p + 10) == 0 &&
        u16(p + 30) == 0 &&
        u16(p + 32) == 0 &&
        u16(p + 34) == 0 &&
        size == u32(p + 20) &&
        off == local &&
        p + 46 + n <= e);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + n));
    _require(['manifest.json', 'document.json'].contains(name) &&
        !files.containsKey(name) &&
        off + 30 + n + size <= start);
    _require(u32(off) == 0x04034b50 &&
        u16(off + 6) == 0 &&
        u16(off + 8) == 0 &&
        u16(off + 26) == n &&
        u16(off + 28) == 0 &&
        u32(off + 14) == crc &&
        u32(off + 18) == size &&
        u32(off + 22) == size &&
        utf8.decode(bytes.sublist(off + 30, off + 30 + n)) == name);
    final data = bytes.sublist(off + 30 + n, off + 30 + n + size);
    _require(_crc(data) == crc);
    files[name] = data;
    local = off + 30 + n + size;
    p += 46 + n;
  }
  _require(local == start && p == e);
  final m = jsonDecode(utf8.decode(files['manifest.json']!)),
      document = files['document.json']!;
  _require(
      m is Map &&
          m['format'] == 'camap' &&
          m['version'] == camapVersion &&
          m['document'] == 'document.json' &&
          m['sha256'] == sha256.convert(document).toString(),
      'Unsupported format or checksum mismatch');
  return CamapDocument.fromJson(
      jsonDecode(utf8.decode(document)) as Map<String, dynamic>);
}

Uint8List encodeCamap(CamapDocument document) {
  final payload = utf8.encode(jsonEncode(document.toJson()));
  final files = {
    'manifest.json': utf8.encode(jsonEncode({
      'format': 'camap',
      'version': camapVersion,
      'document': 'document.json',
      'sha256': sha256.convert(payload).toString()
    })),
    'document.json': payload
  };
  final out = BytesBuilder(), central = BytesBuilder();
  void put(BytesBuilder target, int value, int width) {
    final b = ByteData(width);
    if (width == 2) {
      b.setUint16(0, value, Endian.little);
    } else {
      b.setUint32(0, value, Endian.little);
    }
    target.add(b.buffer.asUint8List());
  }

  for (final entry in files.entries) {
    final offset = out.length,
        n = utf8.encode(entry.key),
        data = entry.value,
        crc = _crc(data);
    put(out, 0x04034b50, 4);
    for (final i in [20, 0, 0, 0, 0]) {
      put(out, i, 2);
    }
    for (final i in [crc, data.length, data.length]) {
      put(out, i, 4);
    }
    put(out, n.length, 2);
    put(out, 0, 2);
    out.add(n);
    out.add(data);
    put(central, 0x02014b50, 4);
    for (final i in [20, 20, 0, 0, 0, 0]) {
      put(central, i, 2);
    }
    for (final i in [crc, data.length, data.length]) {
      put(central, i, 4);
    }
    for (final i in [n.length, 0, 0, 0, 0]) {
      put(central, i, 2);
    }
    put(central, 0, 4);
    put(central, offset, 4);
    central.add(n);
  }
  final offset = out.length, centralBytes = central.takeBytes();
  out.add(centralBytes);
  put(out, 0x06054b50, 4);
  for (final i in [0, 0, 2, 2]) {
    put(out, i, 2);
  }
  put(out, centralBytes.length, 4);
  put(out, offset, 4);
  put(out, 0, 2);
  _require(out.length <= maximumCamapBytes);
  return out.takeBytes();
}

void validateCamap(Map<String, dynamic> d) {
  final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false);
  bool uuid(dynamic s) => s is String && pattern.hasMatch(s);
  bool point(dynamic p) =>
      p is List &&
      p.length == 2 &&
      p.every((n) => n is num && n.isFinite && n.abs() <= 100000);
  _require(
      d['formatVersion'] == camapVersion &&
          uuid(d['id']) &&
          d['title'] is String &&
          (d['title'] as String).trim().isNotEmpty &&
          (d['title'] as String).length <= 200,
      'Invalid document metadata');
  _require(
      d.containsKey('masterId') &&
          d.containsKey('baseRevision') &&
          ((d['masterId'] == null && d['baseRevision'] == null) ||
              (uuid(d['masterId']) &&
                  d['baseRevision'] is int &&
                  d['baseRevision'] >= 0)),
      'Invalid provenance');
  final maps = <String, Map<String, dynamic>>{};
  for (final c in ['frames', 'features', 'nodes', 'edges']) {
    _require(d[c] is List && d[c].length <= 50000, 'Invalid collection');
    maps[c] = {};
    for (final e in d[c]) {
      _require(
          e is Map &&
              uuid(e['id']) &&
              !maps[c]!.containsKey(e['id']) &&
              e['revision'] is int &&
              e['revision'] > 0,
          'Invalid entity');
      maps[c]![e['id']] = e;
    }
  }
  for (final f in d['frames']) {
    _require(f['unit'] == 'm' && f['name'] is String && f['bindings'] is Map,
        'Invalid frame');
    for (final entry in (f['bindings'] as Map).entries) {
      final b = entry.value;
      _require(
          ['amap', 'mapkit'].contains(entry.key) &&
              b is Map &&
              b['longitude'] is num &&
              b['longitude'].isFinite &&
              b['longitude'].abs() <= 180 &&
              b['latitude'] is num &&
              b['latitude'].isFinite &&
              b['latitude'].abs() <= 80 &&
              b['rotation'] is num &&
              b['rotation'].isFinite,
          'Invalid calibration');
    }
  }
  for (final f in d['features']) {
    final g = f['geometry'];
    _require(
        maps['frames']!.containsKey(f['frameId']) &&
            [
              'area',
              'building',
              'merchant',
              'room',
              'door',
              'gate',
              'stairs',
              'elevator',
              'poi',
              'text'
            ].contains(f['kind']) &&
            f['name'] is String,
        'Invalid feature');
    _require(g is Map && ['point', 'line', 'polygon'].contains(g['type']),
        'Invalid geometry');
    _require(
        g['type'] == 'point'
            ? point(g['coordinates'])
            : g['coordinates'] is List &&
                g['coordinates'].length >= (g['type'] == 'polygon' ? 3 : 2) &&
                (g['coordinates'] as List).every(point),
        'Invalid coordinates');
    final b = maps['features']![f['buildingId']];
    if (f['buildingId'] != null) {
      _require(
          b != null && b['kind'] == 'building' && b['frameId'] == f['frameId'],
          'Unknown building');
    }
    if (f['parentId'] != null) {
      final parent = maps['features']![f['parentId']];
      _require(
          parent != null &&
              parent['id'] != f['id'] &&
              parent['frameId'] == f['frameId'],
          'Unknown parent');
    }
    final levels = b?['levels'] ?? [];
    if (f['levelId'] != null) {
      _require((levels as List).any((l) => l['id'] == f['levelId']),
          'Unknown level');
    }
    if (f['servedLevelIds'] != null) {
      _require(
          ['stairs', 'elevator'].contains(f['kind']) &&
              f['servedLevelIds'] is List &&
              (f['servedLevelIds'] as List)
                  .every((id) => (levels as List).any((l) => l['id'] == id)),
          'Unknown served level');
    }
    if (f['levels'] != null) {
      _require(
          f['kind'] == 'building' && f['levels'] is List, 'Invalid levels');
      final seen = <String>{};
      for (final l in f['levels']) {
        _require(
            l is Map &&
                uuid(l['id']) &&
                seen.add(l['id']) &&
                l['label'] is String &&
                l['ordinal'] is num &&
                l['ordinal'].isFinite,
            'Invalid level');
      }
    }
    if (f.containsKey('width')) {
      _require(f['width'] is num && f['width'].isFinite && f['width'] > 0,
          'Invalid width');
    }
    for (final k in ['exterior', 'accessible']) {
      if (f.containsKey(k)) {
        _require(f[k] is bool, 'Invalid boolean');
      }
    }
  }
  for (final n in d['nodes']) {
    _require(
        point(n['position']) &&
            maps['frames']!.containsKey(n['frameId']) &&
            n['name'] is String,
        'Invalid route node');
    if (n['entranceId'] != null) {
      final f = maps['features']![n['entranceId']];
      _require(
          f != null &&
              ['door', 'gate'].contains(f['kind']) &&
              f['exterior'] == true &&
              f['frameId'] == n['frameId'] &&
              f['geometry']['type'] == 'point',
          'Invalid exterior entrance');
      final p = f['geometry']['coordinates'];
      _require(
          math.sqrt(math.pow(p[0] - n['position'][0], 2) +
                  math.pow(p[1] - n['position'][1], 2)) <=
              0.01,
          'Entrance node position mismatch');
    }
  }
  for (final e in d['edges']) {
    final a = maps['nodes']![e['from']], b = maps['nodes']![e['to']];
    _require(
        a != null &&
            b != null &&
            a['id'] != b['id'] &&
            a['frameId'] == e['frameId'] &&
            b['frameId'] == e['frameId'] &&
            e['points'] is List &&
            (e['points'] as List).every(point),
        'Invalid route edge');
    for (final k in ['oneWay', 'accessible', 'covered', 'closed']) {
      _require(e[k] is bool, 'Invalid route property');
    }
  }
  _require(d['tombstones'] is List, 'Invalid tombstones');
  final seen = <String>{};
  for (final t in d['tombstones']) {
    _require(
        t is Map &&
            maps.containsKey(t['collection']) &&
            uuid(t['id']) &&
            !maps[t['collection']]!.containsKey(t['id']) &&
            seen.add('${t['collection']}:${t['id']}'),
        'Invalid tombstone');
  }
}

List<double> toProvider(List<num> p, Map<String, num> binding) {
  final d = math.pi / 180,
      a = binding['rotation']! * d,
      c = math.cos(binding['latitude']! * d),
      x = p[0] * math.cos(a) - p[1] * math.sin(a),
      y = p[0] * math.sin(a) + p[1] * math.cos(a);
  return [
    binding['longitude']! + x / (6378137 * c * d),
    (2 *
                math.atan(math.exp(math.log(
                        math.tan(math.pi / 4 + binding['latitude']! * d / 2)) +
                    y / (6378137 * c))) -
            math.pi / 2) /
        d
  ];
}

List<double> fromProvider(List<num> p, Map<String, num> binding) {
  final d = math.pi / 180,
      a = -binding['rotation']! * d,
      c = math.cos(binding['latitude']! * d),
      x = (p[0] - binding['longitude']!) * 6378137 * c * d,
      y = (math.log(math.tan(math.pi / 4 + p[1] * d / 2)) -
              math.log(math.tan(math.pi / 4 + binding['latitude']! * d / 2))) *
          6378137 *
          c;
  return [x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)];
}
