# JetBrains Mono Font Dependency

最近核对日期：2026-08-19

## 选定依赖与来源

- 依赖：JetBrains Mono `v2.304`。
- 上游：JetBrains 官方开源仓库 `JetBrains/JetBrainsMono` 的 `v2.304` release。
- 官方发布包：`JetBrainsMono-2.304.zip`。
- 官方发布包 SHA-256：`6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf`。
- 许可证：SIL Open Font License 1.1；仓库保留官方原文 `Fonts/JetBrainsMono-OFL.txt`。
- 用途：iPhone、Mac 与 Live Activity 的拉丁字母、数字和技术文本主字体。

本仓库只分发当前源码实际使用的四个官方静态 TTF，不修改、子集化、重命名或重新生成字体：

| 文件 | PostScript 名称 | SHA-256 |
| --- | --- | --- |
| `Fonts/JetBrainsMono-Regular.ttf` | `JetBrainsMono-Regular` | `a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f` |
| `Fonts/JetBrainsMono-Medium.ttf` | `JetBrainsMono-Medium` | `31c92d01a8a08528b718a43addf0ad3df0af2ca4b7b3290a452f70f358e14d3d` |
| `Fonts/JetBrainsMono-SemiBold.ttf` | `JetBrainsMono-SemiBold` | `1b3bfa1ed5665a4ce3f9feb68d2d4e40e70bf8b4b7d9a3edd418f321b4e166a0` |
| `Fonts/JetBrainsMono-Bold.ttf` | `JetBrainsMono-Bold` | `5590990c82e097397517f275f430af4546e1c45cff408bde4255dad142479dcb` |

官方字体页面与仓库说明该字体可按 OFL-1.1 免费用于商业和非商业应用。字体元数据中的 manufacturer/vendor 为 JetBrains，版本为 `2.304`，安装权限为 installable。

## 平台接线

只使用 Apple 官方字体扩展点：

- Xcode 将根目录 `Fonts/` 作为 folder resource 同时复制到 `Rokurics`、`RokuricsMac` 和 `RokuricsLiveActivities` target，保持 bundle 内 `Fonts/` 相对目录。
- iPhone 与 Live Activity 的 Info.plist 使用 `UIAppFonts`，逐项声明四个相对 TTF 路径。
- Mac 的 `RokuricsMac/Info.plist` 使用 `ATSApplicationFontsPath = Fonts/`。
- SwiftUI 使用 `Font.custom` 和字体的 PostScript 名称。`JetBrainsMonoFont` 只做四档 weight 到 PostScript 名称的最薄映射，并在 app/extension 初始化时通过 `UIFont` 或 `NSFont` 校验四个名称均已注册。

没有新增字体 provider、adapter、替代字体、下载器、缓存、运行时网络请求或第一方字形实现。

## 中文与公式边界

JetBrains Mono `v2.304` 不提供 CJK 汉字字形。混排文本以 JetBrains Mono 为拉丁主字体，汉字继续进入 Apple 系统 fallback cascade；当前 macOS Core Text 实测 `ABC中文` 的两个 glyph run 分别为 `JetBrainsMono-Regular` 与 `PingFangSC-Regular`。因此中文仍由苹方承担，不嵌入、复制或替代苹方系统字体。

LaTeX 公式不进入 JetBrains Mono 替换。Markdown/聊天排版只识别现有公式边界 `$...$`、`$$...$$`、`\\(...\\)`、`\\[...\\]`，并为这些 span 保留变更前的系统/serif 公式字体。聊天进入 CommonMark 前只把反斜线 delimiter 做双写保护，避免 `AttributedString(markdown:)` 消耗 `\\(`/`\\[`；解析后的可见文本仍恢复为原 delimiter。`RokuricsLaTeXFontBoundary` 不解析、不排版也不渲染 LaTeX，不构成第二个公式 renderer。

SF Symbols 继续使用 SwiftUI 系统 symbol font；图标的 `.font(.system(...))` 只控制 symbol 尺寸/字重，不是英文文本字体。

## Fail-closed 行为

`RokuricsApp`、`RokuricsMacApp` 与 `RokuricsLiveActivitiesBundle` 启动时都调用 `JetBrainsMonoFont.ensureAvailable()`。任一必需 PostScript 名称不可用时立即产生明确 fatal diagnostic，并停止对应 app/extension；不得静默改用 system serif、SF Mono、Menlo、另一版本 JetBrains Mono 或任意替代字体。

## 验证合同

字体变更至少验证：

1. iOS、Mac Debug/Release 构建以及 Live Activity extension 编译成功。
2. 三个 bundle 都包含 `Fonts/` 下四个 TTF 与 OFL 文本。
3. iOS app 与 extension 的 `UIAppFonts`、Mac 的 `ATSApplicationFontsPath` 与实际 bundle 路径一致。
4. 产物 TTF SHA-256 与本文件锁定值一致。
5. 四个 PostScript 名称可被平台字体 API 解析。
6. 混排 glyph run 仍把中文解析为 PingFang。
7. 应用文本字体不再使用旧 system serif/default/monospaced 路径；剩余 `.font(.system(...))` 只能用于 SF Symbols 或明确的 LaTeX 保留路径。
