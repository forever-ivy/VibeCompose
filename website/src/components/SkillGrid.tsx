"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Locale } from "@/lib/i18n";
import type { Dictionary } from "@/content/dictionary";
import { formatResults } from "@/content/dictionary";
import type {
  SkillCategory,
  SkillEntry,
  SkillSource,
} from "@/lib/catalog-types";
import { CATEGORY_ORDER } from "@/lib/catalog-types";
import { localizeSkill } from "@/lib/skill-localize";
import { SkillCard } from "./SkillCard";

type SourceFilter = "all" | SkillSource;
type CategoryFilter = "all" | SkillCategory;

export function SkillGrid({
  skills,
  locale,
  dict,
}: {
  skills: SkillEntry[];
  locale: Locale;
  dict: Dictionary;
}) {
  const [query, setQuery] = useState("");
  const [source, setSource] = useState<SourceFilter>("all");
  const [category, setCategory] = useState<CategoryFilter>("all");
  const listRef = useRef<HTMLUListElement | null>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = listRef.current;
    const safety = window.setTimeout(() => setInView(true), 120);
    if (!el || typeof IntersectionObserver === "undefined") {
      setInView(true);
      return () => window.clearTimeout(safety);
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { threshold: 0.05 },
    );
    io.observe(el);
    return () => {
      window.clearTimeout(safety);
      io.disconnect();
    };
  }, [source, category, query]);

  const availableSources = useMemo(() => {
    const set = new Set(skills.map((s) => s.source));
    return (["built-in", "community", "example"] as SkillSource[]).filter((s) =>
      set.has(s),
    );
  }, [skills]);

  const availableCategories = useMemo(() => {
    const set = new Set(skills.map((s) => s.category));
    return CATEGORY_ORDER.filter((c) => set.has(c));
  }, [skills]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return skills.filter((skill) => {
      if (source !== "all" && skill.source !== source) return false;
      if (category !== "all" && skill.category !== category) return false;
      if (!q) return true;
      const { name, summary } = localizeSkill(skill, locale);
      return (
        name.toLowerCase().includes(q) ||
        summary.toLowerCase().includes(q) ||
        skill.slug.toLowerCase().includes(q) ||
        dict.labels.category[skill.category].toLowerCase().includes(q)
      );
    });
  }, [skills, source, category, query, locale, dict.labels.category]);

  return (
    <div>
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <label className="block min-w-0 flex-1">
          <span className="sr-only">{dict.skillsPage.searchPlaceholder}</span>
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={dict.skillsPage.searchPlaceholder}
            className="w-full rounded-full border border-line bg-bg px-5 py-3 text-sm text-ink outline-none placeholder:text-muted focus:border-ink focus:ring-2 focus:ring-ink/10"
          />
        </label>

        <div className="flex flex-wrap gap-2">
          <FilterSelect
            label={dict.skillsPage.filterSource}
            value={source}
            onChange={(v) => setSource(v as SourceFilter)}
            options={[
              { value: "all", label: dict.skillsPage.filterAll },
              ...availableSources.map((s) => ({
                value: s,
                label: dict.labels.source[s],
              })),
            ]}
          />
          <FilterSelect
            label={dict.skillsPage.filterCategory}
            value={category}
            onChange={(v) => setCategory(v as CategoryFilter)}
            options={[
              { value: "all", label: dict.skillsPage.filterAll },
              ...availableCategories.map((c) => ({
                value: c,
                label: dict.labels.category[c],
              })),
            ]}
          />
        </div>
      </div>

      <p className="mt-5 text-sm text-muted">
        {formatResults(dict.skillsPage.results, filtered.length)}
      </p>

      {filtered.length === 0 ? (
        <p className="mt-10 rounded-card border border-dashed border-line bg-surface px-6 py-12 text-center text-sm text-muted">
          {dict.skillsPage.empty}
        </p>
      ) : (
        <ul
          ref={listRef}
          key={`${source}-${category}-${query}`}
          className={[
            "mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3",
            inView ? "stagger-in" : "stagger-boot",
          ].join(" ")}
        >
          {filtered.map((skill, i) => (
            <li
              key={skill.slug}
              className="stagger-item"
              style={{ transitionDelay: `${Math.min(i * 50, 400)}ms` }}
            >
              <SkillCard skill={skill} locale={locale} dict={dict} />
            </li>
          ))}
        </ul>
      )}

      <p className="mt-10 text-center text-xs text-muted">
        {dict.skillsPage.catalogNote}
      </p>
    </div>
  );
}

function FilterSelect({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <label className="flex flex-col gap-1 text-xs font-medium text-muted">
      <span>{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="min-w-[9rem] rounded-full border border-line bg-bg px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink focus:ring-2 focus:ring-ink/10"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}
