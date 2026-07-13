# OpenWhisper

[English README](README.md)

OpenWhisper 是一个采用 MIT 许可证的原生 macOS 按键语音输入工具。按下已配置的全局快捷键（默认 `F5`）开始录音，再按同一个快捷键停止；OpenWhisper 会把转写结果安全回填到当前可编辑位置，无法确认安全目标时则保留在剪贴板。

## 当前状态

OpenWhisper 目前处于 **macOS Alpha 产品化阶段**，工作版本为 `0.1.0`，尚未声明为可商业发布的生产版本。

当前代码已经具备：

- 原生 AppKit + SwiftUI 菜单栏应用
- 可自定义的全局开始/停止快捷键，默认 `F5`，支持冲突检测、原子切换和失败回滚
- Refined HUD、Blue Signal Frame 和 Hidden 三种视觉反馈模式，支持减少动态效果、提高对比度、VoiceOver 播报、菜单重试和可选完成通知
- 简体中文和英文界面
- 浏览器连接 ChatGPT，Keychain 保存本机会话
- 语音转写、术语对齐和可选 AI 润色；自动模式会跳过短且低复杂度的听写，避免不必要的等待
- 版本化声明式 Skill Runtime：支持直述、回复、邮件、后端任务提示词、代码提示词和翻译；应用规则只使用应用名称和精确 Bundle Identifier，录音开始时冻结本次技能解析，模型输出未通过本地校验时会在投递前安全回退
- 保守自动粘贴与剪贴板兜底
- Retry 结果默认只复制、要求用户手动粘贴
- 麦克风和辅助功能权限诊断
- 有限留存的本地历史、失败音频恢复、隐私控制和性能基准工具
- 敏感应用排除与“删除全部数据”
- 脱敏支持诊断 ZIP 导出
- 默认关闭、仅保存在本机的产品指标；只记录激活和听写结果的有限枚举及时间区间，不使用持久用户标识，也不会自动上传
- 面向托管转写和 AI 润色事故的签名服务安全策略
- 作为高级恢复路径的 OpenAI-Compatible 转写，包括原生端点/模型配置、Keychain API 密钥、付费 API 显式确认和合成静音连接测试
- 锁定的第三方依赖许可证清单、许可证 SHA-256 校验和 App 内许可证查看

## 产品边界

默认 ChatGPT 账户路径依赖未公开的上游行为，不应被描述为稳定公开 API、OpenAI 官方合作或企业 SLA。

当前 Alpha 已关闭原始审计中的 Managed Endpoint、Recovery 路径、认证刷新竞态和仅凭旧上下文自动粘贴问题。Sparkle 2.9.4 与签名 Provider Capability Policy 客户端已完成技术集成，但商业发布仍受 Developer ID 签名、公证、生产更新与能力策略托管/密钥、实机更新与事故演练、完整安装版 Onboarding/交互验收，以及永久商业运营主体和联系方式约束。详见[当前安全基线](docs/audits/security-baseline-2026-07-13.md)。

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

自动产品界面截图会进入隔离验收模式，仅使用默认配置、空的内存凭据以及空历史、Recovery 和术语数据，不读取或展示用户真实内容。

安装版无障碍结构预检：

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/accessibility_acceptance.sh --install
```

该命令覆盖七个设置页面、Onboarding 的全部四个步骤、History、Terminology 和 Quick Add，检查 SwiftUI 无障碍树是否非空以及可操作控件是否具备可读名称。它是键盘和 VoiceOver 真实交互验收的补充，不替代后者。

使用官方 Computer Use 做安装版交互验收时，可以启用不读取真实配置、凭据、History、Recovery 或术语的隔离模式：

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/interaction_acceptance.sh --install settings account
./scripts/interaction_acceptance.sh --restore
```

第一条命令会保持指定安装版界面打开，所有修改仅作用于非持久化展示数据；第二条命令结束临时验收进程并恢复正常菜单栏运行状态。

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
| 本地产品指标 | 默认关闭；开启后保留 30 天且最多 5,000 条枚举/区间事件 |
| 敏感应用 | 已知密码管理器、钥匙串和“密码”默认不写历史或恢复音频 |
| Retry 文件 | 临时且有有效期；重启时删除不可恢复的孤儿文件 |

诊断只包含耗时、字节数、服务类型、有限枚举的 AI 润色决策原因和错误分类，不包含音频、转写正文、剪贴板内容或 Token。在系统支持的范围内，本地数据文件使用仅当前用户可读写的权限。

可选产品指标默认关闭且只保存在当前 Mac。开启后只记录产品版本/构建、已完成的 Onboarding 步骤、服务类别、时长与延迟区间、结果类别和失败类别；不记录应用名称、路径、账户信息、正文或持久标识，也不会自动上传。开启后可通过 **设置 → 隐私 → 导出产品指标** 生成不含单条事件时间戳的汇总 JSON，由你自行检查并决定是否分享。

通过 **设置 → 高级 → 导出诊断**，可以创建一个由用户自行检查的本地 ZIP，其中包含脱敏运行状态、权限、延迟、可选产品指标和崩溃摘要；不包含音频、转写正文、剪贴板文本、账户邮箱、凭据、术语、自定义端点、原始崩溃报告、历史、Recovery 元数据或 `config.json`。

ChatGPT 会话保存在 Keychain 服务 `app.openwhisper.mac.ChatGPTSession` 中。可选的 OpenAI-Compatible 恢复路径 API 密钥独立保存在 `app.openwhisper.mac.OpenAICompatibleAPIKey`，不会再从 `OPENAI_API_KEY` 读取，也不会写入 `config.json`。通过 **设置 → 高级** 可以管理端点、模型和钥匙串凭据，执行真实连接测试，在确认可能产生 API 费用后启用恢复路径，并随时切回 ChatGPT 账户。恢复路径只改变听写 ASR；AI 润色仍使用 ChatGPT 登录授权。

通过 **设置 → 隐私 → 删除全部数据**，可以删除设置、术语、转写历史、失败录音、诊断、产品指标、Retry 文件、已保存的 ChatGPT 会话和恢复路径 API 密钥，并恢复为退出登录后的默认状态。

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
- [Skill Runtime](docs/engineering/skill-runtime.md)
- [发布流程](docs/engineering/release.md)
- [更新器选型](docs/engineering/updater.md)
- [隐私政策](docs/legal/privacy-policy.zh-CN.md)
- [使用条款](docs/legal/terms-of-use.zh-CN.md)
- [退款政策](docs/legal/refund-policy.zh-CN.md)
- [支持政策](docs/support/support-policy.zh-CN.md)
- [安全问题报告](SECURITY.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。分发软件副本或其重要部分时，必须保留现有版权声明和许可声明。

PermissionFlow、Sparkle 及 Sparkle 内置第三方组件继续适用各自许可证。精确锁定的依赖元数据和许可证全文位于
[`Sources/OpenWhisper/Resources/Legal`](Sources/OpenWhisper/Resources/Legal)，
也可通过 **设置 → 高级 → 查看第三方许可证** 阅读。构建、打包、安装包检查和商业发布门禁会在
`Package.resolved`、许可证哈希、notices 或 App 内资源不一致时直接失败。
