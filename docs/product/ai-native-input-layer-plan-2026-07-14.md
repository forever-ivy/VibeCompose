# OpenWhisper AI-native 输入层完整方案

> 日期：2026-07-14
> 状态：产品与技术方案 v1；Phase 1–3 已落地
> 当前基线：`0.1.0 Alpha`
> 范围：macOS 原生客户端、Skills、上下文、个性化、视觉反馈与可自定义全局热键
> 与现有计划的关系：本方案是当前 V1 听写闭环之上的下一阶段产品方向，不替代签名、公证、更新、权限和安全粘贴等发布门禁。

## 实施进度更新

截至 2026-07-14，本方案已完成 Phase 0 决策确认、Phase 1 交互基础、Phase 2 Skill Runtime 内核和 Phase 3 选区上下文与 Preview：

- `HotkeyBinding`、旧配置迁移、快捷键录制控件、组合校验；
- 候选快捷键预注册、配置持久化、失败回滚、启动时 F5 回退；
- 录制快捷键期间暂时释放全局监听，避免旧快捷键误触发；
- Onboarding、Settings、History、Menu、Ready、Recording 和 VoiceOver 动态显示当前快捷键；
- 统一 `FeedbackSurfaceController`；
- 顶部居中的 Refined HUD；
- Blue Signal Frame；
- Hidden；
- Appearance & Feedback 设置、预览、声音与完成通知；
- Hidden 下的菜单 Retry 与 Esc 取消；
- Reduce Motion、Increase Contrast 和 VoiceOver 状态语义；
- 安装版三模式自动验收脚本。
- 六个稳定、版本化的内置 Skill ID；
- Voice Mode 配置无损迁移到 `skills`，新配置不再写回旧键；
- 手动、本应用规则、全局默认和 Direct 回退的固定解析优先级；
- 录音开始时冻结 Skill ID、版本和解析来源；
- 固定安全外壳优先级的 Prompt Compiler；
- 非空、长度、JSON、Markdown 围栏、必填章节、技术字面量、禁用表达和内部标记校验；
- Validator 失败时在投递前回退规范化 ASR；
- History 与脱敏诊断中的受限 Skill ID、版本和校验问题码；
- Settings、中文本地化、README 与工程文档完成 Skills 术语迁移。
- `ContextConfig`、按 Skill 的每次询问 / 始终允许 / 永不允许；
- 未授权前不读取选区，敏感应用在捕获前直接拒绝；
- 选区字符预算、AX 目标、UTF-16 范围和 SHA-256 摘要冻结；
- Context Rewrite 与 Context Reply；
- 本地 Source / Result / Diff Preview；
- `OutputRouter` 对 automatic、preview 和 copy-only 的本地强制；
- 替换前再次校验同一 AX 元素、选区范围和原文摘要；
- 选区变化时只复制并显示 `Copied — selection changed`；
- Retry 配置主动清除选区正文；
- 脱敏诊断只记录上下文能力枚举和字符数；
- 安装版视觉验收增加 Diff Preview 截图。

对应实现与验收说明见：

- `docs/engineering/hotkey-and-feedback.md`
- `docs/engineering/skill-runtime.md`
- `docs/engineering/context-and-preview.md`
- `scripts/feedback_mode_acceptance.sh`
- `scripts/visual_acceptance.sh`

Phase 4–6 仍按本文顺序执行。当前实现没有声称已经开放 Style Capsule、Terminology Packs、社区 Registry 或 Action Skills。

## 0. 执行结论

OpenWhisper 不应继续只被定义为“语音转文字工具”，而应升级为：

> **macOS 上由语音、上下文和可组合 Skills 驱动的 AI 输入层。**

用户不只是在“说一段文字”，而是在表达意图。OpenWhisper 应结合当前任务、用户明确授权的上下文、专业术语和个人风格，把口述内容转换成可以直接发送、提交、粘贴或继续编辑的产物。

本方案确定以下产品决策：

1. 保留现有“一个快捷键开始、同一个快捷键停止”的单触发工作流。
2. 默认快捷键仍为 `F5`，但用户可以在 Settings 中录制并保存自己的全局快捷键。
3. 现有固定 Voice Modes 逐步迁移为声明式 Skills；迁移期间保持配置向后兼容。
4. 社区 Skill v1 只允许声明式配置、提示词、术语、示例和校验规则，不允许执行任意 Swift、JavaScript、Python、Shell 或任意网络代码。
5. 上下文必须按能力显式授权；首个版本只优先支持“用户选中文本”，不默认读取整个窗口、屏幕或文档。
6. 输出继续服从现有安全回填边界；Skill 无权绕过粘贴验证、敏感应用限制或 copy-only 策略。
7. HUD 提供三种模式：
   - `Refined HUD`：默认，高级、紧凑、重新设计的标准状态框；
   - `Blue Signal Frame`：可选，冷蓝色克制跑马灯式边缘信号；
   - `Hidden`：完全隐藏视觉 HUD，仅保留可选声音和菜单栏状态。
8. Blue Signal 使用冷蓝、靛蓝、冰蓝和少量青色高光，不复制 Apple Intelligence 的彩虹、轨迹或品牌表达。
9. 第一阶段不做插件市场、不做常驻屏幕读取、不做任意 Action、不做自动执行 Shell/SQL、不做网站级深度适配。

## 1. 当前产品基线

### 1.1 已有可复用能力

OpenWhisper 已经具备 Skills Runtime 所需的大部分底座：

- 原生 AppKit + SwiftUI 菜单栏应用；
- 全局 `F5` 开始、再次 `F5` 停止；
- 麦克风录音、转写、术语对齐和可选 AI Polish；
- Direct、Reply、Email、Agent Plan、Code Prompt、Translate；
- 按精确 Bundle Identifier 选择 Voice Mode；
- 保守自动粘贴、确认插入、仅发送粘贴和剪贴板兜底；
- Retry、History、Recovery、诊断和隐私留存策略；
- 敏感应用排除；
- HUD 的 Recording、Processing、Success、Copied、Error、Retry；
- Reduce Motion、Increase Contrast 和 VoiceOver 状态播报；
- 安装版打包、安装、视觉验收和 TextEdit 粘贴验收。

### 1.2 当前实现与目标差距

| 能力 | 当前实现 | 目标 |
| --- | --- | --- |
| 触发热键 | 配置保存 `hotkeyKeyCode`，默认键码 `96`；UI 写死显示 `F5`；主热键未保存修饰键 | 可视化录制、自定义键码和修饰键、冲突检测、原子切换、失败回滚 |
| Voice Mode | 固定 Swift 枚举 | 可版本化、可安装、可测试的声明式 Skill |
| 应用规则 | 精确 Bundle Identifier | Bundle ID 继续作为稳定基础，未来再增加网站或工作区适配 |
| 上下文 | 不读取窗口或文档内容 | 用户显式授权的选区、局部文本、有限会话窗口和 Style Capsule |
| 术语 | 单一用户术语库 | 用户术语 + 可安装领域术语包 + Skill 私有术语 |
| AI Polish | 固定 Prompt Builder | 系统安全外壳 + Skill Prompt Compiler + 输出校验 |
| HUD | 固定 graphite 胶囊与九段波形 | Refined HUD、Blue Signal Frame、Hidden 三模式 |
| 社区扩展 | 无 | 可审计的 `.openwhisperskill` 声明式包 |

