import type { Locale } from "@/lib/i18n";
import type {
  SkillSource,
  SkillCategory,
  SkillDelivery,
  SkillRisk,
  SkillContext,
  SkillFormat,
  SkillLanguage,
} from "@/lib/catalog-types";
import { en } from "./en";
import { zhHans } from "./zh-Hans";

interface TitleDesc {
  title: string;
  desc: string;
}

export interface Dictionary {
  meta: { title: string; description: string };
  nav: {
    brand: string;
    skills: string;
    download: string;
    about: string;
    github: string;
    openMenu: string;
    closeMenu: string;
  };
  actions: {
    download: string;
    viewSkills: string;
    viewOnGithub: string;
    openDirectory: string;
    downloadSkill: string;
    viewDoc: string;
    backToSkills: string;
    browseAll: string;
    learnMore: string;
  };
  badges: {
    alpha: string;
    openSource: string;
    noTelemetry: string;
    local: string;
  };
  hero: {
    eyebrow: string;
    titleLines: string[];
    subtitle: string;
    primaryCta: string;
    secondaryCta: string;
    note: string;
  };
  workflow: { title: string; steps: TitleDesc[] };
  apps: { title: string };
  pillars: { title: string; subtitle: string; items: TitleDesc[] };
  spotlight: {
    eyebrow: string;
    title: string;
    subtitle: string;
    cta: string;
  };
  privacyPanel: { eyebrow: string; title: string; points: TitleDesc[] };
  openSource: {
    eyebrow: string;
    title: string;
    body: string;
    cta: string;
    license: string;
  };
  finalCta: {
    title: string;
    subtitle: string;
    primary: string;
    secondary: string;
  };
  skillsPage: {
    title: string;
    subtitle: string;
    searchPlaceholder: string;
    /** Templates with a {count} placeholder. */
    results: { one: string; other: string };
    filterAll: string;
    filterSource: string;
    filterCategory: string;
    empty: string;
    catalogNote: string;
  };
  skillDetail: {
    maintainedIn: string;
    directoryDesc: string;
    downloadDesc: string;
    summaryHeading: string;
    contextHeading: string;
    requiredContext: string;
    optionalContext: string;
    deliveryHeading: string;
    formatHeading: string;
    riskHeading: string;
    howToUseHeading: string;
    howToUseSteps: string[];
    declarativeNote: string;
    relatedHeading: string;
    versionLabel: string;
    sourceLabel: string;
    categoryLabel: string;
  };
  labels: {
    source: Record<SkillSource, string>;
    category: Record<SkillCategory, string>;
    delivery: Record<SkillDelivery, string>;
    deliveryDesc: Record<SkillDelivery, string>;
    risk: Record<SkillRisk, string>;
    context: Record<SkillContext, string>;
    format: Record<SkillFormat, string>;
    language: Record<SkillLanguage, string>;
  };
  download: {
    title: string;
    subtitle: string;
    requirement: string;
    steps: TitleDesc[];
    note: string;
  };
  about: { title: string; body: string[] };
  legal: {
    privacyTitle: string;
    termsTitle: string;
    updated: string;
    privacy: TitleDesc[];
    terms: TitleDesc[];
  };
  footer: {
    tagline: string;
    columns: { heading: string; links: { label: string; href: string }[] }[];
    /** Template with a {year} placeholder. */
    copyright: string;
    disclaimer: string;
  };
}

const dictionaries: Record<Locale, Dictionary> = {
  en,
  "zh-Hans": zhHans,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale];
}

/** Replace a single `{token}` placeholder in a template string. */
export function fill(template: string, token: string, value: string | number): string {
  return template.split(`{${token}}`).join(String(value));
}

/** Format a "{count} results" string, choosing singular/plural by count. */
export function formatResults(
  results: { one: string; other: string },
  count: number,
): string {
  return fill(count === 1 ? results.one : results.other, "count", count);
}
