# VibeCompose 公开生态与营收路线执行计划

> 日期：2026-07-26
> 状态：执行基线（已按 2026-07-26 代码库实测审计修订）
> 范围：改名收尾、BYOK 默认化、干净公开仓库、Public Alpha 0.2.0、公开社区运营、官方签名 Registry、托管服务营收路线
> 非范围：本文档属内部产品资料，**不进入公开源码快照**
> 相关文档：[品牌身份](brand-identity.md)、[品牌 clearance](brand-clearance-2026-07-14.md)、[Community Skills 核心计划](community-skills-core-next-step-plan-2026-07-15.md)、[官网规划](website-nextjs-plan-2026-07-24.md)、[Community Skill 贡献指南](../engineering/community-skill-contribution-guide.md)、[Registry 与 Actions 边界](../engineering/registry-and-actions-boundary.md)

---

## 0. 执行结论

最终战略采用：

> MIT 开源客户端 + 开放 Agent Skills 标准 + GitHub 社区目录 + 官方签名 Registry + 私有托管服务。

**不做私有 Pilot。** 验证路径改为：

> 公开 Alpha → 公开社区贡献 → 签名 Registry → 公开 Beta → 托管服务收费。

公开 Alpha 是公开测试版：可以快速迭代、修改格式和功能，但必须签名、公证、安全且可正常安装。

现在最合理的路线不是马上收费，也不是马上开启远程 Registry，而是：先完成 BYOK 公共客户端，建立干净开源仓库，以签名 Public Alpha 和 GitHub Skill 社区获得用户；随后启用可信 Registry；最后通过托管推理、同步和团队服务实现营收。

---

## 1. 与前版草案的事实修正（2026-07-26 实测）

本版计划基于对仓库的实际构建、测试和逐文件核查，修正前版草案中的以下陈述：

| 前版陈述 | 实测结果 | 对计划的影响 |
| --- | --- | --- |
| 内置 Skill 有 23 个 | `Sources/VibeCompose/Resources/BuiltInSkills/` 实际为 **21 个**；README 中英文版的"23"是错的 | 阶段一修正 README；首发展示名单按真实 slug 重排 |
| 首发展示含 "GitHub Issue" 与 "Backend Prompt" | 两者都不存在；backend-prompt 已改名为 `code-prompt`（见 `LocalizationTests` 中 "Code Prompt" 断言） | 首发名单改用真实存在的 10 个技能 |
| Swift 测试仅剩一个中文句号断言失败 | 失败点在 `Tests/VibeComposeTests/LocalizationTests.swift:80` 附近的中文全角句号断言（如"技能规则已保存。"） | 阶段一修复；同文件还断言禁止付费文案键存在，改动时不得破坏 |
| 网站"内容检查失败" | 具体失败为 `website/scripts/check-site-content.mjs:110` 要求中文页包含「不承诺无限用量」诚实性文案，当前中文文案缺失 | 阶段一补齐中文文案；同时注意该脚本硬编码了「0.1.0 Alpha」「ChatGPT」「不是稳定公开 API」等断言，阶段二（BYOK 默认化）和阶段四（0.2.0）必须同步改写脚本本身 |
| 本地 `.build` 残留旧路径 | 旧路径残留来自改名前的构建缓存；另外 `.claude/worktrees/` 下仍有一份改名前的完整旧仓副本 | 阶段一删除旧构建缓存与旧仓副本，全新路径重建 |
| — | `verify_repository_hygiene.py` 维护禁用字符串清单（旧产品名、收费相关标记），并校验本地 Markdown 链接 | 所有新文档（含本文档）必须通过该脚本；启动收费服务时需正式修订该清单而非绕过 |
| — | `AGENTS.md` 现有护栏仍写"保持 ChatGPT 私有后端为显式默认故事、OpenAI-Compatible 仅作高级恢复路径" | 与新战略相反；阶段二必须同步修订 AGENTS.md 护栏 |

