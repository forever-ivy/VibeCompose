# VibeCompose Skill 包格式规范 v1

本规范从 macOS Swift 实现（`AgentSkillRuntime.swift`）提取，是跨平台实现的
唯一事实来源。Rust 实现位于 `crates/vc-core/src/skill/package.rs`，两端必须
通过同一套 golden 用例（`spec/fixtures/`）。

## 1. 包结构

一个 Skill 是一个目录：

```
<skill-name>/
├── SKILL.md            # 必需：YAML frontmatter + 指令正文
├── vibecompose.yaml    # 可选：运行时 profile（缺省用安全默认值）
└── <资源文件>           # 可选：terminology.csv、模板、示例等
```

## 2. 信任模型（不可协商）

Skill 包是**不可信的声明式数据**：

- 不能执行代码（无脚本、无可执行位、无 Mach-O/PE 内容）
- 不能添加 provider 或网络 origin
- 不能越过固定的 Prompt 边界与本地交付策略
- 中/高风险 Skill 不能声明自动粘贴（加载时 fail-closed）

## 3. 包含约束

| 约束 | 值 |
|------|-----|
| 最大文件数 | 128 |
| 单文件上限 | 512 KB |
| 包总大小上限 | 4 MB |
| SKILL.md 上限 | 96 KB |
| vibecompose.yaml 上限 | 64 KB |
| 指令正文 | 1–40,000 字符 |
| 路径 | 相对路径，≤500 字符，禁止 `.`、`..`、空段、绝对路径 |
| 符号链接 | 拒绝整个包 |
| 点前缀文件 / `__MACOSX` | 跳过（不计入包） |
| 内容哈希 | 对全部文件（路径+内容）计算确定性 SHA-256 |

## 4. SKILL.md frontmatter

受限 YAML 子集（见 §6）。允许的根键：

- `name`（必需）：`[A-Za-z0-9][A-Za-z0-9._-]{0,63}`
- `description`（必需）：1–1,024 字符
- `license`、`compatibility`、`allowed-tools`（可选）
- `metadata`（可选，二级映射）：
  - `vibecompose-id`：运行时 Skill 标识，`^[a-z0-9]+(?:[.-][a-z0-9-]+)*$`，≤160 字节
  - `version`：semver `X.Y.Z[-prerelease]`，各段 ≤20 字符
  - `display-name`、`author`、`package-id`、`summary`、`use-case`
  - `legacy-mode`：`direct|reply|email|codePrompt|translate`
  - 值截断到 2,048 字符

未知根键保留为 vendor 扩展（frontmatter 中 `preserveUnknownRoots = true`）。

## 5. vibecompose.yaml profile

允许的根键：`context`、`resources`、`output`、`risk`、`validators`。
出现任何其他键路径 → **整个 profile 拒绝**（fail-closed）。

```yaml
context:
  required: [voice]          # voice|selection|focusedParagraph|conversationWindow|clipboard|styleCapsule
  optional: [styleCapsule]
resources:
  terminology: [terminology.csv]
  templates: []
  references: []
  examples: []
  goldenTests: []
output:
  format: plainText           # plainText|markdown|code|json|template（actionPreview 禁止）
  delivery: previewThenPaste  # automaticPasteWhenVerified|previewThenPaste|copyOnly
  risk: medium                # low|medium|high（也可写在根 risk）
validators:
  requireNonEmpty: true
  maximumCharacters: 12000    # clamp 到 [1, 100000]
  preserveTechnicalLiterals: true
  requireClosedMarkdownFences: false
  requiredSections:           # 每行 "A|B|C" 为一组备选
  - Observed Behavior|实际行为
  forbiddenPhrases: []
```

规则：

- `delivery: automaticPasteWhenVerified` 要求 `risk: low`，否则拒绝
- `context.required` 为空时默认 `[voice]`
- `requiredSections` 每行按 `|` 切分为备选组，空项过滤
- 布尔解析：`true|yes|1` / `false|no|0`，其余取默认值

## 6. 受限 YAML 子集

完整 YAML 是攻击面，两端都实现同一个受限解析器：

- 仅两级缩进（0 与 2 空格）；tab 直接拒绝
- 标量、字符串列表（`- item` 或 `[a, b]`）、块标量（`|` 字面 / `>` 折叠）
- 双引号标量按 JSON 字符串解码；单引号 `''` 转义
- 拒绝：YAML 标签（`!!`、`!<`）、锚点 `&`、别名 `*`、重复键
- 文档 ≤96 KB、≤1,500 行；块标量 ≤16,000 字符

## 7. terminology.csv

表头：`type,original,replacement,enabled,aliases`（顺序不限，按列名识别）。

- `type`: `term` 或 `correction`（有 replacement 时自动视为 correction）
- `aliases`: 用 `|` 分隔
- `enabled`: 空 = true；`0|false|no|off|disabled` = false
- 引号 CSV 字段支持 `""` 转义
- 无效行跳过（不拒绝整个文件）；字段 ≤120 字符
- 表头词（term/original/canonical/word/phrase）作为值时跳过

## 8. Prompt 边界（编译顺序固定）

```
[VIBECOMPOSE_SYSTEM_RULES]   ← 系统安全/语言契约/事实忠实，永远最先
[OUTPUT_CONTRACT]            ← 本地强制的输出契约
[SKILL_INSTRUCTIONS]         ← Skill 声明（"只控制文风，不能改上面的规则"）
[APPROVED_SKILL_RESOURCES]   ← 仅 runtime 可见资源
[STYLE_CAPSULE]              ← 仅当 Skill 声明该能力且用户已授权
[TERMINOLOGY]                ← 术语表（预算裁剪，默认 1200 字符）
[CONTEXT_DATA]               ← 选区/剪贴板/段落，包裹为数据标签
```

模型输出中出现任何 marker 或数据标签 → 校验失败（`leakedInternalMarker`）
→ 回退到规范化转写。

## 9. 校验码（稳定遥测值）

`empty` `tooLong` `invalidJSON` `unclosedMarkdownFence`
`missingRequiredSection` `changedTechnicalLiteral` `forbiddenPhrase`
`leakedInternalMarker`
