# OpenWhisper 核心产品与商业化规划

> 版本日期：2026-07-13
> 适用范围：OpenWhisper macOS 原生语音输入产品
> 核心主题：围绕“已有 ChatGPT 用户无需再订阅一套独立语音输入服务”构建产品、功能和商业模式

## 1. 执行摘要

OpenWhisper 不应被定位成“又一款通用语音转文字软件”，而应占据一个更窄、更清晰的品类：

> **把用户现有的 ChatGPT 账号，变成 macOS 的全局语音输入能力。**

核心使用闭环保持不变：

```text
F5 开始录音
→ 用户说话
→ F5 停止录音
→ ChatGPT 账号路径完成转写
→ 本地术语校正与按需润色
→ 安全回填当前输入框
→ 无法安全粘贴时保留到剪贴板
```

核心营销信息建议统一为：

> **已经在用 ChatGPT？不必再订阅另一款语音输入服务。按 F5 说话，文字回到当前光标。**

商业模式的基本原则是：

1. 免费核心负责“不重复订阅”；
2. 一次性 Pro 销售效率层、个性化和高级工作流；
3. 订阅只承载真实存在的持续云服务；
4. 不按 ChatGPT 账号路径的转写分钟数收费；
5. 不出售所谓“无限 ChatGPT 转写额度”；
6. 不对 ChatGPT 私有后端提供 SLA；
7. 企业版必须建立在公共 API、BYOK、本地模型或正式书面授权之上。

---

## 2. 核心定位

### 2.1 产品品类

中文：

> **面向 ChatGPT 用户的 macOS 原生全局语音输入层。**

英文：

> **ChatGPT-native voice input layer for macOS.**

### 2.2 一句话定位

> OpenWhisper 为已经使用 ChatGPT 的 Mac 用户提供全局语音输入能力：按下 F5 说话，即可将转写结果安全送回当前输入位置，默认路径无需单独配置语音 API Key，也通常无需再订阅一款独立听写软件。

### 2.3 传播口号

主口号：

> **已经订阅 ChatGPT，就别为语音输入再订阅一次。**

辅助口号：

> **让你已有的 ChatGPT 账号进入 Mac 的每一个输入框。**

### 2.4 核心用户

第一阶段聚焦同时满足以下条件的用户：

- 已经使用或订阅 ChatGPT；
- 使用 macOS 作为主力工作平台；
- 每天需要在多个应用之间输入大量文字；
- 经常向 ChatGPT、Codex、Cursor、Claude Code 等工具输入长任务；
- 不希望维护 API Key、本地模型或第二份语音输入订阅；
- 对中英文混输、技术术语、路径和命令准确率有要求。

优先用户群：

| 用户群 | 高频需求 | OpenWhisper 价值 |
| --- | --- | --- |
| 开发者、AI Coding 用户 | 口述需求、错误信息、实施计划 | 中文口述并保留英文技术词、路径和命令 |
| 产品经理、创始人 | 邮件、PRD、反馈、Agent 任务 | 在多个应用中使用统一 F5 输入链路 |
| 顾问、研究者、内容工作者 | 草稿、笔记、提纲、回复 | 思考速度不再受打字速度限制 |
| 中英双语知识工作者 | 人名、产品名、缩写和混合语言 | 通过术语词库和本地归一化提高准确率 |

### 2.5 暂不作为核心市场

- 企业 SLA、SSO、审计和严格合规场景；
- 医疗、法律等高风险专业听写；
- 强制离线和零云端传输用户；
- 会议机器人、多人分轨和会议纪要用户；
- Windows、iOS、Android 用户；
- 不愿连接 ChatGPT 账号的用户。

---

## 3. 产品事实与表述边界

### 3.1 当前实现支持的事实

当前代码已经具备以下基础：

- OpenWhisper 通过默认浏览器发起 OAuth + PKCE 登录；
- Access Token 和 Refresh Token 保存在本机 Keychain；
- 默认 ASR 路径不依赖 `OPENAI_API_KEY`；
- ASR 使用 ChatGPT 账号 Bearer Token；
- AI Polish 使用同一 ChatGPT 账号会话；
- `OpenAI-Compatible` 保留为高级恢复路径，其 API Key 独立保存在 macOS Keychain，不读取 shell 环境变量；
- Advanced Settings 可管理 Recovery endpoint/model/Keychain 凭据，发送合成静音执行真实连接测试，并在切换到可能计费的 API 前要求用户确认；
- Recovery 只替换听写 ASR，AI Polish 继续使用 ChatGPT 登录授权；
- F5、录音、转写、术语处理、回填和剪贴板恢复已形成完整闭环。

