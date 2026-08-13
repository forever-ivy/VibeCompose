import { useEffect, useState } from "react";
import {
  api,
  onChatgptLogin,
  type AccountStatus,
  type AppConfig,
  type StyleCapsule,
} from "../ipc";
import { CheckIcon, GlobeIcon } from "../icons";

/**
 * Settings — same information architecture as the macOS app's Settings
 * panes (General / Account / Dictation / Paste / AI Polish / Advanced /
 * Privacy), rendered in the platform's own design language.
 */
export default function SettingsPage() {
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [status, setStatus] = useState<AccountStatus | null>(null);
  const [apiKey, setApiKey] = useState("");
  const [saved, setSaved] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [historyCleared, setHistoryCleared] = useState(false);
  const [loginBusy, setLoginBusy] = useState(false);
  const [loginMessage, setLoginMessage] = useState<string | null>(null);
  const [styles, setStyles] = useState<StyleCapsule[]>([]);
  const [styleName, setStyleName] = useState("");
  const [styleSummary, setStyleSummary] = useState("");
  const [diagPath, setDiagPath] = useState<string | null>(null);
  const [appId, setAppId] = useState("");
  const [appName, setAppName] = useState("");
  const [appSkill, setAppSkill] = useState("");
  const [skillOptions, setSkillOptions] = useState<{ id: string; name: string }[]>(
    [],
  );

  const refreshStatus = () => api.getAccountStatus().then(setStatus).catch(() => {});
  const refreshStyles = () => api.listStyleCapsules().then(setStyles).catch(() => {});

  useEffect(() => {
    api
      .getConfig()
      .then(setConfig)
      .catch((error) => setLoadError(String(error)));
    refreshStatus();
    refreshStyles();
    api.listSkills().then((list) => {
      setSkillOptions(list.map((s) => ({ id: s.id, name: s.name })));
    }).catch(() => {});
    const unlisten = onChatgptLogin((event) => {
      setLoginBusy(false);
      setLoginMessage(event.ok ? "登录成功" : event.message);
      refreshStatus();
    });
    return () => {
      unlisten.then((u) => u());
    };
  }, []);

  const save = (next: AppConfig) => {
    setConfig(next);
    api.saveConfig(next).then(() => {
      setSaved(true);
      setTimeout(() => setSaved(false), 1500);
    });
  };

  if (loadError) {
    return (
      <div className="vc-banner vc-banner-warn">
        无法加载配置。请在桌面应用内打开设置页。
      </div>
    );
  }
  if (!config) {
    return <p className="text-[13px] text-ink-tertiary">加载中…</p>;
  }

  const patch = (fn: (c: AppConfig) => void) => {
    const next = structuredClone(config);
    fn(next);
    save(next);
  };

  const polish = config.transcription.textPolish;

  return (
    <div className="space-y-7">
      {/* 通用 — macOS: General */}
      <section>
        <SectionLabel>通用</SectionLabel>
        <div className="vc-card">
          <Row label="应用语言">
            <Select
              value={config.appLanguage ?? "system"}
              onChange={(v) =>
                patch((c) => (c.appLanguage = v === "system" ? null : v))
              }
              options={[
                { value: "system", label: "跟随系统" },
                { value: "zh-Hans", label: "简体中文" },
                { value: "en", label: "English" },
              ]}
            />
          </Row>
          <Divider />
          <Row label="默认 Skill" hint="在「Skill 库」中选择并设为默认">
            <span className="text-[13px] text-ink-secondary">
              {defaultSkillLabel(config)}
            </span>
          </Row>
          <Divider />
          <Row label="听写快捷键" hint="按下开始，再按一次结束并转写">
            <TextInput
              width="w-36"
              align="text-center"
              value={formatHotkey(config.transcription.dictationHotkey)}
              onChange={(v) =>
                patch((c) => {
                  const parsed = parseHotkey(v);
                  if (parsed) c.transcription.dictationHotkey = parsed;
                })
              }
            />
          </Row>
          <Divider />
          <Row label="Skill 切换器" hint="留空表示关闭">
            <TextInput
              width="w-36"
              align="text-center"
              placeholder="Ctrl+Alt+S"
              value={formatHotkey(config.skillSwitcherHotkey)}
              onChange={(v) =>
                patch((c) => (c.skillSwitcherHotkey = parseHotkey(v)))
              }
            />
          </Row>
          <Divider />
          <Row label="结果预览" hint="重新打开上次听写预览">
            <TextInput
              width="w-36"
              align="text-center"
              placeholder="Ctrl+Alt+P"
              value={formatHotkey(config.resultPreviewHotkey)}
              onChange={(v) =>
                patch((c) => (c.resultPreviewHotkey = parseHotkey(v)))
              }
            />
          </Row>
        </div>
      </section>

      {/* 账户与权限 — macOS: Account & Permissions */}
      <section>
        <SectionLabel>账户与权限</SectionLabel>
        <div className="vc-card">
          <div className="flex items-stretch px-4 py-3">
            <StatusTile
              title="ChatGPT"
              ok={!!status?.chatgptConnected}
              okText="已连接"
              badText="未登录"
            />
            <TileDivider />
            <StatusTile
              title="OpenAI Key"
              ok={!!status?.openaiKeyPresent}
              okText="已保存"
              badText="未配置"
            />
            <TileDivider />
            <StatusTile
              title="辅助功能"
              ok={!status?.accessibilityPermissionMissing}
              okText="就绪"
              badText="需要授权"
            />
          </div>
          <Divider />
          <div className="flex items-center gap-3.5 px-4 py-3.5">
            <span className="grid h-[34px] w-[34px] place-items-center rounded-[9px] bg-[#10a37f] text-white">
              <GlobeIcon size={17} />
            </span>
            <div className="min-w-0 flex-1">
              <div className="text-[13px] font-semibold text-ink">ChatGPT</div>
              <div className="text-[11px] text-ink-tertiary">
                {status?.chatgptConnected
                  ? "已连接 — 托管转写与润色已启用"
                  : loginBusy
                    ? "已打开浏览器，完成登录后会自动回来"
                    : loginMessage
                      ? loginMessage
                      : "使用 ChatGPT 账户登录，无需 API Key"}
              </div>
            </div>
            {status?.chatgptConnected ? (
              <SecondaryButton
                onClick={() => api.disconnectChatgpt().then(refreshStatus)}
              >
                断开
              </SecondaryButton>
            ) : loginBusy ? (
              <SecondaryButton
                onClick={() => {
                  void api.cancelChatgptLogin();
                  setLoginBusy(false);
                }}
              >
                取消登录
              </SecondaryButton>
            ) : (
              <PrimaryButton
                onClick={() => {
                  setLoginBusy(true);
                  setLoginMessage(null);
                  void api.startChatgptLogin().catch((err) => {
                    setLoginBusy(false);
                    setLoginMessage(String(err));
                  });
                }}
              >
                登录
              </PrimaryButton>
            )}
          </div>
          <Divider />
          <div className="flex items-center justify-between gap-6 px-4 py-[9px]">
            <div className="min-w-0">
              <div className="text-[13px] text-ink">OpenAI API Key</div>
              <div className="mt-[1px] text-[11px] text-ink-tertiary">
                {status?.openaiKeyPresent
                  ? "已保存 — 清空并点保存可移除"
                  : "可选，作为备用转写来源"}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <TextInput
                type="password"
                placeholder="sk-..."
                width="w-52"
                value={apiKey}
                onChange={setApiKey}
              />
              <SecondaryButton
                onClick={() =>
                  api.setOpenaiApiKey(apiKey).then(() => {
                    setApiKey("");
                    refreshStatus();
                  })
                }
              >
                保存
              </SecondaryButton>
            </div>
          </div>
        </div>
      </section>

      {/* 听写 / ASR — macOS: Dictation / ASR */}
      <section>
        <SectionLabel>听写</SectionLabel>
        <div className="vc-card">
          <Row label="提示音" hint="录音开始与结束时播放">
            <Toggle
              checked={config.transcription.feedbackSoundsEnabled}
              onChange={(v) =>
                patch((c) => (c.transcription.feedbackSoundsEnabled = v))
              }
            />
          </Row>
          <Divider />
          <Row label="语音清理" hint="自动去除口头禅、口误与重复起头">
            <Toggle
              checked={config.transcription.speechCleanupEnabled}
              onChange={(v) =>
                patch((c) => (c.transcription.speechCleanupEnabled = v))
              }
            />
          </Row>
          <Divider />
          <Row label="标点">
            <Select
              value={config.transcription.punctuationPreference}
              onChange={(v) =>
                patch((c) => (c.transcription.punctuationPreference = v))
              }
              options={[
                { value: "automatic", label: "自动" },
                { value: "fullWidth", label: "全角" },
                { value: "halfWidth", label: "半角" },
                { value: "preserve", label: "保留原样" },
              ]}
            />
          </Row>
        </div>
      </section>

      <section>
        <SectionLabel>每应用 Skill 规则</SectionLabel>
        <div className="vc-card">
          {(config.transcription.skills.applicationRules ?? []).map((rule) => (
            <div
              key={rule.id}
              className="flex items-center justify-between gap-3 border-b border-hairline px-4 py-2.5"
            >
              <div className="min-w-0">
                <div className="truncate text-[13px] text-ink">
                  {rule.applicationName || rule.applicationId}
                </div>
                <div className="text-[11px] text-ink-tertiary">
                  {rule.applicationId} · {rule.skillId.split(".").pop()}
                </div>
              </div>
              <button
                className="vc-btn vc-btn-secondary"
                onClick={() =>
                  patch((c) => {
                    c.transcription.skills.applicationRules =
                      c.transcription.skills.applicationRules.filter(
                        (r) => r.id !== rule.id,
                      );
                  })
                }
              >
                删除
              </button>
            </div>
          ))}
          <div className="flex flex-wrap items-center gap-2 px-4 py-3">
            <TextInput
              width="w-36"
              placeholder="应用 ID"
              value={appId}
              onChange={setAppId}
            />
            <TextInput
              width="w-28"
              placeholder="显示名"
              value={appName}
              onChange={setAppName}
            />
            <Select
              value={appSkill}
              onChange={setAppSkill}
              options={[
                { value: "", label: "选择 Skill" },
                ...skillOptions.map((s) => ({ value: s.id, label: s.name })),
              ]}
            />
            <SecondaryButton
              onClick={() => {
                if (!appId.trim() || !appSkill) return;
                patch((c) => {
                  c.transcription.skills.applicationRules.push({
                    id: crypto.randomUUID(),
                    applicationId: appId.trim(),
                    applicationName: appName.trim(),
                    skillId: appSkill,
                    isEnabled: true,
                  });
                });
                setAppId("");
                setAppName("");
              }}
            >
              添加
            </SecondaryButton>
          </div>
        </div>
      </section>

      {/* 粘贴与剪贴板 — macOS: Paste & Clipboard */}
      <section>
        <SectionLabel>粘贴与剪贴板</SectionLabel>
        <div className="vc-card">
          <Row label="安全时跳过结果预览" hint="低风险 Skill 验证通过后直接粘贴">
            <Toggle
              checked={config.injection.skipResultPreviewWhenSafe}
              onChange={(v) =>
                patch((c) => (c.injection.skipResultPreviewWhenSafe = v))
              }
            />
          </Row>
          <Divider />
          <Row label="验证插入后恢复剪贴板">
            <Toggle
              checked={config.injection.preserveClipboard}
              onChange={(v) => patch((c) => (c.injection.preserveClipboard = v))}
            />
          </Row>
          <Divider />
          <Row label="恢复延迟" hint="粘贴后恢复剪贴板的等待毫秒数">
            <NumberInput
              value={config.injection.restoreDelayMilliseconds}
              min={0}
              max={5000}
              onChange={(v) =>
                patch((c) => (c.injection.restoreDelayMilliseconds = v))
              }
            />
          </Row>
        </div>
      </section>

      {/* AI 润色 — macOS: AI Polish */}
      <section>
        <SectionLabel>AI 润色</SectionLabel>
        <div className="vc-card">
          <Row label="模式">
            <Select
              value={polish.mode}
              onChange={(v) =>
                patch(
                  (c) =>
                    (c.transcription.textPolish.mode =
                      v as AppConfig["transcription"]["textPolish"]["mode"]),
                )
              }
              options={[
                { value: "automaticWhenKeyAvailable", label: "自动" },
                { value: "always", label: "总是润色" },
                { value: "disabled", label: "关闭" },
              ]}
            />
          </Row>
          <Divider />
          <Row label="润色模型" hint="ChatGPT 托管会话使用的模型">
            <TextInput
              width="w-44"
              value={polish.chatGPTResponseModel}
              onChange={(v) =>
                patch((c) => (c.transcription.textPolish.chatGPTResponseModel = v))
              }
            />
          </Row>
          <Divider />
          <Row label="显示成本估算">
            <Toggle
              checked={polish.showCostEstimates}
              onChange={(v) =>
                patch((c) => (c.transcription.textPolish.showCostEstimates = v))
              }
            />
          </Row>
        </div>
      </section>

      <section>
        <SectionLabel>写作风格</SectionLabel>
        <div className="vc-card">
          <Row label="启用风格胶囊" hint="仅注入到声明了 styleCapsule 能力的 Skill">
            <Toggle
              checked={config.styleCapsules?.enabled ?? true}
              onChange={(v) =>
                patch((c) => {
                  c.styleCapsules = c.styleCapsules ?? {
                    enabled: true,
                    defaultCapsuleID: null,
                    skillAssignments: [],
                  };
                  c.styleCapsules.enabled = v;
                })
              }
            />
          </Row>
          <Divider />
          <Row label="默认风格">
            <Select
              value={config.styleCapsules?.defaultCapsuleID ?? ""}
              onChange={(v) =>
                patch((c) => {
                  c.styleCapsules = c.styleCapsules ?? {
                    enabled: true,
                    defaultCapsuleID: null,
                    skillAssignments: [],
                  };
                  c.styleCapsules.defaultCapsuleID = v || null;
                })
              }
              options={[
                { value: "", label: "无" },
                ...styles.map((s) => ({ value: s.id, label: s.name })),
              ]}
            />
          </Row>
          {styles.map((capsule) => (
            <div
              key={capsule.id}
              className="flex items-start justify-between gap-3 border-t border-hairline px-4 py-2.5"
            >
              <div className="min-w-0">
                <div className="text-[13px] text-ink">
                  {capsule.name}
                  {capsule.isBuiltIn && (
                    <span className="ml-1.5 text-[10px] text-ink-tertiary">内置</span>
                  )}
                </div>
                <div className="line-clamp-2 text-[11px] text-ink-tertiary">
                  {capsule.summary}
                </div>
              </div>
              {!capsule.isBuiltIn && (
                <button
                  className="vc-btn vc-btn-danger"
                  onClick={() =>
                    api.deleteStyleCapsule(capsule.id).then(refreshStyles)
                  }
                >
                  删除
                </button>
              )}
            </div>
          ))}
          <div className="space-y-2 border-t border-hairline px-4 py-3">
            <TextInput
              width="w-full"
              placeholder="自定义风格名称"
              value={styleName}
              onChange={setStyleName}
            />
            <textarea
              className="vc-input min-h-[72px] w-full resize-none"
              placeholder="风格说明，例如：专业、克制、完整句子"
              value={styleSummary}
              onChange={(e) => setStyleSummary(e.target.value)}
            />
            <SecondaryButton
              onClick={() => {
                if (!styleName.trim() || !styleSummary.trim()) return;
                api
                  .saveStyleCapsule({
                    name: styleName.trim(),
                    summary: styleSummary.trim(),
                    examples: [],
                  })
                  .then(() => {
                    setStyleName("");
                    setStyleSummary("");
                    refreshStyles();
                  });
              }}
            >
              添加自定义风格
            </SecondaryButton>
          </div>
        </div>
      </section>

      {/* 高级 · 自有 API — macOS: Advanced / Own API */}
      <section>
        <SectionLabel>高级 · 自有 API</SectionLabel>
        <div className="vc-card">
          <Row label="转写端点" hint="OpenAI 兼容 /audio/transcriptions">
            <TextInput
              width="w-72"
              value={config.transcription.openAITranscriptionURL}
              onChange={(v) =>
                patch((c) => (c.transcription.openAITranscriptionURL = v))
              }
            />
          </Row>
          <Divider />
          <Row label="转写模型">
            <TextInput
              width="w-44"
              value={config.transcription.openAIModel}
              onChange={(v) => patch((c) => (c.transcription.openAIModel = v))}
            />
          </Row>
          <Divider />
          <Row label="润色端点" hint="OpenAI 兼容 /chat/completions">
            <TextInput
              width="w-72"
              value={polish.openAICompatibleURL}
              onChange={(v) =>
                patch((c) => (c.transcription.textPolish.openAICompatibleURL = v))
              }
            />
          </Row>
          <Divider />
          <Row label="润色模型（自有 API）">
            <TextInput
              width="w-44"
              value={polish.openAICompatibleModel}
              onChange={(v) =>
                patch(
                  (c) => (c.transcription.textPolish.openAICompatibleModel = v),
                )
              }
            />
          </Row>
        </div>
      </section>

      {/* 隐私与数据 — macOS: Context & Privacy / Local Data */}
      <section>
        <SectionLabel>隐私与数据</SectionLabel>
        <div className="vc-card">
          <Row label="保存历史记录" hint="仅存储在本机，可逐条删除">
            <Toggle
              checked={config.privacy.historyEnabled}
              onChange={(v) => patch((c) => (c.privacy.historyEnabled = v))}
            />
          </Row>
          <Divider />
          <Row label="保存原始转写" hint="除最终文本外，同时保留润色前的原始转写">
            <Toggle
              checked={config.privacy.storeRawTranscripts}
              onChange={(v) => patch((c) => (c.privacy.storeRawTranscripts = v))}
            />
          </Row>
          <Divider />
          <Row label="历史保留天数">
            <NumberInput
              value={config.privacy.historyRetentionDays}
              min={1}
              max={365}
              onChange={(v) => patch((c) => (c.privacy.historyRetentionDays = v))}
            />
          </Row>
          <Divider />
          <Row label="历史条数上限">
            <NumberInput
              value={config.privacy.historyRecordLimit}
              min={10}
              max={10000}
              onChange={(v) => patch((c) => (c.privacy.historyRecordLimit = v))}
            />
          </Row>
          <Divider />
          <Row label="排除敏感应用" hint="密码管理器等应用不保存历史与恢复音频">
            <Toggle
              checked={config.privacy.excludeSensitiveApps}
              onChange={(v) => patch((c) => (c.privacy.excludeSensitiveApps = v))}
            />
          </Row>
          <Divider />
          <Row label="失败音频恢复" hint="转写失败时保留 WAV，可在历史页重试">
            <Toggle
              checked={config.privacy.failedAudioRecoveryEnabled ?? true}
              onChange={(v) =>
                patch((c) => (c.privacy.failedAudioRecoveryEnabled = v))
              }
            />
          </Row>
          <Divider />
          <Row label="恢复保留小时">
            <NumberInput
              value={config.privacy.failedAudioRetentionHours ?? 24}
              min={1}
              max={168}
              onChange={(v) =>
                patch((c) => (c.privacy.failedAudioRetentionHours = v))
              }
            />
          </Row>
          <Divider />
          <Row label="恢复条数上限">
            <NumberInput
              value={config.privacy.failedAudioRecordLimit ?? 10}
              min={1}
              max={100}
              onChange={(v) =>
                patch((c) => (c.privacy.failedAudioRecordLimit = v))
              }
            />
          </Row>
          <Divider />
          <Row label="允许导出诊断" hint="不含转写正文、密钥与 token">
            <Toggle
              checked={config.privacy.diagnosticsEnabled ?? true}
              onChange={(v) => patch((c) => (c.privacy.diagnosticsEnabled = v))}
            />
          </Row>
          <Divider />
          <Row label="导出诊断" hint={diagPath ?? "写入本机应用数据目录"}>
            <SecondaryButton
              onClick={() =>
                api.exportDiagnostics().then((path) => setDiagPath(path))
              }
            >
              导出
            </SecondaryButton>
          </Row>
          <Divider />
          <Row label="重新显示引导" hint="下次打开主窗口时从欢迎页开始">
            <SecondaryButton onClick={() => api.resetOnboarding()}>
              重置
            </SecondaryButton>
          </Row>
          <Divider />
          <Row label="清空历史记录" hint="删除本机全部听写历史，不可恢复">
            {historyCleared ? (
              <span className="flex items-center gap-1 text-[12px] font-medium text-success">
                <CheckIcon size={13} /> 已清空
              </span>
            ) : (
              <DangerButton
                onClick={() =>
                  api.clearHistory().then(() => {
                    setHistoryCleared(true);
                    setTimeout(() => setHistoryCleared(false), 2000);
                  })
                }
              >
                清空历史
              </DangerButton>
            )}
          </Row>
        </div>
      </section>

      <div className="flex items-center justify-between pb-4">
        <span className="text-[11px] text-ink-tertiary">
          配置保存在本机应用数据目录
        </span>
        <span
          className={`text-[11px] font-medium text-success transition-opacity ${
            saved ? "opacity-100" : "opacity-0"
          }`}
        >
          已保存
        </span>
      </div>
    </div>
  );
}

