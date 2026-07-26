/** Public, shareable catalog types (safe to import in client components). */

export type SkillSource = "built-in" | "community" | "example";

export type SkillCategory =
  | "dictation"
  | "writing"
  | "developer"
  | "meeting"
  | "product"
  | "support"
  | "translation"
  | "context";

/** Public delivery labels (normalized from the Host Profile). */
export type SkillDelivery = "automatic-when-verified" | "preview" | "copy-only";

export type SkillRisk = "low" | "medium" | "high";

export type SkillLanguage = "en" | "zh-Hans";

/** Output format declared in the Host Profile. */
export type SkillFormat = "plainText" | "markdown";

/** Context signals a skill declares (matches the on-disk vocabulary). */
export type SkillContext =
  | "voice"
  | "selection"
  | "styleCapsule"
  | "clipboard"
  | "focusedParagraph";

export interface SkillEntry {
  slug: string;
  /** English display name from metadata.display-name. */
  name: string;
  /** English public summary (frontmatter description). */
  summary: string;
  source: SkillSource;
  category: SkillCategory;
  version: string;
  delivery: SkillDelivery;
  risk: SkillRisk;
  format: SkillFormat;
  requiredContext: SkillContext[];
  optionalContext: SkillContext[];
  languages: SkillLanguage[];
  /** Repo-relative directory, e.g. Sources/.../BuiltInSkills/email */
  path: string;
  /** GitHub tree deep link to the skill's maintenance directory. */
  githubUrl: string;
  /** GitHub blob link to SKILL.md (viewable). */
  skillDocUrl: string;
  /** Raw SKILL.md link (directly downloadable). */
  downloadUrl: string;
  featured: boolean;
}

export const CATEGORY_ORDER: SkillCategory[] = [
  "dictation",
  "writing",
  "developer",
  "context",
  "meeting",
  "product",
  "support",
  "translation",
];
