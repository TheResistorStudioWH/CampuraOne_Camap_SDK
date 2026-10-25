# Campura One CAMAP SDK

四种语言共用 CAMAP 0.1.0 文件格式，分别构建。格式规范由独立仓库 `CampuraOne_Camap` 管理；本仓库不依赖其工作目录。固定的规范版本与 Schema 摘要记录在 `camap-spec.lock.json`。

## 目录与能力

| 目录 | 用途 | 本版能力 |
| --- | --- | --- |
| 根目录 Package.swift、swift/ | Xcode / Swift Package Manager | 类型模型、包读写、引用校验、坐标投影 |
| dart/ | Flutter / Dart | 包读写、保留字段的文档模型、引用校验、坐标投影 |
| typescript/ | 万卷图、学校 Web、Node | 包读写、引用校验、三方合并、室外路网寻路、坐标投影 |
| php/ | PHP 8.3 服务端 | 包读写、引用校验、三方合并 |
| tools/cli/ | Node 命令行 | 检查、校验、JSON 导入导出 |

各语言的包解析器限制为两文件、20 MiB 的 ZIP STORE，校验 CRC32 和 SHA-256。校验器检查核心字段、几何与引用关系；Schema 是独立的完整结构约束。不要把 SDK 的成功解析视为对任意附加元数据的完整 JSON Schema 验证。Swift 的 Codable 模型只保留已声明字段，应用不要添加规范外字段。扩展字段应先升级格式版本并同步全部 SDK。

## iOS 导入

在 Xcode 的 File → Add Package Dependencies 输入此 SDK 仓库的 Git URL，选择 `CamapKit`。根目录的 Package.swift 只引用 Swift 目录，Dart、TypeScript 和 PHP 文件不参与 iOS 构建。私有仓库需要开发者自己的 GitHub 访问权限。

```swift
import CamapKit
let document = try Camap.read(from: fileURL)
try Camap.write(document, to: anotherURL)
```

也可先用 Xcode 的 Add Local Package 选择本仓库根目录。学生端 UI 尚未接入；SDK 不会自行请求定位、加载地图或生成室内导航。

## 本地构建与测试

```sh
swift test
cd typescript
npm ci
npm test
cd ../dart
dart pub get
dart analyze
dart test
cd ../php
php tests/test.php
```

PHP 可通过 Composer path repository 安装，也可由服务端环境变量指向 `php/`；详见 Server/docs/camap.md。

```json
{ "dependencies": { "@campura/camap": "file:../CampuraOne_Camap_SDK/typescript" } }
```

使用 TypeScript 本地依赖前先执行该目录的 `npm ci && npm run build`。Dart Git 依赖需指定 `path: dart`，Swift 不需要指定子路径。

## 命令行

在 TypeScript 编译完成后：

```sh
node tools/cli/camap.mjs inspect campus.camap
node tools/cli/camap.mjs validate campus.camap
node tools/cli/camap.mjs to-json campus.camap campus.json
node tools/cli/camap.mjs from-json campus.json campus.camap
```

文件内使用局部米制坐标。AMap 与 MapKit 分别保存绑定，不能直接复用 GCJ-02 与 WGS84 经纬度；投影函数不承担两者转换。示例只使用未绑定真实位置的演示校区。
