#if os(macOS)
import AppKit
import CamapKit
import SwiftUI

@main struct CalibrationApp: App {
  @StateObject private var session = CalibrationSession()
  var body: some Scene {
    WindowGroup("万卷图 · MapKit 对点校准") {
      CalibrationView(session: session).frame(minWidth: 1240, minHeight: 780)
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
    .windowStyle(.titleBar)
  }
}

struct CalibrationView: View {
  @ObservedObject var session: CalibrationSession
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button("打开 .camap") { session.openFile() }
        TextField("学校 ID", text: $session.schoolID).frame(width: 50)
        Button(session.loading ? "正在读取…" : "读取已发布地图") { session.loadPublished() }.disabled(session.loading)
        Text(session.sourceLabel).lineLimit(1)
        Spacer()
        Button("导出校准地图与记录") { session.export() }.disabled(!session.canExport)
      }
      if let doc = session.document {
        Text("主图 \(doc.masterId ?? "独立工程") · 基准版本 \(doc.baseRevision.map(String.init) ?? "无") · \(doc.features.count) 个对象")
          .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
        HStack {
          Picker("区域", selection: $session.frameID) {
            ForEach(doc.frames, id: \.id) { Text($0.name).tag($0.id) }
          }.frame(maxWidth: 300).onChange(of: session.frameID) { _ in session.reset() }
          Toggle("卫星底图", isOn: $session.satellite)
          Toggle("叠加 CAMAP", isOn: $session.showDrawing)
          Toggle("显示平移后预览", isOn: $session.showFitted)
          Button("回到校区") { session.zoomToken = UUID() }
          Text(session.mapStatus).font(.caption)
        }
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading) {
            Text("CAMAP 局部平面").font(.headline)
            Text("橙色为当前对应点；请用同一扇门、同一建筑角点。").font(.caption)
            LocalDrawing(session: session)
          }.frame(minWidth: 270, idealWidth: 330, maxWidth: 400)
          VStack(alignment: .leading) {
            Text("Apple 原生底图 · 正北朝上").font(.headline)
            Text(session.armed ? "已进入取点：点击 Apple 底图中的同名位置" : "可拖动缩放；先按右侧取点按钮才会记录坐标")
              .font(.caption).foregroundColor(session.armed ? .orange : .secondary)
            AppleCalibrationMap(session: session)
          }.frame(minWidth: 450)
          controls.frame(width: 315)
        }
      } else {
        Spacer()
        Text("一个锚点修正平移，另外两个分散地标独立验证。旋转与几何比例保持。")
          .font(.title3)
        Spacer()
      }
      Text(session.status).font(.callout).fixedSize(horizontal: false, vertical: true)
    }.padding(14)
  }
  private var controls: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(0..<3, id: \.self) { i in
          Button {
            session.active = i
            session.armed = false
            if let selection = session.selections[i] {
              session.selectedFeatureID = selection.featureID
            }
          } label: {
            VStack(alignment: .leading) {
              Text(session.roles[i]).bold()
              Text(session.selections[i]?.name ?? "尚未选择 CAMAP 地标").lineLimit(2)
              Text(session.selections[i]?.coordinate == nil ? "尚未在 Apple 底图取点" : "已记录 Apple 观测点")
                .font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
          }.buttonStyle(.bordered).tint(session.active == i ? .orange : .accentColor)
        }
        Divider()
        TextField("查找 CAMAP 地标名称", text: $session.search)
        Picker("同名地标", selection: $session.selectedFeatureID) {
          Text("请选择").tag("")
          ForEach(session.filteredFeatures, id: \.id) {
            Text("\($0.name) · \($0.id.prefix(6))").tag($0.id)
          }
        }.onChange(of: session.selectedFeatureID) { _ in session.vertex = 0; session.armed = false }
        if let feature = session.feature {
          let points = feature.geometry.points
          if points.count > 1 {
            Picker("具体位置", selection: $session.vertex) {
              ForEach(points.indices, id: \.self) { Text("顶点 \($0 + 1)").tag($0) }
              Text("顶点均值中心（须确认同一点位）").tag(points.count)
            }
          }
          Button("选为\(session.roles[session.active])") { session.selectLocal() }
          Text("UUID：\(feature.id)").font(.caption2).textSelection(.enabled)
        }
        Button(session.armed ? "等待在 Apple 底图点击…" : "在 Apple 底图点同名位置") {
          session.armed.toggle()
        }.disabled(session.selections[session.active] == nil || !session.mapReady)
        Divider()
        if let origin = session.frame?.bindings["amap"] {
          Text(String(format: "源 amap 原点：%.6f, %.6f\n旋转：%.3f°", origin.longitude, origin.latitude, origin.rotation))
            .font(.caption).textSelection(.enabled)
        }
        Text(session.frame?.bindings["mapkit"] != nil
          ? "已有独立 mapkit 绑定作为候选"
          : "按高德原生 GCJ-02 反算初始候选，结果尚未校准")
          .font(.caption)
        if session.frame?.bindings["mapkit"] == nil {
          Toggle("已核实源原点本来就是 WGS-84（跳过反算）", isOn: $session.sourceIsVerifiedWGS84)
            .font(.caption).onChange(of: session.sourceIsVerifiedWGS84) { _ in session.reset() }
        }
        Text("只有确认源数据被手动改为 WGS-84 时才勾选；不能仅凭数值或画面猜测。").font(.caption2).foregroundColor(.secondary)
        if let candidate = session.candidate, let fitted = session.fitted {
          let shift = TranslationCalibration.distanceMeters(
            Point(candidate.longitude, candidate.latitude), Point(fitted.longitude, fitted.latitude))
          Text(String(format: "原点平移约 %.1f 米 · 旋转 %.3f° 保持", shift, fitted.rotation)).font(.caption)
        }
        Stepper(value: $session.maximumError, in: 1...30, step: 1) {
          Text("验证误差上限：\(Int(session.maximumError)) 米")
        }.font(.caption)
        if let report = session.report {
          ForEach(report.checks.indices, id: \.self) { i in
            Text(String(format: "%@：%.2f 米", report.checks[i].landmark.name, report.checks[i].errorMeters))
              .font(.caption).foregroundColor(report.checks[i].errorMeters <= session.maximumError ? .green : .red)
          }
          Text(String(format: "最短间距 %.1f 米 · 三角形高度 %.1f 米", report.minimumSeparationMeters, report.triangleHeightMeters))
            .font(.caption2)
          Text(report.accepted ? "三个对应点验证通过，可以导出" : report.issues.joined(separator: "；"))
            .font(.caption).foregroundColor(report.accepted ? .green : .orange)
        }
        Text("三个地标需两两相距 ≥50 米，并分布在不同方向。误差超限时重新核对取点；本工具只修正平移。")
          .font(.caption2)
        Text("观测直接来自 MapKit 点击坐标，未经 GCJ/WGS 再转换。验证的是可见底图对齐，不代表 GPS 测绘精度。")
          .font(.caption2).foregroundColor(.secondary)
      }
    }
  }
}

