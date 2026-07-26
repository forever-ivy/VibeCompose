import type { Dictionary } from "@/content/dictionary";
import { RevealOnScroll } from "../RevealOnScroll";

export function WorkflowStrip({ dict }: { dict: Dictionary }) {
  return (
    <section className="section-band border-y border-line">
      <div className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
        <RevealOnScroll>
          <h2 className="display-section mx-auto max-w-2xl text-center text-[28px] md:text-[40px]">
            {dict.workflow.title}
          </h2>
        </RevealOnScroll>

        <ol className="mt-14 grid gap-6 md:grid-cols-3 md:gap-5">
          {dict.workflow.steps.map((step, i) => (
            <RevealOnScroll key={step.title}>
              <li className="h-full rounded-card border border-line bg-bg p-7 md:p-8">
                <span
                  className="step-mark inline-flex h-8 w-8 items-center justify-center rounded-full text-[13px] font-semibold"
                  aria-hidden
                >
                  {i + 1}
                </span>
                <h3 className="mt-5 text-[18px] font-semibold tracking-tight">
                  {step.title}
                </h3>
                <p className="mt-2.5 text-[15px] leading-relaxed text-muted">
                  {step.desc}
                </p>
              </li>
            </RevealOnScroll>
          ))}
        </ol>
      </div>
    </section>
  );
}
