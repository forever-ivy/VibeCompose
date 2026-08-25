import { useEffect, useRef, useState } from "react";
import {
  api,
  onConfigChanged,
  onDictationError,
  onDictationResult,
  onSessionState,
  type AppConfig,
  type SessionSnapshot,
} from "../ipc";
import StatusPill, { type PillPhase } from "../components/StatusPill";

/**
 * Refined HUD overlay window — the small floating box, matching the macOS
 * Refined HUD (`OverlayController`): a compact capsule with waveform +
 * title + timer + inline ×, shown top/bottom-center of the display on a
 * transparent, always-on-top, unfocusable window. Terminal states (done /
 * copied / error) stay briefly visible before the backend hides the
 * window, mirroring `FeedbackSurfaceController`'s auto-hide delays.
 */

/** macOS FeedbackSurfaceController display durations (ms). */
const TERMINAL_DISPLAY_MS: Record<string, number> = {
  inserted_verified: 900,
  paste_dispatched: 1500,
  clipboard: 2000,
  error: 5000,
};

type Terminal = { phase: PillPhase; title: string } | null;

export default function HudOverlay() {
  const [session, setSession] = useState<SessionSnapshot>({
    phase: "idle",
    sessionId: null,
    elapsedMs: 0,
    level: 0,
  });
  const [feedback, setFeedback] = useState<AppConfig["visualFeedback"] | null>(
    null,
  );
  const [hotkey, setHotkey] = useState("F5");
  const [skillName, setSkillName] = useState("");
  const [terminal, setTerminal] = useState<Terminal>(null);
  const expireTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showTerminal = (phase: PillPhase, title: string, key: string) => {
    if (expireTimer.current) clearTimeout(expireTimer.current);
    setTerminal({ phase, title });
    // Blank the (transparent) window once the display window has passed so
    // a stale result can never flash when the HUD is next shown.
    expireTimer.current = setTimeout(
      () => setTerminal(null),
      (TERMINAL_DISPLAY_MS[key] ?? 2000) + 600,
    );
  };

  useEffect(() => {
    const refresh = () =>
      api
        .getConfig()
        .then((config) => {
          setFeedback(config.visualFeedback);
          const binding = config.transcription.dictationHotkey;
          setHotkey(
            [...(binding.modifiers ?? []), binding.key]
              .filter(Boolean)
              .join("+"),
          );
        })
        .catch(() => {});
    const refreshSkill = () =>
      api
        .listSkills()
        .then((skills) =>
          setSkillName(skills.find((s) => s.isDefault)?.name ?? ""),
        )
        .catch(() => {});
    refresh();
    refreshSkill();
    const unlisteners = [
      onSessionState((snapshot) => {
        setSession(snapshot);
        if (snapshot.phase !== "idle") setTerminal(null);
      }),
      onDictationResult((result) => {
        const copied = result.outcome === "clipboard";
        showTerminal(
          copied ? "copied" : "success",
          copied ? "已复制" : "已完成",
          result.outcome,
        );
      }),
      onDictationError(() => showTerminal("error", "错误", "error")),
      onConfigChanged(() => {
        refresh();
        refreshSkill();
      }),
    ];
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void api.cancelDictation();
        void api.hideOverlay("hud");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      unlisteners.forEach((p) => p.then((u) => u()));
      window.removeEventListener("keydown", onKey);
      if (expireTimer.current) clearTimeout(expireTimer.current);
    };
  }, []);

  const recording = session.phase === "recording";
  const processing = session.phase === "processing";
  const seconds = Math.floor(session.elapsedMs / 1000);
  const timer = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(
    seconds % 60,
  ).padStart(2, "0")}`;

  const showStatusText = feedback?.showStatusText ?? true;
  const reduceMotion = feedback?.alwaysReduceMotion ?? false;
  // The window canvas can be taller than the pill (WebKitGTK minimum-size
  // floor); hug the canvas edge that matches the configured placement so
  // the pill sits at the intended screen inset.
  const rootClass = `hud-root ${
    feedback?.hudPlacement === "bottom" ? "is-bottom" : "is-top"
  }`;

  if (recording || processing) {
    return (
      <div className={rootClass}>
        <StatusPill
          phase={recording ? "recording" : "processing"}
          title={recording ? skillName || "正在录音" : "处理中"}
          timer={recording ? timer : null}
          hint={recording ? `再按一次 ${hotkey} 结束并转写` : null}
          level={session.level}
          showStatusText={showStatusText}
          reduceMotion={reduceMotion}
          onCancel={() => api.cancelDictation()}
        />
      </div>
    );
  }

  if (terminal) {
    return (
      <div className={rootClass}>
        <StatusPill
          phase={terminal.phase}
          title={terminal.title}
          reduceMotion={reduceMotion}
        />
      </div>
    );
  }

  // Idle with no fresh terminal state: paint nothing on the transparent
  // canvas (the backend hides the window shortly after).
  return <div className={rootClass} />;
}
