# VibeWhisper Community Skills 核心化下一步计划

> 日期：2026-07-15  
> 状态：Phase 0–3 工程实现完成；Phase 4 内容、研究手册和执行工具包就绪，招募尚未开始，Community Pilot 与 Registry Go/No-Go 待真实用户证据  
> 产品范围：macOS 原生 VibeWhisper、Community Skills、Context、Preview、History 与安全输出  
> 商业化范围：明确排除；Phase 0 删除现有商业化设计与实现，不保留隐藏付费门禁  
> 当前基线：`0.1.0 Alpha`  
> 公共创作格式：Agent Skills 标准目录；Legacy `.vibewhisperskill` v1 仅保持兼容  
> 相关边界：[AI-native 输入层完整方案](ai-native-input-layer-plan-2026-07-14.md)、[Community Skill SDK](../engineering/community-skill-sdk.md)、[Registry 与 Actions 边界](../engineering/registry-and-actions-boundary.md)

## 实施收口（更新于 2026-07-16）

本计划中可在仓库和安装版内独立交付的 Phase 0–3 已完成：去商业化、Required
Context 权威门禁、冻结的 `ResolvedSkillRun`、Skill 选择与运行可见性、独立
Skill Library、可编辑 Preview、History Receipt，以及 Creator V2/Test Bench
的本地创作闭环均已落地，并由 `swift test`、`scripts/check.sh`、打包、安装版
视觉验收、TextEdit/Terminal 粘贴矩阵和 packaged-app smoke check 覆盖。

本轮收口把以下原本容易停留在“界面占位”的能力接到了真实运行链路：

- Skill Switcher 提供默认关闭、可配置的独立全局快捷键；与听写快捷键冲突时拒绝保存并回滚旧值，不改变默认 `F5` 同键开始/停止。
- Creator、Discover 与安装审查中的 Test Run 通过 App 持有的 Provider 执行，结果进入同一 Editable Preview 与 Validator；支持不持久化的文字样例和使用后删除音频的临时语音样例。
- 内置 Skill 在普通界面只展示双语任务摘要与使用场景，不泄露内部 Prompt、原始枚举或实现字段。
- 安装和升级审查展示人类可读差异；Context 扩权必须重新授权，升级失败不覆盖当前活动版本，并至少保留一个旧版本用于回滚。
- Safe Undo 只在同一 AX 目标的完整文本仍等于已验证插入结果时恢复原快照；允许单纯移动光标，任何正文变化都拒绝自动修改。仅当原操作替换了非空选区时，失败才复制原文作为手动恢复路径；结果同步写入 History 与菜单栏状态。

仍然刻意保持为后续决策的内容：30–50 人 Community Pilot 的真实用户研究、
Collections 是否进入普通导航，以及远程 Registry 的 Go/No-Go。它们不能用
代码或占位指标伪造完成；在证据到位前，Discover 只展示内置精选 Skills，远程
Registry 继续隐藏/禁用。

## 严格复核（更新于 2026-07-18）

本次复核没有把文档顶部的完成声明当作证据，而是重新对照 Backlog、测试和安装版
表面。复核补齐了此前仍有偏差的部分：

- 普通 Settings 从八个入口收敛为 General、Input & Output、Context & Privacy、
  Appearance & Feedback、Advanced 五个权威页面；旧 deep link 仅作迁移兼容；
- 普通 Context Settings 不再展示当前 Runtime 不可用的高级 Adapter；这些声明只在
  Skill 兼容性报告和高级检查中可见；
- Terminology 的完整编辑只保留独立窗口，Settings 只显示 Pack、摘要与入口；
- Default Skill 摘要进入 General，App Defaults 迁入 Skill Library Installed；
- `ContextDecision` 与 `SkillRunReceipt` 记录脱敏的逐来源决策、资源身份、Validator、
  输出路由、目标验证和最终动作，不保存 Context 或 Skill 正文；
- Next Run 只在匹配的录音真正启动后消费，阻断和录音启动失败不会丢失选择；
- Switcher 对 100 个本地 Skills 的折叠搜索、Required/Optional Context 的
  denied/unavailable/empty/超预算组合，以及 History Receipt 持久化均有回归测试；
- 随 App 可发现的精选任务从 8 个增至 13 个，并增加 Bug Report、Commit Message、
  Meeting Action Items、Product Brief、Customer Support Reply；
- Phase 4 使用[Community Pilot 手册](community-pilot-runbook-2026-07-17.md)和
  [Community Skill 贡献指南](../engineering/community-skill-contribution-guide.md)，
  采用本地证据与人工研究，不预先启用远程遥测或 Registry。
- Phase 4 现已补齐[Community Pilot 启动工具包](community-pilot-launch-kit-2026-07-18.md)、
  15 个稳定任务、双语招募/同意文案、三份仅含枚举和分桶值的 CSV 模板，以及
  `scripts/summarize_community_pilot.py`。汇总脚本拒绝未知字段、正文、未同意记录、
  不一致的投递结果和软链接输入，输出不包含 cohort code 或逐行证据；自动门槛通过后
  仍只进入产品所有者人工复核，不能自动作出 Registry 决策。
- 非 UI 发布门禁现可读取上述无逐行数据汇总，并要求四周研究、全部自动退出门槛、
  产品所有者人工复核和零 P0/P1 blocker 后才允许公开发布流程继续；它同时拒绝模板、
  软链接、过期或哈希不匹配的证据。该门禁只防止误发布，不会把 CS-013 自动改成
  `in progress` 或 `complete`，也不会授权 CS-014/CS-015。

截至该复核，CS-000–CS-012 的仓库实现可进入完整门禁；CS-013 仅完成内容和研究
执行准备，尚未获得产品所有者启动批准或任何参与者证据，也未开始 30–50 人、
至少四周的真实 Pilot。CS-014/CS-015 继续等待 Pilot 证据，不能标记完成。

## 0. 执行结论

VibeWhisper 的下一阶段不应继续横向增加设置项，也不应把 Community Skills 留在
“AI Polish 的高级选项”里。Community Skills 应成为用户理解 VibeWhisper 的主要方式：

> **说一次，选择一个可信 Skill，直接得到适合当前任务、可审查、可修改、可安全投递的结果。**

Community Skills 解决的实际痛点不是“再提供一些 Prompt”，而是减少以下重复劳动：

- 每次重新解释“请整理成什么格式、什么语气”；
- 在语音输入、聊天窗口、Prompt 模板和文本编辑器之间反复切换；
- 手工修正固定术语、标题、结构和输出格式；
- 不知道当前运行了哪个模式、为什么用了它、是否读取了选区；
- AI 输出不理想时只能复制出去修改，无法在安全投递前完成最后校对；
- 社区作者能做出 Skill，却无法让普通用户轻松发现、测试、安装和复用。

下一阶段只围绕一个完整闭环建设：

```text
发现 / 创建
→ 看懂用途与边界
→ 安装前测试
→ 快速选择
→ 运行时明确可见
→ 编辑预览
→ 安全应用
→ History 追溯
→ 更新 / 回滚 / Fork
```

本计划确定以下不可变更决策：

1. Community Skills 是产品核心，不是设置页里的高级附属功能。
2. 保留“同一个快捷键开始、同一个快捷键停止”的单触发模型，新配置与重置后仍默认 `F5`。
3. Skill 切换不得要求用户先进入 Settings，也不得为每个 Skill 注册一套全局快捷键。
4. 运行前、运行中和运行后都必须能回答“正在使用哪个 Skill、为什么使用它”。
5. Preview 必须可以直接编辑，Validator 回退必须明确告知，不能静默替换结果。
6. Required Context 不满足时必须真正阻止该 Skill；Optional Context 缺失时才允许明确降级运行。
7. Agent Skills 标准是唯一公共创作格式；Legacy 包只兼容，不继续扩展第二套标准。
8. Skill 始终是声明式内容，不能执行 Shell、脚本、MCP、自定义网络或任意外部 Action。
9. 公共远程 Registry 不是当前前提；先用本地导入、内置精选内容和小规模 Community Pilot 证明价值。
10. 当前阶段完全不考虑商业化：删除定价、订阅、Pro 门禁、许可证激活、购买/退款、增长转化和商业发布设计。

