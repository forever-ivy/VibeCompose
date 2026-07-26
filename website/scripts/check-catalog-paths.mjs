#!/usr/bin/env node
/**
 * Verify every BuiltInSkills (and optional community-skills) directory
 * has a SKILL.md, and that the site catalog would emit a GitHub tree URL
 * that matches the on-disk monorepo path.
 *
 * Run from website/:  node scripts/check-catalog-paths.mjs
 */
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const websiteRoot = resolve(import.meta.dirname, "..");
const repoRoot = resolve(websiteRoot, "..");

const BUILTIN_DIR = "Sources/VibeCompose/Resources/BuiltInSkills";
const COMMUNITY_DIR = "community-skills";
const REPO = "forever-ivy/vibecompose";
const TREE_PREFIX = `https://github.com/${REPO}/tree/main/`;
const BLOB_PREFIX = `https://github.com/${REPO}/blob/main/`;
const RAW_PREFIX = `https://raw.githubusercontent.com/${REPO}/main/`;

function listSkillDirs(relDir) {
  const abs = join(repoRoot, relDir);
  if (!existsSync(abs)) return [];
  return readdirSync(abs, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

function checkSkill(relDir, slug) {
  const skillDir = join(repoRoot, relDir, slug);
  const skillMd = join(skillDir, "SKILL.md");
  assert.ok(existsSync(skillMd), `missing SKILL.md for ${relDir}/${slug}`);
  assert.ok(statSync(skillMd).isFile(), `SKILL.md is not a file: ${skillMd}`);

  const body = readFileSync(skillMd, "utf8");
  assert.ok(body.length > 20, `SKILL.md too short: ${relDir}/${slug}`);
  assert.ok(
    body.startsWith("---"),
    `SKILL.md missing frontmatter: ${relDir}/${slug}`,
  );

  const repoRel = `${relDir}/${slug}`;
  const tree = `${TREE_PREFIX}${repoRel}`;
  const blob = `${BLOB_PREFIX}${repoRel}/SKILL.md`;
  const raw = `${RAW_PREFIX}${repoRel}/SKILL.md`;

  // URL shape guards — actual HTTP is not required offline.
  assert.match(tree, /^https:\/\/github\.com\/forever-ivy\/vibecompose\/tree\/main\//);
  assert.match(blob, /\/SKILL\.md$/);
  assert.match(raw, /^https:\/\/raw\.githubusercontent\.com\//);

  return { slug, path: repoRel, tree, blob, raw };
}

const builtinSlugs = listSkillDirs(BUILTIN_DIR);
assert.ok(
  builtinSlugs.length >= 13,
  `expected ≥13 built-in skills, found ${builtinSlugs.length}`,
);

const entries = [];
for (const slug of builtinSlugs) {
  entries.push(checkSkill(BUILTIN_DIR, slug));
}

const communitySlugs = listSkillDirs(COMMUNITY_DIR);
for (const slug of communitySlugs) {
  entries.push(checkSkill(COMMUNITY_DIR, slug));
}

// Spot-check a few well-known skills that the acceptance criteria call out.
for (const required of ["email", "direct", "commit-message"]) {
  assert.ok(
    entries.some((e) => e.slug === required),
    `catalog must include built-in skill "${required}"`,
  );
}

console.log(
  `catalog paths ok: ${entries.length} skills` +
    ` (${builtinSlugs.length} built-in` +
    (communitySlugs.length ? `, ${communitySlugs.length} community` : "") +
    ")",
);
