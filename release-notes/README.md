# Release Notes

每个版本的发布说明保存在 `<版本号>.md`，包含中英文内容；新增版本时保留历史文件，并在此索引顶部添加链接。

版本号统一在 [`Version.xcconfig`](../Version.xcconfig) 中维护，应用与测试 target 的 Debug / Release 配置共用该文件，构建时自动写入各自的 Info.plist：

- `MARKETING_VERSION`：对外版本号。
- `CURRENT_PROJECT_VERSION`：构建号，每次发布递增。

版本记录：

- [2.2.0](2.2.0.md) — 2026-11-13 · Build 6
- [2.1.2](2.1.2.md) — 2026-11-12 · Build 5
