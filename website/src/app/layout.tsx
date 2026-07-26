import type { Metadata } from "next";
import "@/styles/globals.css";
import { siteConfig } from "@/lib/site-config";

export const metadata: Metadata = {
  title: {
    default: `${siteConfig.productName} — Voice to polished text`,
    template: `%s · ${siteConfig.productName}`,
  },
  description:
    "Open-source, voice-first writing for macOS · Speech becomes clean text through instruction-only Skills",
  applicationName: siteConfig.productName,
  robots: { index: true, follow: true },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh-Hans" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
