import { useState } from "react";
import { api, type AccountStatus } from "../ipc";

const STEPS = [
  {
    id: "welcome",
    title: "欢迎使用 VibeCompose",
    body: "按下快捷键说话，转写、润色后的文字会送到当前光标。Windows 与 Linux 使用各自的系统界面，不模仿 macOS。",
  },
  {
    id: "connect",
    title: "连接转写账户",
    body: "用 ChatGPT 登录即可开始，无需自备 API Key。也可以稍后在设置里填写 OpenAI 兼容密钥作为备用。",
  },
  {
    id: "permissions",
    title: "粘贴权限",
    body: "自动粘贴需要系统允许应用向当前输入框发送按键。macOS 需要辅助功能；Windows 使用 UI Automation；Linux 在无法验证插入时会退回剪贴板。",
  },
  {
    id: "practice",
    title: "试一次听写",
    body: "默认快捷键是 F5：按一下开始，再按一下结束。Esc 取消当前会话。你可以随时在设置里改快捷键。",
  },
] as const;

export default function Onboarding({
  status,
  onDone,
}: {
  status: AccountStatus | null;
  onDone: () => void;
}) {
  const [step, setStep] = useState(0);
  const [loginBusy, setLoginBusy] = useState(false);
  const current = STEPS[step];
  const last = step === STEPS.length - 1;

  const next = () => {
    if (last) {
      void api.completeOnboarding().then(onDone);
      return;
    }
    setStep((s) => s + 1);
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

        {current.id === "connect" && (
          <div className="mt-5 flex items-center gap-2">
            <button
              className="vc-btn vc-btn-primary"
              disabled={loginBusy || !!status?.chatgptConnected}
              onClick={() => {
                setLoginBusy(true);
                void api.startChatgptLogin().finally(() => setLoginBusy(false));
              }}
            >
              {status?.chatgptConnected
                ? "已连接 ChatGPT"
                : loginBusy
                  ? "等待浏览器…"
                  : "登录 ChatGPT"}
            </button>
            <span className="text-[11px] text-ink-tertiary">可跳过，稍后再连</span>
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
