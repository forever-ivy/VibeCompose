import type { Dictionary } from "@/content/dictionary";
import { siteConfig, githubUrls } from "@/lib/site-config";
import { Button } from "../Button";
import { RevealOnScroll } from "../RevealOnScroll";

export function OpenSourceBlock({ dict }: { dict: Dictionary }) {
  return (
    <section className="bg-ink text-white">
      <div className="mx-auto max-w-[1200px] px-5 py-20 md:px-8 md:py-28">
        <RevealOnScroll className="mx-auto max-w-2xl text-center">
          <p className="text-[13px] font-medium tracking-[0.08em] text-dark-muted uppercase">
            {dict.openSource.eyebrow}
          </p>
          <h2 className="display-section mt-3 text-[28px] text-white md:text-[40px]">
            {dict.openSource.title}
          </h2>
          <p className="mt-5 text-[16px] leading-relaxed text-dark-muted md:text-[17px]">
            {dict.openSource.body}
          </p>
          <div className="mt-9 flex flex-wrap items-center justify-center gap-4">
            <Button
              href={siteConfig.repoUrl}
              external
              variant="ghost"
              className="!border-white/20 !text-white hover:!border-accent hover:!bg-accent hover:!text-white"
            >
              {dict.openSource.cta}
            </Button>
            <a
              href={githubUrls.license}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[14px] text-dark-muted underline-offset-4 transition-colors hover:text-white hover:underline"
            >
              {dict.openSource.license}
            </a>
          </div>
        </RevealOnScroll>
      </div>
    </section>
  );
}