其余审计结论（仓库为 Private、改名未形成干净提交、BYOK 底座已存在、Registry 底座已存在但未接 Discover、发布流程被 Private Pilot 证据锁住、Onboarding 含 Codex 官网素材、仅 arm64 发布物、Created 页面对普通用户隐藏）与前版一致，直接并入下文各阶段。

---

## 2. 仓库结构与治理

### 2.1 当前仓库保留为私有开发仓库

将当前 GitHub 仓库改名为 **`VibeCompose-dev`**，保持 Private。它保留：

- 完整改名历史；
- 内部设计和研究文档（含本文档）；
- `.agents/`、`.claude/`、`.codex/`；
- 开发工作流和实验功能；
- ChatGPT Managed Auth 实验代码；
- 发布证据、事故处理和 Registry 运维资料。

### 2.2 新建干净的公开仓库

重新创建 **`forever-ivy/VibeCompose`**（或建 GitHub Organization 后放在 org 下，见 §17 决策点），从当前项目导出一次**经过清理的源码快照**，不直接将现有仓库切换为 Public。

理由：GitHub 明确说明仓库公开后代码、Actions 历史和日志都可能公开，直接切换可见性风险高。参见 [GitHub 仓库可见性说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)。

公开仓建立后即成为**唯一真源**（source of truth）：日常开发、发布 CI 与签名 secrets 全部迁往公开仓；`VibeCompose-dev` 转为历史存档与内部资料仓。注意：fork 发起的 PR 默认拿不到 Actions secrets，Skill 贡献 CI 不使用 `pull_request_target` 提权。

### 2.3 ChatGPT Managed Auth 实验处置（建议：退役）

建议在公开前将浏览器登录态方案整体退役：它依赖非公开的 `chatgpt.com/backend-api/*` 端点，不是稳定公开 API，公开分发存在服务条款与可用性双重风险。退役后代码只存档于 `VibeCompose-dev`，不再维护。若产品所有者决定保留为私有实验，也仅限私有仓，公开版本一律不含（见 §6 边界）。

### 2.4 商业服务仓库以后再建

等公开生态有数据后，再创建私有仓库 **`VibeCompose-Cloud`**，用于：官方托管推理、用户账户、订阅与额度、配置同步、团队和私有 Registry、企业管理、计费与风控后台。现阶段不需要一次建立三个复杂仓库。

---

## 3. 公开仓库保留与移除边界

### 3.1 公开保留

- App 源码（`Sources/VibeCompose/`）；
- Swift 测试（`Tests/VibeComposeTests/`）；
- 21 个内置 Skill；
- Skill Runtime、Creator、Validator；
- Community Skill SDK；
- 网站源码（`website/`）；
- 构建、签名、公证和发布脚本；
- GitHub Actions 工作流；
- Sparkle 更新能力；
- `Package.swift`、`Package.resolved`；
- README、架构、安全、隐私、贡献文档；
- 标准 Skill 示例；
- 第三方许可证清单。

### 3.2 从公开快照移除

- `.agents/`、`.claude/`、`.codex/`；
- worktree、本地设置（`settings.local.json`）和临时文件；
- Private Pilot 文档、模板、汇总脚本和证据；
- 内部产品研究、未批准方案和运维资料（含 `docs/product/` 下的内部计划，本文档在内）；
- ChatGPT 登录态、浏览器授权和未公开 Backend API 路径相关源码；
- Registry 私钥、签名环境和事故运维资料；
- Codex 官网图片、视频及其他来源不清的素材；
- 未解决的内部安全报告原文。

以上内容**不必从私有开发仓库删除**，只需不进入公开快照。

### 3.3 不应删除

不要因为"开发附加内容"而删除：测试、CI、打包脚本、签名与公证、Sparkle、安全校验、第三方许可证。这些恰恰是开源项目可信度的来源。

---

## 4. 许可证、品牌与商标

### 4.1 客户端许可证

