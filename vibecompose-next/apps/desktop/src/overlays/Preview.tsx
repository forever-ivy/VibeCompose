import { useEffect, useState } from "react";
import {
  api,
  onDictationPreview,
  type PendingPreview,
  type SkillSummary,
} from "../ipc";

export default function PreviewOverlay() {
  const [preview, setPreview] = useState<PendingPreview | null>(null);
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void api.getPendingPreview().then((p) => p && setPreview(p));
    void api.listSkills().then((list) => setSkills(list.filter((s) => s.enabled)));
    const unlisten = onDictationPreview(setPreview);
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void api.dismissPreview();
      }
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter" && preview) {
        event.preventDefault();
        void confirm();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      unlisten.then((u) => u());
      window.removeEventListener("keydown", onKey);
    };
  }, [preview]);

  const confirm = async () => {
    const current = preview;
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      await api.confirmPreview(current.finalText);
    } catch (err) {
      setError(String(err));
      setBusy(false);
    }
  };

  if (!preview) {
    return (
      <div className="overlay-page">
        <p className="text-[13px] text-ink-tertiary">没有待确认的听写结果</p>
      </div>
    );
  }

  return (
    <div className="overlay-page">
      <header className="mb-3">
        <div className="text-[11px] font-semibold tracking-wide text-ink-tertiary uppercase">
          结果预览
        </div>
        <div className="mt-1 text-[15px] font-semibold text-ink">
          {preview.skillName}
          {preview.appName ? ` · ${preview.appName}` : ""}
        </div>
      </header>

      <textarea
        className="vc-input min-h-[160px] w-full resize-none text-[13px] leading-relaxed"
        value={preview.finalText}
        onChange={(e) =>
          setPreview({ ...preview, finalText: e.target.value })
        }
      />

      {preview.polishError && (
        <p className="mt-2 text-[11px] text-ink-tertiary">
          润色回退：{preview.polishError}
        </p>
      )}
      {error && <p className="mt-2 text-[11px] text-error">{error}</p>}

      <div className="mt-3 flex items-center gap-2">
        <label className="text-[11px] text-ink-tertiary">换 Skill</label>
        <select
          className="vc-select flex-1"
          value={preview.skillId}
          disabled={busy}
          onChange={(e) => {
            const id = e.target.value;
            setBusy(true);
            api
              .reprocessPreview(id, preview.rawText)
              .then(setPreview)
              .catch((err) => setError(String(err)))
              .finally(() => setBusy(false));
          }}
        >
          {skills.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </div>

      <div className="mt-4 flex justify-end gap-2">
        <button className="vc-btn vc-btn-secondary" onClick={() => api.dismissPreview()}>
          取消
        </button>
        <button
          className="vc-btn vc-btn-secondary"
          disabled={busy}
          onClick={() => api.copyPreview()}
        >
          仅复制
        </button>
        <button
          className="vc-btn vc-btn-primary"
          disabled={busy}
          onClick={() => void confirm()}
        >
          {busy ? "处理中…" : preview.copyOnly ? "复制" : "粘贴"}
        </button>
      </div>
    </div>
  );
}
