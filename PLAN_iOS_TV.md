# 韩剧TV（韩小圈）iOS + TV 双端改造计划

> 基线：PiliPlus（Flutter）原样拷贝，**不修改任何现有工程**
> - 参考源：`/tmp/PiliPlus`（git 干净，HEAD a5665fb）——只读，不动
> - 旧工程：`/Users/qingtang/hxq/HanjuFlutter`（macOS 方向）——不动
> - **本计划工作区**：`/Users/qingtang/hxq/HanjuTV`（28MB，已从 pristine PiliPlus rsync 出来，无 .git）

---

## 0. 环境基线（已实测）

| 项 | 状态 |
|---|---|
| Flutter | 3.47.7 stable arm64 @ `/Users/qingtang/flutter`（pristine，HEAD abaf9c52） |
| SDK patch | 26 个 patch 全部 `git apply --check` **通过**（22 base + bottom_sheet_android + bottom_sheet_ios_flutter + scroll_view + navigator） |
| material_ui / cupertino_ui | 需在 pub-cache 内 patch（tabs / scaffold / navigation_drawer 等） |
| Android | SDK root `/Users/qingtang/.homebrew/share/android-commandlinetools`；build-tools 34/35/36；ndk 27.0.12077973 + 28.2.13676358；JDK 21.0.12；gradle 8.9 已缓存 |
| minSdk | 24（`flutter.minSdkVersion`） |
| 32 位支持 | media_kit `libs/android/media_kit_libs_android_video` 提供 `default-armeabi-v7a.jar`（minSdk 16）→ `--target-platform android-arm` 可行 |
| iOS | Xcode SDK `iphoneos27.1`；Podfile `platform :ios, '14.0'`；**模拟器 runtime 为空** |
| 图标源 | `/tmp/icon1024.png`（1024×1024 粉紫「韩小圈」） |

### 两条硬约束（必须提前知道，避免白跑）
1. **Apple Silicon 无法执行 AArch32** → `armeabi-v7a` APK 在本机 emulator 装不上，TV 包只能真机（电视盒子）验证；本机用 arm64 包 + TV 模式开关验证同一份 Dart 代码。
2. **iOS 模拟器 runtime 缺失** → 只能真机，或先跑 `xcodebuild -downloadPlatform iOS` 拉 runtime（数 GB）。

---

## 1. 阶段划分

### Phase 0 — 工程可编译基线（1 步验证）
1. 给 Flutter SDK 打 26 个 patch（一次性，SDK 级）
2. 给 pub-cache 的 material_ui / cupertino_ui 打对应 patch
3. `flutter pub get` → `flutter analyze` 期望 **0 error**
4. `flutter build apk --target-platform android-arm --debug` 打通链路

验收：analyze 0 error；APK 产出且 `unzip -l` 内含 `lib/armeabi-v7a/libmpv.so`。

### Phase 1 — 韩小圈数据层（Dart 移植）
从 Swift 版（`/Users/qingtang/hxq/HanjuMac`）迁到 Dart，全部放 `lib/hanju/`：

| 文件 | 职责 |
|---|---|
| `hanju/models.dart` | `HjSeries` / `HjBlock` / `HjDetail` / `HjPlayItem` / `HjQuality` / `HjPlayMapEntry` |
| `hanju/api.dart` | 13 个固定头（sign 620 字符、vc=a_8360、vn=6.9.1、ch=bbc、app=hj、said、uk）+ `fetchDetail(sid)` / `fetchPlaylist(dir)`（**必须带 segmentAuth**） |
| `hanju/catalog.dart` | 读 assets `catalog.json`（5 板块 171 部）+ `playmap.json`（145 条 DIR） |
| `hanju/playlist_server.dart` | `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`，把 master m3u8 相对行重写成绝对地址 + 拼 7 个签名参数 + 补 ENDLIST |
| `hanju/segment_auth.dart` | 7 参数常量：`pid / utk / uk / spl / t / sign / ip` |
| `hanju/store.dart` | GetxController：catalog + 详情缓存（Hive，TTL 2h）+ playmap |

**关键结论（已验证，别重走）**：m3u8 与分片不带这 7 参数会被 CDN 限速到 ~950 B/s；参数成套校验，不能省略也不能伪造。

### Phase 2 — 页面层（替换 B 站内容源）
| 页面 | 做法 |
|---|---|
| 首页 `lib/pages/hanju/home` | 5 个板块横滑 + Hero 精选，替换 `pages/home` 的默认 tab 内容 |
| 详情 `lib/pages/hanju/detail` | 海报 + 简介（可展开）+ 清晰度 + 选集网格（按「仅看已收录」筛选） |
| 播放 `lib/pages/hanju/player` | **复用 `pl_player`**（media_kit），只换 DataSource 来源 |
| 主 Tab | `lib/pages/main/view.dart` 的 tab 列表换成：首页 / 分类 / 历史 / 设置（保留 PiliPlus 的骨架与动画） |

验收：三端（手机 / TV / iOS）同一份 Dart，首页 → 详情 → 起播全链路通。

### Phase 3 — 一套样式 + 分辨率自适应
新增 `lib/hanju/ui/responsive.dart`：
```dart
enum HjForm { phone, tablet, tv, desktop }
// shortestSide < 600 → phone；>=600 → tablet；TV 标志位覆盖为 tv；desktop 走 platform
class HjMetrics {
  final HjForm form;
  final double shortest;        // dp
  double sp(double base);       // base * clamp(shortest/390, 0.88, 1.45)（tv 额外 *1.18）
  double gap(double base);
  int posterColumns;            // phone 3 / tablet 5 / tv 6 / desktop 7
  EdgeInsets pagePadding;
}
```
- 全部尺寸走 `HjMetrics.sp/gap`，**禁止裸数字**
- `HjForm.tv` 时字号整体放大 18%、描边加粗、圆角加大（3 米观看距离）
- 断点只用 `LayoutBuilder`/`MediaQuery`，不用固定像素

