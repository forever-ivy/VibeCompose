"use client";

import { useEffect } from "react";
import { defaultLocale, localeFullPath } from "@/lib/i18n";

const target = localeFullPath(defaultLocale, "/");

export default function RootRedirect() {
  useEffect(() => {
    window.location.replace(target);
  }, []);

  return (
    <>
      {/* React 19 hoists this to <head> for the no-JS redirect path. */}
      <meta httpEquiv="refresh" content={`0; url=${target}`} />
      <main
        style={{
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: "var(--font-sans)",
        }}
      >
        <a href={target}>Continue to VibeCompose →</a>
      </main>
    </>
  );
}
