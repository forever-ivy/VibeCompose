import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import HudOverlay from "./overlays/Hud";
import PreviewOverlay from "./overlays/Preview";
import SwitcherOverlay from "./overlays/Switcher";
import QuickAddOverlay from "./overlays/QuickAdd";
import { applyPlatform, initialPlatform } from "./platform";
import "./index.css";

applyPlatform(initialPlatform());

async function overlayLabel(): Promise<string> {
  try {
    const { getCurrentWindow } = await import("@tauri-apps/api/window");
    return getCurrentWindow().label;
  } catch {
    return "main";
  }
}

function OverlayRoot({ label }: { label: string }) {
  if (label === "hud") return <HudOverlay />;
  if (label === "preview") return <PreviewOverlay />;
  if (label === "skill-switcher") return <SwitcherOverlay />;
  if (label === "quick-add") return <QuickAddOverlay />;
  return <App />;
}

overlayLabel().then((label) => {
  document.documentElement.dataset.window = label;
  ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <OverlayRoot label={label} />
    </React.StrictMode>,
  );
});
