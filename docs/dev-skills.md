# AI Development Skills

VibeCompose is developed with the help of AI coding agents. Those agents load a
set of reusable "skills" (prompt/reference bundles) that live under `.agents/`
and are symlinked into `.claude/skills/`.

These skills are **third-party content, synced from upstream repositories**. They
are development tooling only — they are not part of the shipped app, not
referenced by the Swift package or build scripts, and not required to build,
test, or run VibeCompose. For that reason they are **not vendored into this
repository**; both `.agents/` and `.claude/skills/` are git-ignored.

## Sources and licenses

`skills-lock.json` (tracked at the repo root) is the machine-readable manifest
recording the exact upstream source, path, and content hash of every synced
skill. The upstream repositories are:

| Upstream | License |
| --- | --- |
| [`emilkowalski/skills`](https://github.com/emilkowalski/skills) | MIT |
| [`rshankras/claude-code-apple-skills`](https://github.com/rshankras/claude-code-apple-skills) | MIT |

Both are MIT-licensed. If you redistribute any of this content, retain the
respective upstream copyright and license notices as required by the MIT
License.

## Restoring the skills locally

The skills are optional. You only need them if you want the AI agents to use the
same skill set the maintainers use. To restore them, clone each upstream
repository and place the skill directories under `.agents/skills/`, then symlink
the ones you want into `.claude/skills/`. Consult `skills-lock.json` for the
exact `skillPath` of each entry.
