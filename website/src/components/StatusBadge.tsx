import type { ReactNode } from "react";

type Tone = "accent" | "neutral" | "low" | "medium" | "high" | "outline";

const tones: Record<Tone, string> = {
  accent: "bg-accent-soft text-accent",
  neutral: "bg-black/[0.04] text-muted",
  outline: "border border-line text-muted",
  low: "bg-emerald-50 text-emerald-800",
  medium: "bg-amber-50 text-amber-800",
  high: "bg-rose-50 text-rose-800",
};

export function StatusBadge({
  children,
  tone = "neutral",
  className = "",
}: {
  children: ReactNode;
  tone?: Tone;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-medium ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  );
}