## 1. 本计划的权威范围

本计划不是重写既有安全架构，而是为下一阶段确定产品优先级和用户闭环：

- 本文覆盖 Community Skills 的产品定位、信息架构、用户流程、实现顺序和验收门槛。
- [AI-native 输入层完整方案](ai-native-input-layer-plan-2026-07-14.md)中的 Skill Engine、Agent Skills、Context Fabric 和安全输出架构继续有效；与本文冲突的 Settings 信息架构、Registry 时序和商业发布内容由本文取代。
- [Community Skill SDK](../engineering/community-skill-sdk.md)继续定义 Legacy v1 的兼容与安全边界，但不再代表普通用户的主要创作体验。
- [Registry 与 Actions 边界](../engineering/registry-and-actions-boundary.md)只作为未来威胁模型和安全研究参考，不构成当前阶段启用远程 Registry 或 Actions 的承诺。
- 旧商业化计划、商业模块边界、付费层级和许可证设计不再是需求来源，进入 Phase 0 删除清单。

## 2. 当前基线与产品审计结论

### 2.1 已经有价值的底座

现有实现并非从零开始。以下能力已经具有明确实用价值，应被保留并围绕 Skills 重新组织：

| 能力 | 当前价值 | 下一步角色 |
| --- | --- | --- |
| `F5` 单触发录音 | 学习成本低，形成肌肉记忆 | 保持不变，Skill 切换不能破坏它 |
| 安全粘贴与复制回退 | 避免内容进入错误位置 | 所有 Community Skill 共用的不可绕过边界 |
| Retry 与 History | 降低网络、模型和投递失败成本 | 升级为可追溯的 Skill Run Receipt |
| Terminology | 解决专有名词反复修正 | 作为统一资源决策进入 Skill 执行计划 |
| Context 选区冻结与复验 | 支持真实改写任务并避免错替换 | Required/Optional Context 的第一条完整链路 |
| 本地声明式 Skill Loader | 有明确的不可执行安全边界 | Community 生态的可信底座 |
| Inspector、Golden tests、版本回滚 | 作者和高级用户可审查 | 移入 Advanced Inspector，不干扰普通安装流程 |
| Agent Skills Loader 与 Creator | 具备可移植创作方向 | 升级为普通用户可用的 Creator V2/Test Bench |

### 2.2 当前最影响用户价值的问题

| 优先级 | 问题 | 用户后果 | 本计划决策 |
| --- | --- | --- | --- |
| P0 | 使用当下不能快速选择 Skill | 用户仍会退回 Settings 或长期只用一个默认模式 | 建立全局 Skill Switcher，支持一次性、当前 App 和全局默认 |
| P0 | HUD 不显示当前 Skill 和解析原因 | 用户无法预判输出，也无法判断“选错模式” | HUD、菜单和 History 统一显示 Skill 身份与来源 |
| P0 | `ContextPolicy.blocksExecution` 不是端到端权威门禁 | Required Context 缺失时仍可能继续运行，声明与真实行为不一致 | 在 Provider 调用前统一阻断，并提供可理解的恢复动作 |
| P0 | Preview 不能直接编辑 | 用户必须取消、复制到别处修改或接受不满意结果 | 建立 Editable Preview、细粒度 Diff、Apply/Copy/Cancel/Undo |
| P0 | Validator 失败回退可能缺少足够提示 | 用户以为拿到的是 Skill 输出，实际可能是 ASR 回退 | 明确状态、原因和下一步，不允许静默回退 |
| P1 | Community Skills 被塞进 AI Polish Settings 长页面 | 功能看起来像实验参数，不像产品核心 | 建立独立 Skill Library 与 Skill Detail |
| P1 | 安装界面优先展示 SHA-256、安装 ID、测试细节 | 普通用户难以判断“它对我有什么用” | 普通层展示用途、示例、Context、输出和风险；技术细节进 Inspector |
| P1 | Creator 偏向文件格式编辑器 | 非技术用户难以从需求和示例创建 Skill | Creator V2 分为简单模式与高级模式，并增加 Test Bench |
| P1 | History 缺少完整运行解释 | 很难复盘错误 Skill、Context 缺失或 Validator 回退 | 保存脱敏的 Skill Run Receipt 与重试语义 |
| P2 | Collections、Registry、Provider Safety、Updater 等高阶项过早可见 | Settings 认知负担大，尚未解决核心路径 | 未配置或未达到启用条件时不在普通 UI 展示 |
| P2 | 商业化模块已进入 UI、运行时和发布流程 | 分散产品目标，并人为限制核心能力 | Phase 0 全面删除，不保留 dormant paywall |

### 2.3 为什么 Community Skills 值得成为核心

这个方向具有创新性，但创新不来自“可以导入 Prompt”。真正的组合优势是：

1. **语音直接表达意图**：用户不需要先打开聊天窗口再描述转换要求。
2. **可移植标准**：同一个 Agent Skill 目录可以被不同 Host 理解，VibeWhisper 不制造孤岛格式。
3. **受限且可审查的运行时**：社区内容只能声明指令、资源、Context Request、Validator 和输出契约，不能获得任意代码权限。
4. **与真实编辑目标绑定**：Skill 输出经过目标冻结、Diff Preview、再次复验和安全投递，而不是停在聊天答案。
5. **作者—使用者闭环**：用户可以从实际需求创建、测试、Fork、分享，再由其他用户安装和改进。

只有当普通用户可以在几秒内选择、理解、运行和修正 Skill 时，这些架构优势才会转化为产品优势。因此下一阶段优先完成消费闭环，而不是优先扩张 Registry 或插件权限。

## 3. 核心用户与 Jobs-to-be-Done

### 3.1 首批目标用户

| 用户 | 高频任务 | Community Skill 的具体价值 |
| --- | --- | --- |
| 开发者与 Agent 用户 | 把口述变成 Codex 任务、Bug Report、Commit、技术说明 | 固定结构、保留技术字面量、减少重复 Prompt |
| 高频沟通知识工作者 | 邮件、团队聊天、会议行动项、客户回复 | 快速切换语气和格式，直接编辑并投递 |
| 专业术语用户 | 医疗、法律、产品、工程领域听写 | 术语、模板和高风险 Preview 被一起封装 |
| 社区作者 | 把个人模板和工作流分享给他人 | 用示例驱动创建、测试、导出、Fork 和升级 |

首个 Beta 不以“所有 macOS 用户”为目标。优先招募每天有重复文本产出、愿意尝试至少两个非 Direct Skills、能够反馈错误输出原因的用户。

### 3.2 核心 Jobs

1. 当我准备口述时，我希望在不离开当前 App 的情况下确认或更换 Skill，避免生成错误类型的内容。
2. 当我经常在某个 App 做同类工作时，我希望把一个 Skill 设为该 App 默认，但仍能临时覆盖一次。
3. 当 Community Skill 请求选区或个人风格时，我希望先知道它要什么、缺少时会怎样，并能拒绝。
4. 当 AI 结果基本正确但有少量问题时，我希望直接在 Preview 中修改并安全替换，而不是重走整个流程。
5. 当结果异常时，我希望知道是选错 Skill、Context 缺失、Validator 失败、目标变化还是粘贴失败。
6. 当我有一个重复工作流时，我希望用用途和输入/输出示例创建 Skill，而不是先学习 YAML。
7. 当别人分享 Skill 时，我希望在安装前测试和理解风险，安装后可以禁用、回滚或卸载。

## 4. 产品原则与明确非目标

