import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import type { SkillEntry } from "@/lib/catalog-types";
import { SkillCard } from "../SkillCard";
import { Button } from "../Button";
import { RevealOnScroll } from "../RevealOnScroll";

export function SkillsSpotlight({
  locale,
  dict,
  skills,
}: {
  locale: Locale;
  dict: Dictionary;
  skills: SkillEntry[];
}) {
  return (
    <section className="section-band border-y border-line">
      <div className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
        <RevealOnScroll className="mx-auto max-w-2xl text-center">
          <p className="text-[13px] font-medium tracking-[0.06em] text-muted uppercase">
            {dict.spotlight.eyebrow}
          </p>
          <h2 className="display-section mt-3 text-[28px] md:text-[40px]">
            {dict.spotlight.title}
          </h2>
          <p className="mt-4 text-[16px] leading-relaxed text-muted md:text-[17px]">
            {dict.spotlight.subtitle}
          </p>
          <div className="mt-7">
            <Button href={localeHref(locale, "/skills")} variant="ghost">
              {dict.spotlight.cta}
            </Button>
          </div>
        </RevealOnScroll>

        <ul className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {skills.map((skill) => (
            <li key={skill.slug}>
              <SkillCard skill={skill} locale={locale} dict={dict} />
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
