import { useEffect, useMemo, useState } from "react";
import { api, type AppConfig, type SkillSummary, type StyleCapsule } from "../ipc";
import { SearchIcon, SkillIcon } from "../icons";

/**
 * Skill library — the macOS app's card grid:
 * tinted glyph tile + name + one-line summary, generous gutters.
 */
export default function SkillsPage() {
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<SkillSummary | null>(null);

  const refresh = () => {
    api.listSkills().then((s) => {
      setSkills(s);
      setSelected((cur) => (cur ? (s.find((x) => x.id === cur.id) ?? cur) : null));
    });
  };

  useEffect(() => {
    api.listSkills().then(setSkills);
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return skills;
    return skills.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        (s.summary ?? "").toLowerCase().includes(q),
    );
  }, [skills, query]);

  const setDefault = (id: string) => {
    api.getConfig().then((cfg) => {
      cfg.transcription.skills.defaultSkillId = id;
      if (!cfg.transcription.skills.enabledSkillIds.includes(id)) {
        cfg.transcription.skills.enabledSkillIds.push(id);
      }
      api.saveConfig(cfg).then(refresh);
    });
  };

  const setEnabled = (id: string, enabled: boolean) => {
    api.getConfig().then((cfg) => {
      const ids = cfg.transcription.skills.enabledSkillIds;
      if (enabled && !ids.includes(id)) ids.push(id);
      if (!enabled) {
        cfg.transcription.skills.enabledSkillIds = ids.filter((x) => x !== id);
      }
      api.saveConfig(cfg).then(refresh);
    });
  };

  return (
    <div>
      <div className="relative mb-5 max-w-[280px]">
        <span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-tertiary">
          <SearchIcon size={13} />
        </span>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜索"
          className="vc-input vc-input-search placeholder-ink-tertiary"
        />
      </div>

      {selected ? (
        <SkillDetail
          skill={selected}
          onBack={() => {
            setSelected(null);
            refresh();
          }}
          onSetDefault={setDefault}
          onSetEnabled={setEnabled}
        />
      ) : (
        <div className="grid grid-cols-2 gap-x-5 gap-y-1 xl:grid-cols-3">
          {filtered.map((s) => (
            <button
              key={s.id}
              onClick={() => setSelected(s)}
              className={`group flex items-start gap-3 rounded-[10px] px-2.5 py-2.5 text-left transition-colors hover:bg-black/[0.04] ${
                s.enabled ? "" : "opacity-50"
              }`}
            >
              <SkillIcon skillId={s.id} size={34} />
              <span className="min-w-0 pt-[1px]">
                <span className="flex items-center gap-1.5">
                  <span className="truncate text-[13px] font-medium text-ink">
                    {s.name}
                  </span>
                  {s.isDefault && (
                    <span className="shrink-0 rounded-[4px] bg-accent/10 px-1 py-px text-[9px] font-semibold text-accent">
                      默认
                    </span>
                  )}
                  {!s.enabled && (
                    <span className="shrink-0 rounded-[4px] bg-black/[0.06] px-1 py-px text-[9px] font-semibold text-ink-tertiary">
                      已停用
                    </span>
                  )}
                </span>
                <span className="mt-[1px] line-clamp-2 block text-[11px] leading-snug text-ink-tertiary">
                  {s.summary ?? ""}
                </span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

const RISK_LABEL: Record<string, string> = { low: "低", medium: "中", high: "高" };
const DELIVERY_LABEL: Record<string, string> = {
  automaticPasteWhenVerified: "自动粘贴",
  previewThenPaste: "先预览",
  copyOnly: "仅剪贴板",
  auto_paste: "自动粘贴",
  autoPaste: "自动粘贴",
  preview_first: "先预览",
  previewFirst: "先预览",
  clipboard_only: "仅剪贴板",
  clipboardOnly: "仅剪贴板",
};

function SkillDetail({
  skill,
  onBack,
  onSetDefault,
  onSetEnabled,
}: {
  skill: SkillSummary;
  onBack: () => void;
  onSetDefault: (id: string) => void;
  onSetEnabled: (id: string, enabled: boolean) => void;
}) {
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [styles, setStyles] = useState<StyleCapsule[]>([]);

  useEffect(() => {
    api.getConfig().then(setConfig).catch(() => {});
    api.listStyleCapsules().then(setStyles).catch(() => {});
  }, [skill.id]);

  const assigned =
    config?.styleCapsules?.skillAssignments.find((a) => a.skillID === skill.id)
      ?.capsuleID ?? "";

  const setCapsule = (capsuleID: string) => {
    if (!config) return;
    const next = structuredClone(config);
    next.styleCapsules = next.styleCapsules ?? {
      enabled: true,
      defaultCapsuleID: null,
      skillAssignments: [],
    };
    next.styleCapsules.skillAssignments = next.styleCapsules.skillAssignments.filter(
      (a) => a.skillID !== skill.id,
    );
    if (capsuleID) {
      next.styleCapsules.skillAssignments.push({
        skillID: skill.id,
        capsuleID,
      });
    }
    setConfig(next);
    void api.saveConfig(next);
  };

  // The default skill stays enabled: disabling it would silently reroute
  // every dictation to the Direct fallback.
  const canDisable = !skill.isDefault;
  return (
    <div className="page-enter max-w-[560px]">
      <button
        onClick={onBack}
        className="mb-5 text-[12px] font-medium text-accent hover:opacity-75"
      >
        ‹ 返回 Skill 库
      </button>

      <div className="flex items-center gap-4">
        <SkillIcon skillId={skill.id} size={52} />
        <div className="min-w-0 flex-1">
          <h2 className="text-[17px] font-bold tracking-tight text-ink">
            {skill.name}
          </h2>
          <p className="mt-0.5 text-[12px] text-ink-secondary">{skill.summary}</p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <span className="text-[12px] text-ink-secondary">
            {skill.enabled ? "已启用" : "已停用"}
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={skill.enabled}
            disabled={!canDisable && skill.enabled}
            title={
              !canDisable && skill.enabled ? "默认 Skill 不能停用" : undefined
            }
            onClick={() => onSetEnabled(skill.id, !skill.enabled)}
            className={`vc-toggle ${skill.enabled ? "is-on" : ""} ${
              !canDisable && skill.enabled ? "cursor-not-allowed opacity-50" : ""
            }`}
          >
            <span className="vc-toggle-thumb" />
          </button>
        </div>
      </div>

      <div className="vc-card mt-6 overflow-hidden">
        <MetaRow label="版本" value={skill.version} />
        <MetaRow
          label="交付策略"
          value={DELIVERY_LABEL[skill.delivery] ?? skill.delivery}
        />
        <MetaRow
          label="风险等级"
          value={RISK_LABEL[skill.risk] ?? skill.risk}
        />
        {skill.useCase && <MetaRow label="适用场景" value={skill.useCase} />}
        <div className="flex items-center justify-between gap-6 px-4 py-[9px]">
          <span className="text-[13px] text-ink">写作风格</span>
          <select
            className="vc-select"
            value={assigned}
            onChange={(e) => setCapsule(e.target.value)}
          >
            <option value="">跟随默认</option>
            {styles.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="mt-6">
        <button
          onClick={() => onSetDefault(skill.id)}
          disabled={skill.isDefault}
          className="vc-btn vc-btn-primary"
        >
          {skill.isDefault ? "已是默认 Skill" : "设为默认 Skill"}
        </button>
      </div>
    </div>
  );
}

function MetaRow({
  label,
  value,
  last = false,
}: {
  label: string;
  value: string;
  last?: boolean;
}) {
  return (
    <div
      className={`flex items-center justify-between gap-6 px-4 py-[9px] ${
        last ? "" : "border-b border-hairline"
      }`}
    >
      <span className="text-[13px] text-ink">{label}</span>
      <span className="truncate text-[13px] text-ink-secondary">{value}</span>
    </div>
  );
}
