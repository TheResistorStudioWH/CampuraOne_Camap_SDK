# schoolID=1 地图坐标链路核查

核查日期：2026-11-04。初始核查只读获取线上 revision1；用户随后明确确认当前候选已对齐、无需继续校准，按该位置于当日发布 revision2。未编辑学生 iOS 仓库的本地改动。

## 已核对的事实

- 线上主图 `9c3237e6-f91d-4a2f-8ef5-88fd73027ff4`，baseRevision=1，147 个地标，frame `66f67af4-981f-4469-b055-b193f7240456`。amap 原点为经度 114.398994、纬度 30.370608、逆时针旋转 0°；没有 mapkit。
- Downloads 原始 CAMAP 与线上发布版本的整个 bindings 对象一致，发布没有额外做坐标转换。原始文件没有记录原点的采集操作日志或显式 CRS 元数据，因此仅凭经纬度数值不能证明从未被人手工修改。
- 万卷图当前实现：macOS Core Location 返回系统位置；`src/location.ts` 将它经 `AMap.convertFrom(..., "gps")` 转入高德一次，随后 `focus` 显示；`src/amap.ts:getCenter` 直接读取高德视图中心，`src/App.tsx:useCampusCenter` 原样保存为 amap。手动漫游后确认也直接保存高德中心。沿此流程创建的原点应为 GCJ-02，而不是 WGS-84。
- iOS 当前 `CampusMapGeometry.initialPlacement` 仅在缺少 mapkit 时对 amap 原点反算一次并建立会话临时放置；`coordinate` 遇到独立 mapkit 直接调用 `Binding.project`，x 作经度、y 作纬度。已读取的链路没有第二次反算；未将反算结果写回 amap。
- `Binding.project/unproject` 只在局部米制平面与某个 provider 的经纬度间投影，不做 GCJ/WGS 转换。

结论：已有代码和原始/发布文件的一致性支持“amap 保存高德原生 GCJ-02”。当前静态链路没有发现重复转换；仍需实际对点判断 Apple 底图的视觉差异，不能用近似算法自身的往返一致性宣称实际校准。

## 独立校准流程

运行 `tools/mapkit-calibration/build-macos.sh` 构建 Mac 原生工具，读取当前已发布地图。Apple 观测经纬度来自 `MKMapView.convert(_:toCoordinateFrom:)`，不再反算。

选择一个能在两侧明确辨认的门或建筑角点拟合平移。保持原旋转（本图为 0°）与全部局部几何；另选两个分散地标检验，不参与拟合。工具拒绝重复地标、近距离/共线验证和超限误差，默认可见底图残差要求 ≤10 米。通过后才允许生成带 mapkit 的新 CAMAP，以及独立的 JSON 校准记录。

真实三对观测尚未收集时，不能将记录标为通过三点校准。常规工具仍要求两处独立检查通过才导出；此次用户明确接受当前候选、要求直接修正，使用单独的 `user_visual_approval` 发布记录，不伪造检查点，不放宽工具或 SDK 校准校验。发布沿用当前 masterId/baseRevision，检查 frame revision 变化、147 个地标和 106 条商户关联均保留，并通过既有事务发布函数产生新版本。

## 本次运行验证

7 项 Swift 测试通过，包含非零锚点平移求解、旋转不变、验证点不参与拟合、错误/重复/集中/共线验证拒绝、地图几何/高德绑定/发布身份保留和 CAMAP 编解码往返。Mac App 已构建并实际打开，成功读取线上 revision1 的 147 个对象，Apple 卫星图显示校区及初始候选叠加。选定一食堂顶点1后，未取得实际观测；两个检查点也未设置。用户随后确认当前显示已对齐，因此发布的正是一次反算得到的候选，没有额外平移。此项运行验证不能当作三点残差验证通过。

## 已发布结果

2026-11-04 22:36:12（Asia/Shanghai），schoolID=1 发布 revision2。独立 `mapkit` 原点：longitude=114.39346396109258、latitude=30.37294670167217、rotation=0。原 `amap` 114.398994、30.370608、0 保留；frame revision 从1变为2。SDK 计算结果与发布副本一致，不会在消费 mapkit 时再次反算。

线上 JSON、CAMAP 的文档与 manifest 哈希一致，文档 SHA256 为 `4e2e6c4e5d235822351254b1071451e9ef7b54bf229f9ede5c0fc37f8812be01`。逐字段还原此次新增绑定、frame revision 和发布版本号后，与原 revision1 完全相同；147个地标及106条商户关联保留。发布记录和下载后的实际文件在 Server 的 `docs/mapkit-release-2026-11-04.md`、`resources/maps/wuchang-mapkit-published-2026-11-04.camap`。用户视觉确认不代表测量精度保证。

## 参考

- [高德坐标体系说明](https://lbs.amap.com/api/javascript-api-v2/guide/abc/basetype)
- [Apple MKMapView 点击位置转地图坐标](https://developer.apple.com/documentation/mapkit/mkmapview/convert(_:tocoordinatefrom:))
