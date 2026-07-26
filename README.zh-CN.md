# VibeCompose

[English README](README.md)

**macOS 语音优先写作工具。** 一个快捷键，说你想说的，拿到可以直接发送的文字——由声明式 Skill 塑造，绝不在你的机器上运行代码。

VibeCompose 采用 MIT 许可证，原生、本地优先。按 `F5` 开始录音，再按停止。文字落入当前输入框——无法确认安全时则保留在剪贴板。

## 为什么选 VibeCompose

大多数语音工具止步于转写。VibeCompose 更进一步：**Skill Runtime** 把原始语音变成邮件、提交信息、缺陷报告、代码提示词或任意结构化格式——用的是纯文本指令，不是可执行脚本。

- **一键多形态** — 同一个 `F5` 工作流，无论你需要原始转写、润色回复还是结构化任务
- **声明式，不可执行** — Skill 是提示词文件，无法访问文件系统、运行 shell 命令或发起网络请求
- **感知上下文** — 选中文本、剪贴板、写作风格、术语自动参与 Skill 解析，无需手动配置
- **隐私为先** — 零遥测、本地历史、无账号系统、无远程 Skill 商店

## 当前状态

**macOS Alpha · v0.1.0** — 活跃开发中，尚未签名公开分发。

已经实现：

- 原生 AppKit + SwiftUI 菜单栏应用，支持简体中文和英文界面
- 可自定义全局快捷键（默认 `F5`），冲突检测与原子回滚
- 三种视觉反馈模式：状态条、边缘光晕、隐藏——支持减少动态效果、提高对比度和 VoiceOver
- 浏览器连接 ChatGPT，Keychain 保存会话
- 转写 → 术语对齐 → 可选 AI 润色流水线，Auto 模式跳过短听写以降低延迟
- **21 个经审查的内置 Skill**，覆盖转写、回复、邮件、开发、会议、产品、客服、翻译和上下文工作流
- 全局 Skill 切换器、Skill 资料库（已安装/发现/已创建）、可编辑预览、脱敏运行回执、安全撤销和 Creator/Test Bench
- 选中文本上下文：按 Skill 设定权限、敏感应用阻断、本地 Diff 预览、替换前目标校验
- 五个内置 Writing Style，支持自定义创建、按 Skill 分配和导出
- 分层术语：个人纠正 → Skill 私有词条 → 领域术语包（后端工程、医学、Kubernetes）
- `.vibecomposeskill` 包导入：文件校验、SHA-256 验证、多版本、回滚、Skill Inspector
- 保守粘贴：剪贴板兜底、重试仅复制、已验证插入
- 有限本地历史、失败音频恢复、隐私控制与性能基准
- 敏感应用排除与删除全部数据
- 脱敏支持诊断 ZIP 导出
- OpenAI-Compatible 转写作为高级恢复路径，Keychain API 密钥与连接测试
- 签名服务安全策略，用于托管转写和 AI 润色事故
- Sparkle 更新、锁定依赖许可证清单与 SHA-256 校验

## 产品边界

默认 ChatGPT 账户路径依赖未公开的上游行为，**不是**稳定公开 API、OpenAI 官方合作或企业 SLA。

当前 Alpha 已关闭所有原始 Managed Endpoint、Recovery 路径、认证刷新竞态和仅凭旧上下文自动粘贴问题。Sparkle 2.9.4 与签名 Provider Capability Policy 已集成。签名公开分发受 Developer ID 签名、公证、生产托管和最终验收测试约束。详见[安全基线](docs/audits/security-baseline-2026-07-13.md)。

## 系统要求

- macOS 13+
- 可用的 ChatGPT 账户（默认路径）
- 麦克风权限（录音）
- 辅助功能权限（自动粘贴；未授权时结果保留在剪贴板）

## 快速开始

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./scripts/package_app.sh
./scripts/install_app.sh
open -n /Applications/VibeCompose.app
```

本机没有有效 Apple 签名证书时：

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc 签名仅供本地验证，可能导致辅助功能设置中无法出现稳定的应用条目。

> **注意：** 权限和交互验收必须使用 `/Applications/VibeCompose.app`，不要把 `dist/VibeCompose.app` 当作真实运行路径。

### 无障碍结构预检

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/accessibility_acceptance.sh --install
```

