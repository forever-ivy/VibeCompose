import { useEffect, useMemo, useState } from "react";
import { api, type AppConfig, type TerminologyEntry } from "../ipc";
import { BookIcon, PlusIcon, SearchIcon, TrashIcon } from "../icons";

/**
 * Terminology manager — mirrors the macOS Terminology pane:
 * terms (canonical spellings) and corrections (wrong → right),
 * with search, per-entry enable, and a global switch.
 */
export default function TerminologyPage() {
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    api.getConfig().then(setConfig).catch(() => {});
  }, []);

  const save = (next: AppConfig) => {
    setConfig(next);
    void api.saveConfig(next);
  };

  const patch = (fn: (c: AppConfig) => void) => {
    if (!config) return;
    const next = structuredClone(config);
    fn(next);
    save(next);
  };

  const entries = config?.transcription.terminology.entries ?? [];

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return entries;
    return entries.filter(
      (e) =>
        e.original.toLowerCase().includes(q) ||
        (e.replacement ?? "").toLowerCase().includes(q) ||
        e.aliases.some((a) => a.toLowerCase().includes(q)),
    );
  }, [entries, query]);

  if (!config) {
    return <p className="text-[13px] text-ink-tertiary">加载中…</p>;
  }

  const enabled = config.transcription.terminology.enabled;

  return (
    <div>
      <div className="mb-5 flex items-center gap-3">
        <div className="relative max-w-[280px] flex-1">
          <span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-tertiary">
            <SearchIcon size={13} />
          </span>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索术语"
            className="vc-input vc-input-search placeholder-ink-tertiary"
          />
        </div>
        <button
          onClick={() => setAdding((v) => !v)}
          className="vc-btn vc-btn-primary flex items-center gap-1.5"
        >
          <PlusIcon size={12} /> 添加
        </button>
        <div className="ml-auto flex items-center gap-2">
          <span className="text-[12px] text-ink-secondary">启用术语规范化</span>
          <button
            type="button"
            role="switch"
            aria-checked={enabled}
            onClick={() =>
              patch((c) => (c.transcription.terminology.enabled = !enabled))
            }
            className={`vc-toggle ${enabled ? "is-on" : ""}`}
          >
            <span className="vc-toggle-thumb" />
          </button>
        </div>
      </div>

      {adding && (
        <AddEntryForm
          onCancel={() => setAdding(false)}
          onSubmit={(entry) => {
            patch((c) => c.transcription.terminology.entries.unshift(entry));
            setAdding(false);
          }}
        />
      )}

      {entries.length === 0 && !adding ? (
        <EmptyState />
      ) : (
        <div className="vc-card">
          {filtered.length === 0 ? (
            <p className="px-4 py-6 text-center text-[12px] text-ink-tertiary">
              没有匹配的术语
            </p>
          ) : (
            filtered.map((entry, i) => (
              <EntryRow
                key={entry.id}
                entry={entry}
                first={i === 0}
                dimmed={!enabled}
                onToggle={(on) =>
                  patch((c) => {
                    const target = c.transcription.terminology.entries.find(
                      (e) => e.id === entry.id,
                    );
                    if (target) target.isEnabled = on;
                  })
                }
                onDelete={() =>
                  patch((c) => {
                    c.transcription.terminology.entries =
                      c.transcription.terminology.entries.filter(
                        (e) => e.id !== entry.id,
                      );
                  })
                }
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center pt-24 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-[14px] bg-black/[0.05] text-ink-tertiary">
        <BookIcon size={22} />
      </span>
      <p className="mt-4 text-[13px] font-medium text-ink-secondary">
        还没有术语
      </p>
      <p className="mt-1 max-w-[340px] text-[11px] leading-relaxed text-ink-tertiary">
        术语让转写稳定还原专有名词（如产品名、人名）；纠错把常见误听替换为正确写法。
      </p>
    </div>
  );
}

function EntryRow({
  entry,
  first,
  dimmed,
  onToggle,
  onDelete,
}: {
  entry: TerminologyEntry;
  first: boolean;
  dimmed: boolean;
  onToggle: (on: boolean) => void;
  onDelete: () => void;
}) {
  const isTerm = entry.type === "term";
  return (
    <div
      className={`group flex items-center gap-3 px-4 py-2.5 ${
        first ? "" : "border-t border-hairline"
      } ${dimmed || !entry.isEnabled ? "opacity-55" : ""}`}
    >
      <span
        className={`shrink-0 rounded-[4px] px-1.5 py-px text-[10px] font-semibold ${
          isTerm ? "bg-accent/10 text-accent" : "bg-amber/15 text-amber"
        }`}
      >
        {isTerm ? "术语" : "纠错"}
      </span>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px] text-ink">
          {isTerm ? (
            entry.original
          ) : (
            <>
              <span className="text-ink-tertiary line-through">
                {entry.original}
              </span>
              <span className="mx-1.5 text-ink-tertiary">→</span>
              {entry.replacement ?? entry.original}
            </>
          )}
        </div>
        {entry.aliases.length > 0 && (
          <div className="mt-[1px] truncate text-[11px] text-ink-tertiary">
            别名：{entry.aliases.join("、")}
          </div>
        )}
      </div>
      <button
        title="删除"
        onClick={onDelete}
        className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-[5px] text-ink-tertiary opacity-0 transition-opacity group-hover:opacity-100 hover:bg-black/[0.06] hover:text-ink-secondary"
      >
        <TrashIcon size={13} />
      </button>
      <button
        type="button"
        role="switch"
        aria-checked={entry.isEnabled}
        onClick={() => onToggle(!entry.isEnabled)}
        className={`vc-toggle shrink-0 ${entry.isEnabled ? "is-on" : ""}`}
      >
        <span className="vc-toggle-thumb" />
      </button>
    </div>
  );
}

function AddEntryForm({
  onSubmit,
  onCancel,
}: {
  onSubmit: (entry: TerminologyEntry) => void;
  onCancel: () => void;
}) {
  const [type, setType] = useState<"term" | "correction">("term");
  const [original, setOriginal] = useState("");
  const [replacement, setReplacement] = useState("");
  const [aliases, setAliases] = useState("");

  const isTerm = type === "term";
  const valid =
    original.trim().length > 0 && (isTerm || replacement.trim().length > 0);

  const submit = () => {
    if (!valid) return;
    onSubmit({
      id: crypto.randomUUID(),
      type,
      original: original.trim(),
      replacement: isTerm ? null : replacement.trim(),
      aliases: aliases
        .split(/[,，、]/)
        .map((a) => a.trim())
        .filter(Boolean),
      isEnabled: true,
      source: "user",
      usageCount: 0,
      createdAt: new Date().toISOString(),
    });
  };

  return (
    <div className="vc-card mb-5 space-y-3 px-4 py-3.5">
      <div className="flex items-center gap-2">
        <select
          value={type}
          onChange={(e) => setType(e.target.value as "term" | "correction")}
          className="vc-select"
        >
          <option value="term">术语（固定写法）</option>
          <option value="correction">纠错（误听 → 正确）</option>
        </select>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <input
          value={original}
          onChange={(e) => setOriginal(e.target.value)}
          placeholder={isTerm ? "标准写法，如 VibeCompose" : "常见误听，如 外部作曲"}
          className="vc-input w-56 placeholder-ink-tertiary"
        />
        {!isTerm && (
          <>
            <span className="text-[12px] text-ink-tertiary">→</span>
            <input
              value={replacement}
              onChange={(e) => setReplacement(e.target.value)}
              placeholder="正确写法"
              className="vc-input w-56 placeholder-ink-tertiary"
            />
          </>
        )}
        <input
          value={aliases}
          onChange={(e) => setAliases(e.target.value)}
          placeholder="别名（逗号分隔，可留空）"
          className="vc-input w-64 placeholder-ink-tertiary"
        />
      </div>
      <div className="flex items-center gap-2">
        <button
          onClick={submit}
          disabled={!valid}
          className="vc-btn vc-btn-primary"
        >
          保存
        </button>
        <button onClick={onCancel} className="vc-btn vc-btn-secondary">
          取消
        </button>
      </div>
    </div>
  );
}
