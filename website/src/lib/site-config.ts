/**
 * Public site constants. Kept in sync with product.env / version.env.
 * Update here when the repo values change (a Phase 2 script can generate this).
 */
export const siteConfig = {
  productName: "VibeCompose",
  version: "0.1.0",
  versionLabel: "0.1.0 Alpha",
  minMacOS: "13.0",
  minMacOSLabel: "macOS 13+",
  repository: "forever-ivy/vibecompose",
  repoUrl: "https://github.com/forever-ivy/vibecompose",
  license: "MIT",
  // Public-stage flags
  alpha: true,
  registryEnabled: false,
} as const;

const RAW_BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? "/vibecompose";
/** Base path without trailing slash; "" when deployed at a root domain. */
export const basePath = RAW_BASE === "/" ? "" : RAW_BASE.replace(/\/$/, "");

/** Prefix an internal absolute path (e.g. "/brand/og.png") with basePath. */
export function withBasePath(path: string): string {
  if (!path.startsWith("/")) return path;
  return `${basePath}${path}`;
}

const REPO_TREE = `${siteConfig.repoUrl}/tree/main`;
const REPO_BLOB = `${siteConfig.repoUrl}/blob/main`;
const REPO_RAW = `https://raw.githubusercontent.com/${siteConfig.repository}/main`;

/** Location of built-in skills inside the monorepo. */
export const BUILTIN_SKILLS_DIR =
  "Sources/VibeCompose/Resources/BuiltInSkills";
/** Location of curated community skills (may not exist yet). */
export const COMMUNITY_SKILLS_DIR = "community-skills";

export const githubUrls = {
  tree: (repoPath: string) => `${REPO_TREE}/${repoPath}`,
  blob: (repoPath: string) => `${REPO_BLOB}/${repoPath}`,
  raw: (repoPath: string) => `${REPO_RAW}/${repoPath}`,
  security: `${REPO_BLOB}/SECURITY.md`,
  contributing: `${REPO_BLOB}/CONTRIBUTING.md`,
  license: `${REPO_BLOB}/LICENSE`,
};
