#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const html = readFileSync(resolve(root, "docs", "index.html"), "utf8");

function includes(text, label = text) {
  assert.ok(html.includes(text), `landing page must include ${label}`);
}

function hasAnchor(id) {
  assert.match(html, new RegExp(`id=["']${id}["']`), `landing page must include #${id}`);
}

function hasHref(href) {
  const escaped = href.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  assert.match(html, new RegExp(`href=["']${escaped}["']`), `landing page must link to ${href}`);
}

assert.match(html, /<html\s+lang=["']zh-CN["']/, "landing page should be Chinese-first");
includes("VibeCompose", "product name");
includes("0.1.0 Alpha", "alpha version status");
includes("F5", "F5 workflow");
includes("ChatGPT", "ChatGPT account boundary");
includes("剪贴板", "clipboard fallback");
includes("不是稳定公开 API", "private backend boundary");
includes("不承诺无限用量", "upstream usage boundary");
includes("MIT", "license");

for (const id of ["hero", "workflow", "product", "safety"]) {
  hasAnchor(id);
}

hasHref("https://github.com/forever-ivy/vibecompose");
hasHref("product/community-skills-core-next-step-plan-2026-07-15.md");
hasHref("audits/security-audit-2026-07-13.md");

assert.ok(!html.includes("releases/tag/"), "alpha landing page must not claim a published release");
console.log("VibeCompose landing page content contract passed");
