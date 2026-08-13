// IPC types mirroring the Rust command payloads, plus thin invoke wrappers.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export type SessionPhase = "idle" | "recording" | "processing";

export interface SessionSnapshot {
  phase: SessionPhase;
  sessionId: number | null;
  elapsedMs: number;
  level: number;
}

export interface DictationResultEvent {
  sessionId: number;
  outcome: "inserted_verified" | "paste_dispatched" | "clipboard";
  finalText: string;
  skillId: string;
  skillName: string;
  appName: string;
  polishAttempted: boolean;
  polishError: string | null;
  durationMs: number;
}

export interface DictationErrorEvent {
  sessionId: number | null;
  message: string;
  retryable: boolean;
}

export interface SkillSummary {
  id: string;
  version: string;
  name: string;
  summary: string | null;
  useCase: string | null;
  outputFormat: string;
  delivery: string;
  risk: "low" | "medium" | "high";
  enabled: boolean;
  isDefault: boolean;
}

export interface HistoryRecord {
  id: string;
  timestamp: string;
  outcome: string;
  finalText: string;
  rawText?: string | null;
  appName: string;
  appId: string;
  skillId: string;
  skillName: string;
  skillVersion: string;
  textPolishProvider?: string | null;
}

export interface AccountStatus {
  chatgptConnected: boolean;
  openaiKeyPresent: boolean;
  accessibilityPermissionMissing: boolean;
}

export interface TerminologyEntry {
  id: string;
  type: "term" | "correction";
  original: string;
  replacement: string | null;
  aliases: string[];
  isEnabled: boolean;
  source: string;
  usageCount: number;
  createdAt: string;
}

export interface AppSkillRule {
  id: string;
  applicationId: string;
  applicationName: string;
  skillId: string;
  isEnabled: boolean;
}

export interface HotkeyBinding {
  key: string;
  modifiers: string[];
}

export interface StyleCapsule {
  id: string;
  name: string;
  summary: string;
  examples: string[];
  createdAt: string;
  updatedAt: string;
  isBuiltIn: boolean;
}

export interface PendingPreview {
  sessionId: number;
  finalText: string;
  rawText: string;
  skillId: string;
  skillName: string;
  appName: string;
  appId: string;
  polishAttempted: boolean;
  polishError: string | null;
  durationMs: number;
  copyOnly: boolean;
}

export interface RecoveryRecord {
  id: string;
  timestamp: string;
  audioDurationMs: number;
  asrText?: string | null;
  polishText?: string | null;
  appName?: string | null;
  appBundleIdentifier?: string | null;
  outcome: string;
  errorMessage?: string | null;
}

export interface ChatGptLoginEvent {
  ok: boolean;
  message: string | null;
}

export interface AppConfig {
  appLanguage: string | null;
  skillSwitcherHotkey: HotkeyBinding | null;
  resultPreviewHotkey: HotkeyBinding | null;
  transcription: {
    provider: "chatGptManagedAuth" | "openAiCompatible";
    dictationHotkey: HotkeyBinding;
    maxDurationSeconds: number;
    sampleRateHz: number;
    punctuationPreference: string;
    speechCleanupEnabled: boolean;
    feedbackSoundsEnabled: boolean;
    hintTerms: string[];
    openAIFallbackEnabled: boolean;
    openAIModel: string;
    openAITranscriptionURL: string;
    skills: {
      defaultSkillId: string;
      enabledSkillIds: string[];
      applicationRules: AppSkillRule[];
    };
    terminology: { enabled: boolean; entries: TerminologyEntry[] };
    textPolish: {
      mode: "automaticWhenKeyAvailable" | "disabled" | "always";
      chatGptAuthEnabled: boolean;
      openAiCompatibleEnabled: boolean;
      openAiFallbackEnabled: boolean;
      chatGPTResponseModel: string;
      openAICompatibleURL: string;
      openAICompatibleModel: string;
      temperature: number;
      maxOutputTokens: number;
      glossaryBudgetCharacters: number;
      showCostEstimates: boolean;
    };
  };
  injection: {
    preserveClipboard: boolean;
    restoreDelayMilliseconds: number;
    skipResultPreviewWhenSafe: boolean;
  };
  privacy: {
    historyEnabled: boolean;
    historyRecordLimit: number;
    historyRetentionDays: number;
    storeRawTranscripts: boolean;
    failedAudioRecoveryEnabled: boolean;
    failedAudioRetentionHours: number;
    failedAudioRecordLimit: number;
    excludeSensitiveApps: boolean;
    additionalSensitiveAppIds: string[];
    diagnosticsEnabled: boolean;
  };
  styleCapsules: {
    enabled: boolean;
    defaultCapsuleID: string | null;
    skillAssignments: { skillID: string; capsuleID: string }[];
  };
}

