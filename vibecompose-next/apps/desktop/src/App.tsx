import { useEffect, useState } from "react";
import {
  api,
  onChatgptLogin,
  onDictationError,
  onDictationResult,
  onLoginAvailability,
  onSessionState,
  onSoundFeedback,
  type AccountStatus,
  type DictationResultEvent,
  type LoginAvailability,
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
  const [availability, setAvailability] = useState<LoginAvailability | null>(
    null,
  );

  useEffect(() => {
    applyPlatform(initialPlatform());
  }, []);

  useEffect(() => {
    void api.getOnboardingComplete().then((done) => setOnboarding(!done));
    void api.getAccountStatus().then(setAccount).catch(() => {});
    void api.getLoginAvailability().then(setAvailability).catch(() => {});
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
      onLoginAvailability((next) => {
        setAvailability(next);
        void api.getAccountStatus().then(setAccount).catch(() => {});
      }),
    ];
    return () => {
      unlisteners.forEach((p) => p.then((u) => u()));
    };
  }, []);

  // macOS parity: ESC cancels the active session. A global shortcut would
  // swallow ESC system-wide, so cancel-on-ESC applies whenever a VibeCompose
  // window has focus; outside the app the tray and HUD close button cancel.
  useEffect(() => {
    const active = session.phase === "recording" || session.phase === "processing";
    if (!active) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        void api.cancelDictation();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [session.phase]);

  const macHost = HOST === "macos";
  // Linux draws Adwaita-style client-side decorations (the window is
  // undecorated there, see tauri.linux.conf.json); Windows keeps the
  // system title bar, so only drag regions + controls differ per host.
  const linuxHost = HOST === "linux";

  return (
    <div className="app-shell">
      <aside
        data-tauri-drag-region={macHost || linuxHost || undefined}
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
          data-tauri-drag-region={macHost || linuxHost || undefined}
          className="app-header"
        >
          <h1 className="app-title">{PAGE_TITLES[page]}</h1>
          {linuxHost && <CsdWindowControls />}
        </header>
        <div className="app-content">
          <div key={page} className="page-enter app-content-inner">
            {page === "dictation" && (
              <DictationPage
                session={session}
                lastResult={lastResult}
                lastError={lastError}
                availability={availability}
                onOpenSettings={() => setPage("settings")}
              />
            )}
            {page === "skills" && <SkillsPage />}
            {page === "terminology" && <TerminologyPage />}
            {page === "history" && <HistoryPage />}
            {page === "settings" && <SettingsPage />}
          </div>
        </div>
      </main>

      {onboarding && (
        <Onboarding
          status={account}
          availability={availability}
          onDone={() => setOnboarding(false)}
        />
      )}
    </div>
  );
}

/** GNOME-style window controls for the undecorated Linux main window
 *  (minimize / maximize / close, right-aligned like Adwaita header bars). */
function CsdWindowControls() {
  const call = (action: "minimize" | "toggleMaximize" | "close") => {
    void import("@tauri-apps/api/window").then(({ getCurrentWindow }) => {
      const win = getCurrentWindow();
      void win[action]();
    });
  };
  return (
    <div className="csd-controls">
      <button
        className="csd-btn"
        aria-label="最小化"
        onClick={() => call("minimize")}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
          <path d="M3 9.5h8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
      </button>
      <button
        className="csd-btn"
        aria-label="最大化"
        onClick={() => call("toggleMaximize")}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
          <rect x="3.5" y="3.5" width="7" height="7" rx="1" fill="none" stroke="currentColor" strokeWidth="1.4" />
        </svg>
      </button>
      <button
        className="csd-btn"
        aria-label="关闭窗口"
        onClick={() => call("close")}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
          <path d="M4 4l6 6M10 4l-6 6" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
      </button>
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
