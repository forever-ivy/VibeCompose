# VibeCompose website

Static marketing site and Skill catalog for [VibeCompose](https://github.com/forever-ivy/vibecompose).

- **Stack:** Next.js 15 (App Router) · React 19 · Tailwind CSS 4 · Framer Motion
- **Export:** `output: 'export'` → `out/` for GitHub Pages (`basePath: /vibecompose`)
- **Locales:** `/zh-Hans` (default) and `/en`
- **Skill truth source:** on-disk `Sources/VibeCompose/Resources/BuiltInSkills/*/SKILL.md` (build-time catalog)

## Commands

```bash
pnpm install
pnpm dev
pnpm build
pnpm verify   # build + catalog path check + content contract
```

## Content contract

`pnpm verify` asserts:

1. Every built-in skill directory has a `SKILL.md` and emits correct GitHub tree/blob/raw URLs.
2. Exported HTML includes honest Alpha copy (product name, `0.1.0 Alpha`, `F5`, `ChatGPT`, clipboard fallback, non-stable public API, no unlimited usage, MIT, repo link).
3. No fake `releases/tag/` links or partnership/SLA claims.
4. Skill list + detail pages deep-link to the monorepo skill directories.

## Scope (honest boundaries)

This site is marketing + a browseable Skill directory. Skills are declarative instructions only; packages are hosted on GitHub and imported locally in the macOS app. There is no account system, remote registry, pricing, or claimed signed production download.