## 2. 产品定位

### 2.1 新品类定义

OpenWhisper 的长期品类不是输入法，也不是聊天机器人，而是：

> **Intent-to-Output Layer / 意图到产物的输入层**

```text
语音意图
+ 用户明确授权的上下文
+ 当前应用与任务
+ Skill、术语和个人风格
→ 可验证、可预览、可安全投递的结果
```

### 2.2 核心用户

优先服务：

- 使用 Codex、Cursor、Claude Code、Xcode、VS Code 的开发者；
- 产品经理、创始人、研究者和内容工作者；
- 中英文混输且经常使用技术术语的人；
- 需要快速完成邮件、Issue、PR、方案、回复和提示词的人；
- 希望拥有个人表达风格，但不希望应用常驻读取屏幕的人；
- 已经拥有 ChatGPT 账户、不想额外维护复杂模型配置的人。

### 2.3 核心价值

- **说完即可交付**：得到的不是粗糙转写，而是任务需要的结果。
- **同一句话因场景而不同**：在编码工具中成为开发任务，在邮件中成为完整邮件，在聊天中成为简短回复。
- **专业词汇稳定**：路径、命令、API、药名、产品名和缩写不被随意改写。
- **风格一致**：可选择自己的 Style Capsule，而不是每次重复描述语气。
- **权限透明**：用户知道本次读取了什么、发给了哪个模型、如何投递。
- **失败可恢复**：不能安全回填时保留到剪贴板，不能验证时不冒充成功。

## 3. 产品原则与非目标

### 3.1 产品原则

1. **一个动作完成一次输入**
   - 一个全局快捷键开始；
   - 同一个快捷键停止；
   - `ESC` 和 HUD 关闭按钮取消。
2. **默认最小权限**
   - Skill 默认只有 `voice`；
   - 选区、局部上下文、风格档案和外部动作分别授权。
3. **上下文由用户决定**
   - 不把“智能”建立在无提示读取整个屏幕之上。
4. **系统规则高于 Skill**
   - Skill 不能修改隐私、凭据、网络、粘贴和留存边界。
5. **高风险结果先预览**
   - 医疗、法律、财务、命令、SQL、外部写入默认不直接投递。
6. **输出必须可验证**
   - JSON、Markdown、代码块、模板字段和关键字面量应通过本地校验。
7. **向后兼容**
   - 旧 Voice Mode、`F5` 默认值、现有术语和历史记录不能因迁移失效。
8. **原生 Mac 体验优先**
   - Settings、快捷键录制、状态反馈、动画和无障碍应符合 macOS 交互习惯。

### 3.2 近期非目标

- 常驻监听或唤醒词；
- 默认读取整个屏幕；
- 任意代码插件；
- 任意文件系统访问；
- Skill 自行持有 ChatGPT 会话或 API Key；
- 自动执行 Shell、SQL、Git 或生产环境操作；
- 未经确认发送邮件、消息、Issue 或任务；
- 浏览器扩展和网站 DOM 深度读取；
- 团队知识库、企业审计后台和复杂权限中心；
- Windows、iOS、Android 同期开发。

## 4. 目标用户体验

### 4.1 普通听写

```text
聚焦输入框
→ 按自定义快捷键（默认 F5）
→ 录音
→ 再按同一快捷键
→ ASR + Direct Skill
→ 安全回填或剪贴板兜底
```

### 4.2 后端开发提示词

```text
在 Codex/Cursor 中触发
→ 自动解析当前 App 对应的 Backend Prompt Composer
→ 用户口述需求
→ 输出目标、背景、约束、实现步骤、边界情况、验收标准
→ 预览或安全回填
```

### 4.3 选中文本改写

```text
用户选中一段文本
→ 触发 OpenWhisper
→ 说“保持这个语气，缩短一半，但保留日期和数字”
→ Skill 只读取选区
→ 展示 Diff
→ 仅在同一 AX 元素、同一选区仍未变化时允许替换
→ 否则只复制结果
```

### 4.4 个人风格回复

```text
选择工作邮件 Style Capsule
→ 选中对方邮件中的必要段落
→ 口述回复意图
→ 输出符合用户工作风格的邮件正文
→ 预览确认
```

### 4.5 专业术语听写

```text
启用医学术语包
→ 口述药名、检查项和缩写
→ ASR 提示 + 确定性术语纠正
→ 只做转写和格式化，不补全诊断事实
→ 默认预览
```

## 5. Skills Runtime

### 5.1 Skill 不是一段 Prompt

一个 Skill 是一份可审计的“输入与输出契约”，至少包含：

- 身份：ID、名称、版本、作者、来源；
- 触发：手动选择、默认 Skill、应用规则、未来的 Skill 快捷键；
- 输入权限：语音、选区、局部上下文、会话窗口、Style Capsule；
- 知识资产：术语、纠正规则、模板、示例、禁用表达；
- 转换规则：Prompt、语言、结构、模型能力要求；
- 输出契约：纯文本、Markdown、JSON、代码块或结构化模板；
- 投递策略：自动回填、预览后回填、仅复制；
- 风险等级：低、中、高；
- 校验器：长度、格式、字面量、必填字段和禁止臆造；
- 测试：Golden cases、失败样例和兼容版本。

### 5.2 建议包结构

```text
BackendPrompt.openwhisperskill/
  skill.yaml
  prompt.md
  terminology.csv
  examples.jsonl
  validators.json
  localizations/
    en.json
    zh-Hans.json
  tests/
    golden.jsonl
```

### 5.3 Manifest 示例

```yaml
schemaVersion: 1
id: app.openwhisper.skill.backend-prompt
version: 1.0.0
name: Backend Prompt Composer
author: OpenWhisper
minimumAppVersion: 0.2.0

triggers:
  manual: true
  defaultForBundleIdentifiers:
    - com.openai.codex

permissions:
  required:
    - voice
  optional:
    - selection

context:
  maximumCharacters: 6000
  includeSelectionOnly: true

output:
  format: markdown
  delivery: previewThenPaste
  risk: medium

validators:
  preserveTechnicalLiterals: true
  maximumCharacters: 12000
  requireSections:
    - Goal
    - Constraints
    - Acceptance Criteria
```

Manifest 只能声明能力。它不能提升权限、指定任意文件路径、读取 Keychain、修改网络端点或关闭安全回填。

### 5.4 运行流水线

