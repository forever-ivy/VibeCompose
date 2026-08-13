export type Host = "macos" | "windows" | "linux";
/** Shipping surfaces of this Tauri shell. macOS ships the Swift app. */
export type Platform = "windows" | "linux";

export function detectHost(): Host {
  const ua = navigator.userAgent;
  if (/Windows/i.test(ua)) return "windows";
  if (/Linux/i.test(ua)) return "linux";
  return "macos";
}

export function applyPlatform(platform: Platform) {
  document.documentElement.dataset.platform = platform;
  document.documentElement.dataset.host = detectHost();
}

/** Windows and Linux follow the OS. A Mac host is only for debugging this
 *  shell, so it uses the Windows surface (the primary shipping target). */
export function initialPlatform(): Platform {
  return detectHost() === "linux" ? "linux" : "windows";
}