struct LocalDrawing: View {
  @ObservedObject var session: CalibrationSession
  var body: some View {
    Canvas { context, size in
      let all = session.features.flatMap(\.geometry.points)
      guard !all.isEmpty else { return }
      let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
      let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
      let scale = min((size.width-36)/max(1,maxX-minX), (size.height-36)/max(1,maxY-minY))
      func screen(_ p: Point) -> CGPoint {
        CGPoint(x: size.width/2 + (p.x-(minX+maxX)/2)*scale,
          y: size.height/2 - (p.y-(minY+maxY)/2)*scale)
      }
      for f in session.features {
        let ps = f.geometry.points.map(screen)
        guard let first = ps.first else { continue }
        var path = Path()
        if ps.count == 1 { path.addEllipse(in: CGRect(x: first.x-2, y: first.y-2, width: 4, height: 4)) }
        else {
          path.move(to: first)
          for p in ps.dropFirst() { path.addLine(to: p) }
          if case .polygon = f.geometry { path.closeSubpath() }
        }
        let color: Color = f.id == session.selectedFeatureID ? .orange : (f.kind == "building" ? .blue : .secondary)
        context.stroke(path, with: .color(color), lineWidth: f.id == session.selectedFeatureID ? 2 : 0.8)
      }
      if let f = session.feature {
        let ps = f.geometry.points
        let p = session.vertex < ps.count ? ps[max(0,session.vertex)] :
          Point(ps.map(\.x).reduce(0,+)/Double(ps.count), ps.map(\.y).reduce(0,+)/Double(ps.count))
        let q = screen(p)
        context.fill(Path(ellipseIn: CGRect(x:q.x-5,y:q.y-5,width:10,height:10)), with:.color(.orange))
        context.draw(Text(f.name).font(.caption).foregroundColor(.orange), at: CGPoint(x:q.x,y:q.y-16))
      }
      for i in 0..<3 {
        guard let pair = session.selections[i] else { continue }
        let q = screen(pair.local)
        context.draw(Text("\(i+1)").bold().foregroundColor(.red), at: q)
      }
    }.background(Color(nsColor: .textBackgroundColor)).border(.gray.opacity(0.3))
  }
}
#else
@main struct CalibrationApp {
  static func main() { print("MapKit 对点校准工具请在 macOS 运行。") }
}
#endif