验收：1920×1080 TV（960×540 dp）、iPhone 390×844、iPad 1024×768 三档截图布局无溢出、字号比例一致。

### Phase 4 — 电视遥控器
1. `AndroidManifest.xml` 新增：
   - `<uses-feature android:name="android.software.leanback" android:required="false"/>`
   - `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`
   - `<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>`（与 LAUNCHER 并存）
   - `android:banner="@drawable/tv_banner"`（320×180）
2. `lib/hanju/ui/tv_focus.dart`：
   - `CallbackShortcuts` 绑 `arrowUp/Down/Left/Right` + `select(23/enter)` + `back(4/escape)`
   - `HjFocusable` 组件：`Focus` + `AnimatedContainer` 焦点环（3px accent + 外发光 + scale 1.06）
   - 网格焦点用 `FocusTraversalGroup(policy: OrderedTraversalPolicy)` + 每格 `FocusTraversalOrder`
3. 播放器遥控：左右 = seek ±15s，上下 = 音量/选集，OK = 播放暂停，返回 = 退出
4. TV 检测：`device_info_plus` 查 `PackageManager.FEATURE_LEANBACK`，失败回落到 `uiMode & UI_MODE_TYPE_TELEVISION`；设置里加「强制 TV 模式」开关（本机 arm64 emulator 验证用）

验收：emulator 用 `adb shell input keyevent 19/20/21/22/23/4` 全流程可操作，焦点环可见。

### Phase 5 — 历史记录 + 观看进度
不依赖 B 站 API，纯本地：
```dart
// lib/hanju/history.dart
class HjHistoryEntry { String sid; String seriesName; int serialNo; String epTitle; String dir;
  double position; double duration; String? poster; DateTime updatedAt; }
// Hive box: 'hanjuHistory'，key = '$sid#$serialNo'，上限 120 条
```
- 写入时机：每 5 秒 / 暂停 / 退出播放 / App 进后台（`WidgetsBindingObserver`）
- 续播：打开剧集时若 `position > 8s && duration - position > 20s` → 弹「从 12:34 继续播放 / 从头开始」
- 首页顶部「继续观看」横滑（取最近 10 条，进度条覆盖在海报底部）
- 历史页：按剧聚合，长按删除单条 / 清空
- 不与 PiliPlus 自带 `GStorage.watchProgress`（B 站 cid 键）混用，独立 box

验收：杀进程重开 → 进度保留；同集看完 → 记录置为已看完；跨端（TV / iOS）各自本地独立。

### Phase 6 — 图标与品牌
- 用 `/tmp/icon1024.png` 覆盖 `assets/images/logo/logo.png` 与 `logo_2.png`
- `pubspec.yaml` 的 `flutter_launcher_icons` 保持 android/ios 双开，补 `adaptive_icon_background: "#ffffff"`
- Android label → `韩剧TV`；iOS `CFBundleDisplayName` → `韩剧TV`；bundle id → `com.qingtang.hanjutv`
- 跑 `dart run flutter_launcher_icons` 生成 mipmap / AppIcon

验收：桌面图标是韩小圈粉紫图标；TV 启动器显示韩小圈图标 + banner。

### Phase 7 — 打包
| 产物 | 命令 | 说明 |
|---|---|---|
| TV 32 位 APK | `flutter build apk --release --target-platform android-arm` | 只有 armeabi-v7a |
| 通用 APK（自测） | `flutter build apk --release --target-platform android-arm64` | 本机 emulator 用 |
| iOS | `flutter build ios --no-codesign` 先验编译；签名后 `flutter build ipa` | 需 Apple 账号 |

验收：`aapt2 dump badging` 显示 native-code 只有 `armeabi-v7a`；`unzip -l` 含 `lib/armeabi-v7a/libmpv.so`。

---

## 2. 执行顺序（一次一步，每步可验证）

1. **Phase 0**：打 patch → pub get → analyze 0 error → android-arm debug 包打通
2. **Phase 1**：数据层 + playlist server（用 `flutter test` 或命令行小工具验证 m3u8 重写正确）
3. **Phase 2**：首页 + 详情 + 播放（起播能跑就截图）
4. **Phase 3**：Responsive 抽出来，三档截图对比
5. **Phase 4**：TV 遥控 + leanback manifest
6. **Phase 5**：历史与进度
7. **Phase 6/7**：图标 + 打包

## 3. 风险与对策

| 风险 | 对策 |
|---|---|
| Apple Silicon 跑不了 armeabi-v7a | TV 包只做产物级验证（badging/unzip），功能验证走 arm64 + 强制 TV 模式 |
| 无 iOS 模拟器 runtime | 先 `xcodebuild -downloadPlatform iOS`；或只交 `--no-codesign` 编译产物 |
| 51touxiang CDN 签名参数过期 | 7 参数已实测跨剧集跨时间通用；失效时从 emulator 抓包重取 |
| PiliPlus 大量 B 站 API 调用会报错 | 韩小圈页面独立路由，不初始化 B 站登录/账号服务 |
| SDK patch 被 `git reset --hard` 冲掉 | 打完后不重置；升级 Flutter 前先备份 |