export const api = {
  getConfig: () => invoke<AppConfig>("get_config"),
  saveConfig: (config: AppConfig) => invoke<void>("save_config", { config }),
  listSkills: () => invoke<SkillSummary[]>("list_skills"),
  getHistory: () => invoke<HistoryRecord[]>("get_history"),
  deleteHistoryRecord: (id: string) => invoke<void>("delete_history_record", { id }),
  clearHistory: () => invoke<void>("clear_history"),
  setOpenaiApiKey: (key: string) => invoke<void>("set_openai_api_key", { key }),
  getAccountStatus: () => invoke<AccountStatus>("get_account_status"),
  startChatgptLogin: () => invoke<string>("start_chatgpt_login"),
  cancelChatgptLogin: () => invoke<void>("cancel_chatgpt_login"),
  disconnectChatgpt: () => invoke<void>("disconnect_chatgpt"),
  toggleDictation: () => invoke<void>("toggle_dictation"),
  cancelDictation: () => invoke<void>("cancel_dictation"),
  getPendingPreview: () => invoke<PendingPreview | null>("get_pending_preview"),
  confirmPreview: (text?: string) =>
    invoke<void>("confirm_preview", { text: text ?? null }),
  copyPreview: () => invoke<void>("copy_preview"),
  dismissPreview: () => invoke<void>("dismiss_preview"),
  openResultPreview: () => invoke<void>("open_result_preview"),
  openSkillSwitcher: () => invoke<void>("open_skill_switcher"),
  hideOverlay: (label: string) => invoke<void>("hide_overlay", { label }),
  setDefaultSkill: (id: string) => invoke<void>("set_default_skill", { id }),
  reprocessPreview: (skillId: string, sourceText: string) =>
    invoke<PendingPreview>("reprocess_preview", { args: { skillId, sourceText } }),
  addTerminologyEntry: (draft: {
    entryType: "term" | "correction";
    original: string;
    replacement: string;
    aliases: string;
  }) => invoke<void>("add_terminology_entry", { draft }),
  openQuickAdd: () => invoke<void>("open_quick_add"),
  listRecovery: () => invoke<RecoveryRecord[]>("list_recovery"),
  deleteRecovery: (id: string) => invoke<void>("delete_recovery", { id }),
  retryRecovery: (id: string) => invoke<void>("retry_recovery", { id }),
  listStyleCapsules: () => invoke<StyleCapsule[]>("list_style_capsules"),
  saveStyleCapsule: (draft: {
    id?: string | null;
    name: string;
    summary: string;
    examples: string[];
  }) => invoke<StyleCapsule>("save_style_capsule", { draft }),
  deleteStyleCapsule: (id: string) => invoke<void>("delete_style_capsule", { id }),
  summarizeStyle: (samples: string) => invoke<string>("summarize_style", { samples }),
  getOnboardingComplete: () => invoke<boolean>("get_onboarding_complete"),
  completeOnboarding: () => invoke<void>("complete_onboarding"),
  resetOnboarding: () => invoke<void>("reset_onboarding"),
  exportDiagnostics: () => invoke<string>("export_diagnostics"),
};

export function onSessionState(
  handler: (snapshot: SessionSnapshot) => void,
): Promise<UnlistenFn> {
  return listen<SessionSnapshot>("dictation-state", (event) => handler(event.payload));
}

export function onDictationResult(
  handler: (result: DictationResultEvent) => void,
): Promise<UnlistenFn> {
  return listen<DictationResultEvent>("dictation-result", (event) => handler(event.payload));
}

export function onDictationError(
  handler: (error: DictationErrorEvent) => void,
): Promise<UnlistenFn> {
  return listen<DictationErrorEvent>("dictation-error", (event) => handler(event.payload));
}

export function onDictationPreview(
  handler: (preview: PendingPreview) => void,
): Promise<UnlistenFn> {
  return listen<PendingPreview>("dictation-preview", (event) => handler(event.payload));
}

export function onChatgptLogin(
  handler: (event: ChatGptLoginEvent) => void,
): Promise<UnlistenFn> {
  return listen<ChatGptLoginEvent>("chatgpt-login", (event) => handler(event.payload));
}

export function onSoundFeedback(
  handler: (resource: string) => void,
): Promise<UnlistenFn> {
  return listen<string>("sound-feedback", (event) => handler(event.payload));
}
