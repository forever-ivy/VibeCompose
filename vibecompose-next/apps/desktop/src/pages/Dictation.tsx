import { useEffect, useState } from "react";
import {
  api,
  type AccountStatus,
  type DictationResultEvent,
  type RecoveryRecord,
  type SessionSnapshot,
  type SkillSummary,
} from "../ipc";
import { CheckIcon, CopyIcon, MicIcon, XIcon } from "../icons";

/**
 * Dictation hero — mirrors the macOS HUD language:
 * one calm surface, a single accent, 9-bar center-weighted waveform.
 */
export default function DictationPage({
  session,
  lastResult,
  lastError,
}: {
  session: SessionSnapshot;
  lastResult: DictationResultEvent | null;
  lastError: string | null;
}) {
  const [status, setStatus] = useState<AccountStatus | null>(null);
  const [defaultSkill, setDefaultSkill] = useState<SkillSummary | null>(null);
  const [recovery, setRecovery] = useState<RecoveryRecord[]>([]);

  useEffect(() => {
    api.getAccountStatus().then(setStatus).catch(() => {});
    api
      .listSkills()
      .then((skills) => setDefaultSkill(skills.find((s) => s.isDefault) ?? null))
      .catch(() => {});
    api.listRecovery().then(setRecovery).catch(() => {});
  }, [session.phase]);

  const recording = session.phase === "recording";
  const processing = session.phase === "processing";
  const seconds = Math.floor(session.elapsedMs / 1000);
  const timer = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(
    seconds % 60,
  ).padStart(2, "0")}`;

  const needsAccount = status && !status.chatgptConnected && !status.openaiKeyPresent;

  return (
    <div className="space-y-6">
      {/* Hero: big record control, generous whitespace */}
      <section className="flex flex-col items-center pt-14 pb-10">
        <RecordButton
          recording={recording}
          processing={processing}
          onClick={() => api.toggleDictation()}
        />
        <div className="mt-7 h-5 text-[13px] font-medium">
          {recording ? (
            <span className="tabular-nums text-ink-secondary">{timer}</span>
          ) : processing ? (
            <span className="text-ink-secondary">正在处理…</span>
          ) : (
            <span className="text-ink-secondary">
              按 <Kbd>F5</Kbd> 开始听写
            </span>
          )}
        </div>
        <div className="mt-3 flex h-8 items-center">
          {recording && <Waveform level={session.level} />}
        </div>
        <p className="mt-4 max-w-[380px] text-center text-[11px] leading-relaxed text-ink-tertiary">
          {recording
            ? "再按一次快捷键结束并转写"
            : processing
              ? "正在转写与润色"
              : "按下快捷键说话，VibeCompose 会转写、润色并粘贴到当前应用"}
        </p>
        {(recording || processing) && (
          <button
            onClick={() => api.cancelDictation()}
            className="vc-btn vc-btn-secondary mt-4 flex items-center gap-1.5"
          >
            <XIcon size={11} /> 取消
          </button>
        )}
        {!recording && !processing && defaultSkill && (
          <p className="mt-2 text-[11px] text-ink-tertiary">
            当前 Skill：
            <span className="font-medium text-ink-secondary">
              {defaultSkill.name}
            </span>
          </p>
        )}
      </section>

      {needsAccount && (
        <Banner tone="warn">
          尚未配置转写账户 — 请在「设置」中登录 ChatGPT 或填写 OpenAI API Key。
        </Banner>
      )}
      {status?.accessibilityPermissionMissing && (
        <Banner tone="warn">
          需要辅助功能权限才能自动粘贴文本（仅 macOS）。授权后请重启应用。
        </Banner>
      )}
      {lastError && <Banner tone="error">{lastError}</Banner>}
      {recovery.length > 0 && (
        <Banner tone="warn">
          有 {recovery.length} 条失败录音可在「历史记录」中重试。
        </Banner>
      )}

      {lastResult && <ResultCard result={lastResult} />}
    </div>
  );
}

function RecordButton({
  recording,
  processing,
  onClick,
}: {
  recording: boolean;
  processing: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="group relative grid h-[88px] w-[88px] place-items-center rounded-full transition-transform duration-150 active:scale-95"
      style={{
        background: recording ? "var(--color-error)" : "var(--color-accent)",
        boxShadow: recording
          ? "0 10px 28px rgba(255,107,112,0.35), inset 0 1px 0 rgba(255,255,255,0.25)"
          : "0 10px 28px rgba(0,116,255,0.32), inset 0 1px 0 rgba(255,255,255,0.25)",
      }}
      aria-label={recording ? "停止录音" : "开始录音"}
    >
      {recording && (
        <>
          <span className="vc-pulse-ring absolute inset-0 rounded-full bg-error" />
          <span
            className="vc-pulse-ring absolute inset-0 rounded-full bg-error"
            style={{ animationDelay: "0.55s" }}
          />
        </>
      )}
      {processing ? (
        <span className="vc-spin block h-7 w-7 rounded-full border-[2.5px] border-white/30 border-t-white" />
      ) : recording ? (
        <span className="block h-[26px] w-[26px] rounded-[7px] bg-white" />
      ) : (
        <MicIcon size={34} className="text-white" />
      )}
    </button>
  );
}

/** 9 compact bars, center tallest, ice-blue core — the HUD's signature. */
const PROFILE = [0.22, 0.34, 0.48, 0.72, 1.0, 0.74, 0.5, 0.34, 0.22];

function Waveform({ level }: { level: number }) {
  const energy = Math.min(1, 0.25 + level * 0.9);
  return (
    <div className="flex h-8 items-center gap-[3px]">
      {PROFILE.map((p, i) => {
        const center = i >= 3 && i <= 5;
        return (
          <span
            key={i}
            className="vc-bar w-[3px] rounded-full"
            style={{
              height: `${Math.max(6, p * 30 * energy)}px`,
              background: center ? "var(--color-ice)" : "rgba(120,140,160,0.45)",
              animationDelay: `${i * 90}ms`,
              animationDuration: `${900 + (i % 3) * 140}ms`,
            }}
          />
        );
      })}
    </div>
  );
}

function ResultCard({ result }: { result: DictationResultEvent }) {
  const good = result.outcome === "inserted_verified" || result.outcome === "paste_dispatched";
  return (
    <section className="vc-card overflow-hidden">
      <div className="flex items-center gap-3 border-b border-hairline px-4 py-3">
        <span
          className="grid h-[30px] w-[30px] place-items-center rounded-[9px]"
          style={{
            background: good ? "rgba(82,204,148,0.14)" : "rgba(255,184,71,0.16)",
            color: good ? "var(--color-success)" : "var(--color-amber)",
          }}
        >
          {good ? <CheckIcon size={15} /> : <CopyIcon size={14} />}
        </span>
        <div className="min-w-0 flex-1">
          <div className="text-[13px] font-semibold text-ink">
            {good ? "已粘贴到目标应用" : "已复制到剪贴板"}
          </div>
          <div className="text-[11px] text-ink-tertiary">
            {result.skillName} · {(result.durationMs / 1000).toFixed(1)} 秒
            {result.appName ? ` · ${result.appName}` : ""}
          </div>
        </div>
        <button
          onClick={() => navigator.clipboard.writeText(result.finalText)}
          className="vc-btn vc-btn-secondary"
        >
          拷贝
        </button>
      </div>
      <p className="px-4 py-3.5 text-[13px] leading-relaxed whitespace-pre-wrap text-ink">
        {result.finalText}
      </p>
      {result.polishError && (
        <p className="border-t border-hairline px-4 py-2 text-[11px] leading-relaxed text-ink-tertiary">
          润色失败，已回退到规范化转写：{result.polishError}
        </p>
      )}
    </section>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="vc-kbd">{children}</kbd>
  );
}

function Banner({
  tone,
  children,
}: {
  tone: "warn" | "error";
  children: React.ReactNode;
}) {
  return (
    <div
      className={`vc-banner ${tone === "warn" ? "vc-banner-warn" : "vc-banner-error"}`}
    >
      {children}
    </div>
  );
}
