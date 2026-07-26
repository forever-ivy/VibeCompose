import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { getAllSkills } from "@/lib/catalog";
import { SkillGrid } from "@/components/SkillGrid";
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
    title: `${dict.skillsPage.title} · ${dict.nav.brand}`,
    description: dict.skillsPage.subtitle,
  };
}

export default async function SkillsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const typedLocale = locale as Locale;
  const dict = getDictionary(typedLocale);
  const skills = getAllSkills();

  return (
    <div className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
      <RevealOnScroll className="mx-auto max-w-2xl text-center">
        <h1 className="display-section text-[32px] md:text-[44px]">
          {dict.skillsPage.title}
        </h1>
        <p className="mt-4 text-[16px] leading-relaxed text-muted md:text-[17px]">
          {dict.skillsPage.subtitle}
        </p>
      </RevealOnScroll>

      <div className="mt-12">
        <SkillGrid skills={skills} locale={typedLocale} dict={dict} />
      </div>
    </div>
  );
}
