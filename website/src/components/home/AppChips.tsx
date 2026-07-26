import type { Dictionary } from "@/content/dictionary";
import { MarqueeRow } from "../MarqueeRow";
import { RevealOnScroll } from "../RevealOnScroll";

const APPS = [
  "Mail",
  "Messages",
  "Slack",
  "Notion",
  "Linear",
  "VS Code",
  "Xcode",
  "Notes",
  "Browser",
  "Docs",
  "GitHub",
  "Terminal",
];

export function AppChips({ dict }: { dict: Dictionary }) {
  return (
    <section className="py-12 md:py-16">
      <RevealOnScroll className="mx-auto max-w-[1200px] px-5 md:px-8">
        <h2 className="text-center text-[13px] font-medium tracking-[0.06em] text-muted uppercase">
          {dict.apps.title}
        </h2>
      </RevealOnScroll>
      <div className="mt-8 md:mt-10">
        <MarqueeRow
          items={APPS.map((name) => (
            <span
              key={name}
              className="inline-flex h-14 min-w-[120px] items-center justify-center rounded-[14px] border border-line bg-bg px-6 text-[14px] font-medium text-ink shadow-[0_1px_2px_rgba(15,20,25,0.04)]"
            >
              {name}
            </span>
          ))}
        />
      </div>
    </section>
  );
}
