import Link from "next/link";
import type { ReactNode } from "react";

type Variant = "primary" | "ghost" | "dark";
type Size = "md" | "lg";

const base =
  "inline-flex items-center justify-center gap-2 rounded-button font-medium select-none whitespace-nowrap";

const sizes: Record<Size, string> = {
  md: "px-5 py-2.5 text-sm",
  lg: "px-7 py-3.5 text-[15px]",
};

const variants: Record<Variant, string> = {
  primary: "btn-primary bg-accent text-white hover:bg-accent-hover",
  ghost: "btn-ghost border border-line bg-transparent text-ink",
  dark: "btn-primary bg-ink text-white hover:!bg-ink/90 hover:!shadow-[0_10px_28px_rgba(15,20,25,0.22)]",
};

interface ButtonProps {
  href: string;
  children: ReactNode;
  variant?: Variant;
  size?: Size;
  external?: boolean;
  className?: string;
  ariaLabel?: string;
}

export function Button({
  href,
  children,
  variant = "primary",
  size = "md",
  external = false,
  className = "",
  ariaLabel,
}: ButtonProps) {
  const cls = `${base} ${sizes[size]} ${variants[variant]} ${className}`;

  if (external) {
    return (
      <a
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        className={cls}
        aria-label={ariaLabel}
      >
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={cls} aria-label={ariaLabel}>
      {children}
    </Link>
  );
}
