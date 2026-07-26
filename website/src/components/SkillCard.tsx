import Link from "next/link";
import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import type { SkillEntry } from "@/lib/catalog-types";
import { localizeSkill } from "@/lib/skill-localize";
import { StatusBadge } from "./StatusBadge";

const riskTone = {
  low: "low",
  medium: "medium",
  high: "high",
} as const;

export function SkillCard({
  skill,
  locale,
  dict,
}: {
  skill: SkillEntry;
  locale: Locale;
  dict: Dictionary;
}) {
  const { name, summary } = localizeSkill(skill, locale);

  return (
    <Link
      href={localeHref(locale, `/skills/${skill.slug}`)}
      className="skill-card group flex h-full flex-col gap-3 rounded-card border border-line bg-bg p-6"
    >
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="accent">
          {dict.labels.category[skill.category]}
        </StatusBadge>
        <StatusBadge tone="outline">
          {dict.labels.source[skill.source]}
        </StatusBadge>
        <StatusBadge tone={riskTone[skill.risk]}>
          {dict.labels.risk[skill.risk]}
        </StatusBadge>
      </div>

      <div>
        <h3 className="text-[16px] font-semibold tracking-tight text-ink transition-colors group-hover:text-ink">
          {name}
        </h3>
        <p className="mt-2 line-clamp-3 text-[14px] leading-relaxed text-muted">
          {summary}
        </p>
      </div>

      <div className="mt-auto flex items-center justify-between pt-2 text-[12px] text-muted">
        <span>{dict.labels.delivery[skill.delivery]}</span>
        <span className="font-mono opacity-70">v{skill.version}</span>
      </div>
    </Link>
  );
}