```text
全局热键
→ 创建 DictationSession
→ 冻结当前 App、目标和 Skill 解析结果
→ 按权限通过 Context Broker 收集上下文
→ 录音与 ASR
→ Technical Literal 保护
→ 用户术语 + 领域术语包 + Skill 术语
→ Skill Prompt Compiler
→ 模型转换
→ 本地 Validator Engine
→ Diff / Preview / Output Router
→ 确认插入、发送粘贴或剪贴板兜底
→ History / Recovery / 脱敏指标
```

### 5.5 Skill 解析优先级

从高到低：

1. 用户本次手动选择；
2. 当前 App 的用户规则；
3. 当前工作区规则，未来能力；
4. 全局默认 Skill；
5. 内置 `Direct`。

Skill 在录音开始时冻结，避免录音期间切换 App 导致 Prompt、权限或投递策略变化。

### 5.6 内置 Skills

#### 第一批：高频核心

1. **Direct**
   - 保留说话顺序和语气；
   - 去除口头禅和已被后续修正的内容；
   - 不擅自改成计划或邮件。
2. **Reply**
   - 生成简洁自然的聊天回复；
   - 不添加未说出的事实、称呼或签名。
3. **Email**
   - 生成完整邮件正文；
   - 保留人名、日期、附件、请求和约束。
4. **Backend Prompt Composer**
   - 输出目标、背景、约束、接口、边界、步骤和验收标准；
   - 面向 Codex、Cursor、Claude Code 等编码代理。
5. **Code Prompt**
   - 强保护路径、命令、参数、类名、方法名、版本和错误信息。
6. **Translate / Localize**
   - 支持“中文需求 → 英文 GitHub Issue”“中文口述 → 英文商务邮件”等目标语境；
   - 不只做逐字直译。

#### 第二批：工作流

- Bug Triage；
- Git Commit / PR Description；
- API Contract；
- Issue / Standup / ADR；
- Meeting Action Items；
- Audience Rewrite；
- Context Reply；
- Style Rewrite；
- Customer Support；
- Sales Follow-up。

#### 第三批：专业术语

- Medical Terminology；
- Legal Draft Formatting；
- Finance Notes；
- Recruiting Feedback；
- Kubernetes / FastAPI / iOS / macOS 等技术术语包。

专业 Skill 的默认边界：

- 不诊断；
- 不补充未提供事实；
- 不自动执行；
- 默认预览；
- 显示“需要专业人员复核”；
- 保留数值、单位、日期、药名、条款和专有名词。

### 5.7 Skill 组合

v1 只允许受控的线性组合：

```text
基础 Skill
→ 术语包
→ 可选 Style Capsule
→ 输出 Validator
```

示例：

```text
Backend Prompt Composer
+ FastAPI 术语包
+ 团队技术写作 Style Capsule
→ Markdown 开发任务
```

暂不允许社区 Skill 任意调用另一个 Skill，避免循环、权限膨胀和不可预测的多轮成本。

### 5.8 Skill 调试与测试

官方和社区作者需要一个本地 Skill Inspector：

- 显示最终解析到的 Skill 和版本；
- 显示本次请求的权限；
- 显示实际提供的上下文类别和字符数，不默认展示敏感正文；
- 显示编译后的系统约束、Skill Prompt 和输出契约；
- 运行 Golden cases；
- 显示 Validator 失败原因；
- 测试不同语言、空输入、超长输入和技术字面量；
- 导出不含用户正文的诊断。

## 6. Context Broker：上下文权限系统

### 6.1 权限能力

权限不是简单的“允许读取屏幕”，而是独立能力：

| 权限 | 内容 | 默认 |
| --- | --- | --- |
| `voice` | 当前录音转写 | 必需 |
| `selection` | 用户明确选中的文本 | 关闭，按 Skill 授权 |
| `focusedParagraph` | 当前焦点附近的有限文本 | 关闭 |
| `conversationWindow` | 受支持应用中最近有限条目 | 关闭 |
| `clipboard` | 当前剪贴板文本 | 关闭 |
| `styleCapsule` | 用户选择的风格档案 | 关闭，按 Skill 选择 |
| `externalAction` | 创建、发送或更新外部对象 | v1 不支持 |

### 6.2 上下文授权卡

安装或首次运行 Skill 时显示：

> Backend Prompt Composer 将读取：
> - 本次语音
> - 当前选中文本，最多 6,000 字符
>
> 不会读取：
> - 其他文件
> - 终端历史
> - 完整屏幕
> - 剪贴板
>
> 输出方式：预览后回填

用户可以：

- 允许一次；
- 始终允许此 Skill；
- 拒绝并仅使用语音；
- 打开 Settings 查看和撤销权限。

### 6.3 最小化规则

- 只读取完成任务所需的最小范围；
- 每种上下文有字符数上限；
- 上下文在会话结束后释放，不进入普通诊断；
- History 默认只保存最终结果，不保存上下文正文；
- Skill 只能得到 Context Broker 返回的快照，不能直接调用 Accessibility API；
- Provider 请求中不发送完整应用规则表、安装 Skill 列表或无关 App 信息；
- 应用名称、Bundle ID 和上下文类别只在需要解析 Skill 时本地使用。

### 6.4 敏感应用

密码管理器、Keychain、系统“密码”、用户添加的敏感 App 默认：

- 只允许 `voice`；
- 禁止 `selection`、`focusedParagraph`、`conversationWindow` 和 `clipboard`；
- 禁止 History 和 Recovery 正文；
- 禁止自动回填，除非现有安全策略明确允许且用户单独覆盖；
- Blue Signal 和 Refined HUD 不显示转写正文。

### 6.5 选中文本安全替换

选中文本改写必须满足：

1. 录音开始时记录 AX 元素身份、选区范围和选中文本摘要；
2. 结果返回时重新确认是同一 AX 元素；
3. 选区范围和原文本未发生变化；
4. 当前目标仍是可编辑目标；
5. Skill 投递策略允许替换；
6. 高风险 Skill 已经预览确认。

任何条件不满足时：

- 不自动替换；
- 保留结果到剪贴板；
- HUD 明确显示 `Copied — selection changed`；
- Preview 中允许用户重新选择目标。

### 6.6 网站与会话上下文

第一阶段只使用 Bundle Identifier 和 Accessibility 可证明的选区。网站域名、网页 DOM、聊天线程和编辑器工作区属于后续适配层。

引入时必须满足：

- 使用显式浏览器扩展或受支持适配器；
- 用户知道正在读取哪个网站和哪一段内容；
- 不把浏览器历史、其他标签页或完整页面默认发送给模型；
- 网站规则与 App 规则分开授权；
- 不因网页内容中的提示词改变系统权限或输出安全策略。

## 7. Style Capsule：个人风格胶囊

### 7.1 产品定义

Style Capsule 是用户主动创建、可查看、可编辑、可删除的个人表达档案，而不是隐式抓取历史。

一个 Capsule 可以描述：