### 4.1 产品原则

1. **用途优先于实现**：先回答“这个 Skill 帮我完成什么”，再展示格式、哈希和安装身份。
2. **选择必须可见**：Skill 解析不能成为隐藏状态；当前 Skill 在录音前后均可确认。
3. **一次性覆盖优先**：临时任务不应污染长期默认设置。
4. **Context 最小化**：只读取当前 Skill 明确请求且用户允许的来源。
5. **Required 不能假装 Optional**：必需来源缺失必须阻断或由用户明确换用其他 Skill。
6. **输出先可控再自动化**：高风险、选区改写和校验异常优先 Preview；Skill 不能绕过 Output Router。
7. **失败必须可解释**：任何回退都提供用户可理解的原因和恢复动作。
8. **开放格式、受限运行**：接受标准内容，但只执行 VibeWhisper 的声明式兼容子集。
9. **渐进披露**：普通用户不必理解 SHA-256、Golden tests、Host Profile 和 Registry 签名。
10. **本地与隐私优先**：默认不上传音频、转写、选区、Prompt、Skill 正文或应用身份用于指标。

### 4.2 下一阶段非目标

- 不设计价格、订阅、Pro 版、试用、购买、退款、付费升级或商业转化漏斗。
- 不启用任意外部 Action、Shell、脚本、MCP、自定义网络或文件系统访问。
- 不让 Skill 直接操作 GitHub、Linear、Notion、Slack 或其他第三方服务。
- 不为每个 Skill 提供独立全局快捷键；避免快捷键冲突和不可发现性。
- 不默认持续读取屏幕、完整文档、浏览器 DOM、终端历史或剪贴板。
- 不把 Collections 做成 Prompt/权限合并容器。
- 不在用户价值尚未验证前开放公共远程 Registry。
- 不通过新增 Settings 开关代替核心流程设计。

## 5. Phase 0：彻底删除商业化设计

### 5.1 决策

“暂时不商业化”在本计划中不是隐藏付费功能，也不是保留一套默认关闭的许可证系统，而是：

- 所有本地功能对用户完整可用，不按 Community/Pro 或许可证状态分级；
- 不显示 Edition、License、Activation、Upgrade、Pricing、Trial 或 Refund 入口；
- 不维护许可证收据、设备 ID、版本权益和付费功能枚举；
- 不以收入、转化、付费留存为产品指标；
- 如果未来重新讨论商业化，必须另立新提案，从用户价值和项目状态重新论证，不能直接复活当前遗留实现。

“Community”一词此后只表示 Community Skills 生态，不再表示免费版或产品 Edition。

### 5.2 删除与保留边界

| 范围 | 删除 | 保留 |
| --- | --- | --- |
| 产品设计 | 定价、打包层级、Community/Pro 功能表、付费升级、增长转化、商业发布门槛 | Community Skills 用户价值、产品可用性、Beta 学习目标 |
| App UI | License/Activation/Pro Preview、受许可证限制的控件和付费文案 | About、版本信息、隐私入口、第三方许可证查看 |
| 运行时 | 商业许可证管理器、收据校验、设备许可证 ID、Edition 与 Feature Gate | 普通配置迁移、Skill 权限、安全策略、更新检查 |
| 工程/发布 | 商业发布脚本、商业运营主体配置、许可证公钥和 Pro Preview 门禁 | Developer ID 签名、公证、Hardened Runtime、Gatekeeper、可回滚安装 |
| 更新 | 与付费版本权益绑定的更新规则 | 安全、明确、可验证的应用更新机制；未配置时隐藏 UI |
| 法律 | 购买、退款、订阅、付费许可证条款 | 隐私、安全报告、使用条款和必要的开源合规 |
| 开源许可证 | 不删除 | 仓库 `LICENSE`、依赖许可证、Skill 包 `license` 元数据和第三方 Notices |
| 内容传播 | 价格页、销售漏斗、商业增长工作区 | 非商业的使用文档、Community Pilot 招募与贡献指南 |

### 5.3 已知清理清单

执行 Phase 0 时先用全仓扫描形成最终清单；以下是当前已确认的删除或改写入口。

纯商业文件在依赖解除后删除：

- `docs/product/product-and-commercialization-plan-2026-07-13.md`
- `docs/product/commercial-module-boundary.md`
- `docs/engineering/licensing.md`
- `docs/legal/refund-policy.md` 与 `docs/legal/refund-policy.zh-CN.md`
- 仅服务于定价与增长的 `docs/marketing/` 内容
- `Sources/VibeWhisper/CommercialLicensing.swift`
- `Sources/VibeWhisperLicensing/`
- `Sources/VibeWhisperLicenseTool/`
- `Tests/VibeWhisperLicensingTests/`
- `scripts/release_commercial.sh`
- `release/commercial-operator.example.json`

混合文件不整份删除，而是移除商业段落、字段和依赖：

- `Package.swift` 中的 Licensing library、tool、test target 与相关依赖；
- `AppDelegate`、`AppCoordinator`、`PreferencesWindowController` 中的 License Manager 注入、Feature Gate 和 License UI；
- 本地化资源中的 Pro、License、Activation、购买和续费文案；
- `release/production.env.example`、发布 gate、归档/恢复脚本中的许可证字段和商业阶段命名；
- `docs/README.md`、架构、产品化计划、PRD、发布文档、隐私政策和使用条款中的定价、商业运营主体、收据和付费版本描述；
- `docs/product/brand-clearance-2026-07-14.md` 中的商业发布措辞；名称冲突事实如果仍影响公开分发则保留；
- 相关测试中对 `OWLicensePublicEDKey`、`OWProPreviewEnabled`、Pro 功能门禁和商业发布模板的断言。

`SoftwareUpdater`、Sparkle、签名、公证、Gatekeeper 和第三方依赖许可证不是商业化本身，不能在清理中误删。若它们尚未配置，则普通 UI 隐藏；安全发布能力继续作为工程质量基础设施。

### 5.4 Phase 0 完成门槛

- App 内不存在 Community/Pro Edition、License、Activation、Upgrade 或付费功能门禁。
- 所有 Skills、Terminology、History、Retry、Preview 与 Creator 能力不再读取许可证状态。
- `Package.swift` 不再构建商业许可证模块和许可证签发工具。
- 仓库不再包含纯商业规划、退款政策、商业发布脚本和商业运营主体模板。
- 中英文产品文档不再描述价格、订阅、付费许可证、转化目标或“商业可发布”。
- 全仓关键词扫描通过；`license` 的剩余命中必须属于开源合规、第三方 Notices 或 Agent Skill 标准元数据，并有允许清单。
- `scripts/check.sh`、打包、安装和安装版核心流程全部通过，证明清理没有破坏免费完整功能。

## 6. 目标用户旅程

### 6.1 第一次使用 Community Skill

```text
菜单栏 → Skill Library
→ Discover / Import
→ 查看用途、示例、Context、输出与风险
→ 用样例 Test Run
→ 安装
→ 设为“下一次使用”
→ 回到目标 App，F5 开始 / F5 停止
→ HUD 显示 Skill
→ 编辑 Preview
→ Apply 或 Copy
→ History 中可追溯
```

目标：普通用户无需理解 YAML、哈希或 Registry，即可在 5 分钟内完成首个非 Direct Skill 结果。

### 6.2 日常快速切换

```text
当前 App
→ 打开 Skill Switcher
→ Favorites / Recent / 搜索
→ 选择“仅下一次”
→ HUD 立即显示待运行 Skill
→ F5 单触发录音
```

目标：从唤起 Switcher 到确认 Skill 的中位时间不超过 3 秒，不增加录音快捷键步骤。

### 6.3 创建与分享

```text
Skill Library → Created → New / Fork
→ 填写用途与示例
→ Test Bench 输入文字或录音样例
→ 模拟授权 Context
→ 查看编译计划、输出和 Validator
→ 修正
→ 安装到本机
→ 导出标准 Agent Skill 目录 / ZIP
```

