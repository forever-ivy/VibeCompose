import type { Dictionary } from "@/content/dictionary";
import { RevealOnScroll } from "../RevealOnScroll";

export function PrivacyPanel({ dict }: { dict: Dictionary }) {
  return (
    <section className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
      <RevealOnScroll className="mx-auto max-w-2xl text-center">
        <p className="text-[13px] font-medium tracking-[0.06em] text-muted uppercase">
          {dict.privacyPanel.eyebrow}
        </p>
        <h2 className="display-section mt-3 text-[28px] md:text-[40px]">
          {dict.privacyPanel.title}
        </h2>
      </RevealOnScroll>

      <ul className="mt-14 grid gap-4 md:grid-cols-3">
        {dict.privacyPanel.points.map((point) => (
          <RevealOnScroll key={point.title}>
            <li className="h-full rounded-card border border-line bg-bg p-7 md:p-8">
              <h3 className="text-[17px] font-semibold tracking-tight">
                {point.title}
              </h3>
              <p className="mt-2.5 text-[15px] leading-relaxed text-muted">
                {point.desc}
              </p>
            </li>
          </RevealOnScroll>
        ))}
      </ul>
    </section>
  );
}