- 正式程度；
- 句子长度；
- 技术密度；
- 是否使用项目符号；
- 常用称呼和结尾；
- 中英文比例；
- 偏好的礼貌程度；
- 常用术语；
- 禁用词和不喜欢的表达；
- 示例片段。

### 7.2 创建流程

```text
用户选择 5–30 段自己的文本
→ 显示将发送给哪个模型
→ 生成可读的风格摘要
→ 用户编辑和确认
→ 保存 Capsule
→ 默认删除源文本，仅保存风格摘要和用户保留的示例
```

建议预置：

- Work Formal；
- Team Chat；
- Technical Writing；
- English Business；
- Personal Casual。

### 7.3 边界

- 不自动扫描邮件、消息或文档；
- 不建立第三方作者模仿库；
- 不把 Style Capsule 当作事实来源；
- 不覆盖 Skill 的必填结构和安全规则；
- Capsule 在本机可导出和删除；
- 原始样本文本是否保留必须单独选择，默认不保留。

## 8. Terminology Packs

现有 Terminology Dictionary 演进为三层：

1. **Personal Dictionary**
   - 用户自己的产品名、人名、缩写和纠正规则。
2. **Domain Pack**
   - 医学、法律、Kubernetes、FastAPI、Apple 平台等可安装词库。
3. **Skill-local Terminology**
   - 仅在特定 Skill 中生效的模板字段和专有表达。

合并优先级：

```text
用户显式纠正规则
> Skill 私有词条
> 用户普通术语
> 领域包术语
> ASR 原始结果
```

冲突必须在安装或启用时可见，不能静默覆盖用户词条。

## 9. 输出、预览与安全投递

### 9.1 输出类型

- `plainText`
- `markdown`
- `code`
- `json`
- `template`
- `actionPreview`，未来能力

### 9.2 投递策略

| 策略 | 行为 | 适用 |
| --- | --- | --- |
| `automaticPasteWhenVerified` | 沿用现有安全回填；无法证明时复制 | Direct、低风险 Reply |
| `previewThenPaste` | 展示结果或 Diff，确认后投递 | Backend Prompt、邮件、上下文改写 |
| `copyOnly` | 永不自动回填 | Shell、SQL、Retry、高风险专业 Skill |

### 9.3 Preview

Preview 至少支持：

- 原始转写与最终结果切换；
- 文本 Diff；
- 重新运行；
- 切换 Skill；
- 切换 Style Capsule；
- 复制；
- 替换选区；
- 插入到光标；
- 报告“不是我的风格”；
- 显示本次读取的上下文类别；
- 显示结果是否通过 Validator。

Preview 不是每次都出现。Direct 的低风险短输入继续追求低延迟自动回填。

### 9.4 Validator

首批本地校验：

- 最大长度；
- 非空；
- JSON 可解析；
- Markdown 代码围栏闭合；
- 必填章节存在；
- 技术字面量全部且只出现一次；
- 日期、数字、路径、命令和版本未丢失；
- 禁止出现 Skill 声明之外的事实补全提示；
- 高风险输出必须进入 Preview；
- 输出不包含内部 Prompt 或上下文标记。

Validator 失败时不直接投递，可：

- 以更严格 Prompt 重试一次；
- 回退到原始 ASR；
- 只复制并提示校验失败；
- 保留 Recovery 信息，但不记录上下文正文。

## 10. 社区 Skill 生态

### 10.1 分阶段模型

#### Phase A：官方 Skills

- 随 App 发布；
- 完整测试；
- 双语本地化；
- 明确权限和风险；
- 与 App 版本一起回归。

#### Phase B：本地导入

- 用户导入 `.openwhisperskill`；
- 安装前查看作者、版本、权限、文件清单和示例；
- App 解包到自己的受控目录；
- 拒绝软链接、路径穿越、超大文件和未知可执行内容；
- 支持禁用、卸载和版本回滚。

#### Phase C：社区 Registry

- GitHub 仓库式分发；
- 版本锁定；
- 内容哈希；
- 作者签名；
- 权限和兼容性扫描；
- 可复现测试集；
- 安全报告和下架机制。

#### Phase D：认证发布者

- 开源项目、公司、医院或专业组织维护；
- 认证只证明发布者和包完整性，不承诺模型输出永远正确；
- 专业 Skill 继续要求人工复核。

### 10.2 v1 安全边界

社区 Skill 不得：

- 执行代码；
- 启动进程；
- 读取任意文件；
- 读取 Keychain；
- 自定义网络请求；
- 修改 Provider；
- 修改系统 Prompt 安全外壳；
- 绕过敏感应用；
- 自动发送或执行动作；
- 修改 History、Recovery、诊断和产品指标策略。

社区内容被视为不可信数据。即使 `prompt.md` 要求“忽略 OpenWhisper 规则”，运行时也只能在系统固定安全外壳内生效。

### 10.3 未来 Action Skills

连接 GitHub、Linear、Notion、Jira、Slack 或 MCP 属于后续阶段，必须：

- 使用独立 Connector 权限；
- 凭据进入 Keychain；
- 先生成 Action Preview；
- 用户逐次确认；
- 显示将写入的账号、空间、对象和字段；
- 支持撤销时优先提供撤销；
- 不允许 Skill 直接得到通用 Shell 或文件系统权限。

## 11. Blue Signal 视觉反馈系统

### 11.1 设计目标

视觉关键词：

- 安静；
- 精密；
- 冷静；
- 原生；
- 有高级感；
- 状态明确但不抢内容；
- 像 AI 系统正在工作，而不是传统录音软件的均衡器。

不做：

- 彩虹边框；
- Siri 波球；
- 大面积持续呼吸；
- 夸张音频波形；
- 高频闪烁；
- 大段实时转写正文；
- 复制 Apple Intelligence 的具体轨迹、颜色或品牌识别。

### 11.2 三种显示模式

#### A. Refined HUD — 默认

重新设计当前标准状态框，作为最稳妥的默认体验。

- 位置：屏幕顶部居中，支持多显示器的当前活跃显示器；
- 外形：单层紧凑胶囊，不使用卡片套卡片；
- 推荐尺寸：
  - Recording / Processing：`272–300 x 42–46`
  - Error / Retry：宽度上限 `340`，高度不超过 `60`
- 圆角：`14–16`
- 背景：近黑蓝 graphite，轻微材质感，不使用厚重毛玻璃；
- 边框：`1 px` 冷色低对比边线；
- 状态视觉：精细线性信号、微型声纹或一条移动高光；
- 文本：只显示状态、计时和必要动作；
- Recording、Processing、Success 保持稳定几何，避免宽度跳变；
- Retry 和错误只在需要时增加第二行。

#### B. Blue Signal Frame — 可选

围绕当前活跃显示器显示极细的冷蓝边缘信号。

