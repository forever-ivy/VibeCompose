import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { isLocale } from "@/lib/i18n";
import { getDictionary } from "@/content/dictionary";
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
    title: `${dict.legal.termsTitle} · ${dict.nav.brand}`,
    description: dict.legal.terms[0]?.desc,
  };
}

export default async function TermsPage({
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
          {dict.legal.termsTitle}
        </h1>
        <p className="mt-3 text-[14px] text-muted">{dict.legal.updated}</p>
      </RevealOnScroll>

      <dl className="mt-12 space-y-4">
        {dict.legal.terms.map((item) => (
          <RevealOnScroll key={item.title}>
            <div className="rounded-card border border-line bg-bg p-6 md:p-7">
              <dt className="text-[17px] font-semibold tracking-tight">
                {item.title}
              </dt>
              <dd className="mt-2 text-[15px] leading-relaxed text-muted">
                {item.desc}
              </dd>
            </div>
          </RevealOnScroll>
        ))}
      </dl>
    </div>
  );
}
