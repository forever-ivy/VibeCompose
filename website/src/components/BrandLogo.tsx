import Image from "next/image";

type Size = "sm" | "md" | "lg";

const sizes: Record<Size, { box: string; px: number }> = {
  sm: { box: "h-7 w-7", px: 28 },
  md: { box: "h-8 w-8", px: 32 },
  lg: { box: "h-10 w-10", px: 40 },
};

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function BrandLogo({
  size = "md",
  className = "",
  alt = "VibeCompose",
}: {
  size?: Size;
  className?: string;
  alt?: string;
}) {
  const s = sizes[size];
  return (
    <span
      className={`relative inline-grid shrink-0 place-items-center ${s.box} ${className}`}
      aria-hidden={alt === "" ? true : undefined}
    >
      <Image
        src={`${basePath}/logo-256.png`}
        alt={alt}
        width={s.px}
        height={s.px}
        className="h-full w-full object-contain"
        priority={size === "md" || size === "lg"}
      />
    </span>
  );
}
