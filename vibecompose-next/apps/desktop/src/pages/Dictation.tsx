import { useEffect, useState } from "react";
import {
  api,
  type AccountStatus,
  type DictationResultEvent,
  type LoginAvailability,
  type RecoveryRecord,
  type SessionSnapshot,
  type SkillSummary,
} from "../ipc";
import { CheckIcon, CopyIcon, MicIcon } from "../icons";
import StatusPill from "../components/StatusPill";

/**
 * Dictation page. Idle shows the start affordance (mic button + hotkey
 * hint); while a session runs the hero collapses to the same compact
 * status pill as the floating Refined HUD — recording feedback is a small
 * box (macOS `OverlayController` form), never a large in-window circle.
 */
export default function DictationPage({
  session,
  lastResult,
  lastError,
  availability,
  onOpenSettings,
}: {
  session: SessionSnapshot;
  lastResult: DictationResultEvent | null;
  lastError: string | null;
  availability?: LoginAvailability | null;
  onOpenSettings?: () => void;
}) {
  const [status, setStatus] = useState<AccountStatus | null>(null);
  const [defaultSkill, setDefaultSkill] = useState<SkillSummary | null>(null);
  const [recovery, setRecovery] = useState<RecoveryRecord[]>([]);
  const [hotkey, setHotkey] = useState("F5");

  useEffect(() => {
    api.getAccountStatus().then(setStatus).catch(() => {});
    api
      .listSkills()
      .then((skills) => setDefaultSkill(skills.find((s) => s.isDefault) ?? null))
      .catch(() => {});
    api.listRecovery().then(setRecovery).catch(() => {});
    api
      .getConfig()
      .then((config) => {
        const binding = config.transcription.dictationHotkey;
        setHotkey(
          [...(binding.modifiers ?? []), binding.key].filter(Boolean).join("+"),
        );
      })
      .catch(() => {});
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
      {/* Hero: idle keeps the start affordance; an active session shows the
          same compact HUD pill as the floating overlay (macOS small-box
          form) — no large circle, no pulsing rings. */}
      <section className="flex flex-col items-center pt-14 pb-10">
        {recording || processing ? (
          <>
            <StatusPill
              phase={recording ? "recording" : "processing"}
              title={
                recording ? (defaultSkill?.name ?? "正在录音") : "处理中"
              }
              timer={recording ? timer : null}
              hint={recording ? "再按一次快捷键结束并转写" : null}
              level={session.level}
              onCancel={() => api.cancelDictation()}
            />
            <p className="mt-4 text-[11px] text-ink-tertiary">
              {recording ? (
                <>
                  按 <Kbd>{hotkey}</Kbd> 结束并转写，<Kbd>Esc</Kbd> 取消
                </>
              ) : (
                "正在转写与润色"
              )}
            </p>
            {recording && (
              <button
                onClick={() => api.toggleDictation()}
                className="vc-btn vc-btn-secondary mt-3"
              >
                停止并转写
              </button>
            )}
          </>
        ) : (
          <>
            <RecordButton onClick={() => api.toggleDictation()} />
            <div className="mt-7 h-5 text-[13px] font-medium">
              <span className="text-ink-secondary">
                按 <Kbd>{hotkey}</Kbd> 开始听写
              </span>
            </div>
            <p className="mt-4 max-w-[380px] text-center text-[11px] leading-relaxed text-ink-tertiary">
              按下快捷键说话，VibeCompose 会转写、润色并粘贴到当前应用
            </p>
            {defaultSkill && (
              <p className="mt-2 text-[11px] text-ink-tertiary">
                当前 Skill：
                <span className="font-medium text-ink-secondary">
                  {defaultSkill.name}
                </span>
              </p>
            )}
          </>
        )}
      </section>

      {needsAccount && (
        <Banner tone="warn">
          <div className="flex items-center justify-between gap-3">
            <span>
              {availability?.status === "unavailable"
                ? "ChatGPT 登录在此平台暂不可用 — 在「设置」中填写 OpenAI 兼容 API Key 即可继续听写与润色。"
                : "尚未配置转写账户 — 请在「设置」中登录 ChatGPT 或填写 OpenAI API Key。"}
            </span>
            {onOpenSettings && (
              <button
                className="vc-btn vc-btn-secondary shrink-0"
                onClick={onOpenSettings}
              >
                打开设置
              </button>
            )}
          </div>
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

/** Idle start affordance only — active sessions render the compact pill. */
function RecordButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="group relative grid h-[88px] w-[88px] place-items-center rounded-full transition-transform duration-150 active:scale-95"
      style={{
        background: "var(--color-accent)",
        boxShadow:
          "0 10px 28px rgba(0,116,255,0.32), inset 0 1px 0 rgba(255,255,255,0.25)",
      }}
      aria-label="开始录音"
    >
      <MicIcon size={34} className="text-white" />
    </button>
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
