<div align="center">

<img src="assets/images/logo/logo.png" width="140" alt="韩小圈" />

# 韩小圈

**韩国综艺 桌面 / 移动 / TV 客户端**

一份 Flutter 代码，四端同构：macOS · Windows · Android · iOS

</div>

---

## 这是什么

韩小圈是一个韩国综艺聚合播放器：官方目录（171 部综艺 / 5 大板块）+ 本地采集的播放源，
界面用一套 Flutter 代码同时适配桌面、手机与电视，尺寸由 `HjMetrics` 统一换算，
不会在 1080p 窗口上把字号放大 1.5 倍。

## 功能

- **首页**：精选轮播 + 板块横滑（热播综艺 / 在更综艺 / 恋爱真人秀 / 推理烧脑 / 旅游冒险）
- **搜索**：独立搜索页，本地全文检索（剧名 / 嘉宾 / 副标题 / 板块名 / 逐字模糊），带最近搜索、热门、按嘉宾直搜
- **分类**：板块筛选 + 实时过滤（剧名 / 嘉宾 / 副标题）
- **详情**：模糊海报Hero + 评分/期数/画质标签 + 简介展开 + 选集网格 + 「仅看已收录」筛选
- **播放**：media_kit（libmpv）播放，HLS（m3u8）分片经本机并发代理突破 CDN 单连接限速
- **播放操作**：点画面暂停/播放；长按 → 2 倍速（松开还原）；长按 ↑/↓ 连续调音量；← / → 短按跳 15 秒；F 切换画面填充
- **记录**：继续观看横滑 + 全部记录，可逐条删除
- **响应式**：手机 3 列 / 平板 5 列 / TV 6 列 / 桌面按窗口宽度自适应 4–12 列
- **TV 遥控**：所有可点元素支持方向键焦点 + hover 高亮

## 直接下载

正式版发布在 [Releases](https://github.com/t479842598/HXQ-TV-MAC/releases)：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| macOS | `HanjuTV_macos_1.0.2.dmg` / `.zip` | Apple Silicon（arm64），拖进 Applications 即可 |
| Android | `HanjuTV_android_1.0.2_arm64-v8a.apk` | 绝大多数手机；另附 armeabi-v7a / x86_64 |
| iOS | `HanjuTV_ios_1.0.2_unsigned.ipa` | 未签名，需自签（Sideloadly / AltStore / Xcode）后安装 |

macOS 首次打开若提示“无法验证开发者”，执行：

```bash
xattr -dr com.apple.quarantine /Applications/韩小圈.app
```

## 一键构建

### macOS

```bash
export PATH=/path/to/flutter/bin:$PATH
export GEM_HOME=/path/to/ruby/gems GEM_PATH=/path/to/ruby/gems   # CocoaPods 依赖
flutter config --enable-macos-arm64-only
flutter config --no-enable-swift-package-manager
flutter build macos --release
# 产物：build/macos/Build/Products/Release/韩小圈.app
```

### Android

```bash
flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-<abi>-release.apk
```

### iOS（无签名）

Flutter 3.47 起 `--no-codesign` 仍会探测 Development Team，CI 里改用 `--config-only` + 直接调 xcodebuild：

```bash
flutter build ios --release --config-only --no-codesign --no-pub
cd ios && xcodebuild \
  -workspace Runner.xcworkspace -scheme Runner \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath ../build/ios/Runner.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" archive
# 产物：build/ios/Runner.xcarchive/Products/Applications/Runner.app
```

### Windows

```powershell
flutter build windows --release
```

## CI 发布

`.github/workflows/release.yml` 支持手动触发（workflow_dispatch）与 tag 触发（`v*`）：

1. 勾选要构建的平台（android / macos / ios）
2. 填发布 tag（留空只出产物，不建 Release）
3. 产物命名：`HanjuTV_<platform>_<version>.<ext>`

版本号由 `tool/ci_version.sh` 从 `pubspec.yaml` 读取，构建号用 `git rev-list --count HEAD`。

```bash
git tag v1.0.2 && git push origin v1.0.2   # 自动跑全部平台并建 Release
```

## 目录结构

```
lib/hanju/
├── api.dart            # hxqapi 请求封装（详情 / 选集）
├── store.dart          # catalog + playmap + 详情缓存，8 并发刷新
├── models.dart         # HjSeries / HjSeriesInfo / HjPlayItem
├── history.dart        # 观看记录持久化
├── segment_auth.dart   # CDN 分片鉴权参数
├── hj_shell.dart       # 外壳：侧边导航 / 底部导航
├── ui/
│   ├── responsive.dart # HjDevice / HjMetrics 尺寸换算中心
│   └── hj_theme.dart   # 品牌色（粉紫渐变）
├── widgets/
│   └── poster_card.dart
└── pages/
    ├── home_page.dart      # 精选轮播 + 板块横滑
    ├── category_page.dart  # 分类网格 + 搜索
    ├── detail_page.dart    # 详情 + 选集
    ├── player_page.dart    # media_kit 播放器
    └── history_page.dart   # 观看记录

assets/hanju/
├── catalog.json    # 171 部综艺目录（5 板块）
└── playmap.json    # 145 条播放源映射
```

## 尺寸体系

所有字号与间距都必须经过 `HjMetrics`，禁止写死像素：

```dart
final m = HjMetrics.of(context);
Text('标题', style: TextStyle(fontSize: m.sp(13)));   // 字号
SizedBox(height: m.gap(8));                            // 间距
```

| 形态 | 字号倍率 | 间距倍率 | 内容最大宽度 |
|------|---------|---------|-------------|
| 桌面 | 1.0 固定 | 0.94–1.14（随宽度） | 1360 |
| TV | 1.28 | 1.34 | 1360 |
| 平板 | 1.0–1.14 | 1.0–1.18 | 980 |
| 手机 | 0.88–1.06 | 0.88–1.08 | 屏幕宽 |

## 致谢

界面框架复用 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的 Flutter 工程骨架
（GetX 路由、media_kit 播放层、主题系统），业务层 `lib/hanju/` 为本项目自研。

## 免责声明

本项目仅用于个人学习与技术研究，所有内容版权归原权利方所有。