function defaultSkillLabel(config: AppConfig): string {
  const id = config.transcription.skills.defaultSkillId;
  if (!id) return "Direct";
  const tail = id.split(".").pop() ?? id;
  return tail
    .split("-")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

function formatHotkey(binding: AppConfig["transcription"]["dictationHotkey"] | null): string {
  if (!binding) return "";
  return [...binding.modifiers, binding.key].filter(Boolean).join("+");
}

function parseHotkey(raw: string): AppConfig["transcription"]["dictationHotkey"] | null {
  const parts = raw
    .split(/[+\s]+/)
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length === 0) return null;
  const key = parts.pop() as string;
  const modifiers = parts.map((part) => {
    const lower = part.toLowerCase();
    if (lower === "control" || lower === "ctl") return "ctrl";
    if (lower === "command" || lower === "meta" || lower === "super") return "cmd";
    if (lower === "option" || lower === "opt") return "alt";
    return lower;
  });
  return { key, modifiers };
}

function StatusTile({
  title,
  ok,
  okText,
  badText,
}: {
  title: string;
  ok: boolean;
  okText: string;
  badText: string;
}) {
  return (
    <div className="flex flex-1 flex-col items-start gap-0.5 px-1">
      <span className="text-[11px] text-ink-tertiary">{title}</span>
      <span
        className={`flex items-center gap-1 text-[12px] font-medium ${
          ok ? "text-success" : "text-amber"
        }`}
      >
        <span
          className={`h-[6px] w-[6px] rounded-full ${ok ? "bg-success" : "bg-amber"}`}
        />
        {ok ? okText : badText}
      </span>
    </div>
  );
}

