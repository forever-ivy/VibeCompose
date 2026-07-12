# OpenWhisper

[English README](README.md)

OpenWhisper 是一个开源、原生的 macOS 按键语音输入工具。按 `F5` 开始录音，再按一次 `F5` 停止；OpenWhisper 会把转写结果安全回填到当前可编辑位置，无法确认安全目标时则保留在剪贴板。

## 当前状态

OpenWhisper 目前处于 **macOS Alpha 产品化阶段**，工作版本为 `0.1.0`，尚未声明为可商业发布的生产版本。

当前代码已经具备：

- 原生 AppKit + SwiftUI 菜单栏应用
- 全局 `F5` 开始/停止工作流
- 简体中文和英文界面
- 浏览器连接 ChatGPT，Keychain 保存本机会话
- 语音转写、术语对齐和可选 AI 润色
- 保守自动粘贴与剪贴板兜底
- 麦克风和辅助功能权限诊断
- 本地历史、失败恢复和性能基准工具
- 作为高级恢复路径的 OpenAI-Compatible 转写

## 产品边界

默认 ChatGPT 账户路径依赖未公开的上游行为，不应被描述为稳定公开 API、OpenAI 官方合作或企业 SLA。商业发布前必须完成产品化计划中的安全、隐私、发布完整性和上游连续性门禁。

## 系统要求

- macOS 13 或更高版本
- 默认路径需要可用的 ChatGPT 账户
- 录音需要麦克风权限
- 自动回填需要辅助功能权限；未授权时结果仍会保留在剪贴板

## 构建、安装与运行

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./scripts/package_app.sh
./scripts/install_app.sh
open -n /Applications/OpenWhisper.app
```

本机没有有效 Apple 签名证书时，可仅为调试显式使用 ad-hoc 签名：

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc 签名只适合本地验证，可能导致 macOS 辅助功能设置中无法出现稳定、可切换的应用条目。

不要把 `dist/OpenWhisper.app` 当作真实运行路径。权限和交互验收必须使用 `/Applications/OpenWhisper.app`。

## 本地数据

OpenWhisper 的应用数据位于：

```text
~/Library/Application Support/OpenWhisper/
```

ChatGPT 会话存储在 OpenWhisper 对应的 Keychain 服务中。商业发布前还必须补齐明确的数据留存、全部删除和 Token 目标白名单能力。

## 仓库结构

```text
Sources/OpenWhisper/          macOS 应用源码
Tests/OpenWhisperTests/       单元与集成测试
scripts/                      构建、打包、安装、基准和验收工具
packaging/homebrew/           Homebrew Cask 元数据
docs/product/                 PRD、商业化、品牌与产品化计划
docs/audits/                  安全与逻辑审计
docs/research/                UI 和竞品研究
docs/engineering/             架构、发布和验收文档
docs/design/                  视觉规范
```

## 核心文档

- [文档索引](docs/README.md)
- [macOS 产品化改造计划](docs/product/macos-productization-plan-2026-07-13.md)
- [产品与商业化分析](docs/product/product-and-commercialization-plan-2026-07-13.md)
- [安全审计](docs/audits/security-audit-2026-07-13.md)
- [UI 对标调研](docs/research/ui-open-source-comparison-2026-07-12.md)
- [架构说明](docs/engineering/architecture.md)
- [发布流程](docs/engineering/release.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。分发软件副本或其重要部分时，必须保留现有版权声明和许可声明。
