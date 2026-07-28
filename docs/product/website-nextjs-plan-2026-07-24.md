# VibeCompose 官网规划（Next.js · 参照 Typeless）

> 日期：2026-07-24  
> 状态：规划稿，待产品所有者批准后开工  
> 范围：静态营销官网 + GitHub 托管的 Skill 目录展示  
> 非范围：远程 Registry、账号体系、Pilot 研究后台、App 内联网安装
> 相关文档：[品牌身份](brand-identity.md)、[品牌 clearance](brand-clearance-2026-07-14.md)、[Community Skills 核心计划](community-skills-core-next-step-plan-2026-07-15.md)、[Community Skill 贡献指南](../engineering/community-skill-contribution-guide.md)、[隐私政策](../legal/privacy-policy.md)、现有落地页 `docs/index.html`

---

## 0. 执行结论

做官网，但走 **小项目、零后端、全静态** 路线：

```text
Next.js（静态导出）
  → 官方宣传（参照 Typeless 的区块节奏与视觉层级）
  → Skills 目录页（读仓库内 JSON / 前端包元数据）
  → 每个 Skill 的「获取」全部指向 GitHub 目录或 Release ZIP
  → 用户在 App 内本地 Import，官网不提供远程安装 API
```

**一句话定位（对外）：**

> 按一下快捷键说话；选一个可信 Skill；文字安全回到当前光标。

**与 Typeless 的关系：**

| 维度 | Typeless | VibeCompose 采用 / 不采用 |
| --- | --- | --- |
| 核心叙事 | Speak, don't type | 采用：**说话代替打字**，但强调「任务型 Skill」而非纯润色 |
| 首页节奏 | Hero → 兼容 → 能力块 → 隐私 → 跨端 → 证言 → CTA | 采用节奏；**跨端改成「macOS 原生」**；证言在 Alpha 期用场景卡代替名人背书 |
| 主 CTA | Download for free | 改为 **Download Alpha / View on GitHub**（无签名 Stable 前不写「正式版下载」） |
| 多平台 | Mac / Win / iOS / Android | **只承诺 macOS 13+**，其他平台明确「未提供」 |
| Manifesto | 强态度品牌页 | 可选 Phase 2；Phase 1 用首页叙事段覆盖 |
| Skills / 社区 | 无 | **VibeCompose 差异化中枢**：`/skills` 策展目录 → GitHub |
| 后端 | 完整服务端 | **无后端**；GitHub Pages / Cloudflare Pages |

**硬约束（不可违背）：**

1. 不假装远程 Skill 商店或一键 App 内安装。  
2. 不声称 OpenAI 隶属 / 赞助 / 背书；默认路径依赖用户自己的 ChatGPT 会话与上游可用性。  
3. 不在品牌 clearance 完成前绑定生产自定义域名的「Stable 发布」叙事；可用 GitHub Pages 子路径或临时域名上 Alpha 站。  
4. 不出现 `releases/tag/` 式「已正式发版」暗示，除非 release 门禁真正通过。  
5. 保留现有 `docs/index.html` 内容契约的精神（诚实 Alpha、F5、剪贴板、MIT、安全边界），迁移到 Next 后更新 `scripts/check_landing_page.mjs`。  
6. Skill 永远是声明式包；官网文案不得暗示可执行插件、Shell、MCP 或自定义网络。

---

## 1. 目标与非目标

### 1.1 目标

| ID | 目标 | 成功标准 |
| --- | --- | --- |
| G1 | 30 秒内讲清产品是什么、给谁用 | 首屏无需滚动即可读懂价值主张 + 主 CTA |
| G2 | 把 Community Skills 做成可浏览的差异化卖点 | `/skills` 可列出内置 + 社区包，每条可点到 GitHub |
| G3 | 降低「怎么装 / 怎么拿 Skill」的摩擦 | 安装步骤 ≤ 5 步；Skill 安装步骤 ≤ 4 步（下载 → App Import） |
| G4 | 双语（zh-CN 优先，en 完整） | 路由或 locale 切换可用；关键法律链齐全 |
| G5 | 运维成本 ≈ 0 | 纯静态托管；无数据库、无用户系统、无服务端密钥 |
| G6 | 与仓库身份一致 | 名称、蓝色、MIT、repo 链接、版本状态与 `product.env` / 品牌文档一致 |

### 1.2 非目标（明确不做）

- 远程 Registry、自动更新社区包、签名索引 API  
- 用户登录、评论、评分、排行榜、关注作者  
- Windows / iOS / Android 下载  
- 在线 Demo 录音（浏览器麦克风 + 云转写）  
- CMS、Headless 后台  
- Pilot 招募系统与研究数据上传  
- 把 `docs/` 工程文档整站搬成对外知识库（只链关键公开文档）

---

## 2. 参照 Typeless：区块映射

Typeless 首页结构 → VibeCompose Phase 1 对应：

| # | Typeless | VibeCompose 对应 | 说明 |
| --- | --- | --- | --- |
| 1 | Hero「Speak, don't type」+ Download | Hero「按 F5 说话 / 文字回到光标」+ GitHub / Download Alpha | 右侧产品视觉或工作流示意，不做假速度对比数字除非有自测证据 |
| 2 | Works everywhere（应用 icon 跑马灯） | Works where you already write | macOS 应用场景：Mail、Messages、Slack、VS Code、浏览器、Notes… **只列常见类别，不声称「全平台」** |
| 3 | Dictate 功能矩阵 | Skills 驱动的任务输出 | 用 3–4 个能力柱：Dictation、Task Skills、Preview & Safe Paste、Terminology & Style |
| 4 | Translate | 内置 Translate Skill 作为能力点之一 | 不单独做整页，收入 Skills / Features |
| 5 | Ask anything（选区编辑） | Context Rewrite / Context Reply | 明确「需授权选区 + Preview」 |
| 6 | Private by design | Privacy & Boundaries | 本地历史、删除全部数据、敏感应用、无自有转写服务器；**同时诚实写清 ChatGPT 上游处理** |
| 7 | Cross-device | macOS-native focus | 菜单栏、全局快捷键、Accessibility、原生 Settings；不写跨端同步 |
| 8 | Testimonials | Use-case cards（Phase 1） | Alpha 无真实公开证言时用场景卡；有用户原话且获授权后再换 |
| 9 | Final CTA | Final CTA | 源码 / Alpha 下载 / 浏览 Skills |
| 10 | Ask ChatGPT / Claude | 可选「用 AI 帮你判断是否适合」 | Phase 2；优先级低 |
| — | Manifesto / About | About 精简；Manifesto 可选 | 见信息架构 |

