import React from "react";

/**
 * Platform-native control icons.
 *
 * Windows: glyphs from the system icon font — Segoe Fluent Icons (Win11)
 * or Segoe MDL2 Assets (Win10). These are the same glyphs native Win32 /
 * WinUI apps use; the fonts ship with Windows and are not redistributable,
 * so when the font is absent (e.g. debugging on macOS) we fall back to SVG.
 *
 * Linux: inline SVG tuned by CSS to the Adwaita symbolic rhythm
 * (16px grid, heavier rounded strokes).
 */
type IconProps = { size?: number; className?: string };

let segoeAvailable: boolean | null = null;

/** True when the family actually renders our PUA glyphs. `document.fonts
 *  .check()` is useless here: it reports unknown system families as
 *  "available". Compare measured widths against the generic fallback. */
function fontRendersGlyphs(family: string): boolean {
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  if (!context) return false;
  const probe = "\uE713\uE720\uE8C8";
  context.font = "16px monospace";
  const fallbackWidth = context.measureText(probe).width;
  context.font = `16px "${family}", monospace`;
  return context.measureText(probe).width !== fallbackWidth;
}

function useSystemIconFont(): boolean {
  if (segoeAvailable === null) {
    const platform = document.documentElement.dataset.platform;
    try {
      segoeAvailable =
        platform === "windows" &&
        (fontRendersGlyphs("Segoe Fluent Icons") ||
          fontRendersGlyphs("Segoe MDL2 Assets"));
    } catch {
      segoeAvailable = false;
    }
  }
  return segoeAvailable;
}

