"use client";

import { useEffect, useState } from "react";
import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import { Button } from "../Button";

export function HomeHero({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let inner = 0;
    const outer = requestAnimationFrame(() => {
      inner = requestAnimationFrame(() => setReady(true));
    });
    const safety = window.setTimeout(() => setReady(true), 80);
    return () => {
      cancelAnimationFrame(outer);
      cancelAnimationFrame(inner);
      window.clearTimeout(safety);
    };
  }, []);

  return (
    <section className="mx-auto max-w-[1200px] px-5 pb-16 pt-20 text-center md:px-8 md:pb-24 md:pt-28">
      <div className={ready ? "hero-ready" : "hero-boot"}>
        <p
          className="reveal-item text-[13px] font-medium tracking-[0.08em] text-muted uppercase"
          style={{ transitionDelay: "20ms" }}
        >
          {dict.hero.eyebrow}
        </p>

        <h1 className="display-hero mx-auto mt-6 max-w-4xl text-[42px] md:text-[64px] lg:text-[80px]">
          {dict.hero.titleLines.map((line, i) => (
            <span
              key={line}
              className="reveal-item block"
              style={{ transitionDelay: `${60 + i * 70}ms` }}
            >
              {line}
            </span>
          ))}
        </h1>

        <p
          className="reveal-item mx-auto mt-6 max-w-lg text-[16px] leading-relaxed text-muted md:text-[17px]"
          style={{ transitionDelay: "220ms" }}
        >
          {dict.hero.subtitle}
        </p>

        <div
          className="reveal-item mt-10 flex flex-wrap justify-center gap-3"
          style={{ transitionDelay: "300ms" }}
        >
          <Button href={localeHref(locale, "/download")} size="lg">
            {dict.hero.primaryCta}
          </Button>
          <Button href={localeHref(locale, "/skills")} variant="ghost" size="lg">
            {dict.hero.secondaryCta}
          </Button>
        </div>

        <p
          className="reveal-item mt-6 text-[13px] tracking-wide text-muted"
          style={{ transitionDelay: "380ms" }}
        >
          {dict.hero.note}
        </p>
      </div>
    </section>
  );
}
