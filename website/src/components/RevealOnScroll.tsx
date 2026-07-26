"use client";

import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type ElementType,
} from "react";

interface RevealProps {
  children: ReactNode;
  /** Kept for API compat; ignored — CSS handles the reveal. */
  variants?: unknown;
  className?: string;
  as?: ElementType;
  stagger?: boolean;
}

/**
 * Scroll/mount reveal via CSS classes. Content starts visible-enough
 * (opacity 0 only while CSS animation runs) and a JS fallback always
 * adds `is-in` so the page can never stay blank.
 */
export function RevealOnScroll({
  children,
  className,
  as = "div",
}: RevealProps) {
  const ref = useRef<HTMLElement | null>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // Immediate fallback — never leave content invisible.
    const safety = window.setTimeout(() => setInView(true), 120);

    if (typeof IntersectionObserver === "undefined") {
      setInView(true);
      return () => window.clearTimeout(safety);
    }

    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -24px 0px" },
    );
    io.observe(el);

    return () => {
      window.clearTimeout(safety);
      io.disconnect();
    };
  }, []);

  const Tag = as as ElementType;
  const classes = [
    "reveal",
    inView ? "is-in" : "",
    className ?? "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <Tag ref={ref as never} className={classes}>
      {children}
    </Tag>
  );
}