关键实现：

| 模块 | 文件 |
| --- | --- |
| 浏览器登录 | `Sources/OpenWhisper/BrowserAuthBridge.swift` |
| ChatGPT 会话管理 | `Sources/OpenWhisper/ChatGPTAuthManager.swift` |
| Keychain 会话存储 | `Sources/OpenWhisper/ChatGPTSessionStore.swift` |
| Recovery Keychain 存储 | `Sources/OpenWhisper/OpenAICompatibleCredentialStore.swift` |
| Recovery 连接测试 | `Sources/OpenWhisper/OpenAICompatibleConnectionTester.swift` |
| ChatGPT ASR | `Sources/OpenWhisper/ChatGPTTranscriber.swift` |
| AI Polish | `Sources/OpenWhisper/TextPolisher.swift` |
| 听写流水线 | `Sources/OpenWhisper/DictationPipeline.swift` |
| 文本回填 | `Sources/OpenWhisper/TextInjector.swift` |

### 3.2 当前实现不能证明的事实

当前代码没有：

- Plus 套餐识别；
- 订阅等级解析；
- Entitlement 或配额查询；
- 账单状态查询；
- 可用分钟数查询；
- 对底层语音模型身份的稳定确认；
- 对第三方商业调用权限的正式证明。

因此，当前最准确的公开表述是：

> **连接 ChatGPT 账号后，默认听写路径无需单独配置语音 API Key。**

不应表述为：

- “OpenWhisper 可以验证并复用 Plus 权益”；
- “Plus 已包含 OpenWhisper 的全部听写成本”；
- “免费、永久、无限量使用 ChatGPT 语音模型”；
- “OpenWhisper 使用官方公开 ChatGPT 转写 API”；
- “OpenAI 官方合作、推荐或背书”；
- “底层固定使用某一个确定模型”。

### 3.3 推荐的商业表达

可以说：

- 无需再订阅另一款独立语音输入服务；
- 默认路径无需额外配置语音 API Key；
- OpenWhisper 不按分钟收费；
- OpenWhisper 不转售模型额度；
- 复用用户自己的 ChatGPT 账号连接；
- 可用性和限制取决于用户账号及上游服务。

避免说：

- Plus 包含无限 API；
- 绕过 API 计费；
- 把 Plus 变成 API；
- 永久不限量；
- 绝不会封号；
- 官方 OAuth/API 集成；
- 私有后端具有企业级稳定性。

---

## 4. 产品功能分层

## 4.1 Community 免费核心

免费核心必须完整交付“不重复订阅”的核心价值。

| 功能 | 用户价值 | 收费原则 |
| --- | --- | --- |
| ChatGPT 账号连接和基础 ASR | 无需语音 API Key 即可开始使用 | 免费 |
| F5 开始、F5 停止 | 保持单触发工作流 | 免费 |
| 智能快路径 | 短句不等待无意义 AI Polish | 免费 |
| 安全粘贴和剪贴板兜底 | 避免错误回填和结果丢失 | 免费 |
| 基础术语词库 | 保证产品名和技术词准确率 | 免费 |
| 登录刷新和错误恢复 | 避免重复录音 | 免费 |
| 失败录音 Retry | 提高核心成功率 | 免费 |
| 隐私开关和删除全部数据 | 建立用户信任 | 免费 |
| 手动 OpenAI-Compatible Recovery | 避免上游单点失效 | 免费 |

免费版不应：

- 限制 ChatGPT 账号路径的转写分钟数；
- 限制基础听写次数；
- 将核心速度优化设为付费；
- 将失败恢复设为付费；
- 将数据删除和隐私选项设为付费；
- 对私有 ChatGPT 调用按分钟收费。

## 4.2 Pro 一次性高级功能

Pro 销售的是桌面效率层，而不是模型访问权。

### 4.2.1 应用感知 Voice Modes

建议内置模式：

| 模式 | 行为 |
| --- | --- |
| Direct | 尽量原样转写，优先速度 |
| Reply | 输出简短、自然的聊天回复 |
| Email | 整理为主题明确、语气完整的邮件 |
| Agent Plan | 整理为目标、约束、步骤和验收项 |
| Code Prompt | 保护路径、命令、参数、类名和代码符号 |
| Translate | 将口述直接转换为指定语言 |

