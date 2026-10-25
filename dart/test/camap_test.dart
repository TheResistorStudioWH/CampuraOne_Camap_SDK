import 'dart:io';
import 'package:test/test.dart';
import 'package:camap/camap.dart';

void main() {
  test('read/write fixture and reject corruption', () {
    final bytes = File('test/fixtures/demo.camap').readAsBytesSync(),
        d = decodeCamap(bytes);
    expect(d.features.length, 5);
    final folder = Platform.environment['CAMAP_INTEROP_DIR'];
    if (folder != null) {
      File('$folder/dart.camap').writeAsBytesSync(encodeCamap(d));
    }
    expect(decodeCamap(encodeCamap(d)).toJson(), d.toJson());
    bytes[100] ^= 1;
    expect(() => decodeCamap(bytes), throwsFormatException);
  });
  test('provider projection roundtrip', () {
    final b = {'longitude': 114, 'latitude': 30, 'rotation': 20};
    final p = fromProvider(toProvider([45, -20], b), b);
    expect(p[0], closeTo(45, 0.0001));
    expect(p[1], closeTo(-20, 0.0001));
  });
  test('reject missing route endpoint', () {
    final json = decodeCamap(File('test/fixtures/demo.camap').readAsBytesSync())
        .toJson();
    json['nodes'] = [];
    expect(() => CamapDocument.fromJson(json), throwsFormatException);
  });
}
