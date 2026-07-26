import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import { Button } from "../Button";
import { RevealOnScroll } from "../RevealOnScroll";

export function FinalCta({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  return (
    <section className="mx-auto max-w-[1200px] px-5 py-24 md:px-8 md:py-32">
      <RevealOnScroll className="cta-glow mx-auto max-w-2xl text-center">
        <h2 className="display-section text-[32px] md:text-[48px]">
          {dict.finalCta.title}
        </h2>
        <p className="mt-4 text-[16px] leading-relaxed text-muted md:text-[18px]">
          {dict.finalCta.subtitle}
        </p>
        <div className="mt-10 flex flex-wrap justify-center gap-3">
          <Button href={localeHref(locale, "/download")} size="lg">
            {dict.finalCta.primary}
          </Button>
          <Button href={localeHref(locale, "/skills")} variant="ghost" size="lg">
            {dict.finalCta.secondary}
          </Button>
        </div>
      </RevealOnScroll>
    </section>
  );
}
