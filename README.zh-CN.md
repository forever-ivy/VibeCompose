# OpenWhisper

[English README](README.md)

OpenWhisper 是一个采用 MIT 许可证的原生 macOS 按键语音输入工具。按 `F5` 开始录音，再按一次 `F5` 停止；OpenWhisper 会把转写结果安全回填到当前可编辑位置，无法确认安全目标时则保留在剪贴板。

## 当前状态

OpenWhisper 目前处于 **macOS Alpha 产品化阶段**，工作版本为 `0.1.0`，尚未声明为可商业发布的生产版本。

当前代码已经具备：

- 原生 AppKit + SwiftUI 菜单栏应用
- 全局 `F5` 开始/停止工作流
- 简体中文和英文界面
- 浏览器连接 ChatGPT，Keychain 保存本机会话
- 语音转写、术语对齐和可选 AI 润色
- 保守自动粘贴与剪贴板兜底
- Retry 结果默认只复制、要求用户手动粘贴
- 麦克风和辅助功能权限诊断
- 有限留存的本地历史、失败音频恢复、隐私控制和性能基准工具
- 敏感应用排除与“删除全部数据”
- 脱敏支持诊断 ZIP 导出
- 作为高级恢复路径的 OpenAI-Compatible 转写

## 产品边界

默认 ChatGPT 账户路径依赖未公开的上游行为，不应被描述为稳定公开 API、OpenAI 官方合作或企业 SLA。

当前 Alpha 已关闭原始审计中的 Managed Endpoint、Recovery 路径、认证刷新竞态和仅凭旧上下文自动粘贴问题。Sparkle 2.9.4 已完成技术集成，但商业发布仍受 Developer ID 签名、公证、生产更新托管/密钥和实机更新证明、完整安装版 Onboarding/交互验收，以及永久商业运营主体和联系方式约束。详见[当前安全基线](docs/audits/security-baseline-2026-07-13.md)。

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
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc 签名只适合本地验证，可能导致 macOS 辅助功能设置中无法出现稳定、可切换的应用条目。

不要把 `dist/OpenWhisper.app` 当作真实运行路径。权限和交互验收必须使用 `/Applications/OpenWhisper.app`。

## 本地数据

OpenWhisper 的本地应用数据位于：

```text
~/Library/Application Support/OpenWhisper/
```

当前默认隐私策略：

| 数据 | 默认策略 |
| --- | --- |
| 转写历史 | 开启；保留 30 天且最多 500 条 |
| 原始 ASR 文本 | 关闭；除非用户显式开启，否则只保存最终文本 |
| 成功录音 | 处理后删除，不进入 Recovery |
| 失败录音 | 开启 Retry；保留 24 小时且最多 10 条 |
| 本地诊断 | 开启；保留 14 天且最多 1,000 条 |
| 敏感应用 | 已知密码管理器、钥匙串和“密码”默认不写历史或恢复音频 |
| Retry 文件 | 临时且有有效期；重启时删除不可恢复的孤儿文件 |

诊断只包含耗时、字节数、服务类型和错误分类，不包含音频、转写正文、剪贴板内容或 Token。在系统支持的范围内，本地数据文件使用仅当前用户可读写的权限。

通过 **设置 → 高级 → 导出诊断**，可以创建一个由用户自行检查的本地 ZIP，其中包含脱敏运行状态、权限、延迟和崩溃摘要；不包含音频、转写正文、剪贴板文本、账户邮箱、凭据、术语、自定义端点、原始崩溃报告、历史、Recovery 元数据或 `config.json`。

ChatGPT 会话保存在 Keychain 服务 `app.openwhisper.mac.ChatGPTSession` 中。通过 **设置 → 隐私 → 删除全部数据**，可以删除设置、术语、转写历史、失败录音、诊断、Retry 文件和已保存的 ChatGPT 会话，并恢复为退出登录后的默认状态。

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
- [当前安全基线](docs/audits/security-baseline-2026-07-13.md)
- [UI 对标调研](docs/research/ui-open-source-comparison-2026-07-12.md)
- [架构说明](docs/engineering/architecture.md)
- [发布流程](docs/engineering/release.md)
- [更新器选型](docs/engineering/updater.md)
- [隐私政策](docs/legal/privacy-policy.zh-CN.md)
- [使用条款](docs/legal/terms-of-use.zh-CN.md)
- [退款政策](docs/legal/refund-policy.zh-CN.md)
- [支持政策](docs/support/support-policy.zh-CN.md)
- [安全问题报告](SECURITY.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。分发软件副本或其重要部分时，必须保留现有版权声明和许可声明。
