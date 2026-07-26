#!/usr/bin/env node
/**
 * Content contract for the static-exported website.
 *
 * Asserts honest Alpha-stage copy is present in both locales, that
 * GitHub deep-links exist for Skills, and that forbidden claims
 * (fake releases, OpenAI partnership, remote registry) are absent.
 *
 * Requires a prior `pnpm build` (reads website/out/).
 *
 * Run from website/:  node scripts/check-site-content.mjs
 */
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const websiteRoot = resolve(import.meta.dirname, "..");
const outDir = join(websiteRoot, "out");

assert.ok(
  existsSync(outDir),
  "website/out/ missing — run `pnpm build` first",
);

function read(rel) {
  const path = join(outDir, rel);
  assert.ok(existsSync(path), `exported page missing: ${rel}`);
  return readFileSync(path, "utf8");
}

function includes(html, text, label = text) {
  assert.ok(html.includes(text), `must include ${label}`);
}

function excludes(html, text, label = text) {
  assert.ok(!html.includes(text), `must NOT include ${label}`);
}

function hasHref(html, href) {
  const escaped = href.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  assert.match(
    html,
    new RegExp(`href=["']${escaped}["']`),
    `must link to ${href}`,
  );
}

const REPO = "https://github.com/forever-ivy/vibecompose";

/* ------------------------------------------------------------------ */
/* Shared global bans (any exported HTML).                            */
/* ------------------------------------------------------------------ */
function banForbiddenClaims(html, page) {
  excludes(html, "releases/tag/", `${page}: fake releases/tag/ link`);
  // Affirmative over-claims only — honest denials may mention the same terms.
  for (const phrase of [
    "official OpenAI partner",
    "official OpenAI partnership",
    "OpenAI 官方合作",
    "OpenAI 授权",
    "99.99%",
    "enterprise SLA",
    "企业级 SLA",
    "one-click community install",
    "一键安装社区包",
  ]) {
    excludes(html, phrase, `${page}: forbidden claim "${phrase}"`);
  }
}

/* ------------------------------------------------------------------ */
/* Locale-specific honesty phrases (plan §8.3).                       */
/* ------------------------------------------------------------------ */
const zhHome = read("zh-Hans/index.html");
const enHome = read("en/index.html");
const zhDownload = read("zh-Hans/download/index.html");
const enDownload = read("en/download/index.html");
const zhAbout = read("zh-Hans/about/index.html");
const enAbout = read("en/about/index.html");
const zhSkills = read("zh-Hans/skills/index.html");
const enSkills = read("en/skills/index.html");
const zhEmail = read("zh-Hans/skills/email/index.html");
const enEmail = read("en/skills/email/index.html");

for (const [page, html] of [
  ["zh-Hans/", zhHome],
  ["en/", enHome],
  ["zh-Hans/download/", zhDownload],
  ["en/download/", enDownload],
  ["zh-Hans/about/", zhAbout],
  ["en/about/", enAbout],
  ["zh-Hans/skills/", zhSkills],
  ["en/skills/", enSkills],
  ["zh-Hans/skills/email/", zhEmail],
  ["en/skills/email/", enEmail],
]) {
  banForbiddenClaims(html, page);
  includes(html, "VibeCompose", `${page}: product name`);
  includes(html, "MIT", `${page}: MIT license`);
  hasHref(html, REPO);
}

// Chinese honesty phrases (home + download cover the contract).
for (const html of [zhHome, zhDownload, zhAbout]) {
  includes(html, "0.1.0 Alpha", "zh: version label");
  includes(html, "F5", "zh: F5 hotkey");
  includes(html, "ChatGPT", "zh: ChatGPT boundary");
  includes(html, "剪贴板", "zh: clipboard fallback");
  includes(html, "不是稳定公开 API", "zh: non-stable public API");
  includes(html, "不承诺无限用量", "zh: no unlimited usage promise");
}

// English honesty phrases.
for (const html of [enHome, enDownload, enAbout]) {
  includes(html, "0.1.0 Alpha", "en: version label");
  includes(html, "F5", "en: F5 hotkey");
  includes(html, "ChatGPT", "en: ChatGPT boundary");
  includes(html, "clipboard", "en: clipboard fallback");
  includes(html, "stable public API", "en: non-stable public API");
  includes(html, "unlimited usage", "en: no unlimited usage promise");
}

// Skills acceptance: multi-skill list + detail deep-links.
const EMAIL_TREE =
  `${REPO}/tree/main/Sources/VibeCompose/Resources/BuiltInSkills/email`;
const EMAIL_BLOB =
  `${REPO}/blob/main/Sources/VibeCompose/Resources/BuiltInSkills/email/SKILL.md`;
const EMAIL_RAW =
  "https://raw.githubusercontent.com/forever-ivy/vibecompose/main/Sources/VibeCompose/Resources/BuiltInSkills/email/SKILL.md";

for (const [locale, html] of [
  ["zh-Hans", zhEmail],
  ["en", enEmail],
]) {
  hasHref(html, EMAIL_TREE);
  hasHref(html, EMAIL_BLOB);
  hasHref(html, EMAIL_RAW);
  includes(
    html,
    "Sources/VibeCompose/Resources/BuiltInSkills/email",
    `${locale}/skills/email: on-disk path`,
  );
}

// Skills list must surface multiple cards (at least a few built-ins).
for (const [locale, html] of [
  ["zh-Hans", zhSkills],
  ["en", enSkills],
]) {
  for (const slug of ["email", "direct", "commit-message", "bug-report"]) {
    assert.match(
      html,
      new RegExp(`/skills/${slug}/?`),
      `${locale}/skills list must link to ${slug}`,
    );
  }
}

// Count exported skill detail pages (each locale).
const enSkillDirs = readdirSync(join(outDir, "en", "skills"), {
  withFileTypes: true,
})
  .filter((d) => d.isDirectory())
  .map((d) => d.name);
assert.ok(
  enSkillDirs.length >= 13,
  `expected ≥13 exported en skill pages, found ${enSkillDirs.length}`,
);

console.log(
  `site content contract passed` +
    ` (${enSkillDirs.length} skill detail pages per locale)`,
);