**视觉气质（学结构，不抄皮）：**

- 大标题、短段落、充足留白、区块交替明/暗  
- 强主 CTA 重复出现（Hero / 中段 / 底）  
- 产品截图或抽象 HUD 示意，少用杂乱插画  
- 动效克制：滚动显现、轻 hover；尊重 `prefers-reduced-motion`  
- **品牌色**：交互蓝 `#0074FF`（见 brand-identity）；中性纸感背景可参考现 `docs/index.html` 的 `#f4f3ef` / 深色 `#171a20`  
- 字体：系统栈优先（`-apple-system, "SF Pro Text", "PingFang SC", sans-serif`），保持 macOS 亲和力  

**禁止：**

- 伪造「4× faster / 220 wpm / 节省 1 天/周」类未经验证的对比数字  
- 名人假证言、伪造 Product Hunt 徽章  
- 使用 Typeless 的文案、插画、视频或 logo  

---

## 3. 信息架构

### 3.1 站点地图（Phase 1）

```text
/                         首页（营销主路径）
/skills                   Skill 目录（内置 + 社区策展）
/skills/[slug]            Skill 详情（元数据 + GitHub 深链 + 安装说明）
/download                 安装与系统要求（可并入首页锚点，独立页便于外链）
/privacy                  隐私政策（由 docs/legal 渲染或静态同步）
/terms                    使用条款（同上）
/about                    项目简述、开源、边界声明（短页）

可选 Phase 2：
/manifesto                品牌态度长文
/docs/*                   精选用户文档（安装、创作 Skill）
/changelog                版本说明（链 release notes）
```

### 3.2 导航

**Header（桌面）：**

| 元素 | 行为 |
| --- | --- |
| Logo + VibeCompose | → `/` |
| Skills | → `/skills` |
| Download | → `/download` 或 `#download` |
| About | → `/about` |
| GitHub | 外链 `https://github.com/forever-ivy/vibecompose` |
| 语言 | `中文` / `EN` |
| 主 CTA 按钮 | `Download Alpha` 或 `View on GitHub`（按是否有可下载 artifact 切换） |

**Footer：**

- Product: Skills, Download, GitHub  
- Legal: Privacy, Terms, License (MIT)  
- Project: About, Security audit（链 `docs/audits/...` 的 GitHub blob 或镜像页）, Support policy  
- Status 一行：`0.1.0 Alpha · macOS 13+ · MIT · Working identity`  

### 3.3 主用户路径

```text
访客 → 首页理解价值
     → Download 安装 Alpha
     → Skills 浏览任务包
     → 打开 GitHub 目录 / 下载 ZIP
     → App：Skill Library → Import
     → 快捷键切换 Skill → 说话 → Preview → 回填
```

贡献者路径：

```text
/skills → Contribute CTA
       → GitHub contribution guide
       → PR 到 community-skills/
       → 合并后 index.json 更新 → 官网静态重建
```

---

## 4. 页面规格

### 4.1 首页 `/`

自上而下区块（强制顺序，可在实现时微调间距，不增删主线）：

#### A. Nav

见 3.2。滚动后可 sticky；移动端汉堡菜单。

#### B. Hero

| 字段 | zh-CN 草案 | en 草案 |
| --- | --- | --- |
| Eyebrow | macOS 原生语音输入 · Alpha | Native macOS voice input · Alpha |
| H1 | 按 F5 说话。<br>文字回到光标。 | Press F5. Speak.<br>Text returns to the caret. |
| Lead | 连接你自己的 ChatGPT 账户。录音、转写、任务型 Skill、术语与安全回填，压成一个快捷键动作。无法确认可编辑目标时，结果留在剪贴板。 | Connect your own ChatGPT account. Recording, transcription, task Skills, terminology, and safe paste collapse into one shortcut. When the target is not safely editable, the result stays on the clipboard. |
| Primary CTA | 查看源码 / 下载 Alpha | View source / Download Alpha |
| Secondary CTA | 浏览 Skills | Browse Skills |
| 状态面板 | 平台 macOS 13+ · 版本 0.1.0 Alpha · 中英界面 · MIT · 产品化改造中 | 同左 |

视觉：左侧文案，右侧「状态面板 + HUD 静帧 / 快捷键示意」。不嵌入必须自动播放的营销视频（资源未齐前用静态构图）。

#### C. Workflow「不切应用，不打开聊天窗口」

五步条（沿用现落地页语义）：

1. 光标落在真实可编辑位置  
2. F5 开始录音  
3. F5 停止并转写  
4. Skill / 术语 / 可选润色  
5. 安全回填或剪贴板  

#### D. Works where you write

- 标题：在你已经写作的地方工作  
- 一排 macOS 场景图标或文字 chips（邮件、即时消息、文档、IDE、浏览器、终端旁注…）  
- 脚注：依赖 Accessibility 与目标 App 可编辑性；不能保证每一个第三方 App  

#### E. Feature pillars（对应 Typeless Dictate/Ask 节奏）

四列或 2×2：

