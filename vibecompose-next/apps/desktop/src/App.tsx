import { useEffect, useState } from "react";
import {
  api,
  onChatgptLogin,
  onDictationError,
  onDictationResult,
  onSessionState,
  onSoundFeedback,
  type AccountStatus,
  type DictationResultEvent,
  type SessionSnapshot,
} from "./ipc";
import DictationPage from "./pages/Dictation";
import SkillsPage from "./pages/Skills";
import HistoryPage from "./pages/History";
import TerminologyPage from "./pages/Terminology";
import SettingsPage from "./pages/Settings";
import Onboarding from "./pages/Onboarding";
import {
  WaveformIcon,
  SquareGridIcon,
  ClockIcon,
  GearIcon,
  BookIcon,
} from "./icons";
import { applyPlatform, detectHost, initialPlatform } from "./platform";

type Page = "dictation" | "skills" | "terminology" | "history" | "settings";

const NAV: { id: Page; label: string; icon: React.ReactNode }[] = [
  { id: "dictation", label: "听写", icon: <WaveformIcon size={15} /> },
  { id: "skills", label: "Skill 库", icon: <SquareGridIcon size={15} /> },
  { id: "terminology", label: "术语", icon: <BookIcon size={15} /> },
  { id: "history", label: "历史记录", icon: <ClockIcon size={15} /> },
  { id: "settings", label: "设置", icon: <GearIcon size={15} /> },
];

const PAGE_TITLES: Record<Page, string> = {
  dictation: "听写",
  skills: "Skill 库",
  terminology: "术语",
  history: "历史记录",
  settings: "设置",
};

const HOST = detectHost();

export default function App() {
  const [page, setPage] = useState<Page>("dictation");
  const [session, setSession] = useState<SessionSnapshot>({
    phase: "idle",
    sessionId: null,
    elapsedMs: 0,
    level: 0,
  });
  const [lastResult, setLastResult] = useState<DictationResultEvent | null>(
    null,
  );
  const [lastError, setLastError] = useState<string | null>(null);
  const [onboarding, setOnboarding] = useState<boolean | null>(null);
  const [account, setAccount] = useState<AccountStatus | null>(null);

  useEffect(() => {
    applyPlatform(initialPlatform());
  }, []);

  useEffect(() => {
    void api.getOnboardingComplete().then((done) => setOnboarding(!done));
    void api.getAccountStatus().then(setAccount).catch(() => {});
  }, []);

  useEffect(() => {
    const unlisteners = [
      onSessionState(setSession),
      onDictationResult((r) => {
        setLastResult(r);
        setLastError(null);
      }),
      onDictationError((e) => setLastError(e.message)),
      onSoundFeedback((resource) => {
        const audio = new Audio(`/sounds/${resource}.wav`);
        audio.volume = 0.45;
        void audio.play().catch(() => {});
      }),
      onChatgptLogin((event) => {
        void api.getAccountStatus().then(setAccount);
        if (!event.ok && event.message) setLastError(event.message);
      }),
    ];
    return () => {
      unlisteners.forEach((p) => p.then((u) => u()));
    };
  }, []);

  const macHost = HOST === "macos";

  if (onboarding) {
    return (
      <Onboarding
        status={account}
        onDone={() => setOnboarding(false)}
      />
    );
  }

  return (
    <div className="app-shell">
      <aside
        data-tauri-drag-region={macHost || undefined}
        className="app-sidebar"
      >
        <nav className="nav-list">
          {NAV.map((item) => {
            const active = page === item.id;
            return (
              <button
                key={item.id}
                onClick={() => setPage(item.id)}
                className={`nav-item ${active ? "is-active" : ""}`}
              >
                <span
                  className={`nav-icon ${active ? "" : "text-ink-tertiary"}`}
                >
                  {item.icon}
                </span>
                {item.label}
              </button>
            );
          })}
        </nav>
        <SessionDot session={session} />
      </aside>

      <main className="app-panel">
        <header
          data-tauri-drag-region={macHost || undefined}
          className="app-header"
        >
          <h1 className="app-title">{PAGE_TITLES[page]}</h1>
        </header>
        <div className="app-content">
          <div key={page} className="page-enter app-content-inner">
            {page === "dictation" && (
              <DictationPage
                session={session}
                lastResult={lastResult}
                lastError={lastError}
              />
            )}
            {page === "skills" && <SkillsPage />}
            {page === "terminology" && <TerminologyPage />}
            {page === "history" && <HistoryPage />}
            {page === "settings" && <SettingsPage />}
          </div>
        </div>
      </main>
    </div>
  );
}

function SessionDot({ session }: { session: SessionSnapshot }) {
  const recording = session.phase === "recording";
  const processing = session.phase === "processing";
  const label = recording ? "正在录音" : processing ? "处理中" : "就绪";
  return (
    <div className="flex items-center gap-2 px-[10px] py-1.5 text-[11px] text-ink-tertiary">
      <span
        className={`h-[7px] w-[7px] rounded-full ${
          recording
            ? "animate-pulse bg-error"
            : processing
              ? "bg-amber"
              : "bg-success"
        }`}
      />
      {label}
    </div>
  );
}
