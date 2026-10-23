# Pulse Codex Reset

`Pulse Codex Reset` is a personal customization fork of
[`qunqin24/Pulse`](https://github.com/qunqin24/Pulse). Pulse remains the
upstream project; this repository carries a small set of features used by the
fork maintainer and is not an official Pulse distribution.

`Pulse Codex Reset` 是 [`qunqin24/Pulse`](https://github.com/qunqin24/Pulse)
的个人定制 fork。Pulse 仍是上游项目；本仓库只维护少量个人需要的功能，不是
Pulse 官方发行版。

## Baseline and languages / 基线与语言

Updated against official stable **v1.12.3** (`acd02a3712fe3a157bd03bc984154e449cfc1ae4`).
The reset interface follows Pulse's language selection: **English, 简体中文,
繁體中文, 日本語, 한국어, Русский**, or the system setting.

重置界面支持官方全部六种语言，沿用设置中的语言选择。简体中文优先显示 AIhot 中文译文；
其余语言显示英文原文并标注来源，不引入翻译服务。原文缺失时明确标注中文译文。
所有语言均保留 AIhot 与原帖（X）两个链接：中文版将 AIhot 放在前面，其他语言将原帖放在前面。
没有原帖时仅显示 AIhot。链接顺序依据界面语言，不检测所在地。

## Download / 下载

[Download Pulse Codex Reset](https://github.com/guanbear/Pulse-codex-reset/releases/latest)

Latest fork release: **1.12.3**. Download `Pulse-Codex-Reset-1.12.3.zip`, extract
`Pulse.app`, quit the installed copy and move the new app to Applications.
The bundle is universal (Apple Silicon and Intel), ad-hoc signed and not notarized.

最新个人版为 **1.12.3**。从上面的发布页下载压缩包，解压后退出旧版，将新的
`Pulse.app` 放入 Applications。安装包支持 Apple Silicon 和 Intel，采用 ad-hoc
签名，尚未做 Apple 公证。默认不检查上游自动更新。

## Build / 构建

Use this repository's **Pulse Codex Reset build** workflow with the desired branch.
It checks localization, builds and tests on macOS 26, then uploads a fork-safe
`Pulse-codex-reset-<run id>` artifact for 30 days. The bundle disables upstream
Sparkle updates by default. Local builds require full Xcode for SwiftUI preview macros;
Command Line Tools alone are insufficient. See [build instructions](Docs/build-from-source.md).

## Differences from upstream / 与上游的差异

- **Optional Codex reset-news indicator.** An orange dot marks a public
  forecast; a green dot marks a public confirmation. Hovering Codex keeps
  provider-reported usage and the public report inside one pointed detail card.
- **Fork-safe updates.** Release bundles do not poll the upstream Sparkle feed,
  because installing an upstream update would silently remove these changes.
  Fork releases reuse the verified universal bundle from this repository's CI workflow.

- **可选 Codex 重置消息。** 有当前公开重置卡消息时，Codex 百分比旁显示圆点：
  预告为橙色、确认为绿色；悬停后，用量和重置消息合并在同一张有明确指向的详情卡中。
- **适合 fork 的更新边界。** 发行包不轮询上游 Sparkle 更新源，避免安装官方更新后
  静默丢失定制功能。个人发行版使用本仓库 CI 已验证的通用安装包。

## Screenshots / 实机截图

### Codex usage and reset report / Codex 用量与重置消息

![Codex reset report merged into one usage card](Docs/pulse-codex-reset.png)

## Data boundary / 数据边界

The reset report is third-party public information, not an OpenAI entitlement
or a guaranteed reset time. It is displayed as a separate news section and
never replaces the provider-reported Codex quota. The feature is optional and
can be disabled in Settings.

重置消息来自第三方公开信息，不是 OpenAI 官方额度，也不保证实际重置时间。它始终以
独立新闻区域展示，不替换 Codex 自己报告的额度；该功能可以在设置中关闭。

## Upstream relationship / 上游关系

Bug fixes and generally useful provider support should continue to be proposed
upstream. Fork-only product choices stay here. The Apache-2.0 license and
upstream attribution are preserved.

通用 bug 修复与 provider 支持仍优先回馈上游；仅属于个人产品取舍的功能留在本 fork。
本仓库保留 Apache-2.0 许可证和完整上游署名。
