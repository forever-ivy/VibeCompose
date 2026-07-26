"use client";

import { useEffect } from "react";
import { htmlLang, type Locale } from "@/lib/i18n";

/**
 * Syncs <html lang> to the active locale. The root layout renders a static
 * default; this corrects it at runtime for the /en subtree without needing a
 * per-locale root layout (which static export + a single root cannot express).
 */
export function HtmlLang({ locale }: { locale: Locale }) {
  useEffect(() => {
    document.documentElement.lang = htmlLang[locale];
  }, [locale]);
  return null;
}