| 柱 | 要点 |
| --- | --- |
| 一次触发 | 同一快捷键开始/停止；菜单栏常驻 |
| Task Skills | 邮件、回复、Commit、Bug Report、会议待办等声明式任务包 |
| Preview & Safe Paste | 可编辑预览；Validator；目标复核；不安全则剪贴板 |
| Terminology & Style | 个人术语、Domain Pack、Writing Style；高风险 Medical 强制 Preview |

#### F. Skills spotlight

- 标题：先选任务，再说话  
- 横向或网格展示 6 个精选（Direct, Email, Reply, Commit Message, Bug Report, Context Rewrite）  
- 每张卡：名称、一句话、风险/投递标签、链到 `/skills/[slug]`  
- 底部链「查看全部 Skills」 |

#### G. Privacy & boundaries（对应 Private by design，但更诚实）

必须同时出现「我们承诺」与「你需要知道」：

**承诺：**

- 不自营转写服务器（默认走你连接的 ChatGPT 会话）  
- 本地历史与失败录音策略；支持删除全部数据  
- 敏感应用策略；选区 Context 按 Skill 授权  
- 声明式 Skill：不可执行任意代码  

**需要知道：**

- 默认路径依赖上游，不是稳定公开 API  
- 音频与转写请求会发往你选择的服务商  
- 非 OpenAI 官方产品；不承诺无限用量  
- Alpha：未宣称 Developer ID 签名公开发布完成前，下载为测试构建  

#### H. Open source & trust

- MIT  
- 源码、安全审计、架构文档外链  
- 「远程 Community Registry 未启用；Skills 经 GitHub 分发、本地导入」 |

#### I. Final CTA

- 标题：从键盘里腾出手  
- 按钮：GitHub · Download · Skills  
- 状态徽标：Alpha / MIT / macOS 13+  

#### J. Footer

见 3.2。

---

### 4.2 Skills 目录 `/skills`

**目的：** 策展浏览 + 导向 GitHub，不是商店结账页。

**布局：**

1. 页头：标题、说明（「包托管在 GitHub；在 App 中本地导入」）、Contribute 按钮  
2. 筛选：来源（Built-in / Community）、类别（Writing / Developer / Meeting / Support…）、语言  
3. 搜索：名称与摘要（纯前端）  
4. 卡片网格  

**卡片字段：**

| 字段 | 来源 |
| --- | --- |
| name | index.json / SKILL.md |
| summary | 公开摘要，不泄露内部 prompt |
| source | `built-in` \| `community` |
| category | 枚举 |
| version | semver |
| languages | `en`, `zh-Hans`… |
| githubUrl | 仓库 tree 深链 |
| zipUrl | 可选：raw/release zip |
| risk / delivery | preview / automatic / copy-only 等公开标签 |
| slug | URL 用 |

**空态：** 社区包为零时只展示 13 个内置 Skill，并显示「欢迎 PR 贡献」。

**页脚说明：**

> VibeCompose 不会执行 Skill 中的脚本、Hooks、MCP 或自定义网络请求。导入前请在 App 内完成包审查。

---

### 4.3 Skill 详情 `/skills/[slug]`

| 区块 | 内容 |
| --- | --- |
| Header | 名称、版本、来源徽章、类别 |
| Summary | 何时使用 / 不使用 |
| Context | Required / Optional（Voice、Selection、Style…） |
| Delivery | Preview / automatic when verified / copy-only |
| Examples | 2 个正常 + 1 个边界（与贡献指南一致；可截断展示） |
| Install | 编号步骤：打开 GitHub → Download ZIP 或 clone → App Skill Library → Import → 审查权限 → 测试 |
| Links | GitHub 目录、Report issue、License |
| 不展示 | 完整系统 prompt 内部实现细节（与 App 一致：内置只露任务摘要） |

Built-in Skill 的 `githubUrl` 指向：

`https://github.com/forever-ivy/vibecompose/tree/main/Sources/VibeCompose/Resources/BuiltInSkills/<portable-name>`

Community Skill 指向：

`https://github.com/forever-ivy/vibecompose/tree/main/community-skills/<slug>`

（目录名以实现时仓库布局为准，见第 7 节。）

---

### 4.4 Download `/download`

1. 系统要求：macOS 13+，麦克风，Accessibility（自动粘贴需要）  
2. ChatGPT 账户（默认路径）  
3. 获取构建：  
   - **优先**：GitHub Releases（仅在有 artifact 时显示按钮）  
   - **否则**：从源码 `scripts/package_app.sh` 构建（给开发者）  
4. 安装后首次路径：连接账户 → 授权麦克风 → 授权 Accessibility → F5 试说  
5. 明确：Alpha、可能 ad-hoc 签名、权限行可能不稳定  
6. 链：Privacy、Terms、SECURITY.md  

**禁止：** 无 artifact 时放失效下载按钮；禁止写「Free forever」类商业承诺（MIT 开源即可）。

---

### 4.5 About `/about`

短页即可：

- 项目是什么 / 不是什么  
- 开源 MIT、个人/小团队维护  
- 与 OpenAI 关系声明  
- 链 GitHub、审计、贡献  

### 4.6 Privacy / Terms

- 从 `docs/legal/*.md` **构建时导入**或 CI 同步，避免双源长期漂移  
- 中英与仓库法律文一致  
- 页眉标注 effective / last updated 日期  

---

## 5. Skill 数据与 GitHub 分发模型

### 5.1 原则

```text
GitHub monorepo = 唯一内容源
官网 = 静态渲染 + 外链
App  = 本地 Import 权威执行环境
```

不引入第二套 Skill 数据库。

### 5.2 建议仓库布局

