import { useEffect, useState } from "react";
import {
  api,
  onChatgptLogin,
  onLoginAvailability,
  type AccountStatus,
  type LoginAvailability,
} from "../ipc";

/**
 * First-run onboarding — the same five steps as the macOS app
 * (welcome / showcase / connect / permissions / practice), rendered in the
 * platform's own design language. The connect step renders the hosted
 * ChatGPT login when it is available and leads with the OpenAI-compatible
 * API-key fallback when it is not, so setup never dead-ends.
 */
const STEPS = [
  {
    id: "welcome",
    title: "欢迎使用 VibeCompose",
    body: "按下快捷键说话，转写、润色后的文字会送到当前光标。Windows 与 Linux 使用各自的系统界面，不模仿 macOS。",
  },
  {
    id: "showcase",
    title: "为什么是 VibeCompose",
    body: "21 个内置 Skill 把口语变成邮件、待办、代码注释等成品格式；术语表保证专有名词不被听错；历史记录和失败恢复让每一次听写都可追溯、可重试。",
  },
  {
    id: "connect",
    title: "连接转写账户",
    body: "用 ChatGPT 登录即可开始，无需自备 API Key。ChatGPT 托管会话依赖私有后端，并非稳定公开 API；OpenAI 兼容密钥是同样完整的替代路径。",
  },
  {
    id: "permissions",
    title: "粘贴权限",
    body: "自动粘贴需要系统允许应用向当前输入框发送按键。Windows 使用 UI Automation；Linux 在无法验证插入时会退回剪贴板，结果三态如实呈现。",
  },
  {
    id: "practice",
    title: "试一次听写",
    body: "默认快捷键是 F5：按一下开始，再按一下结束。Esc 取消当前会话。你可以随时在设置里改快捷键。",
  },
] as const;

const SHOWCASE_ITEMS = [
  { title: "Skill 库", detail: "口语 → 邮件、待办、消息等成品格式" },
  { title: "术语表", detail: "专有名词与纠错，转写前后都生效" },
  { title: "结果三态", detail: "已验证插入 / 已发送粘贴 / 仅剪贴板" },
  { title: "失败恢复", detail: "转写失败保留音频，可随时重试" },
] as const;

