import type { Variants, Transition } from "framer-motion";

/* Easing + timing tokens (plan §9.4.2). */
export const easeOutSmooth: [number, number, number, number] = [
  0.25, 0.1, 0.25, 1,
];
export const easeOutExpo: [number, number, number, number] = [
  0.16, 1, 0.3, 1,
];

export const dur = { fast: 0.22, base: 0.45, slow: 0.65 } as const;
export const staggerGap = 0.07;

const baseTransition: Transition = {
  duration: dur.base,
  ease: easeOutExpo,
};

/* fadeUp — default reveal for sections and blocks. */
export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 24 },
  visible: { opacity: 1, y: 0, transition: baseTransition },
};

/* fadeIn — for elements that should not translate. */
export const fadeIn: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { duration: dur.base, ease: easeOutSmooth },
  },
};

/* heroLine — larger rise for hero headlines. */
export const heroLine: Variants = {
  hidden: { opacity: 0, y: 28 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: dur.slow, ease: easeOutExpo },
  },
};

/* stagger — parent that releases children in sequence. */
export const stagger: Variants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: staggerGap, delayChildren: 0.05 },
  },
};

/* cardReveal — child card scaling up subtly as it fades in. */
export const cardReveal: Variants = {
  hidden: { opacity: 0, y: 16, scale: 0.98 },
  visible: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: baseTransition,
  },
};

/* slideRight — horizontal entrance for split content. */
export const slideRight: Variants = {
  hidden: { opacity: 0, x: -20 },
  visible: { opacity: 1, x: 0, transition: baseTransition },
};

/** Viewport config for whileInView reveals (kept for any remaining callers). */
export const viewportOnce = {
  once: true,
  amount: 0.12,
  margin: "0px 0px -32px 0px",
} as const;