```text
community-skills/                 # 社区策展包（Agent Skills 标准目录）
  index.json                      # 官网与校验脚本读取
  issue-draft/
    SKILL.md
    vibecompose.yaml              # 可选 Host Profile
    ...
  ...
Sources/VibeCompose/Resources/BuiltInSkills/
  <portable-name>/                # 已有 13 个内置
website/                          # Next.js 应用根（见第 6 节）
  ...
examples/skills/                  # 继续作模板/示例；可被 index 标记为 example 不进入精选
```

### 5.3 `community-skills/index.json` schema（草案）

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "VibeComposeSkillCatalog",
  "type": "object",
  "required": ["generatedAt", "skills"],
  "properties": {
    "generatedAt": { "type": "string", "format": "date-time" },
    "skills": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "slug",
          "name",
          "summary",
          "source",
          "category",
          "version",
          "path",
          "githubUrl"
        ],
        "properties": {
          "slug": { "type": "string", "pattern": "^[a-z0-9]+(?:-[a-z0-9]+)*$" },
          "name": { "type": "string", "maxLength": 80 },
          "summary": { "type": "string", "maxLength": 280 },
          "source": { "enum": ["built-in", "community", "example"] },
          "category": {
            "enum": [
              "dictation",
              "writing",
              "developer",
              "meeting",
              "product",
              "support",
              "translation",
              "context"
            ]
          },
          "version": { "type": "string" },
          "languages": {
            "type": "array",
            "items": { "enum": ["en", "zh-Hans"] }
          },
          "delivery": {
            "enum": ["automatic-when-verified", "preview", "copy-only"]
          },
          "risk": { "enum": ["low", "medium", "high"] },
          "path": { "type": "string" },
          "githubUrl": { "type": "string", "format": "uri" },
          "zipUrl": { "type": "string", "format": "uri" },
          "featured": { "type": "boolean" }
        }
      }
    }
  }
}
```

**生成策略（二选一，实现时定一种）：**

1. **手写 index.json**（小项目首选）：PR 改包时同步改索引；简单、可审。  
2. **脚本生成**：`scripts/generate_skill_catalog.py` 扫描 `BuiltInSkills` + `community-skills`，从 frontmatter 抽字段，CI 校验 diff。  

官网构建时 **只读** 该 JSON + 可选读取各包 `SKILL.md` 的 frontmatter（不要把 instructions 正文渲染到公开页，除非作者明确标记 `public_examples`）。

### 5.4 内置 13 Skills 首批上架清单

| portable-name | 公开名（en） | category |
| --- | --- | --- |
| direct | Direct | dictation |
| reply | Reply | writing |
| email | Email | writing |
| translate | Translate | translation |
| backend-prompt | Backend Prompt | developer |
| code-prompt | Code Prompt | developer |
| context-rewrite | Context Rewrite | context |
| context-reply | Context Reply | context |
| bug-report | Bug Report | developer |
| commit-message | Commit Message | developer |
| meeting-action-items | Meeting Action Items | meeting |
| product-brief | Product Brief | product |
| customer-support-reply | Customer Support Reply | support |

社区首批：可将 `examples/skills/IssueDraft` 规范化进 `community-skills/` 作为示范，或等有真实 PR 再填。

### 5.5 贡献流（官网文案 + 仓库流程）

1. Fork 仓库  
2. 按 [contribution guide](../engineering/community-skill-contribution-guide.md) 创作  
3. 放入 `community-skills/<slug>/`  
4. 更新 `index.json`  
5. PR；维护者审查声明式边界与文案  
6. merge → Pages 自动部署  

官网 **不提供** Web 表单上传。

---

## 6. 技术栈与工程

### 6.1 选型

| 层 | 选择 | 理由 |
| --- | --- | --- |
| 框架 | **Next.js**（App Router） | 用户指定；成熟、静态导出友好 |
| 渲染 | **`output: 'export'`** 全静态 | 零服务器、GitHub Pages / CF Pages 直接挂 |
| UI | React + Tailwind CSS v4（或 v3） | 快速实现 Typeless 式营销布局 |
| 动效 | CSS + 少量 Motion（可选）；尊重 reduced-motion | 克制 |
| 内容 | MDX 或 `next-mdx-remote` 仅用于 legal/about | 法律页与仓库 md 同步 |
| i18n | `next-intl` 或自研字典 + `[locale]` 段 | zh-CN 默认，en 完整 |
| 图标 | SF 风格 lucide 或自绘；App icon 用包装资产导出 WebP | 统一 |
| 分析 | **默认不上**；若以后加，仅隐私友好、opt-in | 与产品 metrics 哲学一致 |
| 包管理 | pnpm 或 npm，锁文件提交 | 与 monorepo 脚本兼容即可 |

**Next 配置要点：**

```js
// next.config.ts（示意）
const nextConfig = {
  output: "export",
  images: { unoptimized: true }, // Pages 无默认 Image Optimization 服务
  trailingSlash: true,           // 对 GitHub Pages 更稳妥
};
```

基路径：若部署到 `https://<user>.github.io/vibecompose/`，设置 `basePath: '/vibecompose'` 与 `assetPrefix`。自定义域名根路径则留空。

### 6.2 建议目录（`website/`）

```text
website/
  package.json
  next.config.ts
  tailwind.config.ts
  postcss.config.mjs
  tsconfig.json
  public/
    brand/
      logo.svg
      app-icon.png
      og-image.png
    favicon.ico
  content/
    zh-Hans/
      home.ts          # 或 messages JSON
      skills.ts
    en/
      ...
  src/
    app/
      layout.tsx
      page.tsx                    # 可 redirect → /zh-Hans
      [locale]/
        layout.tsx
        page.tsx                  # 首页
        skills/page.tsx
        skills/[slug]/page.tsx
        download/page.tsx
        about/page.tsx
        privacy/page.tsx
        terms/page.tsx
        not-found.tsx
    components/
      site-header.tsx
      site-footer.tsx
      hero.tsx
      workflow-strip.tsx
      feature-pillars.tsx
      skills-spotlight.tsx
      skill-card.tsx
      privacy-panel.tsx
      cta-band.tsx
      locale-switcher.tsx
      status-badge.tsx
    lib/
      catalog.ts                 # 读 index.json + built-in 合并
      site-config.ts             # repo URL, version, basePath
      legal.ts                   # 导入或读取 legal md
    styles/
      globals.css
  scripts/
    sync-legal.mjs               # 可选：从 docs/legal 拷贝
    check-site-content.mjs       # 迁移后的 landing 契约
```

