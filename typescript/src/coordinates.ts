import type { Binding, Point } from "./types.js";
const R = 6378137,
  D = Math.PI / 180;
// Provider-native coordinates. This does not convert GCJ-02 to WGS84.
export function toProvider(p: Point, b: Binding): Point {
  const a = b.rotation * D,
    c = Math.cos(b.latitude * D),
    x = p[0] * Math.cos(a) - p[1] * Math.sin(a),
    y = p[0] * Math.sin(a) + p[1] * Math.cos(a);
  return [
    b.longitude + x / (R * c * D),
    (2 *
      Math.atan(
        Math.exp(
          Math.log(Math.tan(Math.PI / 4 + (b.latitude * D) / 2)) + y / (R * c),
        ),
      ) -
      Math.PI / 2) /
      D,
  ];
}
export function fromProvider(p: Point, b: Binding): Point {
  const c = Math.cos(b.latitude * D),
    a = -b.rotation * D,
    x = (p[0] - b.longitude) * R * c * D,
    y =
      (Math.log(Math.tan(Math.PI / 4 + (p[1] * D) / 2)) -
        Math.log(Math.tan(Math.PI / 4 + (b.latitude * D) / 2))) *
      R *
      c;
  return [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)];
}