目标：第一次创建简单 Skill 的用户无需手写 YAML，并能在 15 分钟内完成可运行测试。

## 7. Skill Switcher：把选择放回使用当下

### 7.1 入口

首版提供两个入口：

1. 菜单栏的 `Current Skill` 行，点击后直接展开 Switcher。
2. 一个可选、可配置的“打开 Skill Switcher”快捷键，仅负责打开选择器，不开始录音。

不提供每个 Skill 独立快捷键。默认 `F5` 继续只负责开始/停止，避免破坏单触发心智模型。

### 7.2 信息结构

Switcher 默认只展示高频信息：

```text
Search Skills…

Current
  Backend Task · Current app default

Favorites
  Direct
  Team Reply
  Codex Task

Recent
  Bug Report
  Translate

Installed
  …
```

每行包含：

- 人类可读名称和一句用途；
- 官方、Community、Local Created 或 Imported 来源；
- 必需选区、高风险 Preview、当前不可运行等必要状态；
- 收藏按钮；
- 通过二级动作选择持久范围。

SHA-256、安装身份、完整版本、Golden tests 和文件结构不在 Switcher 中出现。

### 7.3 三种选择语义

| 动作 | 行为 | 生命周期 |
| --- | --- | --- |
| `Use Next Time` | 仅覆盖下一次成功开始的录音 | 使用一次、显式清除或 App 重启后失效 |
| `Default for This App` | 按精确 Bundle Identifier 设默认 | 持久化，用户可在 Switcher 或 Library 清除 |
| `Set as Global Default` | 无临时覆盖和 App Rule 时使用 | 持久化 |

解析顺序固定为：

```text
一次性 Next Run override
→ 当前 App Rule
→ Global Default
→ Direct 安全回退
```

Skill 在录音真正开始时冻结安装身份、版本、解析原因、Context Request、资源、输出策略和风险。录音期间切换 App 或修改设置不得改变本次执行。

如果一次性 Skill 因 Required Context 缺失而未能开始，override 不应被静默消耗；用户可以补齐 Context、换 Skill 或明确取消。

### 7.4 运行可见性

| 表面 | 必须显示 |
| --- | --- |
| 菜单栏 | 当前待运行 Skill、解析原因、是否有 Next Run override |
| Refined HUD Ready/Recording | Skill 名称；Required Context 异常时显示阻断状态 |
| Refined HUD Processing | Skill 名称和 `Processing`，不能只显示泛化 AI 状态 |
| AI Activity Glow | 保持克制视觉；通过紧凑辅助标签或菜单栏/VoiceOver 暴露 Skill 名称 |
| Hidden | 不显示 HUD，但菜单栏状态、可选声音与 VoiceOver 语义一致 |
| Preview | Skill 名称、来源、Context 使用摘要、Validator 状态 |
| History | 冻结的 Skill 名称、安装身份、版本、解析原因与结果状态 |

不要在 HUD 展示完整作者、哈希、权限列表或内部 ID。用户需要的是“接下来会发生什么”。

### 7.5 Switcher 验收

- Favorites、Recent、Installed 搜索在 100 个本地 Skills 下仍可即时响应。
- 一次性、App 默认和全局默认的优先级有单元测试与迁移测试。
- Next Run 被使用、阻断、取消、错误和 Retry 时的生命周期都有明确测试。
- 默认 `F5` 与一个自定义录音绑定均通过安装版验证。
- Switcher 快捷键冲突时拒绝保存并保留旧值，不影响录音快捷键。
- VoiceOver 可读出名称、来源、选择范围和不可用原因；完整流程只用键盘可完成。

## 8. Skill Library：独立的核心产品表面

### 8.1 信息架构

Skill Library 使用独立窗口，不继续嵌入 AI Polish Settings 长页面：

```text
Skill Library
├── Installed
├── Discover
└── Created
```

- **Installed**：启用/禁用、收藏、默认范围、版本、更新、回滚、卸载。
- **Discover**：官方内置样例、精选 Community Pilot 内容和本地 Import；远程 Registry 未启用时不显示空 Registry 配置。
- **Created**：New、Fork、Test、Install、Export、Re-import 和版本管理。

### 8.2 Skill 卡片与详情

普通用户第一屏只回答六个问题：

1. 它帮助我完成什么？
2. 什么时候应该用？
3. 输入和输出大概是什么样？
4. 它需要哪些 Context？哪些是必需的？
5. 它会自动粘贴、先预览还是只复制？
6. 它来自哪里，有什么风险或兼容性限制？

Skill Detail 建议结构：

```text
名称 + 来源 + 状态
一句价值说明
When to use
Before / After 示例
Required / Optional Context
Output & Delivery
Risk & safety explanation
[Test] [Install / Use Next Time]

Advanced Inspector ▸
```

Advanced Inspector 再展示：安装 ID、版本/revision、SHA-256、文件清单、Host Profile、Validator、Golden tests、签名与兼容性报告。

### 8.3 安装审查

安装审查必须是人类可读的差异，而不是 Manifest 转储：

- 新安装：说明用途、来源、Context、输出、风险和本地文件范围。
- 升级：突出指令、Context Request、输出策略、风险、Validator 和资源变更。
- 权限扩大：必须重新确认，不能沿用旧授权静默升级。
- 风险升高或自动投递变化：默认转入 Preview，并要求明确确认。
- 不兼容脚本/工具：说明“VibeWhisper 不会执行这些内容”；若 Skill 依赖它们才能成立，则拒绝安装或标记不可运行。

安装前提供 Test Run。用户可以使用包自带示例，也可以输入本地临时样例；临时样例默认不保存。

### 8.4 生命周期

- 安装完成后提供 `Use Next Time`，避免用户不知道下一步去哪。
- 禁用不删除版本与 History 收据；卸载前说明受影响的 App Rule 和默认项。
- 更新失败保留当前活动版本；不能半覆盖。
- 至少保留一个可回滚的旧版本，除非用户明确删除。
- History 重跑找不到原版本时，明确提示并让用户选择当前版本或仅恢复原结果。

## 9. Editable Preview 与 Output Router

### 9.1 Preview 目标

Preview 不是只读警告框，而是 AI 结果进入真实目标前的最后编辑工作台。它应让用户在一个界面内完成：

- 理解改了什么；
- 修改不满意的部分；
- 确认使用了哪些 Context；
- 知道 Validator 是否通过或发生回退；
- 安全替换、粘贴、复制或取消。

### 9.2 建议布局

```text
Skill: Context Rewrite · Community
Used: Voice + Selection     Validator: Passed

[Diff] [Result]
┌ Original / inline diff ───────────────────┐
│ …                                         │
└───────────────────────────────────────────┘
┌ Editable result ──────────────────────────┐
│ 用户可直接修改                            │
└───────────────────────────────────────────┘

[Cancel] [Copy] [Replace Selection]
```

按钮必须使用具体动作名称：有冻结选区时为 `Replace Selection`，普通可编辑目标为 `Paste`，不能一律写模糊的 `Apply`。

### 9.3 中文友好的 Diff

- 中文按字符与标点分组，不依赖空格分词。
- 英文默认按词，代码和 Markdown 可按 token/行切换。
- 长文本先显示变更段落，允许展开未变部分。
- 插入、删除、替换不能只靠颜色区分，同时使用形状、删除线和无障碍描述。
- Reduce Motion 与 Increase Contrast 下保持完整语义。

### 9.4 编辑与校验

- 用户编辑后保留 `AI generated` 与 `Edited by you` 的本地状态，不把编辑内容自动回传模型。
- 每次编辑后重新运行本地 Validator。
- 安全/目标校验失败必须阻止替换；格式契约失败显示明确警告，并按风险策略决定是否允许用户确认后复制或应用。
- 高风险专业 Skill 的必填结构被用户删除时，默认只允许 Copy，除非产品所有者另行批准更精细的确认机制。
- Cancel 不改变目标文本；Copy 不伪装成已插入。

