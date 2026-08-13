# VibeCompose（Windows / Linux）

按下快捷键说话，文本经过转写、术语规范化和 Skill 变换后，粘贴到当前光标处。

这是 VibeCompose 的跨平台实现，架构为 **Tauri v2 = Rust 核心 + TypeScript UI**，
从 macOS 原生 Swift 版（仓库根）移植行为，**不移植外观**：

- Windows：Fluent（Win11 设置页语言）+ 系统标题栏
- Linux：GNOME Adwaita + 窗口管理器客户端装饰
- macOS 构建仅作开发调试；发行版仍是仓库根的 SwiftUI 应用

## 工作流

```text
聚焦可编辑目标
→ F5 开始录音（同键停止）
→ 转写（ChatGPT 托管会话 / OpenAI 兼容 API）
→ 术语规范化（术语表 + technical literal 保护）
→ 按 Skill 润色（本地校验，失败回退到规范化转写）
→ 重新检查当前目标
→ 证明安全则粘贴，否则保留在剪贴板
```

交付结果三态，永不混淆：`已验证插入` / `已发送粘贴（剪贴板保留）` / `仅剪贴板`。

## 仓库结构

```
crates/
├── vc-core/        平台无关核心：pipeline、Skill 运行时、术语、配置、历史
├── vc-providers/   转写/润色 provider：ChatGPT 托管会话、OpenAI 兼容、端点白名单
├── vc-audio/       跨平台录音（cpal → 24kHz mono WAV）
└── vc-inject/      文本交付：剪贴板、粘贴分发、插入验证（AX / Win32 / 降级）
apps/desktop/       Tauri v2 应用：托盘、全局热键、React UI
skills/             21 个内置 Skill 包（与 macOS 版格式完全兼容）
spec/               格式规范 + 语言无关 golden 夹具（两端共同的验收标准）
```

## 开发

```bash
# 全部 Rust 测试（含内置 Skill golden 验收和 spec 夹具验收）
cargo test

# 前端
cd apps/desktop && npm install && npm run build

# 开发运行 / 打包
cd apps/desktop && cargo tauri dev
cd apps/desktop && cargo tauri build
```

## 平台矩阵

| 能力 | macOS | Windows | Linux |
|------|-------|---------|-------|
| 全局热键（F5） | ✅ | ✅ | ✅（X11） |
| 录音 → 24kHz WAV | ✅ CoreAudio | ✅ WASAPI | ✅ ALSA |
| 粘贴分发 | ✅ Cmd+V | ✅ Ctrl+V | ✅（Wayland 可能降级） |
| 插入验证 | ✅ AX API | ✅ UIA（待真机验收） | 不支持（按设计降级） |
| 选区上下文 | ✅ AX 选中文本 | ✅ UIA TextPattern（待真机验收） | ✅ X11 PRIMARY 选区 |
| 凭据存储 | Keychain | Credential Manager | Secret Service |
| 界面 | SwiftUI 原生（仓库根） | Fluent + 系统标题栏 | Adwaita + CSD |

## 信任边界（继承自原架构六规则）

1. 旧的启动上下文不能证明当前聚焦控件可编辑
2. 托管 ChatGPT token 只能附着到内置批准的 HTTPS origin 与路径
3. 恢复元数据不能选择任意文件路径
4. 异步结果只有在其会话仍为当前会话时才能修改状态
5. 选区仅在按 Skill 授权后读取
6. 社区 Skill 是不可信声明式数据：不能执行代码、加 provider、越过交付边界

## 路线图

- **M1（已完成）**：主链路（热键→录音→转写→Skill→粘贴）、21 个内置 Skill、
  历史、macOS AX 验证
- **M2（已完成）**：ChatGPT OAuth 浏览器登录闭环（回调、换令牌、自动刷新）、
  Windows UIA 插入验证、HUD overlay、结果预览窗口、Skill 切换器
- **M3（已完成）**：术语管理界面与 Quick Add（Ctrl+Alt+Space）、Style Capsules、
  失败录音恢复与重试、转写 prompt（语音清理/标点偏好/hint 术语）、
  选区/剪贴板/焦点段落上下文（按 Skill 能力授权）、提示音、首启引导、诊断导出
- **M4（下一步）**：Windows/Linux 真机验收、每 Skill 上下文授权对话框（对齐
  macOS 的允许一次/总是允许/仅语音）、社区 Skill 导入安全审查、
  自动更新（tauri-plugin-updater）、签名分发

## 与 macOS 版的已知差异

- 上下文授权：macOS 有每 Skill 的授权弹窗；本实现当前以「Skill 声明能力 +
  用户启用该 Skill + 敏感应用排除」作为授权门（见 M4）
- 焦点段落：拿不到光标位置，取焦点控件「最后一个非空段落」近似
- Linux：插入验证与焦点段落按设计不可用，交付结果如实降级
