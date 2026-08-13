import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  clearScreen: false,
  server: {
    // Pinned to IPv4: on some Node/macOS setups Vite binds only [::1] for
    // "localhost", which the Tauri webview cannot reach (blank windows).
    host: "127.0.0.1",
    port: 1420,
    strictPort: true,
  },
  build: {
    target: "es2022",
  },
});