继续使用现有 **MIT License**。MIT 有利于传播，但允许他人修改、分发甚至出售代码（[OSI MIT License](https://opensource.org/license/mit)）。因此真正需要控制的是：

- VibeCompose 商标、Logo、域名；
- GitHub Organization；
- 官方签名证书；
- 官方 Registry；
- 官方网站和发行渠道。

品牌应通过**商标**而非"品牌版权"保护（[WIPO 商标说明](https://www.wipo.int/en/web/trademarks/)）。

### 4.2 品牌检索前移（硬性门禁）

`release/brand-clearance.json` 当前状态为 **blocked**：商标、域名、App Store、GitHub、社交账号五项检查未完成。要求：

- **阶段一启动检索**（外部流程周期长，必须最早启动）；
- **阶段三结束前必须 approved**，否则不建公开仓——公开后再改名的代价不可接受。

### 4.3 公开前新增治理文件

`TRADEMARKS.md`、`CODE_OF_CONDUCT.md`、`GOVERNANCE.md`、`SECURITY.md`（公开版）、`CODEOWNERS`、DCO、`SKILL_REGISTRY_TERMS.md`。

### 4.4 社区贡献规则

现阶段采用 **DCO**（[Developer Certificate of Origin 1.1](https://developercertificate.org/)），不要求作者转让版权：

- Skill 作者保留版权；
- 每个 Skill 必须声明许可证；
- 作者通过 PR 模板勾选 + CI 校验，授权官方仓库和 Registry 展示、分发、缓存和下架；
- 官方有权拒绝恶意、侵权、误导或不可维护的 Skill；
- 不宣称"社区所有 Skill 都属于 VibeCompose"。

官方 Registry 初期只接受明确开放许可证：**MIT、Apache-2.0、CC0-1.0、CC-BY-4.0**。暂不接受无许可证、NC、ND 或 All Rights Reserved 内容。

---

## 5. 阶段一：整理私有开发基线（3–5 天）

### 任务

1. 将改名后的所有源码、测试和网站纳入版本控制，形成一个完整的 VibeCompose 改名提交（当前 172 删除 / 94 修改 / 12 未跟踪必须收敛为干净历史）。
2. 删除旧 `.build` 与 `.claude/worktrees/` 下改名前的旧仓副本，从全新路径重新构建；把 worktrees 与 `settings.local.json` 加入忽略清单。
3. 修复两个已确认失败：
   - `Tests/VibeComposeTests/LocalizationTests.swift:80` 附近的中文全角句号断言；
   - `website` 中文文案补齐「不承诺无限用量」，使 `website/scripts/check-site-content.mjs` 通过。
4. 修正 README 中英文版的内置 Skill 数量（23 → 21）。
5. 全仓检查旧名称，只保留必要的数据迁移标识（迁移逻辑集中在 `LegacyProductIdentity.swift`）。
6. 为所有图片、视频、声音和 Logo 建立 `ASSET_PROVENANCE.md`。
7. 替换来源于 Codex 官网的素材：
   - `Sources/VibeCompose/Resources/OnboardingCodexWallpaper.png`
   - `Sources/VibeCompose/Resources/OnboardingCodexWallpaper.mp4`
8. 启动品牌五项检索（§4.2），本阶段只要求"进行中"。

### 退出条件

- `git status` 干净，新目录不再是未跟踪状态；
- 全新构建目录可以编译；
- Swift 测试全部通过；
- 网站 `npm run verify` 全部通过；
- 没有来源不明的公开素材；
- 品牌检索已启动。

---

## 6. 阶段二：把 BYOK 变成公开默认路径（2–3 周）

BYOK 并非从零开始：OpenAI-Compatible 转写、润色、独立 Keychain API Key、自定义 Endpoint/Model、连接测试都已存在，只是默认路径仍是 ChatGPT 登录态。因此这一阶段是**重新组织**，不是重写 Provider。但要按"真重构"而非"删几个文件"来估算：Auth 管理器被 Onboarding、Preferences、AppDelegate 等多处具体类型绑定，需要先抽协议再拆分。

### 6.1 配置默认值（`Sources/VibeCompose/AppConfig.swift`）

- 默认转写 Provider 改为 `.openAICompatible`（含解码回退与未知值回退路径）；
- 默认润色改为 OpenAI-Compatible 开启、ChatGPT Auth 关闭（含两者同时开启时的冲突偏好反转）；
- 删除"润色仍使用 ChatGPT Auth"等过时注释与文案；
- 新增"转写和润色使用同一个 API Key"的简化选项（当前两个 Keychain service 完全独立）；
- 高级用户仍可分别配置两个服务。

### 6.2 代码拆分

- 从 `ChatGPTTranscriber.swift` 抽出中立的 OpenAI-Compatible 转写实现；`TextPolisher.swift` 同理；
- 将网络安全基建（安全 HTTP 客户端、用户自有 URL 校验）从 `ManagedEndpointPolicy.swift` 中拆出为中立文件，Managed 白名单留在私有仓；
- 将 Auth 管理器的具体类型依赖改为协议注入，使公开版可整体不链接以下文件：
  `BrowserAuthBridge.swift`、`ChatGPTAuthManager.swift`、`ChatGPTSessionStore.swift`、`ChatGPTAccountModelCatalog.swift`、`ManagedEndpointPolicy.swift`。

公开源码和二进制中不得出现：

```text
chatgpt.com/backend-api/transcribe
chatgpt.com/backend-api/codex/responses
chatgpt.com/backend-api/codex/models
```

发布门禁增加对产物二进制的字符串扫描（`strings` 检查上述端点）。

### 6.3 Onboarding

用户首次启动只需要：选择 Provider 预设或自定义端点 → 输入 API Key → 测试连接 → 授予麦克风权限 → 完成第一次听写。移除"连接 ChatGPT"步骤。

### 6.4 配套一致性修改

- 同步更新相关测试（Onboarding、Config、Policy 等约 15 个测试文件受影响）；
- 修订 `AGENTS.md` 中两条与新战略相反的护栏（ChatGPT 默认故事 → BYOK 默认故事）；
- 改写 `website/scripts/check-site-content.mjs` 中「ChatGPT 边界」等硬编码断言；
- README、网站、隐私政策、条款和中文翻译全部一致。

### 退出条件

- 用户不登录 ChatGPT 也能完成全部主流程；
- API Key 只进入 Keychain；Provider 错误不泄露 Key；
- 转写和 Skill 润色都能使用公开 API；
- 公开构建产物通过端点字符串扫描；
- 文档、网站、政策与中文翻译一致。

---

## 7. 阶段三：创建干净公开仓库（约 1 周）

### 7.1 公开目录结构

```text
VibeCompose/
├── Sources/
├── Tests/
├── community-skills/
├── examples/
├── website/
├── docs/
├── packaging/
├── scripts/
├── .github/
├── LICENSE
├── TRADEMARKS.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── GOVERNANCE.md
└── SECURITY.md
```

### 7.2 Community Skill 格式

正式格式采用项目已确定的 Agent Skills 标准目录：

```text
community-skills/<publisher>/<skill-name>/
├── SKILL.md
├── vibecompose.yaml
├── references/
├── assets/
└── tests/
```

`.vibecomposeskill` 只作旧格式兼容，不再作为社区主要格式。现有示例 `examples/skills/IssueDraft.vibecomposeskill/` 移入 legacy 示例，并新增一个标准目录示例；SDK 文档同步改写为以标准目录为主。

### 7.3 贡献流程

1. 作者 Fork 仓库；
2. 从模板创建 Skill；
3. 本地运行 Validator；
4. 提交 PR（DCO 签署 + 分发授权勾选）；
5. CI 检查格式、许可证、危险内容、路径、Golden Tests；
6. Reviewer 审核；
7. 合并后自动进入网站目录；
8. CI 生成标准 ZIP 安装包。

当前网站只提供原始 SKILL.md 下载，只能阅读、不代表完整安装包。网站必须同时提供：**View Source、Download Skill ZIP、Copy Install Link**。

### 退出条件

- 品牌 clearance = approved（§4.2 硬性门禁）；
- 公开仓可独立构建、测试全绿；
- 治理文件齐备；
- 至少一个标准格式 Skill 示例 + 模板 + Validator 可用。

---

## 8. 阶段四：发布 Public Alpha 0.2.0（约 1 周）

首个公开版本：

```text
App version: 0.2.0
Git tag:     v0.2.0
Release:     GitHub Prerelease
Channel:     Sparkle alpha feed
```

不复用当前标记为 Private Alpha 的 0.1.0。当前没有已发出的 Pilot 存量用户，因此没有迁移包袱。

### 8.1 发布门禁改造

修改 `.github/workflows/release.yml`、`scripts/verify_release_readiness.py`、`scripts/release_signed.sh`，把门禁分成三层：

**Candidate**：测试全绿、干净提交、Developer ID 签名、Apple 公证、Hardened Runtime、ZIP/DMG 哈希、安装版验收。

**Public Alpha**：品牌清查通过；素材来源通过；只有公开 API Provider（含二进制字符串扫描）；隐私政策和条款已公开；支持、安全和隐私联系方式有效；无 P0/P1 Blocker；Git tag 与构建源码一致；明确标注 Apple Silicon；使用独立 Alpha Sparkle Feed。

**Stable**：以后再要求公开 Beta 的留存、崩溃和稳定性数据。

删除 Public Alpha 对 Private Pilot 材料（COMMUNITY_PILOT_SUMMARY、BETA_METRICS、参与者证据）的依赖；同步清理政策文档中的 private-alpha 标记。

### 8.2 Sparkle Alpha Feed 落地

appcast 生成器已支持渠道参数，但 App 与 CI 尚未接通：需要在发布 CI 中设置 alpha 渠道变量并在 App 中注入独立的 alpha feed URL（如 `appcast-alpha.xml`），保证 alpha 用户不会被推到未来的 stable feed。

### 8.3 架构标注

第一版只支持 Apple Silicon 可以接受，但必须明确写 **"macOS 13+ · Apple Silicon only"**，网站与 README 同步，不让 Intel 用户误装。

### 8.4 网站下载页

从"查看 GitHub"改为：Download DMG、Download ZIP、SHA-256、Release Notes、Build from Source。网站版本号从 `version.env` 或 release manifest 自动生成，删除手工同步（`check-site-content.mjs` 中「0.1.0 Alpha」硬编码断言同步改为读取版本源）。

---

## 9. 阶段五：公开社区增长（Alpha 后 4–6 周）

这一步**替代 Private Pilot**，验证数据全部来自公开渠道。

### 9.1 首发内容

直接使用现有 21 个内置 Skill，首页核心展示以下 10 个（全部为真实存在的 slug）：

`email`、`reply`、`meeting-action-items`、`bug-report`、`commit-message`、`product-brief`、`translate`、`better-question`、`customer-support-reply`、`incident-report`

### 9.2 开放 Creator 入口

当前 `Sources/VibeCompose/SkillLibraryWindowController.swift` 把 Created 区隐藏在普通导航之外。公开 Alpha 前至少增加：

- Create Skill 按钮（把 Created 区加回普通用户可见导航）；
- Fork This Skill；
- Export ZIP；
- Submit to Community；
- 提交 PR 指南链接。

不一定恢复完整第三 Tab，但普通用户必须能明显找到创建入口。

### 9.3 社区运营

GitHub Discussions、Skill Request Issue 模板、Skill Submission PR 模板、每周 Featured Skill、Good First Skill 标签、每月 Skill Challenge、作者主页和下载次数、发布者署名、中英文贡献指南、安全举报和下架流程。

### 9.4 本阶段不启用远程 Registry

采用：**网站发现 → 下载 ZIP → App 本地审查 → 安装**。先公开社区，不立即承担远程供应链风险。

---

## 10. 阶段六：启用官方签名 Registry（4–6 周，不依赖私有 Pilot）

Registry 核心已存在于 `Sources/VibeCompose/SkillEcosystemRuntime.swift`：Ed25519 签名验证、HTTPS、Archive SHA-256、缓存、版本与兼容性检查、撤销字段、本地安装复用。但当前**没有任何 UI 调用它**，也没有服务端签名工具链。上线前必须补齐：

1. Index 增加单调递增 revision；
2. 增加 expiresAt 和状态新鲜度检查；
3. 拒绝旧 Index 回放；
4. 实现 Registry 根密钥轮换（启用 keyID 机制）；
5. 校验 HTTP Redirect 最终地址；
6. 设置明确超时（复用 §6.2 拆出的安全 HTTP 客户端）；
7. 下载过程中执行大小限制，而不是下载完成后才检查；
8. 保存 Last Known Good Index；
9. 离线时显示缓存目录；
10. Registry 撤销后检查已安装的 Skill；
11. 支持隔离、回滚和重新启用；
12. 建立举报、下架、申诉和事故处理流程；
13. 接入 Discover UI；
14. 官方 Index URL 和公钥随 App 发布；
15. 从零建设 Index 签名工具链（生成、签名、发布流水线），签名私钥只存在于受保护环境，不进入源码仓库。

### Registry 启用条件（公开社区数据，非私有 Pilot）

- 10 个非内置 Community Skill；
- 5 名以上外部作者；
- 所有 Skill 都有许可证、示例和测试；
- 连续四周有人维护 PR 和安全报告；
- 无未解决 P0/P1；
- 完成一次密钥轮换演练；
- 完成一次恶意 Skill 下架和撤销演练。

---

## 11. 指标和数据策略

### 11.1 统一现有承诺文案

当前项目承诺"零自动遥测、Product Metrics 默认关闭、无持久用户标识、只支持本地聚合导出"，但 README 与网站存在"Zero telemetry"式绝对化表述，与"本地可选指标"并存。统一为：**默认零收集、绝不自动上传、本地可选指标需手动导出**。Public Alpha 阶段继续保持。

### 11.2 Alpha 阶段收集（全部公开渠道）

GitHub Release 下载量、Stars/Forks、Issues/Discussions、Skill PR 数量、外部作者数量、Skill ZIP 下载量、用户主动提交的匿名指标报告、用户访谈和公开评价。

### 11.3 Beta 前再决定遥测

必须承认：**没有任何稳定匿名标识，就无法准确计算跨周留存。** 因此二选一：

1. 继续零遥测，只使用用户主动上传的本地聚合；
2. Beta 增加**明确选择加入**的匿名安装标识用于留存分析：默认关闭、独立同意界面、不采集音频/文字/应用名/路径/API Key、有删除和退出入口、明确数据保留期、更新隐私政策和测试。

不能在不更新承诺的情况下偷偷上传现有 Product Metrics。

### 11.4 推荐核心指标

Provider 配置完成率、首次听写成功率、首次成功所需时间、非 Direct Skill 使用占比、每用户安装 Skill 数、Skill 安装后首次使用率、Creator 首次导出成功率、外部作者和发布 Skill 数、W1/W4 留存、Provider 错误率、P0/P1 事故数。

---

## 12. 托管服务与营收落地

建议在公开生态运行约 3 个月后启动。

### 12.1 第一项收费能力：托管推理

解决用户必须自己配置 API Key 的问题：注册登录、无需 API Key、官方模型路由、月度额度、使用量展示、成本上限、超额保护、多设备配置同步。

**开源 BYOK 路径继续完整可用**，不把现有核心功能变成付费功能。

### 12.2 第二项：团队服务

私有 Skill Registry、团队术语、团队 Writing Styles、Skill Allowlist、发布审批、管理员控制、审计、私有模型端点、SSO。

### 12.3 暂时不做

- 付费 Skill Marketplace；
- 客户端付费授权与激活机制；
- Skill 数量付费墙；
- 在公开客户端埋藏休眠付费开关；
- 一开始就向社区作者抽成。

### 12.4 正式解除现有约束，而非绕过

当前测试与卫生脚本明确禁止订阅入口和授权管理相关实现。收费服务启动时，应正式修改：

- `Tests/VibeComposeTests/PolicyDocumentationTests.swift`
- `Tests/VibeComposeTests/SettingsProductizationTests.swift`
- `scripts/verify_repository_hygiene.py` 的禁用标记清单

并同步更新隐私政策与条款，而不是提前偷偷绕过这些约束。

---

## 13. 融资准备

达到以下状态时再正式融资：

- 品牌清查和商标申请完成；
- 域名、GitHub、社交账号和签名身份归属清楚；
- 公司成立后，创始人代码、Logo、域名和 Registry 权利完成 IP 转让；
- 公共客户端可独立 BYOK 使用；
- 有签名 Public Alpha；
- 有官方 Community Skill 目录和外部作者；
- 有真实安装和留存数据；
- 有 10 个以上可引用的用户案例；
- 托管推理成本模型明确（单用户月成本与预计毛利）；
- 有明确的 Team 需求或付费意向。

投资叙事：

> VibeCompose 不是另一个语音转文字 App，而是一个开源的 AI 输入客户端和开放 Skill 标准。我们控制官方品牌、签名发行、可信 Registry 和托管服务，社区持续创造可复用的输入工作流。

---

## 14. 推荐时间表

| 时间 | 目标 |
| --- | --- |
| 第 1 周 | 完成改名提交、修复测试、替换素材、启动品牌检索 |
| 第 2–3 周 | BYOK 默认化，移除公开版 ChatGPT Managed 路径 |
| 第 3–4 周 | 建立干净公开仓库和治理文件（品牌 clearance 须 approved） |
| 第 4–5 周 | 发布签名、公证的 0.2.0 Public Alpha |
| 第 6–10 周 | 运营 GitHub Skill 社区，开放 Creator 和标准 ZIP |
| 第 10–16 周 | Registry 加固、签名发布和 Discover 接入 |
| 第 3–4 月 | Public Beta、选择加入的数据体系 |
| 第 4–6 月 | 私有 Cloud、托管推理和付费候补名单 |
| 第 6 月后 | 团队版、营收验证和融资 |

---

## 15. 立即执行的优先顺序

1. 不直接公开当前仓库。
2. 完成并提交整个 VibeCompose 改名（含删除旧仓副本与旧构建缓存）。
3. 修复 Swift 中文句号断言和网站「不承诺无限用量」两个现有失败；修正 README 的 Skill 数量。
4. 替换 Codex 图片和视频，建立素材来源清单。
5. 启动品牌五项检索。
6. 将 OpenAI-Compatible 设为默认路径（按 §6 重构清单执行）。
7. 从公开版移除 ChatGPT Backend API（源码 + 二进制字符串扫描双保险）。
8. 创建干净公开仓库（品牌 clearance approved 后）。
9. 添加商标、治理、DCO 和 Registry 条款文件。
10. 建立 `community-skills/` 标准目录与模板。
11. 生成完整 Skill ZIP，而不是只下载 SKILL.md。
12. 改造发布门禁为三层制，取消 Private Pilot 依赖，接通 Sparkle alpha feed。
13. 发布签名、公证的 0.2.0 Public Alpha（明确标注 Apple Silicon）。
14. 运营公开社区，开放 Creator 入口。
15. Registry 安全门禁（§10 十五项 + 启用条件）通过后再开启远程安装；有公开生态数据后启动托管服务。

---

## 16. 待产品所有者确认的决策点

| 决策 | 建议 | 备选 |
| --- | --- | --- |
| ChatGPT Managed Auth 实验 | 退役并存档于私有仓（§2.3） | 私有仓内继续维护，公开版不含 |
| 公开仓归属 | 公开前新建 GitHub Organization | 先放个人账号，后迁移（迁移有跳转但 star/fork 保留） |
| 发布架构 | 第一版仅 Apple Silicon，明确标注 | 补 Intel 构建出 universal binary |
| 旧落地页 `docs/index.html` | 退役，统一到 `website/` | 保留为 GitHub Pages 兜底 |
| Beta 遥测 | 零遥测 + 用户主动上传（§11.3 方案一） | 选择加入的匿名安装标识（方案二） |
