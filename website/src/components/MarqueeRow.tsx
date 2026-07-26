import type { ReactNode } from "react";

/**
 * Seamless infinite marquee. Children are rendered twice and the track is
 * translated -50%, so the second copy lands exactly where the first began.
 * Animation is CSS-only (globals.css) and pauses on hover / reduced-motion.
 */
export function MarqueeRow({ items }: { items: ReactNode[] }) {
  return (
    <div className="marquee-wrapper" aria-hidden="true">
      <div className="marquee-track">
        {items.map((item, i) => (
          <div key={`a-${i}`} className="shrink-0">
            {item}
          </div>
        ))}
        {items.map((item, i) => (
          <div key={`b-${i}`} className="shrink-0">
            {item}
          </div>
        ))}
      </div>
    </div>
  );
}