- 默认目标：当前活跃显示器边缘；
- 可选目标：当前焦点窗口，作为实验设置；
- 基础线宽：`1–1.5 px`；
- 高光线宽：不超过 `2 px`；
- 只让一小段蓝青高光沿边缘移动，底层边框保持低亮度；
- 录音时低速、检测到人声时局部增强；
- 处理中转为更连续的数据扫描；
- 成功时向一个点收束后淡出；
- Copied、Error 和 Retry 仍需要小型文字提示，不能只靠颜色；
- 多显示器只显示在会话开始时冻结的目标显示器上。

#### C. Hidden

完全不显示视觉 HUD。

仍可保留：

- 可选开始、停止、成功、复制和失败声音；
- 菜单栏图标状态；
- 可选完成通知；
- 错误时的系统通知。

Hidden 不影响 `ESC` 取消、同快捷键停止、Retry 和剪贴板结果。

### 11.3 颜色 Token

```text
Base Ink        #0B1020
Graphite Blue   #151B2B
Deep Blue       #163B8C
Signal Blue     #2F6BFF
Electric Blue   #5EA2FF
Ice Highlight   #B8DCFF
Accent Cyan     #71E4F3
Success         #59D69E
Copied Amber    #F3A75F
Error Rose      #E86B7A
Primary Text    #F2F6FC
Secondary Text  #B8C3D4
```

使用规则：

- 80% 视觉由 Base Ink、Graphite Blue 和低亮度 Deep Blue 构成；
- Signal Blue 到 Accent Cyan 只作为局部移动高光；
- 不把完整渐变铺满整个边框；
- Success、Copied、Error 保留独立图标和文字；
- 高对比度模式提高边框和文字对比，不增加动画强度。

### 11.4 状态动作语言

| 状态 | Refined HUD | Blue Signal Frame | 建议时长 |
| --- | --- | --- | --- |
| Start | 胶囊快速淡入，信号点亮 | 边缘从一个点展开 | `150–220 ms` |
| Recording | 低频声纹或线性流动，显示计时 | 慢速局部高光；人声时轻微增强 | 循环 `3–5 s` |
| Stop | 信号向右收束 | 边缘高光向一处收束 | `180–260 ms` |
| Transcribing | 单层扫描，不跳尺寸 | 连续低亮扫描 | 循环 `3–5 s` |
| Skill Processing | 第二层细线出现，不提高整体亮度 | 双层错位低速流动 | 循环 `4–6 s` |
| Inserted | 冰蓝闪烁转绿色确认后淡出 | 收束点短暂变绿 | `500–700 ms` |
| Paste Sent | 方向箭头和明确文字 | 小型提示，不只用边框 | `1.2–1.8 s` |
| Copied | 剪贴板图标和琥珀色 | 右下或顶部小提示 | `1.5–2.5 s` |
| Cancelled | 快速降低亮度并退出 | 反向收束 | `180–260 ms` |
| Error | 停止循环，显示原因 | 边缘停止并显示错误提示 | 至少 `5 s` |
| Retryable Error | 保持可见，提供 Retry | 边缘低亮 + 固定 Retry 提示 | 直到操作 |

### 11.5 音频响应

动画不绘制传统实时频谱。只从音量包络提取低频状态：

- 静音时保持基础亮度；
- 人声活动只改变局部亮度、线宽或流速的 `5–15%`；
- 不按每个采样点抖动；
- 使用平滑、限幅和最小变化阈值；
- UI 刷新目标不超过 `30 fps`，Reduce Motion 下不持续刷新。

### 11.6 设置项

Settings → Appearance & Feedback：

- Visual feedback
  - Refined HUD，默认
  - Blue Signal Frame
  - Hidden
- Intensity
  - Subtle
  - Standard
  - Expressive
- Frame target
  - Active display，默认
  - Focused window，实验
- Show status text
- Feedback sounds
- Completion notification
- Follow macOS Reduce Motion，默认开启
- Always reduce motion
- Increase contrast follows macOS，始终开启
- Preview Recording / Processing / Copied / Error

### 11.7 无障碍与隐私

- Reduce Motion：移动高光变为静态渐变或一次性淡入淡出；
- Increase Contrast：提高轮廓和文字，不依赖透明度；
- VoiceOver：播报 Listening、Processing、Inserted、Paste Sent、Copied、Error；
- 状态不能只靠颜色区分；
- HUD 不显示完整转写正文；
- 录屏或屏幕共享用户可快速切换 Hidden；
- 多显示器、全屏 App、Stage Manager 和 Spaces 必须安装版验收；
- Blue Signal Frame 不能抢键盘焦点或阻断鼠标事件。

### 11.8 性能目标

- HUD 出现不阻塞录音开始；
- 动画主线程平均开销应低于一帧预算的 `10%`；
- 空闲状态不保留显示循环；
- Hidden 模式不创建可见窗口；
- Blue Signal Frame 不对整屏做实时截图或模糊；
- 降低能耗时自动减少刷新频率，但不能改变状态语义。

## 12. 可自定义全局热键

### 12.1 产品行为

- 默认：`F5`；
- 用户可以改为其他安全的全局组合；
- 同一个快捷键负责开始和停止；
- `ESC` 继续取消；
- HUD inline close 继续取消；
- 快捷键改变不改变录音、处理、Retry 和安全粘贴语义；
- App 内所有提示动态显示当前快捷键，不再写死 `F5`。

### 12.2 设置交互

Settings → Dictation：

```text
Dictation shortcut      [ F5 ] [Record Shortcut…]
                        Press the shortcut you want to use

                        [Restore F5]
```

录制流程：

1. 点击 `Record Shortcut…`；
2. 控件进入捕获态；
3. 用户按下组合；
4. 本地规则先检查；
5. 尝试临时注册；
6. 成功后才保存并切换；
7. 冲突时显示原因，旧快捷键继续有效；
8. `ESC` 退出捕获，不影响当前配置。

### 12.3 允许规则

建议支持：

- 单独的 `F1–F19`；
- 带 `⌃`、`⌥` 或 `⌘` 的字母、数字、标点和空格；
- `⇧` 可作为附加修饰键，但不能作为可打印键的唯一修饰键；
- 多修饰键组合；
- 国际键盘布局下按物理键码保存，显示名称按当前布局派生。

建议拒绝：

- 无修饰键的字母、数字、空格、回车、Tab、Delete 和方向键；
- 单独 `ESC`；
- `⌘Q`、`⌘W`、`⌘C`、`⌘V`、`⌘X`、`⌘Z`、`⌘A`；
- `⌘Tab`、`⌘Space` 等明显系统级组合；
- 与 OpenWhisper Quick Add 或其他内部快捷键冲突的组合；
- Carbon 无法稳定注册的媒体键；
- 仅包含修饰键、不包含主键的输入。

系统组合无法完全靠静态列表判断，因此最终以真实 `RegisterEventHotKey` 结果为准。

### 12.4 配置模型

当前只保存 `hotkeyKeyCode`。目标模型：

