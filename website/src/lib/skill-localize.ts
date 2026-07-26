import type { Locale } from "@/lib/i18n";
import type { SkillEntry } from "@/lib/catalog-types";
import { skillCopyZh } from "@/content/skill-copy";

/** Display name + summary for a skill in the active locale. */
export function localizeSkill(
  skill: SkillEntry,
  locale: Locale,
): { name: string; summary: string } {
  if (locale === "zh-Hans") {
    const zh = skillCopyZh[skill.slug];
    if (zh) return zh;
  }
  return { name: skill.name, summary: skill.summary };
}