覆盖九个设置页面、四个 Onboarding 步骤、History、Terminology 和 Quick Add，检查 SwiftUI 无障碍树和可操作控件名称。

### 交互验收

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/interaction_acceptance.sh --install settings account
./scripts/interaction_acceptance.sh --restore
```

## 本地数据

应用数据位于：

```text
~/Library/Application Support/VibeCompose/
```

### 隐私默认策略

| 数据 | 默认 |
| --- | --- |
| 转写历史 | 开启 · 30 天 / 最多 500 条 |
| 原始 ASR 文本 | 关闭 · 除非显式开启，只保存最终文本 |
| 成功录音 | 处理后删除 · 不进入 Recovery |
| 失败录音 | 开启重试 · 24 小时 / 最多 10 条 |
| 本地诊断 | 开启 · 14 天 / 最多 1,000 条 |
| 产品指标 | 默认关闭 · 开启后：30 天 / 最多 5,000 条 |
| 敏感应用 | 密码管理器与钥匙串不写历史或恢复音频 |
| Retry 文件 | 临时 · 有时限 · 重启时清理 |

诊断只包含耗时、字节数、服务标签和错误分类——不含音频、转写正文、剪贴板内容或 Token。本地文件使用仅当前用户可读写的权限。

### Keychain 存储

- ChatGPT 会话：`app.vibecompose.mac.ChatGPTSession`
- 恢复路径 API 密钥：`app.vibecompose.mac.OpenAICompatibleAPIKey`（不从 `OPENAI_API_KEY` 读取，不写入 `config.json`）

### 数据管理

- **设置 → 上下文与隐私 → 导出产品指标** — 不含单条时间戳的汇总 JSON
- **设置 → 高级 → 导出诊断** — 脱敏 ZIP，不含音频、转写、凭据和个人数据
- **设置 → 上下文与隐私 → 删除全部数据** — 清除一切并恢复到未登录默认状态

## 官网

营销站与 Skill 目录位于 [`website/`](website/)。面向 GitHub Pages 的 Next.js 静态导出，完整双语路由（`/zh-Hans`、`/en`）。

```bash
cd website
pnpm install
pnpm dev          # 本地预览
pnpm build        # 静态导出 → website/out
pnpm verify       # 构建 + 目录校验 + 文案契约
```

Skill 目录在构建时从 [`Sources/VibeCompose/Resources/BuiltInSkills`](Sources/VibeCompose/Resources/BuiltInSkills) 生成。没有远程 Skill 商店，没有账号系统。

## 仓库结构

```text
Sources/VibeCompose/          macOS 应用源码
Tests/VibeComposeTests/       单元与集成测试
scripts/                      构建、打包、安装、基准与验收工具
website/                      Next.js 营销站 + Skill 目录（静态导出）
examples/skills/              已审查的声明式 Community Skill 模板
packaging/homebrew/           Homebrew Cask 元数据
docs/product/                 PRD、Community Skills、品牌与产品计划
docs/audits/                  安全与逻辑审计
docs/research/                UI 和竞品研究
docs/engineering/             架构、发布和验收文档
docs/design/                  视觉规范
```

## 文档

- [文档索引](docs/README.md)
- [架构说明](docs/engineering/architecture.md)
- [Skill Runtime](docs/engineering/skill-runtime.md)
- [上下文与预览](docs/engineering/context-and-preview.md)
- [Community Skill SDK](docs/engineering/community-skill-sdk.md)
- [Registry 与 Action 边界](docs/engineering/registry-and-actions-boundary.md)
- [发布流程](docs/engineering/release.md)
- [安全审计](docs/audits/security-audit-2026-07-13.md)
- [安全基线](docs/audits/security-baseline-2026-07-13.md)
- [隐私政策](docs/legal/privacy-policy.zh-CN.md)
- [使用条款](docs/legal/terms-of-use.zh-CN.md)
- [支持政策](docs/support/support-policy.zh-CN.md)
- [安全问题报告](SECURITY.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。

PermissionFlow、Sparkle 及 Sparkle 内置组件继续适用各自许可证。锁定依赖元数据和许可证全文位于 [`Sources/VibeCompose/Resources/Legal`](Sources/VibeCompose/Resources/Legal)，也可通过 **设置 → 高级 → 查看第三方许可证** 查看。