```swift
struct HotkeyBinding: Codable, Sendable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

struct TranscriptionConfig {
    var dictationHotkey: HotkeyBinding = .f5
}
```

显示文本不持久化，由键码、修饰键和当前键盘布局派生，避免切换布局后出现错误文案。

兼容迁移：

```text
旧配置存在 hotkeyKeyCode
→ 迁移为 keyCode = hotkeyKeyCode, modifiers = 0
→ 默认仍为 F5
```

在一个兼容周期内继续解码旧字段；新版本只写入新结构。

### 12.5 原子注册与回滚

切换必须是事务式：

```text
保留旧 HotkeyMonitor
→ 校验候选 Binding
→ 尝试创建候选 HotkeyMonitor
→ 成功：保存配置并释放旧 Monitor
→ 失败：释放候选，保留旧 Monitor 和旧配置
```

启动时：

1. 尝试注册用户快捷键；
2. 失败时尝试回退到 `F5`；
3. 回退成功则显示一次可操作提示，并要求用户重新选择；
4. `F5` 也失败时，应用保持菜单栏可用，提供 `Start Dictation` 菜单动作和修复入口；
5. 不能因为快捷键失败而终止应用或丢失设置。

### 12.6 动态文案

以下文案必须从 `HotkeyBinding.displayName` 生成：

- Onboarding；
- Settings；
- Menu Bar；
- Ready 状态；
- HUD 辅助提示；
- 权限引导；
- 通知；
- README 和帮助页中的默认描述。

示例：

```text
Ready. Press F5 to dictate.
Ready. Press ⌃⌥D to dictate.
Press ⌃⌥D again to transcribe.
```

文档可以说明默认是 `F5`，运行时 UI 不能继续硬编码。

### 12.7 与输入法、系统和内部快捷键的冲突

- 注册前检测 OpenWhisper 内部冲突；
- 注册失败时显示“已被其他应用或系统占用”，不猜测具体占用者；
- Quick Add 当前 `⌃⌥Space` 保持不变，直到独立快捷键管理页面完成；
- 如果用户把主热键设置为 Quick Add，阻止保存；
- 系统输入源切换、Spotlight、Mission Control 和媒体功能键应进入验收矩阵；
- 外接键盘和 MacBook 键盘分别验证；
- F5 作为默认值必须继续通过完整安装版验收。

### 12.8 未来扩展

不进入第一个版本：

- 每个 Skill 独立全局快捷键；
- Push-to-talk；
- 双击快捷键；
- 长按快捷键；
- 语音唤醒；
- 键盘序列。

这些交互会破坏当前简单状态机，应在主热键稳定后单独设计。

## 13. Settings 信息架构

建议目标结构：

1. **Account & Permissions**
   - ChatGPT；
   - Microphone；
   - Accessibility；
   - Setup Guide。
2. **Dictation**
   - 自定义快捷键；
   - ASR；
   - 语言；
   - 标点；
   - 录音上限。
3. **Skills**
   - 默认 Skill；
   - 已安装 Skills；
   - App Rules；
   - Skill Inspector；
   - 导入 Skill。
4. **Context**
   - 各 Skill 权限；
   - 敏感 App；
   - 选区和局部上下文；
   - Style Capsules。
5. **Terminology**
   - Personal Dictionary；
   - Domain Packs；
   - 冲突处理。
6. **Appearance & Feedback**
   - Refined HUD / Blue Signal Frame / Hidden；
   - 强度、位置、文字、声音和无障碍。
7. **Output**
   - 自动回填；
   - Preview；
   - 剪贴板策略；
   - 高风险默认策略。
8. **Privacy**
   - History；
   - Raw ASR；
   - Recovery；
   - Diagnostics；
   - Product Metrics；
   - Delete All Data。
9. **Advanced**
   - OpenAI-Compatible Recovery；
   - Diagnostics Export；
   - Updates；
   - Licenses。

为避免 Settings 过度膨胀：

- History、Terminology 和 Skill Inspector 可继续使用独立窗口；
- 侧边栏只显示高频配置；
- 社区 Registry 不进入初版 Settings；
- 高级恢复路线继续保持 Advanced，不成为默认故事。

## 14. 目标技术架构

### 14.1 新增核心组件

```text
HotkeyBinding
HotkeyRecorderView
HotkeyRegistrationService

SkillRegistry
SkillPackageLoader
SkillResolver
SkillPromptCompiler
SkillValidatorEngine
SkillPermissionStore

ContextBroker
SelectionContextProvider
StyleCapsuleStore

PreviewController
OutputRouter

VisualFeedbackConfig
FeedbackSurfaceController
RefinedHUDController
BlueSignalFrameController
HiddenFeedbackController
```

### 14.2 模块职责

#### `HotkeyRegistrationService`

- 规范化键码和修饰键；
- 静态冲突检查；
- 调用现有 Carbon 注册；
- 原子替换 Monitor；
- 启动回退；
- 向 UI 提供明确错误。

#### `SkillRegistry`

- 加载内置和本地 Skills；
- 版本和兼容性解析；
- 禁用、回滚和卸载；
- 不执行包内代码；
- 将社区文件视为不可信输入。

#### `SkillResolver`

- 根据手动选择、Bundle ID 规则和默认 Skill 解析；
- 在录音开始时冻结；
- 输出单个 `ResolvedSkillExecutionPlan`；
- 不把完整规则表发送给 Provider。

#### `ContextBroker`

- 只通过已授权 Provider 收集上下文；
- 强制字符预算；
- 应用敏感 App 策略；
- 记录类别和长度，不记录正文；
- 会话结束释放快照。

#### `SkillPromptCompiler`

按固定顺序编译：

```text
OpenWhisper 系统安全与事实保真规则
→ 输出契约
→ Skill 指令
→ Style Capsule
→ 术语
→ 标记为数据的上下文
→ 当前转写
```

Skill 不能把自己插入到系统安全规则之前。

#### `SkillValidatorEngine`

- 在本地验证结构和关键字面量；
- 不允许 Skill 自带可执行 Validator；
- Validator 只来自 App 支持的声明式规则集合；
- 校验失败进入可控重试或回退。

#### `FeedbackSurfaceController`

- 对上层暴露统一状态；
- 根据配置切换 Refined HUD、Blue Signal Frame 或 Hidden；
- 不让业务状态机依赖具体视图；
- Hidden 仍执行 VoiceOver、声音和通知策略。

### 14.3 建议数据模型

```swift
struct SkillsConfig: Codable {
    var defaultSkillID: String
    var applicationRules: [AppSkillRule]
    var enabledSkillIDs: Set<String>
}

struct AppSkillRule: Codable, Identifiable {
    var id: UUID
    var appName: String?
    var bundleIdentifier: String
    var skillID: String
    var isEnabled: Bool
}

struct SkillPermissionGrant: Codable {
    var skillID: String
    var capability: SkillCapability
    var scope: PermissionScope
}

struct VisualFeedbackConfig: Codable {
    var mode: VisualFeedbackMode
    var intensity: VisualFeedbackIntensity
    var frameTarget: FrameTarget
    var showStatusText: Bool
    var completionNotificationEnabled: Bool
}
```