**是否 monorepo 根目录：** 推荐 `website/` 子目录，避免污染 Swift `Package.swift` 与现有 CI；根 README 增加「Website」一节。

### 6.3 站点配置源

`website/src/lib/site-config.ts` 构建时可读：

- `../../product.env` 或复制字段：`VIBECOMPOSE_VERSION`、`VIBECOMPOSE_REPOSITORY`、`VIBECOMPOSE_MIN_MACOS`  
- 硬编码公开常量：`alpha: true`、`registryEnabled: false`  

版本号与 Alpha 徽章应与 `version.env` / 发布状态一致；可用小脚本生成 `site-config.generated.json`。

### 6.4 SEO 与分享

| 项 | 要求 |
| --- | --- |
| title | `VibeCompose — macOS 原生语音输入` / 英译 |
| description | 一句话价值 + Alpha |
| OG image | 1200×630，含 logo 与 slogan，无假指标 |
| robots | 允许索引 Alpha 站，但可用 `noindex` 仅当明确不想公开时（默认：**允许**） |
| sitemap.xml / robots.txt | `output: 'export'` 下用 next-sitemap 或手写 public 文件 |
| canonical | 与最终域名一致 |

### 6.5 无障碍

- 语义标题层级、跳过链接  
- 对比度达到 WCAG AA  
- 键盘可操作导航与筛选  
- 动画遵循 `prefers-reduced-motion`  
- 图片有 alt；装饰图 `alt=""`  

### 6.6 性能预算（目标）

| 指标 | 目标（移动端 mid） |
| --- | --- |
| LCP | < 2.5s |
| 首页 JS | 尽量小；首屏可无客户端状态 |
| 字体 | 系统字体，零 webfont 阻塞（Phase 1） |

Skills 页筛选可用 Client Component；首页主体 Server 静态 HTML。

---

## 7. 托管、域名与 CI

### 7.1 托管（按优先级）

| 选项 | 适用 | 备注 |
| --- | --- | --- |
| **GitHub Pages** | 默认推荐 | `peaceiris/actions-gh-pages` 或官方 Actions；`website/out` |
| Cloudflare Pages | 自定义域名友好 | 连同一 repo，build `website` |
| Vercel | 可选 | 即使用静态导出也可；注意与「零锁厂商」偏好 |

**费用：** 静态站 + GitHub 免费额度 ≈ **$0**；自定义域名另计。

### 7.2 域名策略（与品牌 clearance 对齐）

| 阶段 | 动作 |
| --- | --- |
| 现在 | `https://forever-ivy.github.io/vibecompose/` 或 `*.pages.dev` 预览 |
| clearance 通过后 | 绑定 `vibecompose.app` / `.com` 等（以实际注册为准） |
| 全程 | 页脚保留 Working identity / Alpha 说明，直到 Stable |

在 clearance 仍为 blocked 时：**可以上 Alpha 站**，但文案与 README 不宣布「正式官方域名发布完成」。

### 7.3 CI 流水线（建议）

```yaml
# .github/workflows/website.yml（示意）
on:
  push:
    branches: [main]
    paths: [website/**, community-skills/**, Sources/VibeCompose/Resources/BuiltInSkills/**, docs/legal/**]
jobs:
  build-deploy:
    - checkout
    - setup node
    - pnpm install --dir website
    - pnpm -C website run lint
    - pnpm -C website run check:content   # 诚实文案契约
    - pnpm -C website run build           # next export → out/
    - deploy out/ to Pages
```

根 `scripts/check.sh`：

- Phase 1 过渡期：保留对 `docs/index.html` 的检查 **或**  
- 迁移完成后：改为调用 `website` 的 content contract，删除或降级旧 HTML。

### 7.4 与现有 `docs/index.html` 的关系

| 阶段 | 策略 |
| --- | --- |
| 开发 Next 期间 | 旧 `docs/index.html` 仍作为 CI 契约与临时页 |
| Next 上线后 | `docs/index.html` 改为短跳转页（meta refresh 或链接到新站），或 GitHub Pages 根改为 `website/out` |
| 文档站 | `docs/` 其余 md 继续服务工程读者；不与营销站混为同一 IA |

---

## 8. 内容与文案规范

### 8.1 语气

- 清晰、克制、产品化；可坚定，但不写「键盘是个错误」级别攻击性文案（除非 Phase 2 Manifesto 明确要做态度品牌）  
- 中文优先完整；英文同等质量，禁止机翻残留  
- 用「你」第二人称；避免企业空话  

### 8.2 禁用词 / 禁用声称

| 禁止 | 原因 |
| --- | --- |
| 「官方 OpenAI 合作 / 授权」 | 非事实 |
| 「企业级 SLA / 99.99%」 | Alpha 无 |
| 「远程 Skill 商店 / 一键安装社区包」 | 未实现 |
| 无来源的速度对比数字 | 诚信 |
| 任何此前的工作名称作为产品名 | 品牌规则 |
| 「Stable / 正式版」 | 门禁未过 |

### 8.3 必现诚实句（content contract）

站点中文或双语等价物必须可被检查脚本断言存在：