const I = (
  children: React.ReactNode,
  segoeGlyph?: string,
  vb = 17,
): ((p: IconProps) => React.ReactElement) =>
  function Icon({ size = 15, className = "" }: IconProps) {
    if (segoeGlyph && useSystemIconFont()) {
      return (
        <span
          className={`vc-icon-font shrink-0 ${className}`}
          style={{ fontSize: size - 1, width: size, height: size }}
          aria-hidden
        >
          {segoeGlyph}
        </span>
      );
    }
    return (
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${vb} ${vb}`}
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={`vc-icon shrink-0 ${className}`}
        aria-hidden
      >
        {children}
      </svg>
    );
  };

// Segoe glyph codepoints are stable across MDL2 Assets and Fluent Icons.
export const WaveformIcon = I(
  <>
    <path d="M2.5 6.5v4" />
    <path d="M5.5 4.5v8" />
    <path d="M8.5 2.5v12" />
    <path d="M11.5 4.5v8" />
    <path d="M14.5 6.5v4" />
  </>,
  "\uE720", // Microphone
);

export const SquareGridIcon = I(
  <>
    <rect x="2.2" y="2.2" width="5" height="5" rx="1.4" />
    <rect x="9.8" y="2.2" width="5" height="5" rx="1.4" />
    <rect x="2.2" y="9.8" width="5" height="5" rx="1.4" />
    <rect x="9.8" y="9.8" width="5" height="5" rx="1.4" />
  </>,
  "\uE8A9", // ViewAll
);

export const ClockIcon = I(
  <>
    <circle cx="8.5" cy="8.5" r="6.3" />
    <path d="M8.5 5v3.6l2.4 1.6" />
  </>,
  "\uE823", // Recent
);

export const GearIcon = I(
  <>
    <circle cx="8.5" cy="8.5" r="2.1" />
    <path d="M8.5 1.8v1.9M8.5 13.3v1.9M1.8 8.5h1.9M13.3 8.5h1.9M3.8 3.8l1.3 1.3M11.9 11.9l1.3 1.3M13.2 3.8l-1.3 1.3M5.1 11.9l-1.3 1.3" />
  </>,
  "\uE713", // Setting
);

export const MicIcon = I(
  <>
    <rect x="6" y="1.8" width="5" height="8.4" rx="2.5" />
    <path d="M3.6 7.4a4.9 4.9 0 0 0 9.8 0M8.5 12.3v2.9M6.2 15.2h4.6" />
  </>,
  "\uE720", // Microphone
);

export const CheckIcon = I(
  <path d="M3 9l3.6 3.6L14 5.2" />,
  "\uE73E", // CheckMark
);
export const CopyIcon = I(
  <>
    <rect x="5.6" y="5.6" width="8" height="8" rx="1.8" />
    <path d="M11.4 5.6V4.4a1.8 1.8 0 0 0-1.8-1.8H4.4a1.8 1.8 0 0 0-1.8 1.8v5.2a1.8 1.8 0 0 0 1.8 1.8h1.2" />
  </>,
  "\uE8C8", // Copy
);
export const TrashIcon = I(
  <>
    <path d="M2.6 4.4h11.8M6.7 4.2V3.1a1 1 0 0 1 1-1h1.6a1 1 0 0 1 1 1v1.1M4.2 4.4l.5 8.6a1.4 1.4 0 0 0 1.4 1.3h4.8a1.4 1.4 0 0 0 1.4-1.3l.5-8.6" />
  </>,
  "\uE74D", // Delete
);
export const ChevronRightIcon = I(
  <path d="M6 3.5l5 5-5 5" />,
  "\uE76C", // ChevronRight
);
export const SearchIcon = I(
  <>
    <circle cx="7.4" cy="7.4" r="4.9" />
    <path d="M11 11l3.4 3.4" />
  </>,
  "\uE721", // Search
);
export const XIcon = I(
  <path d="M4 4l9 9M13 4l-9 9" />,
  "\uE711", // Cancel
);
export const BookIcon = I(
  <>
    <path d="M8.5 4.2C7 3 5 2.8 3.2 3.2v9.6c1.8-.4 3.8-.2 5.3 1 1.5-1.2 3.5-1.4 5.3-1V3.2C12 2.8 10 3 8.5 4.2z" />
    <path d="M8.5 4.2v9.6" />
  </>,
  "\uE82D", // Dictionary
);
export const PlusIcon = I(
  <path d="M8.5 3v11M3 8.5h11" />,
  "\uE710", // Add
);
export const GlobeIcon = I(
  <>
    <circle cx="8.5" cy="8.5" r="6.3" />
    <path d="M2.2 8.5h12.6M8.5 2.2c-3.4 3.6-3.4 9 0 12.6M8.5 2.2c3.4 3.6 3.4 9 0 12.6" />
  </>,
  "\uE774", // Globe
);

/* ------------------------------------------------------------------ */
/* Skill badge glyphs: rounded-square tinted tile + white SF glyph,    */
/* exactly the bundled skill icon language of the macOS app.           */
/* ------------------------------------------------------------------ */

const TINTS: Record<string, string> = {
  blue: "var(--color-tint-blue)",
  purple: "var(--color-tint-purple)",
  pink: "var(--color-tint-pink)",
  orange: "var(--color-tint-orange)",
  green: "var(--color-tint-green)",
  teal: "var(--color-tint-teal)",
  yellow: "var(--color-tint-yellow)",
  gray: "var(--color-tint-gray)",
  brown: "var(--color-tint-brown)",
};

const GLYPHS: Record<string, { tint: keyof typeof TINTS | string; node: React.ReactNode }> = {
  direct: {
    tint: "blue",
    node: (
      <>
        <path d="M4.5 6.5v4" />
        <path d="M8.5 4v9" />
        <path d="M12.5 6.5v4" />
      </>
    ),
  },
  "polish-writing": {
    tint: "purple",
    node: <path d="M11.6 3.6a1.6 1.6 0 0 1 2.3 2.3l-6.4 6.4-3.1.8.8-3.1 6.4-6.4z" />,
  },
  translate: {
    tint: "teal",
    node: (
      <>
        <path d="M3.5 5.5h6M6.5 3.5v2c0 2.6-1.4 4.6-3.4 5.8M4.4 8.2c.8 1.7 2.2 3 4 3.6" />
        <path d="M9.2 13.5l2.1-5.2 2.1 5.2M9.9 11.8h2.8" />
      </>
    ),
  },
  "ai-interview": {
    tint: "orange",
    node: (
      <>
        <rect x="3.2" y="3.2" width="7" height="5.4" rx="1.6" />
        <path d="M5.2 8.6v1.6l2.2-1.6" />
        <rect x="7" y="8" width="7" height="5.4" rx="1.6" />
      </>
    ),
  },
  "career-coach": {
    tint: "green",
    node: (
      <>
        <circle cx="8.5" cy="5.6" r="2.2" />
        <path d="M3.8 13.4c.6-2.6 2.5-4 4.7-4s4.1 1.4 4.7 4" />
      </>
    ),
  },
  "presentation-outline": {
    tint: "pink",
    node: (
      <>
        <rect x="3" y="3" width="11" height="8" rx="1.4" />
        <path d="M8.5 11v2.4M6 13.4h5M5.8 6.2h2.2" />
      </>
    ),
  },
  "product-spec": {
    tint: "yellow",
    node: (
      <>
        <rect x="4" y="2.8" width="9" height="11.4" rx="1.4" />
        <path d="M6.2 6h4.6M6.2 8.6h4.6M6.2 11.2h2.8" />
      </>
    ),
  },
  "lingo-polisher": {
    tint: "brown",
    node: <path d="M3.8 4.2h9.4M6.6 4.2V3M4.6 4.2c0 4.4 2.6 7.8 6.4 9.4M12.4 4.2c0 4.4-2.6 7.8-6.4 9.4" />,
  },
  "writing-polisher": {
    tint: "purple",
    node: <path d="M11.6 3.6a1.6 1.6 0 0 1 2.3 2.3l-6.4 6.4-3.1.8.8-3.1 6.4-6.4z" />,
  },
  "reading-notes": {
    tint: "teal",
    node: (
      <>
        <path d="M8.5 4.2C7 3 5 2.8 3.2 3.2v9.6c1.8-.4 3.8-.2 5.3 1 1.5-1.2 3.5-1.4 5.3-1V3.2C12 2.8 10 3 8.5 4.2z" />
        <path d="M8.5 4.2v9.6" />
      </>
    ),
  },
  "writing-review": {
    tint: "orange",
    node: (
      <>
        <rect x="3.4" y="3" width="10.2" height="11" rx="1.6" />
        <path d="M6.2 8.4l1.6 1.6 3-3.2" />
      </>
    ),
  },
  "brainstorm-ideas": {
    tint: "yellow",
    node: (
      <>
        <path d="M8.5 2.6a3.9 3.9 0 0 1 2.2 7.1c-.5.4-.7 1-.7 1.7v.4H7v-.4c0-.7-.2-1.3-.7-1.7A3.9 3.9 0 0 1 8.5 2.6z" />
        <path d="M7 13.6h3M7.4 15.2h2.2" />
      </>
    ),
  },
  "command-refiner": {
    tint: "gray",
    node: (
      <>
        <path d="M6.2 5.4H4.6a1.6 1.6 0 1 1 1.6-1.6v9.4a1.6 1.6 0 1 1-1.6-1.6h7.8a1.6 1.6 0 1 1-1.6 1.6V3.8a1.6 1.6 0 1 1 1.6 1.6h-1.6z" />
      </>
    ),
  },
  "email-reply": {
    tint: "blue",
    node: (
      <>
        <rect x="2.8" y="4" width="11.4" height="9" rx="1.6" />
        <path d="M3.2 5.2l5.3 3.8 5.3-3.8" />
      </>
    ),
  },
  "meeting-summary": {
    tint: "purple",
    node: (
      <>
        <rect x="3" y="3" width="11" height="8" rx="1.6" />
        <path d="M5.8 6h5.4M5.8 8.4h3.4M8.5 11v3" />
      </>
    ),
  },
  "code-comment": {
    tint: "teal",
    node: <path d="M5.8 3.8l-3.4 4.7 3.4 4.7M11.2 3.8l3.4 4.7-3.4 4.7" />,
  },
  "git-commit": {
    tint: "orange",
    node: (
      <>
        <circle cx="4.6" cy="8.5" r="1.9" />
        <circle cx="12.4" cy="8.5" r="1.9" />
        <path d="M6.5 8.5h4" />
      </>
    ),
  },
  "paper-summarizer": {
    tint: "blue",
    node: (
      <>
        <path d="M4.4 2.8h5.6l3 3v8.4a1.4 1.4 0 0 1-1.4 1.4H5.8a1.4 1.4 0 0 1-1.4-1.4V2.8z" />
        <path d="M10 2.8v3h3M6.4 9h4.2M6.4 11.6h2.6" />
      </>
    ),
  },
  "paper-translator": {
    tint: "teal",
    node: (
      <>
        <path d="M3.5 5.5h6M6.5 3.5v2c0 2.6-1.4 4.6-3.4 5.8" />
        <path d="M9.2 13.5l2.1-5.2 2.1 5.2M9.9 11.8h2.8" />
      </>
    ),
  },
  "social-copy": {
    tint: "pink",
    node: (
      <>
        <path d="M8.5 13.6S3.4 10.4 3.4 6.8a2.6 2.6 0 0 1 5.1-.8 2.6 2.6 0 0 1 5.1.8c0 3.6-5.1 6.8-5.1 6.8z" />
      </>
    ),
  },
  "reply-assistant": {
    tint: "green",
    node: (
      <>
        <path d="M13.8 8.4a5.3 5.3 0 1 1-2.4-4.2" />
        <path d="M13.8 3.4v2.6h-2.6" />
      </>
    ),
  },
  "text-to-speech": {
    tint: "gray",
    node: (
      <>
        <path d="M3.4 6.6v3.8h2.2l3.4 2.8V3.8L5.6 6.6H3.4z" />
        <path d="M11.4 6a3.4 3.4 0 0 1 0 5M13.2 4.4a5.6 5.6 0 0 1 0 8.2" />
      </>
    ),
  },
};

export function SkillIcon({
  skillId,
  size = 34,
}: {
  skillId: string;
  size?: number;
}) {
  const g = GLYPHS[skillId] ?? GLYPHS.direct;
  const tint = TINTS[g.tint as string] ?? g.tint;
  return (
    <span
      className="grid shrink-0 place-items-center rounded-[9px]"
      style={{ width: size, height: size, background: tint }}
    >
      <svg
        width={size * 0.56}
        height={size * 0.56}
        viewBox="0 0 17 17"
        fill="none"
        stroke="#fff"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden
      >
        {g.node}
      </svg>
    </span>
  );
}
