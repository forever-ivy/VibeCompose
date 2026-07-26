"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  locales,
  localeLabels,
  localeHref,
  isLocale,
  type Locale,
} from "@/lib/i18n";

/** Path after the leading /{locale} segment, e.g. "/skills/email". */
function pathWithoutLocale(pathname: string): string {
  const segs = pathname.split("/").filter(Boolean);
  if (segs.length && isLocale(segs[0])) segs.shift();
  return segs.length ? `/${segs.join("/")}` : "/";
}

export function LocaleSwitcher({ current }: { current: Locale }) {
  const pathname = usePathname() ?? "/";
  const rest = pathWithoutLocale(pathname);

  return (
    <div
      className="inline-flex items-center rounded-full border border-line bg-surface p-0.5 text-xs"
      role="group"
      aria-label="Language"
    >
      {locales.map((loc) => {
        const active = loc === current;
        return (
          <Link
            key={loc}
            href={localeHref(loc, rest)}
            aria-current={active ? "true" : undefined}
            className={`rounded-full px-2.5 py-1 transition-colors ${
              active
                ? "bg-accent text-white"
                : "text-muted hover:text-ink"
            }`}
          >
            {localeLabels[loc]}
          </Link>
        );
      })}
    </div>
  );
}