实现建议：

```text
DictationMode
AppModeResolver
AppModeRuleStore
DictationContext
```

隐私边界：

- 默认只使用应用名称和 Bundle Identifier；
- 不默认读取当前聊天、网页、邮件或完整窗口内容；
- 需要上下文时，必须由用户主动选中文本或明确授权。

### 4.2.2 项目级和应用级词库

建议词库层级：

```text
全局词库
  └─ 应用词库
       └─ 项目或仓库词库
```

支持：

- 项目名和客户名；
- GitHub 仓库名；
- API、类名和方法名；
- 文件路径和命令；
- 错误词到正确词映射；
- 术语别名；
- 导入和导出；
- 按应用或项目自动激活。

实现建议：

```text
TerminologyProfile
TerminologyProfileStore
TerminologyContextResolver
```

### 4.2.3 指令化编辑

保留原有 F5 工作流，增加可选 `⌥F5` 命令模式：

- “整理成三点”；
- “改成正式邮件”；
- “翻译成英文”；
- “缩短一半”；
- “保留所有命令和路径”；
- “按后面的决定为准”。

必须具备：

- 原文保存；
- 结果预览；
- 一键撤销；
- 原始文本与处理结果切换；
- 防止把普通口述误识别为命令。

### 4.2.4 高级历史和隐私

- 本地加密搜索；
- 标签、收藏和导出；
- 原始 ASR、Polish 结果和最终结果切换；
- 敏感应用不保存；
- 文本和音频分别设置 TTL；
- 一键删除全部数据；
- 默认不长期保存成功音频。

### 4.2.5 其他 Pro 功能

- 选择文本后语音编辑；
- 自定义 Voice Mode 模板；
- Shortcuts、CLI 和 URL Scheme；
- 多语言和翻译；
- 长音频文件导入；
- 本地模型恢复包；
- 自动备份路由；
- 高级诊断工具。

## 4.3 Workspace 和团队服务

只有存在真实持续成本的服务才适合订阅：

- 多台 Mac 加密同步；
- 词库和模式云备份；
- 跨设备配置恢复；
- 持续更新的工作流模板；
- 团队共享术语和模式；
- 席位、策略、MDM 和管理后台；
- 可选公共 API 托管备用额度。

团队版不得依赖消费者 ChatGPT 私有账号路径承担 SLA。

正式团队产品的前置条件：

1. 公共 API、BYOK 或本地模型恢复路径可用；
2. 客户端安全问题关闭；
3. 发布、签名和自动更新稳定；
4. 团队试点转正式率超过 30%；
5. 支持成本低于合同额的 25%；
6. 如继续将账号路径作为核心权益，需要获得正式书面授权。

---

## 5. 性能优化规划

### 5.1 当前性能判断

此前本机样本显示：

| 阶段 | P50 |
| --- | ---: |
| 总处理耗时 | 约 7.6 秒 |
| ASR | 约 5.2 秒 |
| AI Polish | 约 2.5 秒 |
| 注入 | 数十毫秒 |

主要问题不是文本注入，而是：

1. ASR 网络耗时；
2. 所有短句基本都会继续执行 AI Polish；
3. WAV 和 multipart 在内存中完整构造；
4. 缺少细粒度 TTFB、重试和构建耗时指标。

### 5.2 真正的 Auto Polish

当前 `TextPolishProviderSelector` 只判断模式和登录状态，没有根据长度或复杂度决策。

建议决策规则：

```text
Direct 模式：默认跳过

≤10 秒、≤80 字：
  无改口、列表、翻译和结构化意图时跳过

10–20 秒：
  根据改口词、列表标志、复杂度和当前模式评分

>20 秒：
  默认执行

Email / Agent Plan / Translate：
  按模式执行

Always Rewrite：
  无条件执行
```

建议记录决策原因：

```text
skip_short_direct
skip_low_complexity
run_self_correction
run_agent_plan
run_translation
forced_always
```

实现建议：

```text
Sources/OpenWhisper/TextPolishDecisionEngine.swift
Sources/OpenWhisper/DictationContext.swift
```

接入位置：

- `Sources/OpenWhisper/DictationPipeline.swift`
- `Sources/OpenWhisper/AppCoordinator.swift`

### 5.3 请求链路优化