### 14.4 本地存储

建议目录：

```text
~/Library/Application Support/OpenWhisper/
  Skills/
    Installed/
    Cache/
    Registry/
  StyleCapsules/
  TerminologyPacks/
  config.json
```

规则：

- 目录 `0700`；
- 文件 `0600`；
- 安装包解压拒绝路径穿越和软链接；
- 包大小、文件数量和单文件大小有硬限制；
- 不从 Skill 目录加载动态库或可执行文件；
- Delete All Data 同时删除 Skills、Capsules、Packs 和权限授权；
- 导出诊断不包含 Prompt、上下文正文、Capsule 示例或社区包正文。

### 14.5 Voice Mode 兼容迁移

迁移表：

| 旧模式 | 内置 Skill ID |
| --- | --- |
| `direct` | `app.openwhisper.skill.direct` |
| `reply` | `app.openwhisper.skill.reply` |
| `email` | `app.openwhisper.skill.email` |
| `agentPlan` | `app.openwhisper.skill.agent-plan` |
| `codePrompt` | `app.openwhisper.skill.code-prompt` |
| `translate` | `app.openwhisper.skill.translate` |

迁移要求：

- 自动迁移默认模式和 App 规则；
- 未知 Skill 回退 Direct；
- 旧配置至少支持一个版本周期；
- History 中保留旧模式名称，不重写历史；
- Provider 不接收完整 Skill Registry。

## 15. 分阶段实施路线

### Phase 0 — 决策与视觉原型

交付：

- 本方案评审；
- Refined HUD 和 Blue Signal Frame 的静态稿与动效原型；
- 快捷键录制控件原型；
- Skill Manifest JSON Schema 草案；
- 隐私与权限文案。

退出条件：

- 确认三种 HUD 模式；
- 确认默认仍为 F5；
- 确认声明式 Skill 边界；
- 确认首批内置 Skills。

### Phase 1 — 交互基础：自定义热键与新 HUD

交付：

- `HotkeyBinding`；
- 快捷键录制、冲突检测、原子注册和回退；
- 所有运行时 `F5` 文案动态化；
- Refined HUD；
- Blue Signal Frame；
- Hidden；
- Appearance & Feedback 设置；
- 安装版视觉、快捷键和无障碍验收。

退出条件：

- 默认 F5 行为完全不回退；
- 自定义快捷键重启后仍生效；
- 冲突不会破坏旧快捷键；
- 三种 HUD 模式覆盖完整状态；
- 正常安装版最终保持运行。

### Phase 2 — Skill Runtime 内核（已完成）

交付：

- 内置 Skill Registry；
- Voice Mode 迁移；
- Skill Resolver；
- Prompt Compiler；
- Validator Engine；
- App Rules 迁移；
- Direct、Reply、Email、Backend Prompt、Code Prompt、Translate。

退出条件：

- 旧配置无损迁移；
- Direct 性能不明显回退；
- Skill 不能绕过输出和隐私规则；
- Golden tests 全绿。

### Phase 3 — 选区上下文与 Preview（已完成）

交付：

- `selection` 权限；
- 选区捕获和同目标安全替换；
- Diff Preview；
- Context Rewrite；
- Context Reply；
- 权限卡和撤销入口。

退出条件：

- 选区变化时绝不自动覆盖；
- 敏感 App 默认拒绝；
- 无 Accessibility 时稳定 copy-only；
- TextEdit、Notes、浏览器编辑器和 Codex 的安装版矩阵有明确结果。

### Phase 4 — Style Capsule 与 Terminology Packs

交付：

- Capsule 创建、编辑、选择、删除和导出；
- 用户样本默认不保留；
- Domain Pack；
- 冲突处理；
- Backend、Medical、Kubernetes 等示例包。

退出条件：

- 用户可读懂 Capsule；
- 删除后无残留；
- 术语优先级确定；
- 专业 Skill 默认 Preview。

### Phase 5 — 本地社区 Skill

交付：

- `.openwhisperskill` 导入；
- 包校验；
- 权限审查；
- 禁用、卸载、回滚；
- Skill Inspector；
- SDK 文档和模板仓库。

退出条件：

- 任意代码无法执行；
- 路径穿越、软链接和超大包被拒绝；
- 权限和版本不兼容清晰可见；
- 恶意 Prompt 不能改变系统边界。

### Phase 6 — Registry 与 Action 研究

在核心体验和安全模型稳定后再进入：

- 社区 Registry；
- 发布者签名；
- 认证发布者；
- Connector 和 Action Preview；
- GitHub、Linear、Notion 等有限集成。

## 16. 建议 MVP

首个 AI-native 可用版本只包含：

- 可自定义主听写快捷键，默认 F5；
- Refined HUD、Blue Signal Frame、Hidden；
- Direct、Reply、Email、Backend Prompt、Code Prompt、Translate；
- App → Skill 规则；
- Personal Dictionary；
- 只支持用户选区的上下文权限；
- Diff Preview；
- Style Capsule 先作为实验功能；
- 高风险 Skill 默认 Preview 或 copy-only；
- 不开放社区导入；
- 不开放 Action。

这已经足以证明：

> OpenWhisper 能把“跨应用听写”升级为“跨应用任务输出”，而不需要先承担插件市场和自动化平台的全部风险。

## 17. 验收标准

### 17.1 自定义热键

- 新安装默认 `F5`；
- `F5` 开始、`F5` 停止；
- 可设置例如 `⌃⌥D`；
- 重启后仍为 `⌃⌥D`；
- 同一个 `⌃⌥D` 开始和停止；
- `ESC` 取消；
- 冲突组合不能保存；
- 注册失败时旧快捷键继续有效；
- 配置损坏时回退 F5；
- Onboarding、Settings、Menu 和 Ready 状态显示当前快捷键；
- Quick Add 冲突被阻止；
- 外接键盘和内置键盘均通过；
- 安装版而非 `dist` 完成验证。

### 17.2 Skills

- Voice Mode 配置自动迁移；
- 每个 Skill 有稳定 ID 和版本；
- Bundle ID 规则正确解析；
- 录音中切换 App 不改变本次 Skill；
- 技术字面量不丢失；
- Validator 失败不会自动投递；
- 未知或损坏 Skill 回退 Direct；
- Skill 无法访问未授权上下文。

### 17.3 Context

- 未授权时不读取选区；
- 允许一次和始终允许行为不同；
- 权限可撤销；
- 敏感 App 默认拒绝；
- 上下文不进入普通诊断；
- 选区改变后 copy-only；
- 同一选区保持时可验证替换；
- 无 Accessibility 时行为清晰。

### 17.4 HUD

