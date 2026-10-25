import type { CamapDocument, Point, RouteEdge } from "./types.js";
export function edgeLength(d: CamapDocument, e: RouteEdge): number {
  const a = d.nodes.find((n) => n.id === e.from),
    b = d.nodes.find((n) => n.id === e.to);
  if (!a || !b) return Infinity;
  const p: Point[] = [a.position, ...e.points, b.position];
  return p
    .slice(1)
    .reduce((s, q, i) => s + Math.hypot(q[0] - p[i][0], q[1] - p[i][1]), 0);
}
export function findRoute(
  d: CamapDocument,
  from: string,
  to: string,
  options: { accessible?: boolean; preferCovered?: boolean } = {},
) {
  const costs = new Map([[from, 0]]),
    previous = new Map<string, { node: string; edge: string }>(),
    queue = new Set(d.nodes.map((n) => n.id)),
    adj = new Map<string, { node: string; edge: RouteEdge; cost: number }[]>();
  if (!queue.has(from) || !queue.has(to)) return null;
  for (const e of d.edges) {
    if (e.closed || (options.accessible && !e.accessible)) continue;
    const cost =
      edgeLength(d, e) * (options.preferCovered && !e.covered ? 1.3 : 1);
    for (const [a, b] of e.oneWay
      ? [[e.from, e.to]]
      : [
          [e.from, e.to],
          [e.to, e.from],
        ])
      adj.set(a, [...(adj.get(a) || []), { node: b, edge: e, cost }]);
  }
  while (queue.size) {
    let u: string | undefined,
      best = Infinity;
    for (const id of queue) {
      const c = costs.get(id) ?? Infinity;
      if (c < best) {
        best = c;
        u = id;
      }
    }
    if (!u) break;
    queue.delete(u);
    if (u === to) break;
    for (const next of adj.get(u) || []) {
      const cost = best + next.cost;
      if (cost < (costs.get(next.node) ?? Infinity)) {
        costs.set(next.node, cost);
        previous.set(next.node, { node: u, edge: next.edge.id });
      }
    }
  }
  if (!costs.has(to)) return null;
  const nodes = [to],
    edges: string[] = [];
  let n = to;
  while (n !== from) {
    const p = previous.get(n);
    if (!p) return null;
    edges.unshift(p.edge);
    nodes.unshift(p.node);
    n = p.node;
  }
  return {
    nodes,
    edges,
    distanceMeters: edges.reduce(
      (sum, id) =>
        sum +
        edgeLength(
          d,
          d.edges.find((e) => e.id === id)!,
        ),
      0,
    ),
  };
}