- 避免 `Data(contentsOf:)` 后再次完整复制 multipart；
- 改为临时 multipart 文件或流式上传；
- 记录文件读取和 multipart 构建耗时；
- 执行 `maxDurationSeconds`；
- 对 16kHz、24kHz、WAV、M4A 做准确率与延迟 A/B；
- 保留兼容性最好的 WAV batch 回退路径；
- 对 3、10、30、60 秒固定语料分别测试。

### 5.4 性能目标

| 指标 | 目标 |
| --- | ---: |
| ≤10 秒听写 warm P50 | ≤5.0 秒 |
| ≤10 秒听写 warm P95 | ≤5.5 秒 |
| 实际使用 P95 | ≤7 秒 |
| Polish 跳过率 | 60%–80% |
| 请求准备 P95 | <100ms |
| 高频术语正确率 | ≥95% |

如果要实现停录后 1–2 秒完成，必须单独验证 Realtime 或流式方案。当前批量 ChatGPT 账号路径不应被宣传成稳定 Realtime 权益。

---

## 6. 稳定性、隐私和安全阻断项

以下问题需要在商业发布前优先解决。

### 6.1 Managed Token 目标白名单

当前 ChatGPT ASR 和 Polish endpoint 可从普通配置读取，并会携带 ChatGPT Bearer Token、录音或完整文本发出。

必须：

- 将 Managed Auth 限制为固定 HTTPS host；
- 将可访问 path 限制为明确白名单；
- 禁止 Managed Token 被发送到用户自定义 URL；
- 用户自定义 URL 必须搭配独立 Compatible API Key；
- 对 URL 做安全解析，禁止强制解包。

涉及文件：

- `Sources/OpenWhisper/ChatGPTTranscriber.swift`
- `Sources/OpenWhisper/TextPolisher.swift`
- `Sources/OpenWhisper/AppConfig.swift`

### 6.2 安全粘贴

当前 `launchAppContext` 在部分情况下可参与允许粘贴的判断，可能与“只有可编辑目标才粘贴”的公开承诺不一致。

正确原则：

```text
恢复原应用 ≠ 获得粘贴许可
```

必须：

- `launchAppContext` 只用于恢复原应用；
- 发送 `Cmd+V` 前重新确认当前窗口和 focused element；
- 无法确认可写时只复制到剪贴板；
- Retry 默认不向任意当前应用自动粘贴；
- 区分“已发送粘贴命令”和“已确认插入成功”。

涉及文件：

- `Sources/OpenWhisper/TextInjector.swift`
- `Sources/OpenWhisper/FocusedElementInspector.swift`
- `Tests/OpenWhisperTests/TextInjectorTests.swift`

### 6.3 Token Refresh 竞态

增加：

- Refresh single-flight；
- Session generation；
- 注销后拒绝迟到的 Refresh 写回；
- 并发 Refresh 去重；
- 401 只自动刷新一次。

涉及文件：

- `Sources/OpenWhisper/ChatGPTAuthManager.swift`

### 6.4 错误分类和熔断

当前已落地签名 `ProviderCapabilityPolicyController`：通过 App 内固定的 HTTPS
地址和独立 Ed25519 公钥获取策略，在读取音频、解析 Token 或发送转写文本前停用
`managedTranscription` / `chatGPTTextPolish`，并使用 31 天硬到期、build 范围和
单调 revision 拒绝重放。生产托管、密钥和事故演练仍未完成。

后续仍需新增：

```text
ProviderHealthMonitor
ProviderErrorCategory
ProviderCircuitBreaker
```

处理规则：

| 上游结果 | OpenWhisper 行为 |
| --- | --- |
| 401 | 刷新一次，失败后要求重新登录 |
| 403 / Cloudflare | 避免连续无退避重试，保留录音并提示替代路径 |
| 429 | 尊重 `Retry-After`，显示可重试时间 |
| 404 / Schema 变化 | 关闭对应 Provider，提示更新 |
| 5xx / 网络错误 | 有上限的退避和抖动重试 |
| 大规模账号异常 | 暂停账号路径推广和新用户接入 |

### 6.5 数据留存

建议默认策略：

- 成功音频立即删除；
- 失败音频保留 24 小时；
- 最近恢复记录设置数量上限；
- 文本历史可关闭；
- 历史和延迟日志按时间或大小轮转；
- 增加“删除全部数据”；
- 敏感应用可禁用历史；
- Retry 文件路径必须规范化并限制在 Recovery 目录内。

实现建议：

