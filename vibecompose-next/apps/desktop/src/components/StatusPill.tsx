import { XIcon, CheckIcon, CopyIcon } from "../icons";

/**
 * Compact dictation status pill — the cross-platform form of the macOS
 * Refined HUD (`Sources/VibeCompose/OverlayController.swift` /
 * `OverlayVisualModel.swift`): one small rounded box with a leading 5-bar
 * waveform glyph (or a state badge), a short title, a monospaced-digit
 * timer, and an inline × cancel control. Structure and sizing follow the
 * macOS capsule (44pt row, 5 bars, trailing timer + cancel); the skin is
 * per-platform (Adwaita toast pill on Linux, Fluent flyout card on
 * Windows) via `.vc-hud-pill` CSS.
 */

export type PillPhase =
  | "recording"
  | "processing"
  | "success"
  | "copied"
  | "error";

/** macOS `OverlayStylePreset.dictationHUD.waveformBarCount` = 5 bars with a
 *  center-weighted contour (`WaveformNormalizer.smoothedLevels`). */
const BAR_CONTOUR = [0.45, 0.78, 1.0, 0.78, 0.45];

export default function StatusPill({
  phase,
  title,
  timer,
  hint,
  level,
  showStatusText = true,
  reduceMotion = false,
  onCancel,
}: {
  phase: PillPhase;
  title: string;
  /** Elapsed time, recording only (macOS: trailing tabular-digit label). */
  timer?: string | null;
  /** Optional second line, e.g. "再按一次 F5 结束并转写". */
  hint?: string | null;
  level?: number;
  showStatusText?: boolean;
  reduceMotion?: boolean;
  onCancel?: (() => void) | null;
}) {
  const active = phase === "recording" || phase === "processing";
  const showTitle = showStatusText && title.length > 0;
  const showHint = showStatusText && !!hint;
  return (
    <div
      className={`vc-hud-pill ${reduceMotion ? "vc-reduce-motion" : ""}`}
      role="status"
      data-phase={phase}
    >
      <div className="vc-hud-row">
        {active ? (
          <PillWaveform
            level={level ?? 0}
            processing={phase === "processing"}
          />
        ) : (
          <PillBadge phase={phase} />
        )}
        {showTitle && <span className="vc-hud-title">{title}</span>}
        {timer != null && <span className="vc-hud-timer">{timer}</span>}
        {onCancel && (
          <button
            className="vc-hud-cancel"
            onClick={onCancel}
            aria-label="取消听写"
            title="取消并丢弃本次录音 (Esc)"
          >
            <XIcon size={11} />
          </button>
        )}
      </div>
      {showHint && <div className="vc-hud-hint">{hint}</div>}
    </div>
  );
}

/** Leading 5-bar voice glyph: brand accent while recording, amber pulse
 *  while processing — mirroring the macOS waveform accents. */
function PillWaveform({
  level,
  processing,
}: {
  level: number;
  processing: boolean;
}) {
  const energy = processing ? 0.72 : Math.min(1, 0.3 + level * 0.9);
  return (
    <div
      className={`vc-hud-wave ${processing ? "is-processing" : "is-recording"}`}
      aria-hidden
    >
      {BAR_CONTOUR.map((contour, index) => (
        <span
          key={index}
          className="vc-bar vc-hud-bar"
          style={{
            height: `${Math.max(3, contour * 16 * energy)}px`,
            animationDelay: `${index * (processing ? 140 : 90)}ms`,
            animationDuration: `${processing ? 1050 : 900 + (index % 3) * 140}ms`,
          }}
        />
      ))}
    </div>
  );
}

/** Terminal-state badge tile (macOS `configureBadge`): green check for a
 *  delivered paste, amber clipboard for copy-only, red ! for errors. */
function PillBadge({ phase }: { phase: PillPhase }) {
  return (
    <span className={`vc-hud-badge is-${phase}`} aria-hidden>
      {phase === "copied" ? (
        <CopyIcon size={11} />
      ) : phase === "error" ? (
        <span className="vc-hud-badge-glyph">!</span>
      ) : (
        <CheckIcon size={11} />
      )}
    </span>
  );
}
