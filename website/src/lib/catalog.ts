import "server-only";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { parse as parseYaml } from "yaml";
import {
  BUILTIN_SKILLS_DIR,
  COMMUNITY_SKILLS_DIR,
  githubUrls,
} from "./site-config";
import type {
  SkillEntry,
  SkillCategory,
  SkillDelivery,
  SkillRisk,
  SkillContext,
  SkillFormat,
} from "./catalog-types";

/* ------------------------------------------------------------------ */
/* Locate the monorepo root from the website/ working directory.      */
/* ------------------------------------------------------------------ */
function findRepoRoot(): string {
  const candidates = [
    resolve(process.cwd(), ".."), // website/ -> repo root (next build cwd)
    process.cwd(),
    resolve(process.cwd(), "..", ".."),
  ];
  for (const c of candidates) {
    if (existsSync(join(c, BUILTIN_SKILLS_DIR))) return c;
  }
  throw new Error(
    `Cannot locate BuiltInSkills. Looked under: ${candidates.join(", ")}`,
  );
}

const REPO_ROOT = findRepoRoot();

/* ------------------------------------------------------------------ */
/* Slug -> category mapping for the 13 built-ins.                     */
/* ------------------------------------------------------------------ */
const CATEGORY_BY_SLUG: Record<string, SkillCategory> = {
  // dictation
  direct: "dictation",
  // writing (generate new prose from voice)
  reply: "writing",
  email: "writing",
  "better-question": "writing",
  "social-post": "writing",
  // context (transform existing selection / clipboard / paragraph)
  "context-rewrite": "context",
  "context-reply": "context",
  "context-summarize": "context",
  "clipboard-rewrite": "context",
  "paragraph-polish": "context",
  // developer
  "backend-prompt": "developer",
  "code-prompt": "developer",
  "frontend-prompt": "developer",
  "code-review-comment": "developer",
  "commit-message": "developer",
  "bug-report": "developer",
  "changelog-entry": "developer",
  "incident-report": "developer",
  // meeting
  "meeting-action-items": "meeting",
  "standup-update": "meeting",
  // product
  "product-brief": "product",
  // support
  "customer-support-reply": "support",
  // translation
  translate: "translation",
};

/** Featured on the homepage spotlight (plan §4.1.F). */
const FEATURED = new Set([
  "direct",
  "email",
  "reply",
  "commit-message",
  "bug-report",
  "context-rewrite",
]);

function normalizeDelivery(raw: unknown): SkillDelivery {
  switch (String(raw)) {
    case "automaticPasteWhenVerified":
      return "automatic-when-verified";
    case "copyOnly":
    case "clipboardOnly":
      return "copy-only";
    case "previewThenPaste":
    default:
      return "preview";
  }
}

function normalizeRisk(raw: unknown): SkillRisk {
  const v = String(raw);
  return v === "low" || v === "medium" || v === "high" ? v : "medium";
}

function normalizeContext(list: unknown): SkillContext[] {
  if (!Array.isArray(list)) return [];
  const allowed: SkillContext[] = [
    "voice",
    "selection",
    "styleCapsule",
    "clipboard",
    "focusedParagraph",
  ];
  return list
    .map((x) => String(x) as SkillContext)
    .filter((x) => allowed.includes(x));
}

function normalizeFormat(raw: unknown): SkillFormat {
  return String(raw) === "markdown" ? "markdown" : "plainText";
}

/* ------------------------------------------------------------------ */
/* Frontmatter parsing (--- yaml --- body).                           */
/* ------------------------------------------------------------------ */
interface Frontmatter {
  name?: string;
  description?: string;
  metadata?: {
    "display-name"?: string;
    version?: string;
  };
}

function parseFrontmatter(md: string): Frontmatter {
  const match = md.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!match) return {};
  try {
    return (parseYaml(match[1]) as Frontmatter) ?? {};
  } catch {
    return {};
  }
}

interface HostProfile {
  output?: { delivery?: string; risk?: string; format?: string };
  context?: { required?: unknown; optional?: unknown };
}

function readHostProfile(dir: string): HostProfile {
  const yamlPath = join(dir, "vibecompose.yaml");
  if (!existsSync(yamlPath)) return {};
  try {
    return (parseYaml(readFileSync(yamlPath, "utf8")) as HostProfile) ?? {};
  } catch {
    return {};
  }
}

function toTitleCase(slug: string): string {
  return slug
    .split("-")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

/* ------------------------------------------------------------------ */
/* Build a single entry from a skill directory.                       */
/* ------------------------------------------------------------------ */
function buildEntry(
  slug: string,
  repoRelDir: string,
  source: SkillEntry["source"],
): SkillEntry | null {
  const absDir = join(REPO_ROOT, repoRelDir);
  const skillMd = join(absDir, "SKILL.md");
  if (!existsSync(skillMd)) return null;

  const fm = parseFrontmatter(readFileSync(skillMd, "utf8"));
  const host = readHostProfile(absDir);

  const skillDocRepoPath = `${repoRelDir}/SKILL.md`;

  return {
    slug,
    name: fm.metadata?.["display-name"] ?? toTitleCase(fm.name ?? slug),
    summary: fm.description ?? "",
    source,
    category: CATEGORY_BY_SLUG[slug] ?? "writing",
    version: fm.metadata?.version ?? "1.0.0",
    delivery: normalizeDelivery(host.output?.delivery),
    risk: normalizeRisk(host.output?.risk),
    format: normalizeFormat(host.output?.format),
    requiredContext: normalizeContext(host.context?.required),
    optionalContext: normalizeContext(host.context?.optional),
    // Built-in skills operate in the speaker's language; the app ships zh/en.
    languages: ["en", "zh-Hans"],
    path: repoRelDir,
    githubUrl: githubUrls.tree(repoRelDir),
    skillDocUrl: githubUrls.blob(skillDocRepoPath),
    downloadUrl: githubUrls.raw(skillDocRepoPath),
    featured: FEATURED.has(slug),
  };
}

/* ------------------------------------------------------------------ */
/* Public loaders.                                                    */
/* ------------------------------------------------------------------ */
let _cache: SkillEntry[] | null = null;

export function getAllSkills(): SkillEntry[] {
  if (_cache) return _cache;

  const entries: SkillEntry[] = [];

  // 1) Built-in skills (always present).
  const builtinDir = join(REPO_ROOT, BUILTIN_SKILLS_DIR);
  const builtinSlugs = readdirSync(builtinDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
  for (const slug of builtinSlugs) {
    const entry = buildEntry(slug, `${BUILTIN_SKILLS_DIR}/${slug}`, "built-in");
    if (entry) entries.push(entry);
  }

  // 2) Community skills (optional; directory may not exist yet).
  const communityDir = join(REPO_ROOT, COMMUNITY_SKILLS_DIR);
  if (existsSync(communityDir)) {
    const communitySlugs = readdirSync(communityDir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
    for (const slug of communitySlugs) {
      const entry = buildEntry(
        slug,
        `${COMMUNITY_SKILLS_DIR}/${slug}`,
        "community",
      );
      if (entry) entries.push(entry);
    }
  }

  _cache = entries;
  return entries;
}

export function getSkillBySlug(slug: string): SkillEntry | undefined {
  return getAllSkills().find((s) => s.slug === slug);
}

export function getFeaturedSkills(): SkillEntry[] {
  return getAllSkills().filter((s) => s.featured);
}