- 产品名 `VibeCompose`  
- `0.1.0 Alpha`（或与 version.env 同步的 Alpha 标记）  
- `F5`（或「可配置全局快捷键，默认 F5」）  
- `ChatGPT`  
- 剪贴板回退  
- 非稳定公开 API / 上游依赖  
- 不承诺无限用量  
- `MIT`  
- 指向 GitHub 仓库的链接  
- Skills 本地导入 / GitHub 分发说明  
- 无 `releases/tag/` 假发布链接（无真实 release 时）  

英文 locale 使用对应英文诚实句，脚本按 locale 分断言。

---

## 9. 设计系统（Web）

### 9.1 Token（与 brand-identity 对齐）

| Token | Light | Dark |
| --- | --- | --- |
| `--bg` | `#f4f3ef` | `#111318` |
| `--surface` | `#fbfaf7` | `#191c22` |
| `--ink` | `#15181d` | `#f3f5f7` |
| `--muted` | `#626872` | `#aeb4be` |
| `--line` | `#d8d7d2` | `#333842` |
| `--accent` | `#0074FF` | `#0074FF` |
| `--dark` | `#171a20` | （暗色区块底） |

圆角：按钮 10px、卡片 16px（与现落地页一致）。  
主按钮：深色实心或 accent；次按钮：描边 surface。

### 9.2 布局

- 内容最大宽 ~1120–1200px  
- 区块垂直 padding ~72–96px  
- Hero 大标题 `clamp(48px, 7vw, 80px)`  
- 栅格：功能 2×2 或 3 列；Skills 卡片 3 列 → 移动 1 列  

### 9.3 组件清单（实现 checklist）

- [ ] SiteHeader / MobileNav  
- [ ] SiteFooter  
- [ ] Hero  
- [ ] WorkflowStrip  
- [ ] LogoMarquee 或 AppChips（降级为静态 chips 若不做无限滚动）  
- [ ] FeaturePillars  
- [ ] SkillCard / SkillGrid  
- [ ] PrivacyPanel  
- [ ] CtaBand  
- [ ] StatusBadge / AlphaBanner  
- [ ] LocaleSwitcher  
- [ ] MarkdownLegal  
- [ ] MotionProvider（reduced-motion 守卫）  
- [ ] RevealOnScroll（通用滚动入场包装器）  
- [ ] MarqueeRow（App Chips 无限滚动）  

---

### 9.4 动效系统（对标 Typeless）

> **核心原则：** 克制、快速、服务内容。动效存在感要低于内容本身；每一条动效必须有功能理由（引导视线、确认操作、表达层级），纯装饰动效一律不加。

#### 9.4.1 依赖

```bash
pnpm add framer-motion
# 不引入 GSAP / anime.js —— Framer Motion 对 React 足够，减少包体积
```

#### 9.4.2 Easing & Timing Token

与 Typeless 同级的营销站惯用的参数区间：

| Token | 值 | 用途 |
| --- | --- | --- |
| `ease-out-smooth` | `cubic-bezier(0.25, 0.1, 0.25, 1)` | 大多数入场、状态切换 |
| `ease-out-expo` | `cubic-bezier(0.16, 1, 0.3, 1)` | Hero 标题大字、模态出现 |
| `ease-spring` | `type: "spring", stiffness: 360, damping: 30` | 按钮 tap、卡片 hover lift |
| `dur-fast` | `0.22s` | hover、focus、小状态变化 |
| `dur-base` | `0.45s` | 区块入场、淡入 |
| `dur-slow` | `0.65s` | Hero 主标题行、整页背景切换 |
| `stagger-gap` | `0.07s` | 子元素交错间隔 |
| `scroll-margin` | `-80px` | `viewport.margin`，提前触发避免突兀 |

在 `website/src/lib/motion.ts` 统一导出，所有组件从此文件引用，不在组件内散写参数。

#### 9.4.3 Variant 库

```ts
// website/src/lib/motion.ts

export const fadeUp = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0,
    transition: { duration: 0.45, ease: [0.25, 0.1, 0.25, 1] } },
};

export const fadeIn = {
  hidden: { opacity: 0 },
  visible: { opacity: 1,
    transition: { duration: 0.55, ease: "easeOut" } },
};

// Hero 大标题专用：更快、更强 easing
export const heroLine = {
  hidden: { opacity: 0, y: 28 },
  visible: { opacity: 1, y: 0,
    transition: { duration: 0.65, ease: [0.16, 1, 0.3, 1] } },
};

// 容器：子元素交错
export const stagger = (delayChildren = 0.05) => ({
  hidden: {},
  visible: { transition: { staggerChildren: 0.07, delayChildren } },
});

// 卡片入场（含轻微缩放）
export const cardReveal = {
  hidden: { opacity: 0, y: 16, scale: 0.975 },
  visible: { opacity: 1, y: 0, scale: 1,
    transition: { duration: 0.45, ease: [0.25, 0.1, 0.25, 1] } },
};

// 水平滑入（左 → 右，用于 Workflow 步骤指示线）
export const slideRight = {
  hidden: { scaleX: 0, originX: 0 },
  visible: { scaleX: 1,
    transition: { duration: 0.55, ease: [0.25, 0.1, 0.25, 1] } },
};
```

#### 9.4.4 全局 reduced-motion 守卫

所有 Framer Motion 入场动效必须通过 `RevealOnScroll` 包装，不直接散写 `whileInView`：

```tsx
// website/src/components/reveal-on-scroll.tsx
"use client";
import { motion, useReducedMotion, type Variants } from "framer-motion";
import { fadeUp } from "@/lib/motion";

export function RevealOnScroll({
  children, className, variants = fadeUp, delay = 0,
}: {
  children: React.ReactNode;
  className?: string;
  variants?: Variants;
  delay?: number;
}) {
  const reduced = useReducedMotion();
  if (reduced) return <div className={className}>{children}</div>;
  return (
    <motion.div
      className={className}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: "-80px" }}
      variants={variants}
      transition={{ delay }}
    >
      {children}
    </motion.div>
  );
}
```