```text
HistoryRetentionPolicy
SensitiveAppPolicy
StorageCleanupService
```

涉及文件：

- `Sources/OpenWhisper/RecoveryHistory.swift`
- `Sources/OpenWhisper/TranscriptionHistory.swift`
- `Sources/OpenWhisper/LatencyRecorder.swift`

### 6.6 Advanced Recovery 完整化

状态：**macOS Alpha 实现已完成，安装版可用性与无障碍矩阵仍属于发布验收。**

已完成：

- Advanced 页显示当前 Dictation/AI Polish 路径，并可原生编辑 Endpoint 和 Model；
- API Key 使用 `app.openwhisper.mac.OpenAICompatibleAPIKey` 独立保存在 macOS Keychain；
- 旧 `openAIAuthTokenEnv` 仅为兼容旧配置而被忽略，重新编码时会删除；`OPENAI_API_KEY` 不再启用 Recovery；
- 真实连接测试通过 `SecureHTTPClient` 向用户配置的 HTTPS endpoint 发送生成的 0.1 秒静音 WAV，不发送用户录音、转写或术语；
- 用户可以删除 Recovery Key、切回 ChatGPT 账户路径，Delete All Data 也会删除该 Key；
- Recovery 只切换 Dictation ASR，AI Polish 继续依赖 ChatGPT Auth；
- 从默认 ChatGPT 路径切换到可能计费的 API 前会显示费用与数据流向确认。

持续验收：

- 使用至少两个公开兼容服务和一个自托管测试 endpoint 验证 multipart 兼容性与错误文案；
- 在安装版中完成全键盘、VoiceOver、高对比度和窄窗口布局检查；
- 不把第三方 API 费用、可用性、额度或隐私承诺归属于 OpenWhisper。

---

## 7. 商业版本与定价

### 7.1 推荐版本

| 版本 | 建议价格 | 核心权益 |
| --- | ---: | --- |
| Community | 免费 | 当前核心功能和基础恢复能力 |
| Founder Pro | ¥198 / $29 | 新增 Pro 功能，最多 3 台 Mac，含一年更新 |
| 正式 Pro | ¥268 / $39 | Voice Modes、项目词库、指令编辑、高级历史和自动化 |
| Pro 更新续期 | ¥128 / $19/年 | 一年新增功能更新；不续费仍可使用已有版本 |
| Workspace | ¥198 / $29/年 | 多 Mac 同步、配置备份和持续模板更新 |
| Team Pilot | ¥14,800–36,800 / $2,000–5,000 | 30–60 天部署、培训和工作流验证 |
| Team | ¥699 / $99 每席每年 | MDM、共享词库、席位和管理员工具 |

### 7.2 Pro 授权原则

- 当前主版本永久可用；
- 包含 12 个月新功能更新；
- 到期不续费仍可使用已有版本；
- 安全修复和严重兼容性修复不强制付费；
- 现有 MIT 功能不重新锁定；
- Pro 代码采用独立模块或独立授权；
- OpenWhisper 品牌、签名构建、更新和支持仍可形成商业价值。

### 7.3 退款和支持

退款：

- Pro：14 天退款；
- Workspace：随时取消续费；
- Team Pilot：按客户端功能、部署和培训里程碑验收；
- 不按私有后端可用率验收。

支持：

| 版本 | 支持方式 |
| --- | --- |
| Community | 文档、GitHub Issues、社区 |
| Pro | 2 个工作日内首次响应目标 |
| Team | 1 个工作日内首次响应目标 |

可以承诺：

- 客户端响应时间；
- 安装和部署支持；
- 客户端 Bug 修复；
- 已售 Pro 功能；
- 公共 API 或本地恢复能力。

不能承诺：

- ChatGPT 私有端点恢复时间；
- 用户账号限额；
- 固定上游模型；
- 上游延迟和可用率；
- 无限转写。

---

## 8. 单位经济与收入情景

### 8.1 成本结构

如果核心账号路径不产生 OpenWhisper 自营模型成本，主要成本将来自：

- 安装和权限支持；
- 登录、403、429 和上游变化工单；
- macOS 兼容性；
- Developer ID、签名、公证和更新；
- 支付、税务、退款和换汇；
- 用户教育和内容获客；
- 上游故障导致的集中退款和声誉损失。

目标指标：