function TileDivider() {
  return <div className="mx-3 w-px self-stretch bg-hairline" />;
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <h3 className="mb-1.5 pl-3 text-[11px] font-semibold tracking-[0.04em] text-ink-tertiary uppercase">
      {children}
    </h3>
  );
}

function Divider() {
  return <div className="ml-4 border-t border-hairline" />;
}

function Row({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-6 px-4 py-[9px]">
      <div className="min-w-0">
        <div className="text-[13px] text-ink">{label}</div>
        {hint && (
          <div className="mt-[1px] text-[11px] text-ink-tertiary">{hint}</div>
        )}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  );
}

function TextInput({
  value,
  onChange,
  placeholder,
  type = "text",
  width = "w-56",
  align = "",
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
  width?: string;
  align?: string;
}) {
  return (
    <input
      type={type}
      value={value}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className={`vc-input ${width} ${align} placeholder-ink-tertiary`}
    />
  );
}

function NumberInput({
  value,
  onChange,
  min,
  max,
}: {
  value: number;
  onChange: (value: number) => void;
  min: number;
  max: number;
}) {
  return (
    <input
      type="number"
      value={value}
      min={min}
      max={max}
      onChange={(e) => {
        const parsed = Number(e.target.value);
        if (Number.isFinite(parsed)) {
          onChange(Math.min(max, Math.max(min, Math.round(parsed))));
        }
      }}
      className="vc-input w-24 text-right"
    />
  );
}

function Select({
  value,
  onChange,
  options,
}: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="vc-select"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

function Toggle({
  checked,
  onChange,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`vc-toggle ${checked ? "is-on" : ""}`}
    >
      <span className="vc-toggle-thumb" />
    </button>
  );
}

function PrimaryButton({
  onClick,
  children,
}: {
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button onClick={onClick} className="vc-btn vc-btn-primary">
      {children}
    </button>
  );
}

function SecondaryButton({
  onClick,
  children,
}: {
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button onClick={onClick} className="vc-btn vc-btn-secondary">
      {children}
    </button>
  );
}

function DangerButton({
  onClick,
  children,
}: {
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button onClick={onClick} className="vc-btn vc-btn-danger">
      {children}
    </button>
  );
}
