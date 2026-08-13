import { useEffect, useMemo, useState } from "react";
import { api, type SkillSummary } from "../ipc";
import { SearchIcon, SkillIcon } from "../icons";

export default function SwitcherOverlay() {
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [query, setQuery] = useState("");

  useEffect(() => {
    void api.listSkills().then(setSkills);
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void api.hideOverlay("skill-switcher");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const enabled = skills.filter((s) => s.enabled);
    if (!q) return enabled;
    return enabled.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        (s.summary ?? "").toLowerCase().includes(q),
    );
  }, [skills, query]);

  return (
    <div className="overlay-page">
      <div className="text-[11px] font-semibold tracking-wide text-ink-tertiary uppercase">
        Skill 切换器
      </div>
      <div className="relative mt-3">
        <span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-tertiary">
          <SearchIcon size={13} />
        </span>
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜索并设为默认"
          className="vc-input vc-input-search w-full placeholder-ink-tertiary"
        />
      </div>
      <div className="mt-3 max-h-[360px] overflow-y-auto">
        {filtered.map((skill) => (
          <button
            key={skill.id}
            onClick={() => api.setDefaultSkill(skill.id)}
            className="flex w-full items-center gap-3 rounded-[8px] px-2 py-2 text-left hover:bg-black/[0.04]"
          >
            <SkillIcon skillId={skill.id} size={28} />
            <span className="min-w-0 flex-1">
              <span className="flex items-center gap-1.5">
                <span className="truncate text-[13px] font-medium text-ink">
                  {skill.name}
                </span>
                {skill.isDefault && (
                  <span className="rounded-[4px] bg-accent/10 px-1 text-[9px] font-semibold text-accent">
                    当前
                  </span>
                )}
              </span>
              <span className="line-clamp-1 block text-[11px] text-ink-tertiary">
                {skill.summary ?? ""}
              </span>
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
