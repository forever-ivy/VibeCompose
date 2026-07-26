import Link from "next/link";
import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import { fill } from "@/content/dictionary";
import { siteConfig, githubUrls } from "@/lib/site-config";
import { BrandLogo } from "./BrandLogo";

export function SiteFooter({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const year = new Date().getFullYear();

  return (
    <footer className="mt-8 border-t border-line bg-bg">
      <div className="mx-auto grid max-w-[1200px] gap-12 px-5 py-16 md:grid-cols-[1.6fr_1fr_1fr] md:px-8">
        <div>
          <div className="flex items-center gap-2.5 text-[15px] font-semibold tracking-tight">
            <BrandLogo size="md" alt="" />
            <span>{dict.nav.brand}</span>
          </div>
          <p className="mt-4 max-w-sm text-[14px] leading-relaxed text-muted">
            {dict.footer.tagline}
          </p>
          <div className="mt-5 flex flex-wrap gap-2 text-[12px] text-muted">
            <span className="rounded-full border border-line px-2.5 py-1">
              {dict.badges.alpha}
            </span>
            <span className="rounded-full border border-line px-2.5 py-1">
              {dict.badges.openSource}
            </span>
            <span className="rounded-full border border-line px-2.5 py-1">
              {dict.badges.noTelemetry}
            </span>
          </div>
        </div>

        {dict.footer.columns.map((col) => (
          <div key={col.heading}>
            <h3 className="text-[13px] font-semibold tracking-wide text-ink">
              {col.heading}
            </h3>
            <ul className="mt-4 space-y-2.5">
              {col.links.map((link) => (
                <li key={link.href}>
                  <Link
                    href={localeHref(locale, link.href)}
                    className="text-[14px] text-muted transition-colors hover:text-ink"
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
              {col.heading === dict.footer.columns[0].heading && (
                <li>
                  <a
                    href={siteConfig.repoUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[14px] text-muted transition-colors hover:text-ink"
                  >
                    {dict.nav.github}
                  </a>
                </li>
              )}
              {col.heading === dict.footer.columns[1].heading && (
                <li>
                  <a
                    href={githubUrls.license}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[14px] text-muted transition-colors hover:text-ink"
                  >
                    {siteConfig.license}
                  </a>
                </li>
              )}
            </ul>
          </div>
        ))}
      </div>

      <div className="border-t border-line">
        <div className="mx-auto flex max-w-[1200px] flex-col gap-2 px-5 py-6 text-[12px] text-muted md:flex-row md:items-center md:justify-between md:px-8">
          <p>{fill(dict.footer.copyright, "year", year)}</p>
          <p>{dict.footer.disclaimer}</p>
        </div>
      </div>
    </footer>
  );
}