CSS 层兜底（`globals.css`）：

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
  }
}
```

#### 9.4.5 区块动效规格（逐区块）

| 区块 | 触发时机 | 动效描述 | Variant / 实现 |
| --- | --- | --- | --- |
| **Nav** | 页面加载 | 整行从顶部 `y: -8 → 0` + `opacity 0→1`，`0.3s ease-out` | `motion.header animate` |
| **Hero Eyebrow** | 立即（animate） | `fadeUp`，delay 0 | `heroLine` |
| **Hero H1（两行）** | 立即（animate） | 每行独立 `heroLine`，stagger 0.1s | `stagger(0)` + `heroLine` |
| **Hero Lead 段落** | 立即（animate） | `fadeUp`，delay 0.25s | `fadeUp` |
| **Hero CTA 组** | 立即（animate） | `fadeUp`，delay 0.38s | `fadeUp` |
| **Hero 右侧 HUD** | 立即（animate） | `fadeIn` + 轻微 `scale 0.97→1`，delay 0.2s | 自定义 variant |
| **Workflow Strip** | 滚动进入 | 五步卡片从左到右依次 `fadeUp`，stagger 0.08s；步骤连接线 `slideRight` | `stagger` + `cardReveal` + `slideRight` |
| **App Chips 行** | 页面加载后 | 无限向左匀速滚动（`marquee`），`20s linear infinite`；hover 暂停 | CSS `animation: marquee` |
| **Feature Pillars** | 滚动进入 | 2×2 网格，行交错 stagger 0.07s，`cardReveal` | `stagger` + `cardReveal` |
| **Skills Spotlight** | 滚动进入 | 标题先 `fadeUp`，卡片网格 stagger 0.07s | `stagger` + `cardReveal` |
| **Privacy Panel** | 滚动进入 | 整区块 `fadeIn`（深色背景区块不做位移，只做透明度） | `fadeIn` |
| **Open Source 区块** | 滚动进入 | 文案 `fadeUp`，徽章 stagger 0.06s | `stagger` + `fadeUp` |
| **Final CTA** | 滚动进入 | 标题 `heroLine`，按钮组 `fadeUp` delay 0.2s | |
| **Footer** | 静态渲染 | 无入场动效 | — |

#### 9.4.6 交互动效（Hover / Tap）

所有交互动效**仅用 CSS transition**，不用 Framer Motion `whileHover`（性能更稳，SSR 无闪烁）：

```css
/* 主 CTA 按钮 */
.btn-primary {
  transition: background-color 0.18s ease, transform 0.18s var(--ease-spring),
              box-shadow 0.18s ease;
}
.btn-primary:hover  { transform: translateY(-1px); box-shadow: 0 4px 16px rgba(0,116,255,0.25); }
.btn-primary:active { transform: translateY(0px) scale(0.98); }

/* 次级按钮 / Ghost */
.btn-ghost {
  transition: border-color 0.18s ease, color 0.18s ease, background 0.18s ease;
}
.btn-ghost:hover { border-color: var(--accent); color: var(--accent); }

/* Skill 卡片 */
.skill-card {
  transition: transform 0.22s var(--ease-smooth),
              box-shadow 0.22s ease,
              border-color 0.22s ease;
}
.skill-card:hover {
  transform: translateY(-3px);
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.09);
  border-color: var(--accent);
}

/* Nav 链接下划线滑入 */
.nav-link {
  position: relative;
}
.nav-link::after {
  content: '';
  position: absolute; bottom: -2px; left: 0;
  width: 100%; height: 1.5px;
  background: var(--ink);
  transform: scaleX(0); transform-origin: left;
  transition: transform 0.22s var(--ease-smooth);
}
.nav-link:hover::after { transform: scaleX(1); }

/* reduced-motion：关闭所有 hover transform */
@media (prefers-reduced-motion: reduce) {
  .btn-primary:hover,
  .skill-card:hover  { transform: none; }
}
```

#### 9.4.7 App Chips 无限滚动（对标 Typeless 应用图标跑马灯）

```tsx
// website/src/components/marquee-row.tsx
export function MarqueeRow({ items }: { items: string[] }) {
  return (
    <div className="marquee-wrapper" aria-hidden="true">
      <ul className="marquee-track">
        {[...items, ...items].map((item, i) => (
          <li key={i} className="marquee-chip">{item}</li>
        ))}
      </ul>
    </div>
  );
}
```

```css
.marquee-wrapper { overflow: hidden; mask-image: linear-gradient(to right, transparent, black 10%, black 90%, transparent); }
.marquee-track   { display: flex; gap: 12px; width: max-content;
                   animation: marquee 22s linear infinite; }
.marquee-wrapper:hover .marquee-track { animation-play-state: paused; }

@keyframes marquee {
  from { transform: translateX(0); }
  to   { transform: translateX(-50%); }
}

@media (prefers-reduced-motion: reduce) {
  .marquee-track { animation: none; }
  /* 静止显示一行即可 */
}
```

#### 9.4.8 产品 HUD / 截图区动效

在获得真实产品录屏素材前：

- **静态构图**：HUD 静帧 WebP，入场用 `fadeIn + scale 0.97→1`，无自动播放视频。
- **获得素材后（Phase 2）**：替换为 `<video autoPlay muted loop playsInline>`，入场同上；`prefers-reduced-motion` 时 `video { animation-play-state: paused }` + `poster` 静帧兜底。

#### 9.4.9 页面切换（App Router）

```tsx
// app/[locale]/layout.tsx — 轻淡入即可，不做滑动（避免跨页面 layout shift）
<motion.main
  initial={{ opacity: 0 }}
  animate={{ opacity: 1 }}
  transition={{ duration: 0.25, ease: "easeOut" }}
>
  {children}