- Refined HUD 覆盖 Recording、Processing、Inserted、Paste Sent、Copied、Error、Retry；
- Blue Signal Frame 覆盖相同状态；
- Hidden 不创建可见 HUD；
- Reduce Motion 无持续跑马灯；
- Increase Contrast 状态清晰；
- VoiceOver 播报完整；
- 多显示器位置正确；
- 全屏、Spaces、Stage Manager 下不抢焦点；
- Copied 与 Inserted 不能只靠颜色区分；
- 错误至少显示五秒，Retry 保持可操作；
- 视觉验收使用 `/Applications/OpenWhisper.app`。

### 17.5 输出安全

- Direct 继续使用现有安全回填；
- 无可编辑目标时复制；
- 无法验证时保留剪贴板；
- Retry copy-only；
- 高风险 Skill 不自动回填；
- 选区替换验证同一 AX target、范围和文本；
- Clipboard 恢复继续服从现有 ownership 验证。

## 18. 测试与验收矩阵

### 18.1 自动化

- `HotkeyBinding` 编解码和旧配置迁移；
- 修饰键规范化；
- 禁止组合；
- 注册服务状态机；
- Skill Manifest 解码、版本、大小和路径校验；
- Voice Mode → Skill 迁移；
- Skill Resolver 优先级；
- Context 权限；
- 敏感 App；
- Prompt 编译顺序；
- Validator；
- VisualFeedbackConfig；
- Reduce Motion 状态模型；
- Preview 和 Output Router。

### 18.2 安装版交互

必须覆盖：

- 默认 F5；
- 自定义快捷键；
- 切换快捷键时冲突；
- Recording → Stop；
- Recording → ESC；
- Recording → inline close；
- Processing → ESC；
- Error → Retry；
- Refined HUD；
- Blue Signal Frame；
- Hidden；
- TextEdit 插入；
- Codex/浏览器编辑器的已发送粘贴或确认插入；
- 选区未变化替换；
- 选区变化 copy-only；
- 多显示器；
- Reduce Motion；
- Increase Contrast；
- VoiceOver。

关闭任务前：

- 重新安装最新构建；
- 正常启动 `/Applications/OpenWhisper.app`；
- 确认菜单栏进程仍在；
- 如果本次修改 Settings 或 Skills，尽量让对应窗口可见；
- 不以退出应用作为最终状态。

## 19. 隐私、指标与质量评估

### 19.1 本地优先指标

继续沿用产品指标默认关闭、不自动上传的原则。可选指标只记录：

- Skill ID 的受限官方枚举或“community”，不记录社区包名称；
- Skill 执行成功、校验失败、回退；
- Preview 接受、复制、取消；
- Context 权限类别，不记录正文；
- HUD 模式；
- 快捷键注册成功或失败类别，不记录具体组合；
- 插入、发送粘贴、剪贴板；
- 延迟区间。

不得记录：

- 语音或文本内容；
- 选区正文；
- Style Capsule 内容；
- App 名称和 Bundle ID；
- 快捷键具体按键；
- 账户、路径、域名或文件名；
- 社区 Prompt。

### 19.2 产品质量指标

- 首次成功听写时间；
- 自定义快捷键设置成功率；
- Direct 低延迟完成率；
- Skill 输出 Validator 通过率；
- Preview 接受率；
- 用户手动切回 Direct 的比例；
- 选区替换确认率；
- Copied 与 Paste Sent 比例；
- “不是我的风格”反馈率；
- HUD 模式使用分布；
- 取消和 Retry 成功率。

## 20. 主要风险与缓解

| 风险 | 缓解 |
| --- | --- |
| Skills 变成 Prompt 收藏夹 | 强制输入、权限、输出、Validator 和测试契约 |
| 社区包成为代码执行入口 | v1 禁止可执行代码、网络、文件和 Keychain |
| 上下文读取破坏信任 | 最小权限、授权卡、敏感 App、字符预算、可撤销 |
| Style Capsule 泄露历史 | 主动选择、显示 Provider、源文本默认不保存 |
| 医疗等专业内容被误认为结论 | 只转写/格式化、不补事实、默认预览、明确复核 |
| 自定义快捷键导致应用不可用 | 原子注册、旧键保留、F5 回退、菜单动作 |
| Blue Signal 过度抢眼或耗电 | 默认 Refined HUD、动画可选、低刷新、Reduce Motion |
| 视觉模式导致状态不一致 | 统一 FeedbackSurface 状态模型，三种视图只负责表现 |
| Voice Mode 迁移破坏用户规则 | 稳定映射、兼容解码、未知项回退 Direct |
| Preview 增加延迟和步骤 | 只用于上下文、高风险和结构化 Skill；Direct 保持直达 |
| Prompt 注入改变系统行为 | 上下文标记为数据，系统安全外壳固定且优先级最高 |
| 产品范围失控 | 按 Phase 交付，Action 和 Registry 最后做 |

## 21. 需要产品负责人确认的决策

建议默认采用以下答案：

1. **默认视觉模式**
   - 建议：`Refined HUD`；
   - Blue Signal Frame 为推荐的可选品牌体验，不在稳定性验证前强制默认。
2. **默认快捷键**
   - 建议：继续 `F5`；
   - 用户可改，但同键开始/停止语义不可变。
3. **首个上下文能力**
   - 建议：只做 `selection`；
   - 暂不做整屏和完整会话读取。
4. **首批 Skills**
   - 建议：Direct、Reply、Email、Backend Prompt、Code Prompt、Translate。
5. **医疗能力**
   - 建议：先做术语包和结构化草稿，不做诊断型 Skill。
6. **社区生态**
   - 建议：先完成官方 Skill 和包规范，再开放本地导入，最后做 Registry。
7. **Style Capsule**
   - 建议：实验功能；原始样本默认生成后删除。
8. **Action Skills**
   - 建议：不进入 AI-native MVP。

## 22. 最终产品表达

### 中文

> **OpenWhisper 是 macOS 上由语音、上下文和可组合 Skills 驱动的 AI 输入层，把自然口述转成符合当前任务、当前工具和个人风格的可用产物。**

### 英文

> **OpenWhisper is an AI-native input layer for macOS that turns spoken intent into task-ready output using context, personal style, and composable Skills.**

### 简短版本

> **Speak your intent. Get usable output.**

## 23. 推荐下一步

Phase 1–3 已完成。后续仍按依赖和风险执行：

1. 在已完成的选区安全边界上实现 Style Capsule 和 Terminology Packs；
2. 最后实现 `.openwhisperskill` 本地导入、包安全校验和社区分发研究。

已落地的 Phase 1–3 已解决**触发方式不够自由**、**录音反馈不够高级**、**固定 Voice Mode 无法形成可验证运行时契约**和**选区改写缺少安全替换证明**。下一阶段必须让个人风格和领域术语继续服从已建立的权限、Prompt、Validator、Preview 和安全投递边界。
