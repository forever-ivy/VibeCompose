import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { getFeaturedSkills } from "@/lib/catalog";
import { HomeHero } from "@/components/home/HomeHero";
import { WorkflowStrip } from "@/components/home/WorkflowStrip";
import { AppChips } from "@/components/home/AppChips";
import { FeaturePillars } from "@/components/home/FeaturePillars";
import { SkillsSpotlight } from "@/components/home/SkillsSpotlight";
import { PrivacyPanel } from "@/components/home/PrivacyPanel";
import { OpenSourceBlock } from "@/components/home/OpenSourceBlock";
import { FinalCta } from "@/components/home/FinalCta";

export default async function HomePage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const typedLocale = locale as Locale;
  const dict = getDictionary(typedLocale);
  const featured = getFeaturedSkills();

  return (
    <>
      <HomeHero locale={typedLocale} dict={dict} />
      <WorkflowStrip dict={dict} />
      <AppChips dict={dict} />
      <FeaturePillars dict={dict} />
      <SkillsSpotlight locale={typedLocale} dict={dict} skills={featured} />
      <PrivacyPanel dict={dict} />
      <OpenSourceBlock dict={dict} />
      <FinalCta locale={typedLocale} dict={dict} />
    </>
  );
}
