import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, localeHref, locales, type Locale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { getAllSkills, getSkillBySlug } from "@/lib/catalog";
import { localizeSkill } from "@/lib/skill-localize";
import { Button } from "@/components/Button";
import { StatusBadge } from "@/components/StatusBadge";
import { SkillCard } from "@/components/SkillCard";
import { RevealOnScroll } from "@/components/RevealOnScroll";

export function generateStaticParams() {
  const skills = getAllSkills();
  return locales.flatMap((locale) =>
    skills.map((skill) => ({ locale, slug: skill.slug })),
  );
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string; slug: string }>;
}): Promise<Metadata> {
  const { locale, slug } = await params;
  if (!isLocale(locale)) return {};
  const skill = getSkillBySlug(slug);
  if (!skill) return {};
  const dict = getDictionary(locale);
  const { name, summary } = localizeSkill(skill, locale);
  return {
    title: `${name} · ${dict.skillsPage.title}`,
    description: summary,
  };
}

export default async function SkillDetailPage({
  params,
}: {
  params: Promise<{ locale: string; slug: string }>;
}) {
  const { locale, slug } = await params;
  if (!isLocale(locale)) notFound();
  const typedLocale = locale as Locale;
  const skill = getSkillBySlug(slug);
  if (!skill) notFound();

  const dict = getDictionary(typedLocale);
  const { name, summary } = localizeSkill(skill, typedLocale);

  const related = getAllSkills()
    .filter((s) => s.slug !== skill.slug && s.category === skill.category)
    .slice(0, 3);

  const riskTone = {
    low: "low",
    medium: "medium",
    high: "high",
  } as const;

  return (
    <div className="mx-auto max-w-[1200px] px-5 py-16 md:px-8 md:py-20">
      <Link
        href={localeHref(typedLocale, "/skills")}
        className="nav-link text-sm text-muted hover:text-ink"
      >
        ← {dict.actions.backToSkills}
      </Link>

      <div className="mt-8 grid gap-12 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <div>
          <RevealOnScroll>
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
              <StatusBadge tone="neutral">
                {dict.skillDetail.versionLabel} {skill.version}
              </StatusBadge>
            </div>

            <h1 className="display-section mt-5 text-[32px] md:text-[40px]">
              {name}
            </h1>
            <p className="mt-4 max-w-2xl text-[16px] leading-relaxed text-muted md:text-[17px]">
              {summary}
            </p>
          </RevealOnScroll>

          <RevealOnScroll className="mt-12">
            <h2 className="text-[13px] font-medium tracking-wide text-muted">
              {dict.skillDetail.summaryHeading}
            </h2>
            <p className="mt-3 max-w-2xl text-[15px] leading-relaxed text-ink">
              {summary}
            </p>
          </RevealOnScroll>

          <RevealOnScroll className="mt-10 grid gap-6 sm:grid-cols-2">
            <section className="rounded-card border border-line bg-bg p-5 md:p-6">
              <h2 className="text-[13px] font-medium tracking-wide text-muted">
                {dict.skillDetail.contextHeading}
              </h2>
              <dl className="mt-4 space-y-4 text-sm">
                <div>
                  <dt className="font-medium text-ink">
                    {dict.skillDetail.requiredContext}
                  </dt>
                  <dd className="mt-1.5 flex flex-wrap gap-1.5">
                    {skill.requiredContext.length === 0 ? (
                      <span className="text-muted">—</span>
                    ) : (
                      skill.requiredContext.map((c) => (
                        <StatusBadge key={c} tone="neutral">
                          {dict.labels.context[c]}
                        </StatusBadge>
                      ))
                    )}
                  </dd>
                </div>
                <div>
                  <dt className="font-medium text-ink">
                    {dict.skillDetail.optionalContext}
                  </dt>
                  <dd className="mt-1.5 flex flex-wrap gap-1.5">
                    {skill.optionalContext.length === 0 ? (
                      <span className="text-muted">—</span>
                    ) : (
                      skill.optionalContext.map((c) => (
                        <StatusBadge key={c} tone="outline">
                          {dict.labels.context[c]}
                        </StatusBadge>
                      ))
                    )}
                  </dd>
                </div>
              </dl>
            </section>

            <section className="space-y-4">
              <div className="rounded-card border border-line bg-bg p-5 md:p-6">
                <h2 className="text-[13px] font-medium tracking-wide text-muted">
                  {dict.skillDetail.deliveryHeading}
                </h2>
                <p className="mt-3 text-sm font-medium text-ink">
                  {dict.labels.delivery[skill.delivery]}
                </p>
                <p className="mt-1.5 text-sm leading-relaxed text-muted">
                  {dict.labels.deliveryDesc[skill.delivery]}
                </p>
              </div>
              <div className="rounded-card border border-line bg-bg p-5 md:p-6">
                <h2 className="text-[13px] font-medium tracking-wide text-muted">
                  {dict.skillDetail.formatHeading}
                </h2>
                <p className="mt-3 text-sm text-ink">
                  {dict.labels.format[skill.format]}
                </p>
              </div>
              <div className="rounded-card border border-line bg-bg p-5 md:p-6">
                <h2 className="text-[13px] font-medium tracking-wide text-muted">
                  {dict.skillDetail.riskHeading}
                </h2>
                <p className="mt-3">
                  <StatusBadge tone={riskTone[skill.risk]}>
                    {dict.labels.risk[skill.risk]}
                  </StatusBadge>
                </p>
              </div>
            </section>
          </RevealOnScroll>

          <RevealOnScroll className="mt-10 rounded-card border border-line bg-bg p-5 md:p-6">
            <h2 className="text-[13px] font-medium tracking-wide text-muted">
              {dict.skillDetail.howToUseHeading}
            </h2>
            <ol className="mt-4 list-decimal space-y-2.5 pl-5 text-[15px] leading-relaxed text-ink">
              {dict.skillDetail.howToUseSteps.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </RevealOnScroll>

          <RevealOnScroll className="mt-6 rounded-card border border-line bg-soft p-5 text-[14px] leading-relaxed text-muted md:p-6">
            {dict.skillDetail.declarativeNote}
          </RevealOnScroll>
        </div>

        {/* Sidebar: GitHub maintenance directory + download — core acceptance */}
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <RevealOnScroll className="rounded-card border border-line bg-surface p-6 md:p-7">
            <h2 className="text-[17px] font-semibold tracking-tight text-ink">
              {dict.skillDetail.maintainedIn}
            </h2>
            <p className="mt-2 text-[14px] leading-relaxed text-muted">
              {dict.skillDetail.directoryDesc}
            </p>
            <p className="mt-3 break-all font-mono text-[12px] text-muted">
              {skill.path}
            </p>

            <div className="mt-5 flex flex-col gap-2.5">
              <Button href={skill.githubUrl} external variant="primary">
                {dict.actions.openDirectory}
              </Button>
              <Button href={skill.downloadUrl} external variant="ghost">
                {dict.actions.downloadSkill}
              </Button>
              <Button href={skill.skillDocUrl} external variant="ghost">
                {dict.actions.viewDoc}
              </Button>
            </div>

            <p className="mt-4 text-[12px] leading-relaxed text-muted">
              {dict.skillDetail.downloadDesc}
            </p>
          </RevealOnScroll>
        </aside>
      </div>

      {related.length > 0 && (
        <section className="mt-20 border-t border-line pt-14">
          <h2 className="display-section text-center text-[28px] md:text-[32px]">
            {dict.skillDetail.relatedHeading}
          </h2>
          <ul className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {related.map((s) => (
              <li key={s.slug}>
                <SkillCard skill={s} locale={typedLocale} dict={dict} />
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
