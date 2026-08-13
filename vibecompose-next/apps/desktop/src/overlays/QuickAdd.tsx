import { useState } from "react";
import { api } from "../ipc";

/**
 * Terminology Quick Add — the Ctrl+Alt+Space floating panel, mirroring the
 * macOS window: type (term / correction), original, replacement, aliases.
 */
export default function QuickAddOverlay() {
  const [entryType, setEntryType] = useState<"term" | "correction">("term");
  const [original, setOriginal] = useState("");
  const [replacement, setReplacement] = useState("");
  const [aliases, setAliases] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const close = () => void api.hideOverlay("quick-add");

  const save = () => {
    setBusy(true);
    setError(null);
    api
      .addTerminologyEntry({ entryType, original, replacement, aliases })
      .then(() => {
        setOriginal("");
        setReplacement("");
        setAliases("");
      })
      .catch((err) => setError(String(err)))
      .finally(() => setBusy(false));
  };

  return (
    <div
      className="overlay-page"
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          close();
        }
        if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
          event.preventDefault();
          save();
        }
      }}
    >
      <div className="text-[11px] font-semibold tracking-wide text-ink-tertiary uppercase">
        快速添加术语
      </div>

      <div className="mt-3 flex gap-1">
        {(
          [
            { id: "term", label: "术语" },
            { id: "correction", label: "纠错" },
          ] as const
        ).map((chip) => (
          <button
            key={chip.id}
            onClick={() => setEntryType(chip.id)}
            className={`vc-chip ${entryType === chip.id ? "is-on" : ""}`}
          >
            {chip.label}
          </button>
        ))}
      </div>

      <div className="mt-3 space-y-2">
        <label className="block">
          <span className="mb-1 block text-[11px] text-ink-tertiary">
            {entryType === "term" ? "标准写法" : "听错的文本"}
          </span>
          <input
            autoFocus
            className="vc-input w-full"
            value={original}
            placeholder={entryType === "term" ? "例如 Kubernetes" : "例如 库伯内提斯"}
            onChange={(e) => setOriginal(e.target.value)}
          />
        </label>
        {entryType === "correction" && (
          <label className="block">
            <span className="mb-1 block text-[11px] text-ink-tertiary">替换为</span>
            <input
              className="vc-input w-full"
              value={replacement}
              placeholder="例如 Kubernetes"
              onChange={(e) => setReplacement(e.target.value)}
            />
          </label>
        )}
        <label className="block">
          <span className="mb-1 block text-[11px] text-ink-tertiary">
            别名（逗号分隔，可选）
          </span>
          <input
            className="vc-input w-full"
            value={aliases}
            placeholder="K8s, k8s"
            onChange={(e) => setAliases(e.target.value)}
          />
        </label>
      </div>

      {error && <p className="mt-2 text-[11px] text-error">{error}</p>}

      <div className="mt-4 flex justify-end gap-2">
        <button className="vc-btn vc-btn-secondary" onClick={close}>
          取消
        </button>
        <button className="vc-btn vc-btn-primary" disabled={busy} onClick={save}>
          {busy ? "保存中…" : "保存"}
        </button>
      </div>
    </div>
  );
}
