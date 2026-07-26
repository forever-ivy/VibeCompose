import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { siteConfig } from "@/lib/site-config";
import { Button } from "@/components/Button";
import { RevealOnScroll } from "@/components/RevealOnScroll";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const dict = getDictionary(locale);
  return {
    title: `${dict.about.title} · ${dict.nav.brand}`,
    description: dict.about.body[0],
  };
}

export default async function AboutPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const dict = getDictionary(locale);

  return (
    <div className="mx-auto max-w-[720px] px-5 py-20 md:px-8 md:py-28">
      <RevealOnScroll className="text-center">
        <h1 className="display-section text-[32px] md:text-[44px]">
          {dict.about.title}
        </h1>
      </RevealOnScroll>

      <div className="mt-10 space-y-5">
        {dict.about.body.map((para) => (
          <RevealOnScroll key={para.slice(0, 24)}>
            <p className="text-[16px] leading-relaxed text-muted md:text-[17px]">
              {para}
            </p>
          </RevealOnScroll>
        ))}
      </div>

      <RevealOnScroll className="mt-12 flex justify-center">
        <Button href={siteConfig.repoUrl} external size="lg">
          {dict.actions.viewOnGithub}
        </Button>
      </RevealOnScroll>
    </div>
  );
}