export default function Onboarding({
  status,
  availability: initialAvailability,
  onDone,
}: {
  status: AccountStatus | null;
  availability?: LoginAvailability | null;
  onDone: () => void;
}) {
  const [step, setStep] = useState(0);
  const [loginBusy, setLoginBusy] = useState(false);
  const [loginMessage, setLoginMessage] = useState<string | null>(null);
  const [availability, setAvailability] = useState<LoginAvailability | null>(
    initialAvailability ?? null,
  );
  const [apiKey, setApiKey] = useState("");
  const [keySaved, setKeySaved] = useState(false);
  const [keyError, setKeyError] = useState<string | null>(null);
  const current = STEPS[step];
  const last = step === STEPS.length - 1;

  useEffect(() => {
    if (!initialAvailability) {
      void api.getLoginAvailability().then(setAvailability).catch(() => {});
    }
    const unlisteners = [
      onLoginAvailability(setAvailability),
      onChatgptLogin((event) => {
        setLoginBusy(false);
        setLoginMessage(event.ok ? null : event.message);
      }),
    ];
    return () => {
      unlisteners.forEach((p) => p.then((u) => u()));
    };
  }, [initialAvailability]);

  const next = () => {
    if (last) {
      void api.completeOnboarding().then(onDone);
      return;
    }
    setStep((s) => s + 1);
  };

  const unavailable = availability?.status === "unavailable";
  const connected =
    !!status?.chatgptConnected || availability?.status === "connected";

  /** Never fail silently: without a Secret Service / keyring the OS
   *  credential store rejects the write, and the user needs to see why. */
  const saveKey = () => {
    if (!apiKey.trim()) return;
    setKeyError(null);
    void api
      .setOpenaiApiKey(apiKey.trim())
      .then(() => {
        setApiKey("");
        setKeySaved(true);
      })
      .catch((error) => setKeyError(String(error)));
  };

  return (
    <div className="onboarding-root">
      <div className="onboarding-card">
        <div className="text-[11px] font-semibold tracking-wide text-ink-tertiary uppercase">
          {step + 1} / {STEPS.length}
        </div>
        <h1 className="mt-3 text-[22px] font-semibold tracking-tight text-ink">
          {current.title}
        </h1>
        <p className="mt-3 text-[13px] leading-relaxed text-ink-secondary">
          {current.body}
        </p>

        {current.id === "showcase" && (
          <div className="mt-5 grid grid-cols-2 gap-2.5">
            {SHOWCASE_ITEMS.map((item) => (
              <div
                key={item.title}
                className="rounded-[8px] border border-hairline bg-canvas px-3 py-2.5"
              >
                <div className="text-[12px] font-semibold text-ink">
                  {item.title}
                </div>
                <div className="mt-0.5 text-[11px] leading-relaxed text-ink-tertiary">
                  {item.detail}
                </div>
              </div>
            ))}
          </div>
        )}

        {current.id === "connect" && (
          <div className="mt-5 space-y-3">
            {unavailable && (
              <div className="vc-banner vc-banner-warn">
                ChatGPT 登录在此平台暂不可用
                {availability?.reason === "platformPolicy"
                  ? "（此版本未启用托管登录）"
                  : availability?.reason === "credentialStoreUnavailable"
                    ? "（系统凭据存储不可用）"
                    : availability?.reason === "callbackBlocked"
                      ? "（本机回调端口被策略拦截）"
                      : availability?.reason === "backendRejected"
                        ? "（登录服务拒绝了此平台的请求）"
                        : ""}
                。填写 OpenAI 兼容 API Key 即可获得完整的听写与润色能力。
              </div>
            )}

            {!unavailable && (
              <div className="flex items-center gap-2">
                <button
                  className="vc-btn vc-btn-primary"
                  disabled={loginBusy || connected}
                  onClick={() => {
                    setLoginBusy(true);
                    setLoginMessage(null);
                    void api.startChatgptLogin().catch((err) => {
                      setLoginBusy(false);
                      setLoginMessage(String(err));
                    });
                  }}
                >
                  {connected
                    ? "已连接 ChatGPT"
                    : loginBusy
                      ? "等待浏览器…"
                      : "登录 ChatGPT"}
                </button>
                <span className="text-[11px] text-ink-tertiary">
                  可跳过，稍后再连
                </span>
              </div>
            )}
            {loginMessage && (
              <p className="text-[11px] leading-relaxed text-error">
                {loginMessage}
              </p>
            )}

            <div className="rounded-[8px] border border-hairline px-3 py-2.5">
              <div className="text-[12px] font-medium text-ink">
                {unavailable
                  ? "OpenAI 兼容 API Key（推荐路径）"
                  : "或使用 OpenAI 兼容 API Key"}
              </div>
              <div className="mt-0.5 text-[11px] text-ink-tertiary">
                {keySaved || status?.openaiKeyPresent
                  ? "已保存 — 可直接开始听写"
                  : "支持 api.openai.com 及任何 OpenAI 兼容端点"}
              </div>
              <div className="mt-2 flex items-center gap-2">
                <input
                  type="password"
                  placeholder="sk-..."
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  className="vc-input flex-1 placeholder-ink-tertiary"
                />
                <button
                  className={`vc-btn ${unavailable ? "vc-btn-primary" : "vc-btn-secondary"}`}
                  onClick={saveKey}
                >
                  保存
                </button>
              </div>
              {keyError && (
                <p className="mt-2 text-[11px] leading-relaxed text-error">
                  无法保存 API Key（系统凭据存储不可用）：{keyError}
                </p>
              )}
            </div>

            {unavailable && availability?.canRetry && (
              <button
                className="text-[12px] text-ink-tertiary hover:text-ink-secondary"
                disabled={loginBusy}
                onClick={() => {
                  setLoginBusy(true);
                  setLoginMessage(null);
                  void api.startChatgptLogin().catch((err) => {
                    setLoginBusy(false);
                    setLoginMessage(String(err));
                  });
                }}
              >
                仍要重试 ChatGPT 登录
              </button>
            )}
          </div>
        )}

        <div className="mt-8 flex items-center justify-between">
          <button
            className="text-[12px] text-ink-tertiary hover:text-ink-secondary"
            onClick={() => void api.completeOnboarding().then(onDone)}
          >
            跳过引导
          </button>
          <div className="flex gap-2">
            {step > 0 && (
              <button className="vc-btn vc-btn-secondary" onClick={() => setStep((s) => s - 1)}>
                上一步
              </button>
            )}
            <button className="vc-btn vc-btn-primary" onClick={next}>
              {last ? "开始使用" : "继续"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
