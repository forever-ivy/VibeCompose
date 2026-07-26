"use client";

import { useEffect, useRef, useState } from "react";
import type { Dictionary } from "@/content/dictionary";
import { RevealOnScroll } from "../RevealOnScroll";

export function FeaturePillars({ dict }: { dict: Dictionary }) {
  const ref = useRef<HTMLUListElement | null>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = ref.current;
    const safety = window.setTimeout(() => setInView(true), 120);
    if (!el || typeof IntersectionObserver === "undefined") {
      setInView(true);
      return () => window.clearTimeout(safety);
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { threshold: 0.08 },
    );
    io.observe(el);
    return () => {
      window.clearTimeout(safety);
      io.disconnect();
    };
  }, []);

  return (
    <section className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
      <RevealOnScroll className="mx-auto max-w-2xl text-center">
        <h2 className="display-section text-[28px] md:text-[40px]">
          {dict.pillars.title}
        </h2>
        <p className="mt-4 text-[16px] leading-relaxed text-muted md:text-[17px]">
          {dict.pillars.subtitle}
        </p>
      </RevealOnScroll>

      <ul
        ref={ref}
        className={[
          "mt-14 grid gap-4 sm:grid-cols-2",
          inView ? "stagger-in" : "stagger-boot",
        ].join(" ")}
      >
        {dict.pillars.items.map((item, i) => (
          <li
            key={item.title}
            className="stagger-item rounded-card border border-line bg-bg p-7 text-left md:p-8"
            style={{ transitionDelay: `${i * 70}ms` }}
          >
            <div
              className="mb-4 h-1 w-8 rounded-full bg-accent"
              aria-hidden
            />
            <h3 className="text-[17px] font-semibold tracking-tight">
              {item.title}
            </h3>
            <p className="mt-2.5 text-[15px] leading-relaxed text-muted">
              {item.desc}
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}