</motion.main>
```

#### 9.4.10 动效实现 Checklist

- [ ] `website/src/lib/motion.ts` — variant 库  
- [ ] `RevealOnScroll` 组件（含 `useReducedMotion` 守卫）  
- [ ] `MarqueeRow` 组件 + CSS  
- [ ] Hero 区块：`animate`（非 `whileInView`）+ stagger  
- [ ] Workflow Strip：`useInView` + 步骤 stagger + `slideRight` 连接线  
- [ ] Feature Pillars：`stagger` + `cardReveal`  
- [ ] Skills Spotlight grid：`stagger` + `cardReveal`  
- [ ] 全局 CSS hover token（button / card / nav-link）  
- [ ] `globals.css` reduced-motion 兜底  
- [ ] Phase 1 验收：在 `prefers-reduced-motion: reduce` 模式下全站无异常跳变  

---

## 10. 分阶段交付

### Phase 0 — 批准与脚手架（0.5–1 天）

- [ ] 产品所有者批准本文  
- [ ] 确认托管：GitHub Pages 路径 vs 自定义域  
- [ ] `website/` `create-next-app`（TS, App Router, Tailwind, ESLint）  
- [ ] `output: 'export'` 跑通空首页  
- [ ] `site-config` 接入 version / repo  

### Phase 1 — MVP 上线（约 3–5 天，单人）

- [ ] 全局布局、Header、Footer、i18n 骨架  
- [ ] 首页全部区块（B–I）  
- [ ] `/skills` + `/skills/[slug]`（先只内置 13 + index.json）  
- [ ] `/download`、`/about`  
- [ ] Privacy/Terms 同步  
- [ ] OG 图、favicon  
- [ ] content contract 脚本  
- [ ] CI 构建；部署预览 URL  
- [ ] README 增加 Website 一节  

**Phase 1 验收：**

1. 静态 `out/` 可本地 `npx serve` 完整点击。  
2. 每个 Skill 卡片 GitHub 链打开正确目录。  
3. 契约脚本绿。  
4. 无假下载、无 Registry 承诺。
5. Lighthouse 无障碍与性能无严重项（人工抽检）。  

### Phase 2 — 打磨（按需）

- [ ] 真实产品截图 / 短循环视频（自有素材）  
- [ ] `community-skills/` 示范包与贡献 CTA 打磨  
- [ ] catalog 生成脚本  
- [ ] Manifesto 页（若要强品牌态度）  
- [ ] 自定义域名（clearance 后）  
- [ ] 旧 `docs/index.html` 降级为跳转  

### Phase 3 — 仅当产品需要时

- [ ] 与签名 Release 联动的真下载按钮  
- [ ] Changelog  
- [ ] 远程 Registry **另立 Go/No-Go**，不在本官网计划默认开启  

---

## 11. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 品牌改名 | 文案与域名集中在 `site-config`；clearance 完成前用 Pages 子路径 |
| 文案过度承诺 | content contract + 本文件禁用表 |
| 双源法律文漂移 | 构建同步 `docs/legal`；PR 模板勾选 |
| Skill 索引过期 | CI 校验 path 存在；PR 检查 index |
| Next 升级成本 | 锁版本；静态导出避免 server 特性依赖 |
| 与 App Discover 行为不一致 | 官网写清「浏览器目录 ≠ App 内联网安装」 |
| 把官网做成第二个产品 | 严格 Phase 1 范围；禁止账号与商店 |

---

## 12. 开放决策（实施前需产品所有者点头）

| # | 问题 | 建议默认 |
| --- | --- | --- |
| D1 | 默认语言 zh-CN 还是 en？ | **zh-CN**（延续现落地页），en 完整 |
| D2 | 主 CTA 文案在无 Release 时？ | **View on GitHub** 为主，Download 页讲自建 |
| D3 | `website/` 子目录还是独立 repo？ | **子目录 monorepo**，降低分叉 |
| D4 | 是否 Phase 1 就做 Manifesto？ | **否** |
| D5 | 社区包目录名 `community-skills` vs `skills`？ | **`community-skills`**，避免与 App 内术语混淆 |
| D6 | 是否在首页放速度对比数字？ | **否**，除非有自有 benchmark 页面 |
| D7 | 分析脚本？ | **Phase 1 不上** |

---

## 13. 批准后立即执行顺序

1. 确认 D1–D7 默认或修订。  
2. 脚手架 `website/` + 静态导出。  
3. 落地设计 token 与 Header/Footer。  
4. 首页 Hero + Workflow + Privacy（诚实句优先）。  
5. 生成 `community-skills/index.json`（含 13 built-in 元数据）。  
6. Skills 列表/详情 + GitHub 深链。  
7. Download / About / Legal。  
8. content contract + CI + 部署预览。  
9. 产品所有者浏览预览 URL 签字后切 Pages 生产。  

---

## 14. 附录

### A. Typeless 对照速查

- 学：首屏口号力度、区块节奏、重复 CTA、隐私独立段、多列 Footer  
- 不学：多端下载、夸张 wpm、证言墙（暂无）

### B. 关键现有资产

- 文案种子：`docs/index.html`  
- 蓝与中性色：brand-identity + 现 CSS 变量  
- 法律：`docs/legal/*`  
- Skill 真相来源：`docs/engineering/skill-runtime.md`、`BuiltInSkills/`  
- 贡献：`docs/engineering/community-skill-contribution-guide.md`  
- 仓：`https://github.com/forever-ivy/vibecompose`  

### C. 一页范围声明（可贴进 README）

> VibeCompose 官网是 MIT 项目的静态宣传与 Skill 目录。Skill 包托管在 GitHub，于 macOS App 内本地导入。不提供账号、远程 Registry 或跨平台客户端。产品处于 Alpha，默认转写路径依赖用户自己的 ChatGPT 会话与上游可用性。

---

**文档结束。** 批准后按第 13 节开工；若需调整范围，先改本文再写代码。
