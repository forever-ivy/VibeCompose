import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { siteConfig } from "@/lib/site-config";
import { Button } from "@/components/Button";
import { RevealOnScroll } from "@/components/RevealOnScroll";
import { StatusBadge } from "@/components/StatusBadge";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const dict = getDictionary(locale);
  return {
    title: `${dict.download.title} · ${dict.nav.brand}`,
    description: dict.download.subtitle,
  };
}

export default async function DownloadPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const typedLocale = locale as Locale;
  const dict = getDictionary(typedLocale);

  return (
    <div className="mx-auto max-w-[720px] px-5 py-20 md:px-8 md:py-28">
      <RevealOnScroll className="text-center">
        <div className="flex flex-wrap justify-center gap-2">
          <StatusBadge tone="accent">{dict.badges.alpha}</StatusBadge>
          <StatusBadge tone="outline">{siteConfig.minMacOSLabel}</StatusBadge>
        </div>
        <h1 className="display-section mt-5 text-[32px] md:text-[44px]">
          {dict.download.title}
        </h1>
        <p className="mt-4 text-[16px] leading-relaxed text-muted md:text-[17px]">
          {dict.download.subtitle}
        </p>
        <p className="mt-2 text-[14px] text-muted">{dict.download.requirement}</p>
      </RevealOnScroll>

      <ol className="mt-14 space-y-4">
        {dict.download.steps.map((step, i) => (
          <RevealOnScroll key={step.title}>
            <li className="flex gap-4 rounded-card border border-line bg-bg p-6 text-left md:p-7">
              <span
                className="step-mark flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[13px] font-semibold"
                aria-hidden
              >
                {i + 1}
              </span>
              <div>
                <h2 className="text-[17px] font-semibold tracking-tight">
                  {step.title}
                </h2>
                <p className="mt-1.5 text-[15px] leading-relaxed text-muted">
                  {step.desc}
                </p>
              </div>
            </li>
          </RevealOnScroll>
        ))}
      </ol>

      <RevealOnScroll className="mt-12 flex flex-wrap justify-center gap-3">
        <Button href={siteConfig.repoUrl} external size="lg">
          {dict.actions.viewOnGithub}
        </Button>
        <Button href={siteConfig.repoUrl} external variant="ghost" size="lg">
          {dict.actions.download}
        </Button>
      </RevealOnScroll>

      <RevealOnScroll className="mt-10 rounded-card border border-line bg-surface p-5 text-[14px] leading-relaxed text-muted">
        {dict.download.note}
      </RevealOnScroll>
    </div>
  );
}
