"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { Locale } from "@/lib/i18n";
import { localeHref } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import { siteConfig } from "@/lib/site-config";
import { LocaleSwitcher } from "./LocaleSwitcher";
import { Button } from "./Button";
import { BrandLogo } from "./BrandLogo";

export function SiteHeader({
  locale,
  dict,
}: {
  locale: Locale;
  dict: Dictionary;
}) {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const links = [
    { label: dict.nav.skills, href: localeHref(locale, "/skills") },
    { label: dict.nav.download, href: localeHref(locale, "/download") },
    { label: dict.nav.about, href: localeHref(locale, "/about") },
  ];

  return (
    <header
      className={`sticky top-0 z-50 transition-all duration-200 ${
        scrolled
          ? "border-b border-line bg-bg/90 backdrop-blur-md"
          : "border-b border-transparent bg-bg/0"
      }`}
    >
      <div className="mx-auto flex h-[72px] max-w-[1200px] items-center justify-between px-5 md:px-8">
        <Link
          href={localeHref(locale, "/")}
          className="flex items-center gap-2.5 text-[15px] font-semibold tracking-tight"
        >
          <BrandLogo size="md" alt="" />
          <span>{dict.nav.brand}</span>
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="nav-link text-[14px] text-muted transition-colors"
            >
              {l.label}
            </Link>
          ))}
          <a
            href={siteConfig.repoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="nav-link text-[14px] text-muted transition-colors"
          >
            {dict.nav.github}
          </a>
        </nav>

        <div className="hidden items-center gap-3 md:flex">
          <LocaleSwitcher current={locale} />
          <Button href={localeHref(locale, "/download")} className="!px-4 !py-2 !text-[13px]">
            {dict.nav.download}
          </Button>
        </div>

        <button
          type="button"
          className="grid h-10 w-10 place-items-center rounded-full border border-line md:hidden"
          aria-label={open ? dict.nav.closeMenu : dict.nav.openMenu}
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
        >
          <span className="text-base leading-none">{open ? "✕" : "☰"}</span>
        </button>
      </div>

      {open && (
        <div className="border-t border-line bg-bg md:hidden">
          <nav className="mx-auto flex max-w-[1200px] flex-col gap-1 px-5 py-4">
            {links.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className="rounded-xl px-3 py-2.5 text-[15px] text-ink hover:bg-surface"
                onClick={() => setOpen(false)}
              >
                {l.label}
              </Link>
            ))}
            <a
              href={siteConfig.repoUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-xl px-3 py-2.5 text-[15px] text-ink hover:bg-surface"
            >
              {dict.nav.github}
            </a>
            <div className="mt-3 flex items-center justify-between px-1">
              <LocaleSwitcher current={locale} />
              <Button
                href={localeHref(locale, "/download")}
                className="!px-4 !py-2 !text-[13px]"
              >
                {dict.nav.download}
              </Button>
            </div>
          </nav>
        </div>
      )}
    </header>
  );
}