### 9.5 Validator 回退必须显式

如果生成结果未通过 Validator，界面必须显示：

```text
Skill output did not pass its checks.
Showing the original normalized transcript instead.
Reason: Missing required section.
[Review details] [Retry] [Use transcript]
```

规则：

- 不把 ASR 回退结果标记成成功的 Skill 输出；
- History 保存失败问题码、回退类型和最终用户动作，不保存敏感正文到诊断；
- Retry 使用同一个冻结 Skill 安装身份，但重新获取需要重新授权或已失效的 Context；
- 如果原 Skill 版本已卸载，不能静默换版本重试。

### 9.6 目标复验与 Undo

替换前继续校验：

- 同一 Accessibility 目标；
- 同一选区范围；
- 原文 SHA-256 摘要；
- 当前 App 与冻结目标一致；
- Preview 期间目标没有变成敏感或不可编辑状态。

复验失败时只复制并明确显示原因。绝不为了“成功率”放宽目标匹配。

Undo 只在 VibeWhisper 能验证“目标当前仍包含刚刚插入的准确结果”时执行反向替换；无法验证时不自动修改目标，而是提供复制原文。Undo 状态必须与 History 结果一致。

## 10. Context：从声明变成统一权威门禁

### 10.1 Required/Optional 运行语义

| 来源状态 | Required | Optional |
| --- | --- | --- |
| 可用且已允许，返回内容 | 加入 Snapshot，继续 | 加入 Snapshot，继续 |
| 可用且已允许，但当前为空 | 按来源契约决定阻断；不能伪造内容 | 省略并记录 `empty` |
| 尚未决定授权 | 先询问；拒绝则阻断 | 先询问或按产品策略省略 |
| 用户拒绝 | 阻断，提供换 Skill/改权限 | 省略并记录 `denied` |
| 系统或适配器不可用 | 阻断，解释不可用 | 省略并记录 `unavailable` |
| 超出预算或读取失败 | 阻断或要求缩小范围 | 省略并记录受限原因 |

`ContextPolicy.blocksExecution == true` 必须在调用 Provider 和编译最终 Prompt 前成为硬门禁。任何调用方不得忽略后继续执行。

### 10.2 单一决策链

```text
Resolved Skill Run
→ Context Request
→ Source availability
→ User/Skill permission
→ Sensitive-app policy
→ Budget and capture
→ Context Decision
→ Snapshot + Receipt
→ Prompt Compiler 或 Blocked Recovery UI
```

所有 Context 和 Skill 资源都必须服从这条链：

- Selection、未来 focused paragraph 等敏感来源由 Context Broker 捕获。
- Style Capsule 必须先确认 Skill 声明、用户分配和允许状态，不能旁路注入。
- Terminology、Domain Pack、Skill-local terminology 由统一 Resource Decision 冻结，不能在录音后悄悄变化。
- Skill references/assets 只从已检查的安装副本解析，并受大小、类型与路径限制。
- Provider 只收到本次获准且必要的数据，不收到完整 App Rule、Skill 列表或无关应用信息。

### 10.3 普通 UI 的展示原则

- 当前机器根本不可用的 Context Source 不在普通设置中展示空开关。
- Skill Detail 如果声明了不可用的 Required Source，应标记当前不可运行，并说明原因。
- 作者和高级 Inspector 可以看到完整声明及兼容性分析。
- 权限文案使用“会读取什么、用于什么、缺少会怎样”，而不是仅显示能力枚举。
- 支持 `Allow Once`、`Always Allow for This Skill`、`Never Allow`；敏感 App Policy 始终拥有更高优先级。

### 10.4 必需测试

- `blocksExecution` 为真时 Provider 调用次数必须为零。
- Required 与 Optional 对 denied/unavailable/empty/budget-exceeded 的组合测试完整。
- Style Capsule、Terminology 和 Selection 的冻结身份进入同一 Run Receipt。
- Retry 不复用失效的 Selection 正文，也不绕过新的目标复验。
- 支持诊断只包含来源枚举、字符数、决策码和时间，不包含正文。

## 11. Creator V2 与 Test Bench

### 11.1 两层创作体验

**简单模式**面向普通用户，仅要求：

- 名称；
- 一句话用途和“什么时候使用”；
- 示例输入与期望输出；
- 是否需要用户选区；
- 输出策略：先预览、仅复制或在低风险条件下允许自动投递；
- 可选的语气、结构和必须保留内容。

Creator 根据这些信息生成标准 `SKILL.md` 和可选安全 Host Profile。生成前展示人类可读摘要，不要求用户理解 Frontmatter。

**高级模式**提供：

- `SKILL.md` 正文与 Frontmatter；
- `vibewhisper.yaml` Host Profile；
- References、Assets、Terminology；
- Required/Optional Context；
- Validators、风险和输出策略；
- Golden tests 与兼容性报告。

两种模式编辑同一个标准包，不产生两套不可互通格式。

### 11.2 Test Bench

Test Bench 必须支持：

1. 输入文字样例，或录制一段仅用于本次测试的语音样例；
2. 手动提供模拟 Selection、Style 和 Terminology；
3. 查看本次会发送给 Provider 的数据类别与字符预算；
4. 查看编译后的系统安全外壳、Skill 指令、Context 摘要和输出契约的分层结构；
5. 运行测试并在 Editable Preview 中修改；
6. 查看 Validator 结果、兼容性问题与 Golden case 差异；
7. 验证后直接安装到本机。

模拟 Context 和测试语音默认仅在内存中存在，关闭 Test Bench 后清除；用户显式保存为 Golden case 时必须预览实际保存内容。

### 11.3 Fork、分享与升级

- 官方或 Community Skill 均可 Fork 为本地 Created Skill；新身份不能冒充原发布者。
- 默认导出 Agent Skills 标准目录或 ZIP；Legacy 格式只提供导入兼容，不作为新导出默认。
- Re-import 能识别同一 Created Skill 的新 revision，并展示差异。
- 升级 Community Skill 时保留用户 Fork，不自动覆盖本地修改。
- 分享包不包含测试时临时输入、用户 Context、Style Capsule、私有术语或 History。

### 11.4 作者质量门槛

一个可进入精选 Pilot 的 Skill 至少满足：

- 用途和触发场景清晰；
- 至少两个正常样例和一个边界/失败样例；
- 声明真实的 Required/Optional Context；
- 输出策略与风险匹配；
- 不依赖 VibeWhisper 不执行的工具、脚本或网络；
- Golden tests 可重现；
- 安装审查中不存在未解释的权限扩大；
- 中英文至少有一种完整文案，另一种缺失时明确标识而不是机器伪翻译。

## 12. Community Pilot、Collections 与 Registry 时序

### 12.1 先证明内容价值

首轮 Community Pilot 使用三种内容来源：

1. 随 App 提供的高质量官方 Skills；
2. 经人工审查、随测试构建分发的精选 Community Skills；
3. 用户本地导入或自己创建的标准 Agent Skills。

建议首批覆盖 10–15 个真实任务，而不是堆数量：

- Codex task、Bug report、Commit message、Code explanation；
- Team reply、Email、Meeting action items；
- Selection rewrite、Context reply、Translate；
- Product brief、Support reply；
- 1–2 个带高风险 Preview 的专业模板，用于验证边界而非宣传“专业替代”。

每个 Skill 都要对应可观察的重复工作痛点和样例，不能仅用“有趣 Prompt”填充目录。

### 12.2 Favorites 与 Collections

