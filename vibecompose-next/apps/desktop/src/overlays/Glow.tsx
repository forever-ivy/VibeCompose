import { useEffect, useState } from "react";
import {
  api,
  onConfigChanged,
  onSessionState,
  type AppConfig,
  type SessionSnapshot,
} from "../ipc";

/**
 * AI activity glow — the cross-platform counterpart of the macOS
 * "Blue Signal Frame": a soft edge glow wrapping the active display while
 * VibeCompose records or processes. The window is click-through and never
 * takes focus; this component only paints the frame.
 */
export default function GlowOverlay() {
  const [session, setSession] = useState<SessionSnapshot>({
    phase: "idle",
    sessionId: null,
    elapsedMs: 0,
    level: 0,
  });
  const [feedback, setFeedback] = useState<AppConfig["visualFeedback"] | null>(
    null,
  );

  useEffect(() => {
    const refresh = () =>
      api
        .getConfig()
        .then((config) => setFeedback(config.visualFeedback))
        .catch(() => {});
    refresh();
    const unlisteners = [onSessionState(setSession), onConfigChanged(refresh)];
    return () => {
      unlisteners.forEach((p) => p.then((u) => u()));
    };
  }, []);

  const recording = session.phase === "recording";
  const processing = session.phase === "processing";
  const active = recording || processing;

  const scale =
    feedback?.intensity === "subtle"
      ? 0.72
      : feedback?.intensity === "expressive"
        ? 1.22
        : 1;
  const reduceMotion = feedback?.alwaysReduceMotion ?? false;

  return (
    <div className="glow-root">
      <div
        className={`glow-frame ${
          active && !reduceMotion
            ? recording
              ? "is-breathing"
              : "is-pulsing"
            : ""
        }`}
        style={{
          opacity: active ? Math.min(1, 0.85 * scale) : 0,
          // Recording keeps the calm accent; processing shifts to the
          // ice tone, matching the HUD's state colors.
          ["--glow-color" as string]: recording
            ? "var(--color-accent)"
            : "var(--color-ice)",
          ["--glow-size" as string]: `${Math.round(46 * scale)}px`,
        }}
      />
    </div>
  );
}
