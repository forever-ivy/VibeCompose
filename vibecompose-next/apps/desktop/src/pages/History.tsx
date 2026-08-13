import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type HistoryRecord, type RecoveryRecord } from "../ipc";
import { CopyIcon, SearchIcon, TrashIcon, WaveformIcon } from "../icons";

const OUTCOME_LABEL: Record<string, { text: string; cls: string }> = {
  inserted_verified: { text: "已验证插入", cls: "text-success" },
  paste_dispatched: { text: "已发送粘贴", cls: "text-success" },
  clipboard: { text: "已复制", cls: "text-amber" },
  copied_to_clipboard: { text: "已复制", cls: "text-amber" },
};

type StatusFilter = "all" | "pasted" | "copied";

const PASTED = new Set(["inserted_verified", "paste_dispatched"]);

export default function HistoryPage() {
  const [records, setRecords] = useState<HistoryRecord[]>([]);
  const [recovery, setRecovery] = useState<RecoveryRecord[]>([]);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<StatusFilter>("all");

  const refresh = useCallback(() => {
    api.getHistory().then(setRecords).catch(() => {});
    api.listRecovery().then(setRecovery).catch(() => {});
  }, []);

  useEffect(refresh, [refresh]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return records.filter((r) => {
      if (status === "pasted" && !PASTED.has(r.outcome)) return false;
      if (status === "copied" && PASTED.has(r.outcome)) return false;
      if (!q) return true;
      return (
        r.finalText.toLowerCase().includes(q) ||
        (r.rawText ?? "").toLowerCase().includes(q) ||
        r.skillName.toLowerCase().includes(q) ||
        r.appName.toLowerCase().includes(q)
      );
    });
  }, [records, query, status]);

  if (records.length === 0 && recovery.length === 0) {
    return (
      <div className="flex flex-col items-center pt-24 text-center">
        <span className="grid h-12 w-12 place-items-center rounded-[14px] bg-black/[0.05] text-ink-tertiary">
          <WaveformIcon size={22} />
        </span>
        <p className="mt-4 text-[13px] font-medium text-ink-secondary">
          还没有听写记录
        </p>
        <p className="mt-1 text-[11px] text-ink-tertiary">
          按全局快捷键开始你的第一次听写
        </p>
      </div>
    );
  }

  return (
    <div>
      {recovery.length > 0 && (
        <section className="mb-6">
          <h3 className="mb-1.5 pl-1 text-[11px] font-semibold tracking-[0.04em] text-ink-tertiary uppercase">
            失败恢复
          </h3>
          <div className="vc-card">
            {recovery.map((item, i) => (
              <article
                key={item.id}
                className={`flex items-start justify-between gap-3 px-4 py-3 ${
                  i > 0 ? "border-t border-hairline" : ""
                }`}
              >
                <div className="min-w-0">
                  <div className="text-[12px] font-medium text-ink">
                    {item.appName || "未知应用"} · {(item.audioDurationMs / 1000).toFixed(1)} 秒
                  </div>
                  <div className="mt-0.5 text-[11px] text-ink-tertiary">
                    {item.errorMessage || "转写失败"} · {formatTimestamp(item.timestamp)}
                  </div>
                </div>
                <div className="flex shrink-0 gap-1.5">
                  <button
                    className="vc-btn vc-btn-primary"
                    onClick={() => api.retryRecovery(item.id).then(refresh)}
                  >
                    重试
                  </button>
                  <button
                    className="vc-btn vc-btn-secondary"
                    onClick={() => api.deleteRecovery(item.id).then(refresh)}
                  >
                    删除
                  </button>
                </div>
              </article>
            ))}
          </div>
        </section>
      )}

      {records.length > 0 && (
      <>
      <div className="mb-4 flex items-center gap-3">
        <div className="relative max-w-[280px] flex-1">
          <span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-tertiary">
            <SearchIcon size={13} />
          </span>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索历史"
            className="vc-input vc-input-search placeholder-ink-tertiary"
          />
        </div>
        <FilterChips value={status} onChange={setStatus} />
        <button
          onClick={() => api.clearHistory().then(refresh)}
          className="vc-btn vc-btn-secondary ml-auto"
        >
          清空
        </button>
      </div>

      <div className="vc-card">
        {filtered.length === 0 ? (
          <p className="px-4 py-6 text-center text-[12px] text-ink-tertiary">
            没有匹配的记录
          </p>
        ) : (
          filtered.map((r, i) => {
            const outcome = OUTCOME_LABEL[r.outcome] ?? {
              text: "已处理",
              cls: "text-ink-secondary",
            };
            return (
              <article
                key={r.id}
                className={`group px-4 py-3 ${i > 0 ? "border-t border-hairline" : ""}`}
              >
                <div className="flex items-baseline gap-2.5">
                  <span className="text-[12px] font-medium text-ink">
                    {r.skillName}
                  </span>
                  <span className={`text-[11px] font-medium ${outcome.cls}`}>
                    {outcome.text}
                  </span>
                  {r.textPolishProvider && (
                    <span className="text-[11px] text-ink-tertiary">
                      已润色
                    </span>
                  )}
                  <span className="ml-auto shrink-0 text-[11px] tabular-nums text-ink-tertiary">
                    {formatTimestamp(r.timestamp)}
                    {r.appName ? ` · ${r.appName}` : ""}
                  </span>
                  <span className="flex shrink-0 gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                    <IconButton
                      title="拷贝"
                      onClick={() => navigator.clipboard.writeText(r.finalText)}
                    >
                      <CopyIcon size={13} />
                    </IconButton>
                    <IconButton
                      title="删除"
                      onClick={() => api.deleteHistoryRecord(r.id).then(refresh)}
                    >
                      <TrashIcon size={13} />
                    </IconButton>
                  </span>
                </div>
                <p className="mt-1 line-clamp-2 text-[12px] leading-relaxed text-ink-secondary">
                  {r.finalText}
                </p>
                {r.rawText && r.rawText !== r.finalText && (
                  <p className="mt-1 line-clamp-1 text-[11px] leading-relaxed text-ink-tertiary">
                    原始转写：{r.rawText}
                  </p>
                )}
              </article>
            );
          })
        )}
      </div>
      </>
      )}
    </div>
  );
}

function FilterChips({
  value,
  onChange,
}: {
  value: StatusFilter;
  onChange: (v: StatusFilter) => void;
}) {
  const chips: { id: StatusFilter; label: string }[] = [
    { id: "all", label: "全部" },
    { id: "pasted", label: "已粘贴" },
    { id: "copied", label: "已复制" },
  ];
  return (
    <div className="flex gap-1">
      {chips.map((chip) => (
        <button
          key={chip.id}
          onClick={() => onChange(chip.id)}
          className={`vc-chip ${value === chip.id ? "is-on" : ""}`}
        >
          {chip.label}
        </button>
      ))}
    </div>
  );
}

function formatTimestamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  if (sameDay) return `${hh}:${mm}`;
  return `${d.getMonth() + 1}月${d.getDate()}日 ${hh}:${mm}`;
}

function IconButton({
  title,
  onClick,
  children,
}: {
  title: string;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      title={title}
      onClick={onClick}
      className="grid h-[22px] w-[22px] place-items-center rounded-[5px] text-ink-tertiary transition-colors hover:bg-black/[0.06] hover:text-ink-secondary"
    >
      {children}
    </button>
  );
}
