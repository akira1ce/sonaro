> [!IMPORTANT]
> Sonaro 是个人开发的非官方客户端，与网易云音乐官方无任何关联。
> 项目不包含任何音乐内容或账号数据，仅供学习与个人使用，请勿用于商业用途。
> 音乐版权归网易云音乐及版权方所有。

<div align="right">

[English](README.md) | **简体中文**

</div>

<div align="center">

<img src="Sonaro/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="128" alt="Sonaro" />

# Sonaro

**聆听你的世界 — 原生 SwiftUI 的 macOS 网易云音乐客户端**

SwiftUI · AVPlayer · NeteaseCloudMusicApiEnhanced 后端

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue?logo=apple)](#构建与运行)
[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white)](#构建与运行)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)](#功能)

<table>
  <tr>
    <td><img src="public/screenshot-recommend.png" alt="推荐" /></td>
    <td><img src="public/screenshot-dayly.png" alt="每日推荐" /></td>
  </tr>
  <tr>
    <td><img src="public/screenshot-full-player.png" alt="全屏播放页" /></td>
    <td><img src="public/screenshot-artist.png" alt="歌手详情" /></td>
  </tr>
</table>

</div>

## 功能

- 🔐 **扫码登录** — 使用网易云音乐 App 扫码授权；cookie 保存在 Keychain，冷启动先用缓存会话立即渲染，再后台校验，网络波动不会让你掉登录
- 🏠 **推荐** — 每日推荐歌单、排行榜、精品歌单、热门歌手四个横向歌单区，带骨架屏与整页重试
- 📅 **每日推荐** — 每天更新的推荐歌曲，封面头部 + 播放全部 + 歌曲列表
- 🕘 **最近播放** — 播放记录支持「最近一周 / 所有时间」切换
- 🔍 **搜索** — 单曲搜索，600 ms 防抖、重复提交去重、骨架屏、滚动加载更多、空结果与失败状态
- 💿 **歌单与歌手** — 歌单详情（创建者、简介、播放量、更新时间、播放全部、收藏/取消收藏）；歌手主页（圆形头像、简介、热门歌曲）。歌曲行里的艺人名可直接点进歌手页
- ❤️ **喜欢** — 列表悬停快捷播放/喜欢，播放器内红心；乐观更新，请求失败自动回滚
- 🎧 **播放** — AVPlayer 队列；顺序 / 单曲循环 / 随机 / 列表循环四种模式；标准、较高、极高、无损、Hi-Res 五档音质（下一首生效）；加载与失败状态可见
- 🪟 **迷你播放器** — 悬浮在窗口底部的玻璃胶囊，点击展开全屏播放页
- 🖼 **全屏播放页** — 大封面随播放状态缩放，左侧封面与传输控制、右侧同步歌词；窗口过窄时自动切换为「歌词 + 控制栏」紧凑布局
- 📝 **同步歌词** — 逐行高亮与滚动跟随，点击歌词跳转进度；手动滚动时暂停跟随，2.5 秒后回到当前行；上下边缘渐隐
- ⌨️ **系统集成** — 锁屏 / 控制中心 / 媒体键（播放、暂停、上一首、下一首、拖动进度）；空格键播放/暂停
- 🎨 **外观与字体** — 深色 / 浅色 / 跟随系统；自定义字体族与四档字号，设置页实时预览
- 🗄️ **缓存** — 封面写入磁盘 `URLCache`（约 256 MB），歌词按歌曲 ID 落盘；设置页显示占用并可一键清除
- 🧪 **单元测试** — 覆盖 LRC 解析、播放模式切换、容错模型解码、格式化与搜索分页等纯逻辑

## 构建与运行

要求 **macOS 26+** 与 **Xcode 26+**（Swift 5）。

```bash
open Sonaro.xcodeproj
```

选择 **Sonaro** scheme 和 **My Mac**，⌘R 运行。工程使用 synchronized folder groups，磁盘上新增的源文件会自动进入 target。

> [`APIConfig.swift`](Sonaro/Core/Networking/APIConfig.swift) 不纳入版本控制，方便每个环境保留自己的后端地址。克隆后请从 [`APIConfig.swift.template`](Sonaro/Core/Networking/APIConfig.swift.template) 创建：
>
> ```bash
> cp Sonaro/Core/Networking/APIConfig.swift.template Sonaro/Core/Networking/APIConfig.swift
> ```
>
> 然后修改 `baseURL` 指向你自己的 NeteaseCloudMusicApiEnhanced 实例。

### 命令行构建与测试

```bash
# 构建（CI 同款命令）
xcodebuild -scheme Sonaro -destination 'platform=macOS' build

# 运行单元测试
xcodebuild test -scheme Sonaro -destination 'platform=macOS'
```

`.github/workflows/ci.yml` 会在 push / PR 时执行上述构建与测试。

### 打包 DMG

```bash
brew install create-dmg
./build-dmg.sh
# 输出：dist/Sonaro-<版本号>.dmg
```

脚本构建 Universal Release 应用并生成带拖拽安装布局的 DMG。产物未签名，首次打开需右键 → 打开。

## 后端与配置

Sonaro 依赖第三方、非官方的 [NeteaseCloudMusicApiEnhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced) 服务（与网易云音乐官方无关）：

- API 地址是内置常量，位于 [`APIConfig.swift`](Sonaro/Core/Networking/APIConfig.swift)，该文件不纳入版本控制；请从 [`APIConfig.swift.template`](Sonaro/Core/Networking/APIConfig.swift.template) 创建（见[构建与运行](#构建与运行)），修改 `baseURL` 指向自己的实例后重新编译即可；应用内没有服务器设置项。
- HTTP 明文访问通过 ATS 例外放行（`NSAllowsArbitraryLoads`），换成 HTTPS 实例同样可用。
- 登录态以 `cookie` 查询参数随请求发送；后端返回 301 表示会话已过期，冷启动校验到失效时会回到扫码页。
- 本机设备 ID 单独保存在 Keychain，退出账号后仍保留。扫码前的请求只携带设备 ID，登录后的请求合并账号 Cookie 并统一使用同一个 `deviceId`；后端需支持读取 `cookie.deviceId`。
- 完整接口说明见 [`api-doc.md`](api-doc.md)。

> 登录 cookie 会随请求发送到所配置的后端。默认地址仅供演示，建议使用自己部署的实例并启用 HTTPS，不要连接不可信的服务。

## 架构

五个 `@MainActor` `ObservableObject` 在 [`SonaroApp.swift`](Sonaro/SonaroApp.swift) 中创建，并通过 `.environmentObject` 注入。所有会话、网络与播放状态都由它们持有，页面不自己维护：

- `AuthManager` — 会话状态机（`.unknown → .loggedOut/.loggedIn`）与扫码登录轮询
- `PlayerManager` — AVPlayer 队列、播放控制、歌词同步、系统 Now Playing；高频进度单独放在 `PlaybackProgress` / `LyricPlaybackState`，避免列表页每秒重绘
- `AppearanceManager` — 深色 / 浅色 / 跟随系统
- `FontManager` — 全局字体族与字号
- `LikeManager` — 喜欢的歌曲 ID 集合，负责乐观更新与失败回滚

`RootView` 根据 `auth.state` 切换（启动页 → 扫码登录 → `MainShell`）。`MainShell` 使用 `NavigationSplitView` 侧边栏；迷你播放器和全屏播放页挂在窗口层级，确保进入歌单详情后仍然可见。

```
Sonaro/
├─ SonaroApp.swift          # @main，创建并注入共享状态
├─ App/                     # RootView、MainShell、Theme、AppearanceManager、FontModifier
├─ Core/
│  ├─ Networking/           # APIConfig（内置地址）、APIClient（async + cookie）、APIError
│  ├─ Models/               # Song / Album / Artist / Playlist / Profile（容错解码）
│  ├─ Services/             # MusicService（每个接口一个方法）、LyricParser、LyricsCache
│  ├─ Auth/                 # AuthManager、Keychain、SessionStore
│  ├─ Player/               # PlayerManager、LyricSynchronizer、NowPlayingController
│  ├─ Library/              # LikeManager
│  └─ Utils/                # ImageLoader、平台辅助、格式化
└─ Features/                # Login、Recommend、Daily、Search、Recent、Home、
                            # Artist、Player、Settings、Sidebar、Components
```

## 免责声明

- 本项目为个人学习与技术交流项目，非网易云音乐官方产品，与网易云音乐无任何隶属或合作关系。
- 项目不提供、不分发任何音乐资源；歌曲、封面、歌词等内容均由用户自行配置的第三方 API 服务返回。
- 使用本项目需要你自己的网易云音乐账号，请遵守网易云音乐的用户协议；账号及使用风险由使用者自行承担。
- 本项目的默认后端仅为演示，推荐自行部署 NeteaseCloudMusicApiEnhanced 并通过 HTTPS 访问；第三方服务的可用性、安全性及数据处理不由本项目负责。
- 本项目仅供个人学习研究，不得用于商业用途或任何侵犯版权的行为。

## 致谢

- [NeteaseCloudMusicApiEnhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced) — 提供全部数据接口
- 界面与交互参考 Apple Music，仅借鉴设计思路，未使用其任何资源