- Favorites 从 Switcher 首版即提供，它解决个人高频选择。
- Collections 只有在 Discover 支持成组浏览、批量安装和逐项审查时才进入普通 UI。
- Collection 只组织元数据和分发；安装时逐个 Skill 显示权限/风险，运行时只解析一个 Skill。
- Collection 不合并 Prompt、Context、权限、版本或执行结果。
- 如果 Pilot 数据显示用户很少批量安装，Collections 继续留在作者/高级层，不占据主导航。

### 12.3 公共 Registry 的 Go/No-Go

远程 Registry 只在以下条件全部满足后进入单独实施提案：

- 本地与精选 Pilot 已证明用户会主动安装、切换和持续使用非 Direct Skills；
- Skill Detail、安装审查、权限扩大重授权、更新、回滚和撤销都有安装版证据；
- 至少有一组非核心团队作者能够通过 Creator/Test Bench 产出合格包；
- Community 内容报告、隔离、下架和申诉流程有负责人；
- 签名索引、包哈希、本地重新检查和内容寻址缓存的威胁模型复核通过；
- Beta 无 Critical 安全/隐私事件，错误 Skill 和错误目标投递低于门槛；
- 产品所有者批准真实 Registry 来源、运营责任和长期维护能力。

即使启用 Registry，它也只是分发信任层，不能增加运行权限。Registry 包仍与本地导入包经过相同检查、Context、Validator、Preview 和 Output Router。

## 13. 信息架构与 Settings 收敛

### 13.1 菜单栏

建议稳定结构：

```text
Start / Stop Recording · F5
Current Skill: … ▸
Use Next Time: …          # 仅有 override 时显示

Skill Library…
History…
Terminologies…
Settings…

Quit VibeWhisper
```

Retry、Cancel 和错误恢复按当前运行状态就近出现，不把状态动作埋进 Settings。

### 13.2 Settings

Settings 只保留全局、低频配置：

1. **General**：默认 Skill 摘要与 Library 入口、录音快捷键、启动行为。
2. **Input & Output**：输入语言、基础转写、输出与安全粘贴策略。
3. **Context & Privacy**：按来源和 Skill 的授权、敏感 App、数据清理。
4. **Appearance & Feedback**：Refined HUD、AI Activity Glow、Hidden、声音、辅助功能。
5. **Advanced**：OpenAI-Compatible 恢复入口、诊断、已配置时的更新；默认折叠。

规则：

- Skill Library 和 Creator 使用独立窗口，不复制完整管理器到 Settings。
- Terminology 的完整编辑器只保留一个；Settings 仅显示摘要和入口。
- 默认 Skill 放在 General 首屏，但详细 App Rules 在 Library/Skill Detail 管理。
- Registry、Updater、Provider Safety 或高级 Context Source 未配置/不可用时不显示普通控件。
- License、Edition、Activation 和 Pro Preview 整个删除。
- 设置项如果只为实现细节服务且没有明确用户决策，应改为安全默认值而不是新增开关。

## 14. 技术架构与数据契约

### 14.1 主执行链

```text
SkillSelectionStore
→ SkillResolver
→ frozen ResolvedSkillRun
→ ContextPolicy + ContextBroker
→ ContextDecision / ResourceDecision
→ SkillExecutionEngine
→ Provider
→ Validator
→ Editable Preview
→ OutputRouter
→ TextInjector verification
→ SkillRunReceipt / History
```

任何 UI 都不得自行绕过这条链拼接 Prompt 或直接投递文本。

### 14.2 建议新增或收敛的数据模型

#### `SkillSelectionState`

```text
nextRunInstallationID?       # 短生命周期
globalDefaultInstallationID
appDefaults[bundleID]
favoriteInstallationIDs
recentInstallationIDs
```

- 持久引用使用安装身份，不只使用可重名的标准 `name`。
- 未知、禁用或卸载身份保留可诊断状态，但运行时安全回退 Direct。
- Recent 只记录身份和时间，不记录输入/输出正文。

#### `ResolvedSkillRun`

```text
runID
installationID + version/revision + contentDigest
displayName + source
resolutionReason
targetApplicationIdentity
contextRequest
resourceIdentities
deliveryPolicy + risk
startedAt
```

对象在录音开始时冻结，Retry 必须明确是复用该身份还是创建新 Run。

#### `ContextDecision`

每个来源保存：`requestedAs`、`availability`、`permission`、`captureResult`、`characterCount`、`decisionCode`。正文只存在于短生命周期 Snapshot，不进入普通诊断事件。

#### `PreviewDraft`

保存本次 Run 引用、原始目标摘要、生成结果、用户编辑结果、Validator 状态和可用动作。窗口关闭、Cancel 或投递完成后按保留策略清理正文。

#### `SkillRunReceipt`

```text
runID + timestamp
skill installation identity + display snapshot
resolution reason
context/resource decision codes
validator result / fallback code
output route requested / actual
target verification result
final user action
```

History 中可保存用户允许的结果正文；诊断导出默认只包含上述脱敏元数据。

### 14.3 迁移要求

- 现有 Voice Mode、默认 Skill 和 App Rule 无损迁移到安装身份模型。
- 遗失 Community Skill 时不崩溃，不静默换成同名包；显示缺失并回退 Direct。
- Legacy `.vibewhisperskill` 的历史版本、授权与回滚继续有效。
- 删除商业许可证状态时，不要把旧 License 配置迁移成新的隐藏开关；安全忽略并在 Delete All Data 时清除。
- Settings 窗口状态迁移到新导航时，对已删除 pane 回退 General。

### 14.4 Provider 与公开使用路径

- 面向普通用户的公开路径继续是浏览器方式连接 ChatGPT、`F5` 录音、转写，再按验证结果粘贴或回退到剪贴板。
- ChatGPT 后端依赖必须在 Onboarding、帮助和错误恢复中明确说明为私有、非稳定公共 API 路径，不能把它描述成官方稳定集成。
- `OpenAI-Compatible` 只保留为 Advanced 中的恢复选项，不成为默认产品叙事，也不因 Community Skill 核心化而暴露更多 Provider 参数。
- Community Skill、Creator 和 Test Bench 只能通过 App 持有的 Provider 边界发起请求，不能获得会话、Cookie、API Key 或凭据。
- Skill 安装来源与 Provider 身份彼此独立；来自精选来源的 Skill 也不能绕过登录、隐私、Context、Validator 或 Output Router。

## 15. 分阶段实施路线

时间为顺序与规模估算，不是发布日期承诺。每一阶段必须独立通过测试和安装版验收后再进入下一阶段。

### Phase 0 — 去商业化与行为真相层（约 1–2 周）

交付：

- 完成第 5 节的商业化删除；
- 让 `ContextPolicy.blocksExecution` 成为 Provider 前硬门禁；
- 明确 Required/Optional 的状态机与错误恢复；
- 为现有运行建立最小 `ResolvedSkillRun` / Receipt，不先改大 UI；
- 修复 Validator 回退提示，禁止静默成功。

退出门槛：商业模块与门禁清零；Context 阻断测试通过；现有 Direct、Retry、粘贴和 History 无回归。

### Phase 1 — Skill Switcher 与运行可见（约 2 周）

交付：

- Next Run、App Default、Global Default、Favorites、Recent；
- 菜单栏 Switcher 与可选独立快捷键；
- Refined HUD、AI Activity Glow/Hidden 辅助语义、菜单和 History 显示同一 Skill 身份；
- 解析原因和冻结语义进入 Receipt。

退出门槛：用户不打开 Settings 可完成切换；F5 与自定义绑定、取消、Retry、三档反馈模式安装版通过。

### Phase 2 — Skill Library 与 Editable Preview（约 2–3 周）

交付：

- 独立 Installed / Discover / Created 窗口；
- 人类可读 Skill Detail、安装审查、Test Run 和 Advanced Inspector；
- 可编辑结果、中文 Diff、明确 Validator 状态；
- Replace/Paste/Copy/Cancel/安全 Undo；
- History Run Receipt 与版本缺失恢复。

