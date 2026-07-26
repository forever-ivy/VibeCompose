import { basePath } from "./site-config";

export const locales = ["zh-Hans", "en"] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "zh-Hans";

export function isLocale(value: string): value is Locale {
  return (locales as readonly string[]).includes(value);
}

export const localeLabels: Record<Locale, string> = {
  "zh-Hans": "中文",
  en: "English",
};

/** <html lang="…"> value. */
export const htmlLang: Record<Locale, string> = {
  "zh-Hans": "zh-Hans",
  en: "en",
};

/**
 * App-relative href for a locale route, WITHOUT the deploy basePath.
 * Pass these to next/link — it prepends basePath automatically.
 * localeHref("en", "/skills") -> "/en/skills/"
 */
export function localeHref(locale: Locale, path = "/"): string {
  const clean = path === "/" ? "" : path.replace(/^\/+|\/+$/g, "");
  const tail = clean ? `/${clean}/` : "/";
  return `/${locale}${tail}`;
}

/**
 * Fully-qualified internal path INCLUDING basePath. Use for raw navigation
 * such as window.location redirects, never with next/link.
 * localeFullPath("en", "/skills") -> "/vibecompose/en/skills/"
 */
export function localeFullPath(locale: Locale, path = "/"): string {
  return `${basePath}${localeHref(locale, path)}`;
}
