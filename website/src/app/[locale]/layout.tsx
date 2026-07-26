import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { locales, isLocale, type Locale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";
import { HtmlLang } from "@/components/HtmlLang";

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const dict = getDictionary(locale);
  return {
    title: { absolute: dict.meta.title },
    description: dict.meta.description,
  };
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const typedLocale = locale as Locale;
  const dict = getDictionary(typedLocale);

  return (
    <>
      <HtmlLang locale={typedLocale} />
      <SiteHeader locale={typedLocale} dict={dict} />
      <main>{children}</main>
      <SiteFooter locale={typedLocale} dict={dict} />
    </>
  );
}