| 指标 | 目标 |
| --- | ---: |
| Pro 退款率 | <5% |
| 新 Pro 用户首月平均支持成本 | <$3 |
| Workspace 年流失率 | <20% |
| Team 支持成本 | <合同额 25% |
| 激活用户到 Pro | 2%–4% |
| 高频用户到 Pro | 8%–12% |

### 8.2 12 个月预算情景

以下是内部预算模型，不是收入承诺。

假设：

- Pro 加权平均售价 $34；
- Workspace $29/年；
- Team $99/席/年；
- 激活用户至少完成 3 次成功听写；
- 不计算创始人工资、研发和法律成本。

| 情景 | 激活用户 | Pro 转化 | 年度 Bookings |
| --- | ---: | ---: | ---: |
| 保守 | 8,000 | 1.5% | 约 $7k / ¥5 万 |
| 基准 | 25,000 | 3% | 约 $41k / ¥29 万 |
| 乐观 | 80,000 | 5% | 约 $210k / ¥151 万 |

当前公开推广尚未形成有效分发和安装反馈，因此现金预算应按保守情景制定。

最敏感的变量不是模型成本，而是：

1. 下载到首次成功率；
2. 首次成功时间；
3. W1 和 W4 留存；
4. 高频使用次数；
5. Free 到 Pro 转化；
6. 上游变化造成的工单和退款。

---

## 9. 增长策略

### 9.1 核心市场切口

第一市场：

> **ChatGPT + Mac + AI Coding 用户。**

重点场景：

- 中文口述需求进入 Codex；
- 保留 `kubectl`、`SwiftUI`、类名、参数和路径；
- 将长口述整理为 Agent Plan；
- 在 Codex、Cursor、Mail、Slack、Notes 等应用中复用同一 F5 工作流。

第二市场：

> **ChatGPT + Mac 知识工作者。**

重点场景：

- 邮件；
- Slack、飞书或聊天回复；
- 周报和需求文档；
- Notes、Notion 和浏览器表单；
- 中英文翻译。

### 9.2 信息顺序

公开页面建议按以下顺序表达：

1. 已经在用 ChatGPT，不必为听写再订阅一次；
2. 15 秒真实操作演示；
3. F5 开始、F5 停止、结果回到当前光标；
4. 中文技术词、Agent Plan 和专业词库；
5. 开源、安全粘贴和隐私；
6. 私有账号路径的边界说明。

### 9.3 内容形式

现有推广记录显示静态产品卡片效果较弱，后续应优先真实录屏：

```text
显示真实输入框
→ 按下 F5
→ 口述一段包含中英文技术词的需求
→ 再按 F5
→ 展示转写和回填
→ 展示无法安全粘贴时的剪贴板兜底
```

每周建议：

- 2 条中文 15–30 秒录屏；
- 1 条英文录屏；
- 1 篇构建日志或技术复盘；
- 1 个具体术语或应用兼容案例。

### 9.4 社区增长资产

建议建设：

#### Terminology Packs

- Swift；
- Rust；
- Kubernetes；
- AI 工具；
- 产品经理；
- 常用中英文技术术语。

#### Voice Recipes

- Codex Plan；
- GitHub Issue；
- Email；
- Slack Reply；
- Standup；
- PRD Draft。

#### Compatibility Matrix

- Codex；
- Cursor；
- Slack；
- Mail；
- Notes；
- 浏览器输入框；
- 终端和特殊控件。

### 9.5 North Star 和漏斗

North Star：

> **每周每位激活用户成功完成的听写回填次数。**

激活定义：

- 完成 ChatGPT 连接；
- 24 小时内完成至少 3 次成功听写；
- 在至少 2 个不同应用中完成回填。

90 天目标：

| 指标 | 目标 |
| --- | ---: |
| 合格访问到下载 | ≥20% |
| 下载到首次启动 | ≥65% |
| 首次启动到 ChatGPT 连接 | ≥70% |
| 连接到首次成功转写 | ≥80% |
| 首次转写到成功回填 | ≥85% |
| 首次成功到激活 | ≥50% |
| W1 留存 | ≥35% |
| W4 留存 | ≥25% |
| 激活用户到一次性付费 | 3%–5% |

---

## 10. 90 天实施计划

### 第 1–2 周：定位、安全和数据基础

- 统一首页、README、设置页、定价页和结账文案；
- 统一 GitHub owner、Release、落地页和 Homebrew 链接；
- 增加独立项目和非官方关系声明；
- 增加隐私友好的匿名漏斗指标；
- 禁止上传录音、文本、剪贴板、账号和 Token；
- 修复 Managed Token endpoint 白名单；
- 招募 30 名 ChatGPT + Mac 测试用户；
- 制作 Codex、Mail、Slack、Notes 四条真实录屏。

