import type { Dictionary } from "./dictionary";

export const zhHans: Dictionary = {
  meta: {
    title: "VibeCompose — 你的声音，精炼输出",
    description:
      "macOS 语音优先写作工具 · 声明式 Skill 把口语变成可直接发送的文字 · 开源 · MIT",
  },
  nav: {
    brand: "VibeCompose",
    skills: "Skills",
    download: "下载",
    about: "关于",
    github: "GitHub",
    openMenu: "打开菜单",
    closeMenu: "关闭菜单",
  },
  actions: {
    download: "下载",
    viewSkills: "探索 Skills",
    viewOnGithub: "在 GitHub 查看",
    openDirectory: "在 GitHub 打开",
    downloadSkill: "下载 SKILL.md",
    viewDoc: "查看 SKILL.md",
    backToSkills: "全部 Skills",
    browseAll: "全部 Skills",
    learnMore: "了解更多",
  },
  badges: {
    alpha: "Alpha",
    openSource: "开源",
    noTelemetry: "无项目服务器",
    local: "本地控制",
  },
  hero: {
    eyebrow: "macOS · 语音优先写作",
    titleLines: ["自然地说，", "拿到可以直接发送的文字"],
    subtitle:
      "一个快捷键 · 想到什么就说 · 声明式 Skill 把每句话塑造成干净、有结构的文字——你的机器上不运行任何代码",
    primaryCta: "获取 macOS 版",
    secondaryCta: "探索 Skills",
    note: "0.1.0 Alpha · 非官方社区项目 · macOS 13+ · MIT",
  },
  workflow: {
    title: "三步搞定",
    steps: [
      {
        title: "按键说话",
        desc: "F5——或你指定的任意快捷键 · 音频直接发送到 ChatGPT 转写",
      },
      {
        title: "Skill 塑形",
        desc: "转写、邮件、提交信息、回复——选择文字落地的形态",
      },
      {
        title: "先审后发",
        desc: "始终先看到结果 · 自动粘贴不安全时，文字留在剪贴板",
      },
    ],
  },
  apps: { title: "在你已经打字的地方直接开口" },
  pillars: {
    title: "为写作而生，不止于转写",
    subtitle: "声明式 Skill · 无脚本 · 无副作用",
    items: [
      {
        title: "纯指令",
        desc: "纯文本提示词告诉模型如何塑造语音 · 你的 Mac 上不执行任何程序",
      },
      {
        title: "始终由你掌控",
        desc: "每条结果先预览 · 低风险 Skill 仅在验证通过后自动粘贴",
      },
      {
        title: "感知上下文",
        desc: "选中文本、剪贴板、写作风格——匹配你的语气、意图和术语",
      },
      {
        title: "完全可审计",
        desc: "每个 Skill 都在仓库里 · 读它、fork 它，或从零编写你自己的",
      },
    ],
  },
  spotlight: {
    eyebrow: "Skills",
    title: "一个目录，无限形态",
    subtitle: "从忠实转写到结构化报告——打开任意 Skill 阅读完整源码",
    cta: "探索全部 Skills",
  },
  privacyPanel: {
    eyebrow: "隐私",
    title: "你的文字始终在你手中",
    points: [
      {
        title: "无项目服务器",
        desc: "没有 VibeCompose 账户或中转服务 · 本地指标默认关闭且不会自动上传",
      },
      {
        title: "本地优先存储",
        desc: "历史保存在你的 Mac · 音频和可选润色请求直接发送到 ChatGPT",
      },
      {
        title: "发送前先审阅",
        desc: "高风险 Skill 始终预览 · 自动粘贴被阻止时，剪贴板兜底",
      },
    ],
  },
  openSource: {
    eyebrow: "开源",
    title: "MIT，从头到尾",
    body: "独立且非官方 · 应用与 Skill 同处一个公开仓库 · 读每一行代码 · 提 issue · 贡献代码",
    cta: "在 GitHub 查看",
    license: "MIT 许可证",
  },
  finalCta: {
    title: "你的声音值得更好的输出",
    subtitle: "下载 Alpha，体验 Skills 能做什么",
    primary: "获取 macOS 版",
    secondary: "探索 Skills",
  },
  skillsPage: {
    title: "Skills",
    subtitle: "声明式指令，为特定任务塑造语音 · 打开任意一个查看完整源码与文档",
    searchPlaceholder: "搜索 Skills…",
    results: { one: "{count} 个 Skill", other: "{count} 个 Skill" },
    filterAll: "全部",
    filterSource: "来源",
    filterCategory: "分类",
    empty: "没有符合条件的 Skill",
    catalogNote: "构建时从仓库生成",
  },
  skillDetail: {
    maintainedIn: "在 GitHub 维护",
    directoryDesc: "仓库目录是唯一事实来源",
    downloadDesc: "原始 SKILL.md 指令文件",
    summaryHeading: "它做什么",
    contextHeading: "上下文",
    requiredContext: "必需",
    optionalContext: "可选",
    deliveryHeading: "交付",
    formatHeading: "格式",
    riskHeading: "风险",
    howToUseHeading: "如何使用",
    howToUseSteps: [
      "在 VibeCompose 中选择该 Skill",
      "按住快捷键并说话",
      "审阅结果，然后粘贴",
    ],
    declarativeNote:
      "纯指令 · 不含代码 · 你的机器上不运行任何程序——只告诉模型如何塑造你的文字",
    relatedHeading: "相关",
    versionLabel: "版本",
    sourceLabel: "来源",
    categoryLabel: "分类",
  },
  labels: {
    source: {
      "built-in": "内置",
      community: "社区",
      example: "示例",
    },
    category: {
      dictation: "转写",
      writing: "写作",
      developer: "开发",
      meeting: "会议",
      product: "产品",
      support: "客服",
      translation: "翻译",
      context: "上下文",
    },
    delivery: {
      "automatic-when-verified": "验证后自动粘贴",
      preview: "先预览",
      "copy-only": "仅复制",
    },
    deliveryDesc: {
      "automatic-when-verified": "通过校验的低风险输出自动粘贴",
      preview: "你先审阅，再决定是否交付",
      "copy-only": "仅进剪贴板，绝不自动粘贴",
    },
    risk: { low: "低", medium: "中", high: "高" },
    context: {
      voice: "语音",
      selection: "选中文本",
      styleCapsule: "风格胶囊",
      clipboard: "剪贴板",
      focusedParagraph: "光标所在段落",
    },
    format: { plainText: "纯文本", markdown: "Markdown" },
    language: { en: "英语", "zh-Hans": "中文" },
  },
  download: {
    title: "下载",
    subtitle: "macOS 0.1.0 Alpha · 早期版本，快速迭代中",
    requirement: "需要 macOS 13 或更高版本",
    steps: [
      {
        title: "从源码构建",
        desc: "克隆仓库，按 README 操作 · 尚无签名二进制",
      },
      {
        title: "授予两项权限",
        desc: "麦克风用于录音 · 辅助功能用于自动粘贴（可选——剪贴板始终可用）",
      },
      {
        title: "连接你的服务",
        desc: "默认路径使用你的 ChatGPT 会话——不是公开 API，不是合作关系，不承诺无限",
      },
    ],
    note: "活跃开发中的 Alpha · 无 App Store 上架 · 从开源仓库安装",
  },
  about: {
    title: "关于",
    body: [
      "VibeCompose 是面向 macOS 的语音优先写作工具 · 按一个快捷键，说话，通过 Skill 得到有结构的文字——Skill 是声明式指令，永远不在你的机器上运行代码",
      "0.1.0 Alpha · 功能持续演进 · Skill 目录在公开仓库中成长 · 每个内置 Skill 都可查看源码 · 仅本地安装——没有远程商店",
      "独立于 OpenAI 和任何服务商 · 你选择服务 · 限额跟随上游",
    ],
  },
  legal: {
    privacyTitle: "隐私",
    termsTitle: "条款",
    updated: "最后更新：2026-07-24",
    privacy: [
      {
        title: "零遥测",
        desc: "不收集任何分析数据、指标或追踪信息",
      },
      {
        title: "本地历史",
        desc: "转写历史保存在你的 Mac，随时可清除",
      },
      {
        title: "第三方服务",
        desc: "音频处理遵循服务商隐私政策 · 默认路径不是公开 API，也不承诺无限 · 选择你信任的服务",
      },
      {
        title: "本网站",
        desc: "GitHub Pages 静态站 · 无 cookie · 无追踪",
      },
    ],
    terms: [
      {
        title: "Alpha 软件",
        desc: "Alpha 阶段按原样提供，不附带任何形式的担保",
      },
      {
        title: "MIT 许可证",
        desc: "源码基于 MIT 授权 · 详见仓库 LICENSE",
      },
      {
        title: "你的责任",
        desc: "使用前请审阅生成文字 · Skill 塑造输出，但不保证正确性",
      },
    ],
  },
  footer: {
    tagline: "说出 · 塑造 · 交付",
    columns: [
      {
        heading: "产品",
        links: [
          { label: "Skills", href: "/skills" },
          { label: "下载", href: "/download" },
          { label: "关于", href: "/about" },
        ],
      },
      {
        heading: "法律",
        links: [
          { label: "隐私", href: "/privacy" },
          { label: "条款", href: "/terms" },
        ],
      },
    ],
    copyright: "© {year} VibeCompose 贡献者 · MIT",
    disclaimer:
      "Alpha 软件 · 默认 ChatGPT 路径不是稳定公开 API · 不保证无限用量 · 与 OpenAI 或任何转写服务商均无从属关系",
  },
};