退出门槛：普通用户可完成“导入—测试—安装—Use Next Time—编辑—安全投递—追溯”全链路。

### Phase 3 — Creator V2 与本地分享闭环（约 2–3 周）

交付：

- 简单/高级模式；
- 文字与语音样例 Test Bench、模拟 Context、Prompt 分层预览；
- Golden tests、Fork、Export、Re-import、升级差异；
- 精选 Pilot 的作者质量门槛与贡献说明。

退出门槛：非工程用户在不手写 YAML 的情况下完成 Skill；标准包可被重新导入并保留身份/版本语义。

### Phase 4 — 30–50 人 Community Pilot（约 4 周）

交付：

- 10–15 个高质量 Skills；
- 覆盖普通听写、Codex 任务、聊天回复、选区改写和失败恢复；
- 明确同意、可重置的匿名 cohort 指标，或完全本地的人工研究方案；
- 每周质量复盘、错误分类和 Skill 改进记录。

退出门槛：达到第 17 节的用户价值、安全和留存门槛；没有 Critical 隐私/目标投递事件。

### Phase 5 — Registry Go/No-Go（无预设日期）

只做决策，不默认进入开发。若不满足门槛，继续改善本地发现、Creator 和内容质量；不要用 Registry 数量掩盖核心使用率不足。

## 16. 首个实施 Backlog

| ID | 优先级 | 工作项 | 依赖 | 完成信号 |
| --- | --- | --- | --- | --- |
| CS-000 | P0 | 删除商业许可证、Pro 门禁和商业规划 | 无 | 第 5.4 节全部通过 |
| CS-001 | P0 | Context Required/Optional 权威门禁 | 无 | Blocked 时 Provider 调用为零 |
| CS-002 | P0 | `ResolvedSkillRun` 与最小 Receipt | CS-001 | HUD/History 可读取同一冻结身份 |
| CS-003 | P0 | Validator 显式回退 | CS-002 | UI/History 不再记录为普通成功 |
| CS-004 | P0 | Skill Selection Store 与解析优先级 | CS-002 | Next/App/Global/Direct 测试完整 |
| CS-005 | P0 | 菜单栏 Skill Switcher | CS-004 | 不进 Settings 可完成一次性切换 |
| CS-006 | P0 | HUD/VoiceOver/Hidden 状态一致 | CS-002、CS-005 | 三种反馈模式显示相同语义 |
| CS-007 | P0 | Editable Preview 与中文 Diff | CS-002、CS-003 | 编辑后可安全 Replace/Paste/Copy |
| CS-008 | P1 | 独立 Skill Library 与 Detail | CS-004 | Installed/Discover/Created 可用 |
| CS-009 | P1 | 安装 Test Run 与升级差异 | CS-008 | 权限扩大必须重新确认 |
| CS-010 | P1 | History Receipt、Retry 和 Undo | CS-002、CS-007 | 可解释最终投递与回退 |
| CS-011 | P1 | Creator V2 简单模式 | CS-008 | 不写 YAML 可创建标准包 |
| CS-012 | P1 | Test Bench 与 Fork/Export | CS-007、CS-011 | 本地创作分享闭环成立 |
| CS-013 | P1 | Community Pilot 内容与研究 | CS-009、CS-012 | 30–50 人真实数据可评估 |
| CS-014 | P2 | Collections 普通 UI 决策 | CS-013 | 由批量发现数据决定 |
| CS-015 | P2 | 远程 Registry Go/No-Go | CS-013 | 满足第 12.3 与第 17 节 |

## 17. Beta、指标与 Go/No-Go

### 17.1 研究规模

- 30–50 名目标用户；
- 至少 4 周；
- 至少 20 名用户在 W1 仍有有效运行；
- 至少 300 次非 Direct Skill Run，且每个核心场景有足够样本；
- 至少 5 名非核心团队作者成功创建或 Fork Skill；
- 访谈与行为指标必须能区分“识别准确”与“Skill 真正节省工作”。

### 17.2 核心指标定义

| 指标 | 定义 | Pilot 目标 |
| --- | --- | --- |
| 首次有用 Skill 输出时间 | 首次打开 Library 到首个非 Direct 结果被 Apply/Copy | 中位数 ≤ 5 分钟 |
| Skill 切换成功率 | 用户选择的安装身份与冻结运行身份一致且成功开始 | ≥ 97% |
| 错误 Skill 率 | 用户因选错/解析错 Skill 立即取消、重试或反馈 | ≤ 3% |
| 最终应用率 | 有生成结果的 Run 最终 Replace/Paste/Copy | ≥ 70% |
| Preview 编辑率 | 用户在应用前修改结果的 Run 占比 | 观察指标，不单独追求高低 |
| Preview 取消率 | 看到结果后取消且未复制 | ≤ 20%，并按原因分类 |
| Validator 回退率 | 生成结果未通过、退回 ASR 的比例 | 官方/精选 Skills ≤ 5% |
| 目标复验失败率 | 因目标/选区变化转为 Copy | 观察并分类；不能通过放宽安全降低 |
| Switcher 用时 | 打开到确认一个可运行 Skill | 中位数 ≤ 3 秒 |
| Creator 首次成功时间 | 打开 New 到 Test Bench 首次通过 | 中位数 ≤ 15 分钟 |
| W1 / W4 有效留存 | 当周至少完成 3 次非 Direct Skill Run | W1 ≥ 40%，W4 ≥ 20% |

Preview 编辑率高可能代表编辑能力有价值，也可能代表 Skill 质量差；必须结合编辑距离、取消原因和访谈解释，不能作为增长 KPI。

### 17.3 隐私约束

生产默认继续隐私优先。Closed Beta 如果收集匿名事件，必须：

- 首次单独说明并由用户明确同意；拒绝不影响任何功能；
- 使用可重置、随机的 cohort ID，不使用硬件 ID、Apple ID、邮箱或 License Device ID；
- 不收集音频、转写正文、选区、生成结果、用户编辑、Prompt、Skill 正文、术语、文件路径或窗口标题；
- App 身份与 Skill 身份只记录受限类别或本地聚合，不上传可反推出私人工作内容的值；
- 支持随时关闭、查看已收集类别并删除本地队列；
- 事件只用于质量、安全和实用性判断，不加入收入、付费转化或广告归因字段。

### 17.4 Registry Go 条件

除第 12.3 节外，至少同时满足：

- 非 Direct Skill 的 W4 使用不是由单个内置 Skill 垄断；
- 至少 25% Pilot 用户安装或创建过一个非内置 Skill；
- 至少 5 个外部作者包通过质量门槛；
- 安装后 7 天内的卸载/禁用原因可解释，未出现普遍信任问题；
- Critical 安全、隐私和错误目标投递事件为 0；
- 产品所有者确认 Registry 的维护责任不会挤压 Switcher、Preview 和内容质量。

任何一项不满足，结论都是继续本地 Pilot，而不是降低门槛。

## 18. 验收矩阵

