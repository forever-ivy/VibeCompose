import { useEffect, useState } from "react";
import {
  api,
  onSessionState,
  type SessionSnapshot,
} from "../ipc";
import { XIcon } from "../icons";

const PROFILE = [0.22, 0.34, 0.48, 0.72, 1.0, 0.74, 0.5, 0.34, 0.22];

export default function HudOverlay() {
  const [session, setSession] = useState<SessionSnapshot>({
    phase: "idle",
    sessionId: null,
    elapsedMs: 0,
    level: 0,
  });

  useEffect(() => {
    const unlisten = onSessionState(setSession);
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void api.cancelDictation();
        void api.hideOverlay("hud");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      unlisten.then((u) => u());
      window.removeEventListener("keydown", onKey);
    };
  }, []);

  const recording = session.phase === "recording";
  const processing = session.phase === "processing";
  const seconds = Math.floor(session.elapsedMs / 1000);
  const timer = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(
    seconds % 60,
  ).padStart(2, "0")}`;

  return (
    <div className="hud-root">
      <div className="hud-card" data-tauri-drag-region>
        <span
          className={`hud-dot ${recording ? "is-rec" : processing ? "is-proc" : ""}`}
        />
        <div className="hud-copy">
          <div className="hud-title">
            {recording ? "正在录音" : processing ? "正在处理" : "就绪"}
          </div>
          <div className="hud-sub">
            {recording ? timer : processing ? "转写与润色" : "Esc 取消"}
          </div>
        </div>
        {recording && <MiniWave level={session.level} />}
        {(recording || processing) && (
          <button
            className="hud-cancel"
            onClick={() => api.cancelDictation()}
            aria-label="取消"
          >
            <XIcon size={12} />
          </button>
        )}
      </div>
    </div>
  );
}

function MiniWave({ level }: { level: number }) {
  const energy = Math.min(1, 0.25 + level * 0.9);
  return (
    <div className="flex h-7 items-center gap-[3px]">
      {PROFILE.map((p, i) => (
        <span
          key={i}
          className="vc-bar w-[3px] rounded-full"
          style={{
            height: `${Math.max(5, p * 26 * energy)}px`,
            background:
              i >= 3 && i <= 5 ? "var(--color-ice)" : "rgba(120,140,160,0.45)",
            animationDelay: `${i * 90}ms`,
          }}
        />
      ))}
    </div>
  );
}