验收：

- 下载链接零失效；
- 20 名用户完成首次成功转写；
- 首次成功率 ≥70%；
- 所有 Managed Token 请求通过目标白名单。

### 第 3–6 周：性能、可靠性和隐私

- 实现 `TextPolishDecisionEngine`；
- 优化音频读取和 multipart；
- 执行 `maxDurationSeconds`；
- 增加 TTFB、重试次数和决策原因；
- 完善 401、403、429、5xx 错误分类；
- 增加 Token refresh single-flight；
- 修复安全粘贴；
- 完成音频 TTL 和删除全部数据；
- 完善 Advanced Recovery UI；
- 发布 P0 版本。

验收：

- ≤10 秒听写 warm P50 ≤5 秒；
- 首次成功率 ≥95%；
- 重试后成功率 ≥99%；
- 成功音频默认不长期保存；
- 所有不可确认目标只进入剪贴板。

### 第 7–9 周：Pro MVP

- Direct、Reply、Email、Agent Plan；
- 项目和应用词库；
- 原文和润色结果切换；
- 高级历史搜索；
- 可选 `⌥F5` 指令模式；
- License Manager；
- 14 天退款流程；
- Pro 功能与 Community Core 分层。

验收：

- 应用模式误激活率 <1%；
- 项目词库激活正确率 ≥99%；
- 用户二次编辑量下降 ≥30%；
- 普通 Direct 模式不增加额外延迟。

### 第 10–12 周：Founder Pro

- 上线 ¥198 / $29 Founder License；
- 最多 3 台 Mac；
- 含一年新功能更新；
- 只向完成第 20 次成功听写或连续使用 7 天的用户展示升级；
- 访谈或调查前 100 名付费及拒绝付费用户；
- A/B 测试 $29 与 $39；
- 分批发布开发者社区和真实演示内容。

升价条件：

- 激活到 Pro 转化 ≥3%；
- 退款率 <5%；
- 首月平均支持成本 <$3；
- 购买理由主要是工作流和个性化，而不是“无限用量”。

---

## 11. 12 个月实施节奏

### M1–M2：商业化基础

- 安全粘贴；
- Token endpoint 白名单；
- 数据留存策略；
- Release build；
- Developer ID 签名；
- Notarization 和 staple；
- 自动更新；
- 隐私、条款、退款和非官方声明；
- 匿名漏斗指标。

### M3：Founding Pro

- ¥198 / $29；
- 只销售新增高级工作流；
- 招募前 100 位付费用户；
- 复盘购买和拒绝原因。

### M4–M6：验证产品和定价

- Voice Modes；
- 项目词库；
- 高级历史；
- 指令化编辑；
- 翻译；
- 测试 $29 和 $39；
- 达到转化和退款门槛后升至正式价格。

### M7–M8：Workspace Beta

- 50 人测试加密同步；
- 优先年付；
- 验证实际同步使用率；
- 不包含模型额度。

### M9–M10：团队试点

- 3–5 个开发、产品或内容团队；
- 每个试点付费；
- 验证共享词库、部署、MDM 和支持成本；
- 报价单明确不承诺消费者 ChatGPT 私有端点 SLA。

### M11–M12：决定是否扩张

只有满足以下条件才推出正式 Team：

- 高优先级安全问题关闭；
- 退款率 <5%；
- 团队试点转正式 >30%；
- 公共 API、BYOK 或本地模型恢复可用；
- 支持成本不会吞掉团队毛利；
- 商业和法律边界完成复核。

---

## 12. 近期明确不做

以下方向会稀释核心定位，近期不建议投入：

1. 完整会议机器人；
2. 多人分轨和会议纪要平台；
3. 通用 RPA；
4. 自动发送消息或自动执行命令；
5. 完整 AI 聊天客户端；
6. 企业知识库；
7. Windows、iOS、Android 同时扩张；
8. 将本地模型管理放入默认 Onboarding；
9. 多 Provider 市场和复杂 API Key 配置；
10. 团队管理后台优先于个人用户留存；
11. 常驻监听和唤醒词；
12. 模板市场和社交功能。

这些方向只有在核心闭环达到“快、稳、准、可信”，并形成稳定个人留存后再评估。

