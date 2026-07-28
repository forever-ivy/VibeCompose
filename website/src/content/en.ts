import type { Dictionary } from "./dictionary";

export const en: Dictionary = {
  meta: {
    title: "VibeCompose — Your Voice, Refined",
    description:
      "Voice-first writing for macOS · Declarative Skills turn raw speech into ready-to-send text · Open source · MIT",
  },
  nav: {
    brand: "VibeCompose",
    skills: "Skills",
    download: "Download",
    about: "About",
    github: "GitHub",
    openMenu: "Open menu",
    closeMenu: "Close menu",
  },
  actions: {
    download: "Download",
    viewSkills: "Explore Skills",
    viewOnGithub: "View on GitHub",
    openDirectory: "Open on GitHub",
    downloadSkill: "Download SKILL.md",
    viewDoc: "View SKILL.md",
    backToSkills: "All Skills",
    browseAll: "All Skills",
    learnMore: "Learn more",
  },
  badges: {
    alpha: "Alpha",
    openSource: "Open source",
    noTelemetry: "No project server",
    local: "Local controls",
  },
  hero: {
    eyebrow: "macOS · Voice-first writing",
    titleLines: ["Talk naturally", "Get text that's ready to send"],
    subtitle:
      "One hotkey · Speak your mind · A declarative Skill shapes every result into clean, structured text — no code runs on your machine",
    primaryCta: "Get VibeCompose for macOS",
    secondaryCta: "Explore Skills",
    note: "0.1.0 Alpha · Unofficial community project · macOS 13+ · MIT",
  },
  workflow: {
    title: "Three steps. That's it",
    steps: [
      {
        title: "Press and speak",
        desc: "F5 — or any shortcut you choose · Audio is sent directly to ChatGPT for transcription",
      },
      {
        title: "A Skill shapes it",
        desc: "Transcript, email, commit message, reply — pick the format your words land in",
      },
      {
        title: "Review, then deliver",
        desc: "Always see the result first · If auto-paste isn't safe, it lands in your clipboard",
      },
    ],
  },
  apps: { title: "Works wherever you already type" },
  pillars: {
    title: "Writing, not just transcription",
    subtitle: "Declarative Skills · No scripts · No side effects",
    items: [
      {
        title: "Pure instructions",
        desc: "Plain-text prompts tell the model how to shape your speech · Nothing executes on your Mac",
      },
      {
        title: "You're always in control",
        desc: "Every result previews first · Low-risk Skills auto-paste only after verification",
      },
      {
        title: "Context-aware",
        desc: "Selected text, clipboard, writing style — matches your tone, intent, and terminology",
      },
      {
        title: "Fully auditable",
        desc: "Every Skill lives in the repo · Read it, fork it, or write your own from scratch",
      },
    ],
  },
  spotlight: {
    eyebrow: "Skills",
    title: "One catalog, unlimited formats",
    subtitle: "From faithful transcription to structured reports — open any Skill and read the source",
    cta: "Explore all Skills",
  },
  privacyPanel: {
    eyebrow: "Privacy",
    title: "Your words never leave your control",
    points: [
      {
        title: "No project server",
        desc: "No VibeCompose account or relay · Local metrics are off by default and never auto-uploaded",
      },
      {
        title: "Local-first storage",
        desc: "History lives on your Mac · Audio and optional polish requests go directly to ChatGPT",
      },
      {
        title: "Review before delivery",
        desc: "High-risk Skills always preview · Clipboard fallback when auto-paste is blocked",
      },
    ],
  },
  openSource: {
    eyebrow: "Open source",
    title: "MIT from top to bottom",
    body: "Independent and unofficial · App and Skills share one public repo · Read every line · File issues · Ship contributions",
    cta: "View on GitHub",
    license: "MIT License",
  },
  finalCta: {
    title: "Your voice deserves a better output",
    subtitle: "Download the Alpha and see what Skills can do",
    primary: "Get VibeCompose for macOS",
    secondary: "Explore Skills",
  },
  skillsPage: {
    title: "Skills",
    subtitle: "Declarative instructions that shape speech for specific tasks · Open any one for full source and docs",
    searchPlaceholder: "Search Skills…",
    results: { one: "{count} Skill", other: "{count} Skills" },
    filterAll: "All",
    filterSource: "Source",
    filterCategory: "Category",
    empty: "No Skills match your filter",
    catalogNote: "Generated from the repository at build time",
  },
  skillDetail: {
    maintainedIn: "On GitHub",
    directoryDesc: "The repo directory is the single source of truth",
    downloadDesc: "Raw SKILL.md instruction file",
    summaryHeading: "What it does",
    contextHeading: "Context",
    requiredContext: "Required",
    optionalContext: "Optional",
    deliveryHeading: "Delivery",
    formatHeading: "Format",
    riskHeading: "Risk",
    howToUseHeading: "How to use",
    howToUseSteps: [
      "Select this Skill in VibeCompose",
      "Hold your hotkey and speak",
      "Review the result, then paste",
    ],
    declarativeNote:
      "Pure instructions · No code · Nothing runs on your machine — only the model is told how to shape your words",
    relatedHeading: "Related",
    versionLabel: "Version",
    sourceLabel: "Source",
    categoryLabel: "Category",
  },
  labels: {
    source: {
      "built-in": "Built-in",
      community: "Community",
      example: "Example",
    },
    category: {
      dictation: "Dictation",
      writing: "Writing",
      developer: "Developer",
      meeting: "Meetings",
      product: "Product",
      support: "Support",
      translation: "Translation",
      context: "Context",
    },
    delivery: {
      "automatic-when-verified": "Auto-paste when verified",
      preview: "Preview first",
      "copy-only": "Copy only",
    },
    deliveryDesc: {
      "automatic-when-verified": "Verified low-risk output pastes automatically",
      preview: "You review before anything is delivered",
      "copy-only": "Clipboard only — never auto-pasted",
    },
    risk: { low: "Low", medium: "Medium", high: "High" },
    context: {
      voice: "Voice",
      selection: "Selection",
      styleCapsule: "Style capsule",
      clipboard: "Clipboard",
      focusedParagraph: "Focused paragraph",
    },
    format: { plainText: "Plain text", markdown: "Markdown" },
    language: { en: "English", "zh-Hans": "Chinese" },
  },
  download: {
    title: "Download",
    subtitle: "0.1.0 Alpha for macOS · Early, raw, and evolving fast",
    requirement: "Requires macOS 13 or later",
    steps: [
      {
        title: "Build from source",
        desc: "Clone the repo and follow the README · No signed binary yet",
      },
      {
        title: "Grant two permissions",
        desc: "Microphone for recording · Accessibility for auto-paste (optional — clipboard always works)",
      },
      {
        title: "Connect your provider",
        desc: "Default path uses your ChatGPT session — not a public API, not a partnership, not unlimited",
      },
    ],
    note: "Active Alpha · Not on the App Store · Install from the open-source repo",
  },
  about: {
    title: "About",
    body: [
      "VibeCompose is voice-first writing for macOS · Press one hotkey, speak, and get structured text through Skills — declarative instructions that never run code on your machine",
      "0.1.0 Alpha · The feature set is evolving · The Skill catalog grows in the open · Every built-in Skill lives in the repo · Local install only — no remote store",
      "Independent from OpenAI and every provider · You pick the service · Upstream limits apply",
    ],
  },
  legal: {
    privacyTitle: "Privacy",
    termsTitle: "Terms",
    updated: "Last updated: 2026-07-24",
    privacy: [
      {
        title: "Zero telemetry",
        desc: "No analytics, metrics, or tracking of any kind",
      },
      {
        title: "Local history",
        desc: "Dictation history stays on your Mac · Clear it anytime",
      },
      {
        title: "Third-party providers",
        desc: "Provider policies govern audio processing · Default route is not a public API and is not unlimited · Choose a provider you trust",
      },
      {
        title: "This website",
        desc: "Static GitHub Pages · No cookies · No tracking",
      },
    ],
    terms: [
      {
        title: "Alpha software",
        desc: "Provided as-is during Alpha, without warranty of any kind",
      },
      {
        title: "MIT License",
        desc: "Source code under MIT · See LICENSE in the repository",
      },
      {
        title: "Your responsibility",
        desc: "Review generated text before use · Skills shape output but do not guarantee correctness",
      },
    ],
  },
  footer: {
    tagline: "Speak · Shape · Deliver",
    columns: [
      {
        heading: "Product",
        links: [
          { label: "Skills", href: "/skills" },
          { label: "Download", href: "/download" },
          { label: "About", href: "/about" },
        ],
      },
      {
        heading: "Legal",
        links: [
          { label: "Privacy", href: "/privacy" },
          { label: "Terms", href: "/terms" },
        ],
      },
    ],
    copyright: "© {year} VibeCompose contributors · MIT",
    disclaimer:
      "Alpha software · Default ChatGPT route is not a stable public API · No guarantee of unlimited usage · Not affiliated with OpenAI or any transcription provider",
  },
};