| 场景 | 自动化前置检查 | 安装版用户流 | 通过标准 |
| --- | --- | --- | --- |
| Direct 基础听写 | Unit/Integration | TextEdit 中 `F5` 开始/停止 | 安全插入或明确 Copy 回退 |
| Next Run 切换 | Resolver/State tests | 当前 App 打开 Switcher 选一次性 Skill | HUD 与实际 Run 身份一致，之后恢复默认 |
| App 默认 | Bundle ID rule tests | TextEdit 与 Terminal 分别设置/清除 | 精确 App 解析，不因焦点漂移换 Skill |
| 自定义快捷键 | Hotkey registration tests | 改绑后开始/停止，再恢复默认 F5 | 冲突安全回滚，单触发不变 |
| Required Context 缺失 | Provider spy 为零 | Context Rewrite 无选区/拒绝授权 | 阻断并提供恢复动作，不调用 Provider |
| Optional Context 缺失 | Decision matrix tests | 关闭 Style/Terminology 后运行 | 明确降级，Receipt 记录原因 |
| Editable Preview | Diff/validator tests | 修改中英文结果后 Replace/Paste | 修改保留，目标复验通过才投递 |
| 选区变化 | AX snapshot tests | Preview 期间修改目标选区 | 只 Copy，显示 `selection changed` |
| Validator 回退 | Failing fixture | 运行缺少必填章节的 Skill | 显示回退原因，History 不记普通成功 |
| 安装 Community Skill | Loader/inspection tests | Import→Test→Install→Use Next Time | 普通层看懂用途/风险，高级细节可展开 |
| 升级与回滚 | Store/version tests | 扩大 Context 的升级、失败升级、回滚 | 扩权重授权；失败不覆盖；可恢复旧版 |
| Creator V2 | Export/re-import tests | 示例创建→Test Bench→安装→Fork | 不手写 YAML，标准包身份稳定 |
| 三档反馈 | Visual tests | Refined/Glow/Hidden 分别运行/取消/Retry | 状态语义一致，Hidden 仍可从菜单恢复 |
| 去商业化 | 全仓 allowlist scan | Settings、Onboarding、About、全部功能 | 无 License/Pro/Upgrade UI，无功能门禁 |
| 无障碍 | AX structure tests | Keyboard + VoiceOver 完整核心流 | 名称、状态、按钮结果均可理解 |

### 18.1 仓库验证梯度

每个阶段遵循：

1. 精确模型与状态机单元测试；
2. Skill/Context/Preview/History 集成测试；
3. `scripts/check.sh`；
4. `scripts/package_app.sh`；
5. `scripts/install_app.sh`；
6. `./scripts/visual_acceptance.sh --install`；
7. `./scripts/paste_acceptance.sh --install`；
8. `scripts/check_packaged_app.sh`；
9. 使用 `/Applications/VibeWhisper.app` 做真实 installed-app 流程。

不得从 `dist/VibeWhisper.app` 直接启动进行权限或交互证明。

### 18.2 安装版必测分支

- 聚焦真实可编辑目标；
- 默认 `F5` 和一个自定义录音绑定；
- 同键开始/停止；
- `ESC` 取消、Refined HUD inline close 取消；
- 取消、Context 阻断、Validator 错误和投递错误后的 Retry；
- Refined HUD / AI Activity Glow / Hidden；
- Preview 编辑、Copy、Replace/Paste、安全 Undo；
- TextEdit verified insertion 与 Terminal unverified paste dispatch；
- Accessibility/Microphone `.notDetermined` 首次权限顺序；
- Community Skill 安装、升级、禁用、回滚和卸载；
- Settings、Skill Library、Creator、Preview 的键盘与 VoiceOver。

完成验收后必须重新启动正常的 `/Applications/VibeWhisper.app` 并保持菜单栏 App 运行；如果最终工作是 Skill Library/Creator，则在实际可行时将对应窗口留给产品所有者检查。

## 19. 风险与缓解

| 风险 | 表现 | 缓解 |
| --- | --- | --- |
| 核心范围过大 | 同时做 Registry、Creator、Context Adapter，主路径迟迟不可用 | 严格按 Phase 0–4；Registry 无默认日期 |
| Community 内容质量不稳定 | 用户安装后频繁编辑、取消或禁用 | Test Bench、Golden tests、精选 Pilot、版本回滚和质量指标 |
| 选错 Skill | 输出形式完全不符预期 | Next Run、HUD 可见、解析原因、快速 Retry/切换 |
| Required Context 造成阻塞感 | 用户只看到失败，不知道怎么恢复 | 在录音前提示，提供授权、选择文本、换 Direct 三种动作 |
| Preview 变成重型编辑器 | 交互拖慢快速听写 | Direct 低风险仍可按策略自动；Preview 聚焦轻量校对，不做完整文档编辑器 |
| “Agent Skills 兼容”被误解 | 用户以为 VibeWhisper 会执行脚本或工具 | 安装兼容性报告明确“可读取/忽略/拒绝”，文案不承诺等价运行 |
| Settings 再次膨胀 | Library 功能复制到多个 Pane | 一个功能一个权威表面，Settings 只留摘要与入口 |
| 远程 Registry 带来运营负担 | 恶意包、下架、更新和信任问题 | 本地/精选 Pilot 先行，满足 Go 条件后再立项 |
| 去商业化清理破坏构建 | License DI 深入 AppCoordinator 和发布脚本 | 先建立完整功能基线测试，再按 target→DI→UI→docs 顺序删除 |
| 指标侵害隐私 | 事件可推断用户工作内容 | 明确同意、随机可重置 ID、严格字段 allowlist、默认本地 |

## 20. 完成定义

当且仅当以下条件全部满足，才能称为“Community Skills 已成为 VibeWhisper 的产品核心”：

### 产品体验

- 新用户 5 分钟内完成首个非 Direct Skill 输出。
- 日常用户不进 Settings 即可在 3 秒左右选择高频 Skill。
- 用户在录音前后都知道当前 Skill 及解析原因。
- Community Skill 从发现、测试、安装到使用、编辑、追溯、更新/回滚形成闭环。

### 实际价值

- 首批 Skills 对应真实重复工作，而不是展示型 Prompt。
- Beta 的最终应用率、错误 Skill 率、W1/W4 达到目标。
- 用户访谈能具体说明减少了哪些重复操作、模板修正或 App 切换。

### 安全与信任

- Required Context 缺失绝不调用 Provider。
- Skill 不执行任意代码、网络、Shell、MCP 或外部 Action。
- Preview 目标变化时绝不盲目替换。
- Validator 回退、Context 降级和 Copy fallback 全部明确可见且可追溯。

### 创作与社区

- 非工程用户可以创建、测试、安装和导出标准 Agent Skill。
- 外部作者可以 Fork、升级并通过质量门槛。
- Collections 和 Registry 只在数据证明需要时出现，不以功能数量代替用户价值。

### 去商业化

- 仓库、运行时、Settings、文案、发布流程和法律页面中不存在付费层级、许可证激活、购买/退款和商业转化设计。
- 所有当前功能完整开放；没有 dormant paywall 或“未来 Pro”占位。
- 开源合规、签名、公证、更新安全和隐私能力保持完整，且不再使用商业化措辞。

### 工程与安装版证据

- 单元、集成、完整检查、打包、安装和 installed-app 验收全绿。
- 默认 F5、自定义绑定、取消、Retry、三档反馈、Preview、Context 阻断、Skill 生命周期均有真实证据。
- 关闭任务时 `/Applications/VibeWhisper.app` 以正常菜单栏状态运行并留给产品所有者复核。

## 21. 下一步立即执行顺序

批准本计划后，不先做远程 Registry，也不先扩充更多 Settings。立即按以下顺序推进：

1. 建立 Phase 0 去商业化删除清单与安全基线，移除商业模块、功能门禁和相关文案。
2. 修复 Required Context 权威阻断与 Validator 显式回退，先让声明和行为一致。
3. 落地冻结的 `ResolvedSkillRun` / Receipt，成为 Switcher、HUD、Preview 和 History 的共同真相源。
4. 实现 Next Run/App Default/Global Default 和菜单栏 Skill Switcher。
5. 让三种反馈模式、菜单和 History 都能解释当前 Skill。
6. 实现 Editable Preview 与安全 Replace/Paste/Copy/Undo。
7. 将 Skills 从 Settings 拆成独立 Library，再建设 Creator V2/Test Bench。
8. 用 10–15 个真实任务启动 30–50 人 Community Pilot。
9. 根据用户价值与安全指标决定是否需要 Collections 普通 UI 和远程 Registry。

下一阶段的判断标准不再是“又实现了多少高级能力”，而是：用户是否更快得到真正可用的结果，是否清楚并信任 Skill 的行为，以及社区作者能否持续创造这种价值。