---

## 13. 商业和平台风险

### 13.1 核心风险

| 风险 | 概率 | 影响 | 应对 |
| --- | ---: | ---: | --- |
| 私有 endpoint 变化 | 高 | 严重 | Provider 抽象、恢复路径、快速更新 |
| OAuth Client 变化或撤销 | 中高 | 严重 | 获得正式授权或迁移 |
| Plus 权益误述 | 高 | 高 | 禁止“无限、免费 API”文案 |
| 用户账号受限 | 中高 | 严重 | 降低异常重试、明确风险 |
| 数据留存表述错误 | 中高 | 高 | 不承诺未公开的数据政策 |
| 品牌关系误导 | 中 | 高 | 独立项目声明 |
| 集中上游故障工单 | 高 | 高 | 熔断、状态说明、暂停付费推广 |
| MIT 代码易复制 | 高 | 中 | 品牌、签名构建、更新、服务和个人资产 |

### 13.2 Go / No-Go

| 商业模式 | 判断 |
| --- | --- |
| 免费开源、明确边界、无 SLA | 有条件继续 |
| 一次性 Pro，销售桌面工作流 | Go |
| 将私有账号路径作为附带免费能力 | 有条件继续 |
| 依赖私有路径出售订阅 SLA | No-Go |
| 企业版使用公共 API、BYOK 或本地模型 | Go |
| 获得正式书面授权后的账号集成 | Go |
| 宣传无限量 ChatGPT 转写 | No-Go |

OpenAI 当前消费者条款对自动或程序化提取数据或输出设置限制。OpenWhisper 的私有后端调用因此存在合同解释和平台连续性风险。这不等于可以直接断言产品违规，但意味着该路径不能作为收费 SLA 或企业合同的唯一交付基础。

---

## 14. 推荐公开文案

### 14.1 首页标题

> **已经在用 ChatGPT？不必再订阅另一款语音输入服务。**
> 按 F5 说话，文字回到当前光标。

### 14.2 首页副标题

> OpenWhisper 不按分钟收费，也不销售模型额度。免费核心负责连接 ChatGPT、完成转写和安全回填；Pro 只为专业词库、应用模式和高级工作流收费。

### 14.3 下载区说明

> 需要用户自备可用的 ChatGPT 账号。默认转写路径依赖上游登录状态、使用限制和私有接口行为，不保证无限使用或持续可用。

### 14.4 独立项目声明

> OpenWhisper 是独立项目，与 OpenAI 无隶属、赞助或背书关系。

### 14.5 结账说明

> 本次购买仅包含 OpenWhisper Pro 客户端功能和更新权益，不包含 ChatGPT 订阅、OpenAI API 额度、模型服务或上游可用性保证。

### 14.6 英文版

标题：

> **Already use ChatGPT? Do not pay for a second dictation subscription.**

副标题：

> OpenWhisper turns F5 into a native speak-to-paste workflow across macOS. Core dictation does not require a separate speech API key, while Pro charges only for advanced desktop workflows and personalization.

脚注：

> A usable ChatGPT account is required for the default account route. Availability and usage are subject to upstream account limits and undocumented backend behavior. OpenWhisper is an independent project and is not affiliated with, sponsored by, or endorsed by OpenAI.

---

## 15. 决策原则

今后每个新功能都必须回答以下问题：

1. 是否让 F5 输入更快？
2. 是否让转写和回填更可靠？
3. 是否提高术语和混合语言准确率？
4. 是否减少用户二次编辑？
5. 是否增强用户对隐私和费用的信任？
6. 是否服务“已有 ChatGPT 用户不重复订阅”这一核心定位？

如果一个功能不能改善其中至少一项，就不应进入近期路线图。

最终商业战略：

> **免费核心负责“不重复订阅”；一次性 Pro 销售输入效率、个性化和高级工作流；订阅只承载同步、团队和公共 API 等真实云服务；不销售所谓“无限 ChatGPT 转写额度”。**

---

## 16. 参考资料

以下外部资料在形成本文档时用于核验产品边界，发布重要商业文案前应重新检查其最新版本：

- [OpenAI：What is ChatGPT Plus?](https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus)
- [OpenAI：Terms of Use](https://openai.com/policies/terms-of-use/)
- [OpenAI：Brand guidelines](https://openai.com/brand/)
- [OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)
- [Wispr Flow Pricing](https://wisprflow.ai/pricing)
