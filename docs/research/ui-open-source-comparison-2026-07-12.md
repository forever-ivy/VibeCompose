# OpenWhisper UI 与成熟开源产品对比调研

> 调研日期：2026-07-12
>
> 范围：OpenWhisper 当前 macOS UI、首次使用、权限、菜单栏、HUD、History、Terminology、视觉验收
>
> 方法：OpenWhisper 工作树静态审计、源码离屏渲染、并行子代理审计、6 个开源仓库 pinned-commit 对比

## 1. 结论摘要

OpenWhisper 的底层 UI 技术路线是正确的：应用使用 **AppKit + SwiftUI、`NSStatusItem`、`NSPanel`、SF Symbols 和系统字体**，不是跨平台 Web 壳。当前最影响“iOS / macOS 原生感”的问题也不是 graphite + ice blue HUD 品牌，而是：

1. **Settings 像桌面 Web 管理台，不像 macOS Settings。**
   - 固定 `980 × 720`，不可调整大小。
   - 自绘 `HStack + Button` 侧栏，缺少原生列表选中、键盘导航和 sidebar 语义。
   - 多层圆角卡片、固定底栏和全局 `Save Settings` 增加了“网页后台”感。
2. **首次使用与权限流程仍偏工程诊断。**
   - 麦克风说明窗口直接展示安装路径和 clean TCC 等实现细节。
   - Microphone 与 Accessibility 的“必需 / 可选 / 降级模式”虽然已有代码基础，但尚未形成简洁、可理解的产品叙事。
3. **History 和 Terminology 被当作 Settings 内的小组件，而不是完整数据工作流。**
   - History 主要展示 Latest 10、两行预览、复制和 Retry。
   - Terminology 只显示前 5 条，并提示用户编辑 `config.json` 完成批量操作。
4. **HUD 已具备可保留的品牌资产，但状态切换会明显横向跳动。**
   - recording `300 × 44`
   - processing / success `196 × 44`
   - error `286 × 44`
   - 普通 error 仅显示 2 秒；如果错误需要用户阅读或处理，这一时长不足。
5. **视觉事实源不一致。**
   - 源码 HUD 尺寸与 `docs/openwhisper-hud-visual-spec.md` 不一致。
   - 文档宣传图不是安装版真实截图。
   - 当前视觉验收只证明“有足够像素且状态截图不同”，不验证文字、尺寸、颜色、裁切、动作或自动隐藏语义。

推荐方向是 **“保留 HUD 品牌，原生化工作流和窗口结构”**，而不是全盘重做：

- 保留 graphite + ice blue HUD 和单触发 `F5` 工作流。
- Settings 改为 `NavigationSplitView + List(selection:) + Form/Section/LabeledContent`。
- History 和 Terminology 最终从“设置项”升级为独立管理工作流。
- Microphone 定义为 required；Accessibility 定义为 recommended / optional，并明确 clipboard limited mode。
- 增加 Reduce Motion、Increase Contrast、VoiceOver、本地化和 installed-app 视觉快照覆盖。

---

## 2. 调研基线与子代理分工

### 2.1 OpenWhisper 基线

| 项目 | 值 |
| --- | --- |
| 基线提交 | `5ed14d50b9e2f4ca40fd11a53a4fcf489b648694` |
| 分支 | `main` |
| 基线提交时间 | 2026-07-07 11:19:33 +0800 |
| UI 审计日期 | 2026-07-12 |
| 最低系统 | macOS 13 |
| 权威运行路径 | `/Applications/OpenWhisper.app` |

本报告审计的是 **2026-07-12 的工作树**，其中中文本地化和权限状态刷新已在其他并发改动中开始落地，包括：

- `Sources/OpenWhisper/Localization.swift`
- `Sources/OpenWhisper/Resources/zh-Hans.lproj/`
- `Sources/OpenWhisper/PermissionStatusMonitor.swift`

因此，不能再将当前项目描述为“完全没有本地化”或“完全没有权限状态模型”。更准确的结论是：**本地化和权限基础已经出现，但 UI 架构、键值治理、布局适配和可访问性尚未完成系统化改造。**

本次调研没有覆盖、回退或重写这些并发产品源码改动。

### 2.2 并行子代理轨道

本次通过并行子代理完成了四条审计轨道：

1. OpenWhisper Settings、HUD、菜单栏、权限窗口和视觉规范静态审计。
2. VoiceInk、Buzz、Handy 的同类语音产品功能与信息架构审计。
3. Maccy、CotEditor、Ice 的 macOS 原生窗口、Settings、菜单栏、权限和可访问性范式审计。
4. 安装版视觉证据链、宣传素材和 screenshot verifier 审计。

### 2.3 对标仓库

| 产品 | 对标角色 | pinned commit |
| --- | --- | --- |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | 最直接的 macOS 语音输入竞品 | `cf0c366906a52ba2b9950074ed2fd0270548c910` |
| [Buzz](https://github.com/chidiwilliams/buzz) | History、任务表格、模型管理 | `191795bab21ee8414fc5479fb8c72d16f457c496` |
| [Handy](https://github.com/cjpais/Handy) | History、模型目录、overlay 状态完整性 | `ea10f7454e86f893581f5a380a15866476aa6423` |
| [Maccy](https://github.com/p0deje/Maccy) | 菜单栏 utility、浮动面板、标准菜单 | `3fe63ec3a0eabf6605d40c48b3c85b7bf555c86a` |
| [CotEditor](https://github.com/coteditor/CotEditor) | 原生 Settings、空状态、a11y、本地化 | `9542a4ef88d3aa1f12a51e9a2a0f3c2d21c8a810` |
| [Ice](https://github.com/jordanbaird/Ice) | Settings sidebar、权限 required/optional 模型 | `11edd39115f3f43a83ae114b5348df6a0e1741cf` |

这些仓库以 pinned commit 源码为证据，没有将仓库截图误认为当前运行时截图。调研目标是提炼交互和架构范式，不复制第三方视觉资产。

---

## 3. OpenWhisper 当前 UI 盘点

### 3.1 已有优势

| 表面 | 当前优势 |
| --- | --- |
| 技术基础 | 原生 AppKit + SwiftUI；无需为了“原生感”替换技术栈。 |
| 菜单栏 | `NSStatusItem`、template image、Settings `⌘,`、Quit `⌘Q`、tooltip 和 accessibility label 已存在。 |
| HUD 窗口 | 使用非激活浮动 `NSPanel`，支持跨 Space、全屏辅助窗口、ESC 和 inline close。 |
| 工作流 | `F5` 启动 / 停止的单触发路径清晰，应作为核心产品约束继续保留。 |
| 降级策略 | 无可编辑焦点时保留剪贴板，Accessibility 不应被误建模为“应用完全不可用”。 |
| 视觉品牌 | graphite、mist、ice blue、success、amber、error token 已集中定义，HUD 识别度高于通用系统灰色 pill。 |
| 权限实现 | `.notDetermined`、denied、签名异常、系统设置修复和状态刷新已有独立代码基础。 |
| 本地化进展 | 已开始建立 `L10n`、`zh-Hans.lproj` 和 UI 文案迁移。 |

### 3.2 当前 Settings 视觉证据

品牌迁移期间已删除旧名称时期生成的离屏截图，避免继续把过时视觉资产作为 OpenWhisper 的公开事实源。本节结论来自同一代码基线的结构审计；后续证据必须从 `/Applications/OpenWhisper.app` 重新生成。

从该画面可以直接观察到：

- 自绘侧栏选中行已经接近原生，但仍缺少原生 `List` 的键盘、焦点、VoiceOver 和 sidebar row-size 行为。
- 内容区上方是大标题，下方又进入 “Account & Permissions” 卡片，出现重复层级。
- 卡片内部继续嵌套状态 tile、按钮带和诊断文案，密度不均。
- 权限诊断长文以橙色贯穿内容区，缺少 summary / disclosure / diagnostics 分级。
- 全局底栏长期占据空间；“Open Config Folder”属于 Advanced / Diagnostics 工具，不应在每个 pane 中常驻。

### 3.3 当前 HUD 视觉证据

旧名称时期的 HUD 离屏截图也已清理。OpenWhisper 后续只接受安装版生成的 recording、processing、verified insert、paste sent、copied、error 和 retryable-error 证据。

HUD 的视觉语言可以保留，但需要解决：

- `300 → 196 → 286` 的明显宽度跳变。
- processing 动画不尊重 Reduce Motion。
- Increase Contrast 下没有更强边框或替代表达。
- 普通 error 两秒后自动隐藏，阅读和修复时间不足。
- icon 的 accessibility description、tooltip 等仍有英文硬编码，没有完全进入本地化体系。

---

## 4. 开源产品逐项对标

### 4.1 VoiceInk：直接竞品与功能完整度标杆

重点证据：

- `Views/Onboarding/` 下存在完整的分阶段 onboarding：
  - permissions
  - microphone
  - model
  - API
  - experience
  - context awareness
  - trust
  - license
- `Views/Recorder/` 同时提供 Mini 和 Notch 两类 recorder panel。
- `HistoryWindowController.swift` 创建独立 History window，并保存窗口 frame。
- `TranscriptionHistoryView.swift` 提供搜索、分页、选择、sidebar、inspector、分析和删除。
- `Views/Dictionary/` 将 Vocabulary 与 Word Replacement 分开，并提供独立 Quick Add panel。

OpenWhisper 应借鉴：

1. 首次使用应该有明确阶段、进度、返回和恢复，而不是把所有配置压入 Settings。
2. History 是用户内容，不只是一个设置卡片。
3. Terminology 应支持“快速添加”和完整管理两个入口。
4. Recorder 可有不同显示模式，但这属于 P2；不应优先于 Settings、History 和权限清晰度。

不应照搬：

- VoiceInk 的 8 步流程对 OpenWhisper 过长。OpenWhisper 更适合 4 步紧凑 onboarding。
- Notch 模式容易成为视觉噱头，不应成为默认或第一优先级。
- VoiceInk 部分表面也使用较多自绘卡片，不能作为 macOS Settings 原生性的唯一标杆。

### 4.2 Maccy：菜单栏 utility 与浮动面板标杆

重点证据：

- `AppDelegate.swift` 统一维护 status item 可见性、状态和标准菜单命令。
- `FloatingPanel.swift` 使用 `.nonactivatingPanel`、`.resizable`、`.fullSizeContentView`，并处理点击外部关闭和键盘焦点。
- 菜单栏资源使用 template rendering，交给系统处理明暗和选中态。
- Settings pane metadata 集中定义，标题、symbol 和 destination 不散落在多个 switch 中。

OpenWhisper 应借鉴：

- 保留当前 template status icon 和 `⌘,` / `⌘Q`。
- 将 Settings destination metadata 集中化。
- 如果增加 Quick Add 或轻量历史弹层，可复用“非激活窗口但允许输入”的 panel 分层。

不应照搬：

- Maccy 的历史空状态和权限流程并不完整。
- popup panel 的点击外部关闭行为不适用于 Settings。

### 4.3 CotEditor：macOS 原生性、a11y 与本地化标杆

重点证据：

- `SettingsWindowController` 使用原生 toolbar-style Settings。
- `SettingsTabViewController` 记忆 pane，并在切换时调整窗口尺寸。
- 动画检查 Reduce Motion。
- 自绘控件在 Increase Contrast 下增加边界。
- 大量表单使用 label/content 可访问性配对。
- 空状态使用 `ContentUnavailableView`。
- String Catalog 按功能拆分，并给 translator 提供 default value 和 comment。

OpenWhisper 应借鉴：

- 记忆上次 Settings destination 和窗口 frame。
- 将 Reduce Motion、Increase Contrast、VoiceOver 作为实现条件，而非发布后补丁。
- 用系统空状态结构表达“发生了什么、为什么、下一步做什么”。
- 本地化覆盖 UI、tooltip、VoiceOver、错误修复和带变量文案。

兼容性注意：

- OpenWhisper 当前最低支持 macOS 13，而 `ContentUnavailableView` 需要更高系统版本。
- 推荐在 macOS 14+ 使用 `ContentUnavailableView`，macOS 13 使用同语义的自定义 fallback；不要为了一个控件无意提高最低系统版本。

### 4.4 Ice：Settings sidebar 与权限状态模型标杆

重点证据：

- `SettingsView.swift` 使用 `NavigationSplitView + List(selection:) + Section + Label`。
- sidebar 行高和字号跟随系统 sidebar row size。
- `Permission.swift` 统一定义 title、details、required、check、request 和系统设置入口。
- `PermissionsManager` 汇总：
  - missing permissions
  - has required permissions
  - has all permissions
- optional permission 缺失时显示 Limited Mode，而不是阻断整个应用。

OpenWhisper 应直接映射为：

| 权限 | 产品级别 | 未授权行为 |
| --- | --- | --- |
| Microphone | required | 无法录音；在用户按 F5 的首次路径中解释并请求。 |
| Accessibility | recommended / optional | 继续录音和转写；结果保留在 clipboard；明确“不会自动粘贴”。 |

不应照搬：

- Ice 的 Settings selection 没有完整持久化，OpenWhisper 应增加 `@AppStorage` 或等效状态恢复。
- 颜色状态仍需配合文字、glyph 和 VoiceOver value，不能只依赖红黄绿。
- OpenWhisper 必须保留现有 `.notDetermined` 权限请求顺序和签名修复逻辑。

### 4.5 Buzz：任务表格和模型管理参考

Buzz 是 Qt 跨平台应用，不适合作为 macOS 视觉样式模板，但其数据工作流成熟：

- `TranscriptionTasksTableWidget` 使用可排序、可移动、可隐藏列的任务表格。
- 状态列展示 queued / progress / ETA / completed / failed / canceled / skipped。
- History 任务可重启、删除、复制、查看错误和备注。
- 模型管理明确区分 downloaded 与 available，并提供下载、进度、删除和文件位置。

OpenWhisper 应借鉴：

- History 的字段完整性和状态动作。
- 长列表的排序、过滤、上下文菜单和批量操作。
- 如果未来引入本地模型，模型下载必须有可取消进度和明确生命周期。

不应照搬：

- Qt 控件密度、平台中性视觉和复杂列配置不适合 OpenWhisper 的轻量菜单栏产品。

### 4.6 Handy：History、模型目录和 overlay 状态参考

Handy 使用 Tauri + React，不适合作为原生控件视觉标杆，但功能层面值得参考：

- History 支持分页、实时增量更新、收藏、复制、音频播放、删除和 Retry。
- 模型目录支持搜索、语言筛选、下载、验证、解压、切换、删除和 Rescan。
- overlay 将 recording / streaming / transcribing / processing 建模为统一状态集合。
- 本地化覆盖多语言。

OpenWhisper 应借鉴：

- History 行动作和音频回放。
- 对异步状态进行完整建模，而不是仅显示 spinner。
- 数据变化时做增量更新，避免用户手动 Refresh 成为主路径。

不应照搬：

- HTML/CSS 卡片、Lucide 图标、Web toggle 和自绘 dropdown 会削弱 macOS 原生感。
- OpenWhisper 应用同等功能时应优先使用 `Table`、`List`、`Form`、`Menu`、`ProgressView`、SF Symbols 和系统 dialog。

---

## 5. 差异矩阵

| 维度 | OpenWhisper 当前 | 成熟对标 | 主要差异 | 优先级 |
| --- | --- | --- | --- | --- |
| 技术栈 | AppKit + SwiftUI | Maccy / CotEditor / Ice 同样以原生框架为主 | 技术路线无须替换 | 保留 |
| Settings 窗口 | 固定 `980 × 720`，不可 resize | Ice 可调整 sidebar window；CotEditor 恢复 pane / size | 缺窗口恢复、尺寸适配和系统行为 | P0 |
| Settings 导航 | 自绘 Button sidebar | Ice `NavigationSplitView + List(selection:)` | 缺键盘、焦点、VoiceOver、row-size 语义 | P0 |
| 表单结构 | 大标题 + card + 内层 tile | 原生 `Form / Section / LabeledContent` | 层级重复、卡片套卡片、密度不均 | P0 |
| 保存语义 | 全局 `Save Settings` | 成熟 macOS Settings 通常即时保存 | 用户无法判断哪些修改已生效 | P0 |
| 工具入口 | Config Folder 常驻底栏 | 高级工具通常在菜单或 Advanced | 工程工具侵占所有 pane | P0 |
| 首次使用 | 分散在权限窗和 Settings | VoiceInk 分阶段 onboarding | 缺进度、练习、恢复和完成状态 | P0 |
| 权限层级 | 状态已有，但叙事混合 | Ice required / optional / limited mode | 未形成简单清晰的产品模型 | P0 |
| 权限文案 | 展示安装路径、clean TCC、签名长诊断 | 用户层说明 + 独立 diagnostics | 工程细节过度暴露 | P0 |
| HUD 品牌 | 统一 graphite pill | VoiceInk / Handy 有完整 recorder 状态 | OpenWhisper 已有识别度，应保留 | 保留 |
| HUD 几何 | 196 / 286 / 300 三种宽度 | 成熟 overlay 通常维持稳定锚点和壳体 | 状态切换横向跳动明显 | P0 |
| HUD 错误 | 普通错误 2 秒消失 | actionable error 常保持到处理 | 阅读与恢复时间不足 | P0 |
| History | Settings 内 Latest 10 预览 | VoiceInk 独立窗口；Buzz 表格；Handy 完整动作 | 搜索、详情、音频、批量、自动更新不足 | P1 |
| Terminology | 最多显示 5 条，批量编辑依赖 JSON | VoiceInk Dictionary + Quick Add | 数据管理被压缩成配置预览 | P1 |
| 空状态 | 单行灰色文字 | CotEditor 标准空状态结构 | 缺原因、下一步和行动入口 | P0 |
| 菜单栏 | template icon、标准快捷键已有 | Maccy / Ice | 基础良好，只需增强状态形状与菜单入口 | P1 |
| 动效 | HUD timer 固定播放 | CotEditor 尊重 Reduce Motion | 缺辅助功能分支 | P1 |
| 高对比 | 自绘低透明度边界 | CotEditor / Ice 显式适配 | Increase Contrast 下可能过淡 | P1 |
| VoiceOver | 部分按钮已有 label | CotEditor 系统性覆盖 label/value/pair/group | 覆盖不完整且英文硬编码仍存在 | P1 |
| 本地化 | `L10n` 与简中正在落地 | CotEditor feature-scoped catalog | key、显示文案、a11y 和注释治理仍弱 | P1 |
| 视觉规范 | 文档与代码尺寸不一致 | 单一 token / snapshot 事实源 | 设计、实现、宣传和验收可能漂移 | P0 |
| 视觉验收 | 检查可见像素和状态差异 | 语义断言 + snapshot + live flow | 不能证明文案、尺寸、裁切、颜色和动作正确 | P0 |

---

## 6. 推荐目标架构

### 6.1 产品窗口层级

推荐最终形成五类清晰表面：

1. **Menu Bar**
   - 状态摘要
   - Start / Stop 提示
   - History…
   - Terminology…
   - Settings… `⌘,`
   - Quit `⌘Q`
2. **HUD**
   - recording
   - processing
   - verified insert
   - paste sent
   - copied
   - error
   - retryable error
3. **Settings**
   - General / Account & Permissions
   - Dictation
   - AI Polish
   - Paste
   - Advanced / Diagnostics
4. **History Window**
   - 用户内容浏览、搜索、详情、音频和恢复动作
5. **Terminology Manager / Quick Add**
   - 完整词典管理窗口或 destination
   - 全局快捷 Quick Add panel

迁移期可以继续在 Settings 中保留 History 和 Terminology destination，但最终应将“偏好设置”和“用户数据管理”分离。

### 6.2 Settings 原生化方案

#### 推荐结构

```swift
NavigationSplitView {
    List(SettingsDestination.allCases, selection: $selection) { destination in
        Label(destination.localizedTitle, systemImage: destination.symbol)
            .tag(destination)
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
} detail: {
    destinationView(selection)
}
```

detail 内容优先使用：

- `Form`
- `Section`
- `LabeledContent`
- `Toggle`
- `Picker`
- `TextField`
- `SecureField`
- `ProgressView`
- `DisclosureGroup`
- `ControlGroup`

只在以下情况使用 `GroupBox` 或自绘卡片：

- 需要表达一组独立产品状态。
- 需要与普通表单明显区分的 warning / limited mode。
- 需要承载可交互的预览。

#### 窗口行为

- 默认约 `900 × 625`。
- 最小约 `820 × 560`，允许 resize。
- 使用 frame autosave name 保存位置和尺寸。
- 使用稳定、非本地化 ID 保存最后 destination。
- Settings 打开时正常激活应用；关闭最后一个普通窗口后恢复 menu bar accessory 行为。

#### 保存行为

推荐移除全局 Save footer：

- Toggle / Picker：即时保存。
- 普通 TextField：提交或失焦后校验并保存。
- API URL / 高风险字段：显示 inline validation；只有合法值才能提交。
- destructive reset：使用确认 dialog。
- `Open Config Folder` 移到 Advanced / Diagnostics 或菜单栏菜单。

如果短期无法改为即时保存，至少应：

- 显示明确 dirty state。
- 仅在有未保存修改时显示 Apply / Revert。
- 关闭窗口时处理未保存状态。
- 不让一个长期存在的 Save 按钮同时承担所有 pane 的模糊提交语义。

### 6.3 首次使用与权限方案

OpenWhisper 不需要复制 VoiceInk 的 8 步流程，推荐 4 步：

1. **Welcome**
   - 一句话说明：本地 Codex 桌面登录、按 F5 录音、转写后自动粘贴或留在剪贴板。
   - 明确私有 ChatGPT backend 依赖，不描述为稳定公共 API。
2. **Connect ChatGPT**
   - Browser Login。
   - 显示连接状态和隐私说明。
3. **Microphone**
   - 在用户明确点击 Continue 后请求。
   - Settings / preflight 只允许 check，不得提前 request。
4. **Paste & Practice**
   - Accessibility 为 optional / recommended。
   - 未授权时明确显示 Clipboard Mode。
   - 提供真实可编辑练习区，完成一次 F5 start / stop / paste-or-copy。

权限 UI 只展示用户需要理解的信息：

- 这项权限用于什么。
- 是否必需。
- 未授权会发生什么。
- 下一步唯一主动作。

以下内容移入 Advanced / Diagnostics：

- `/Applications/OpenWhisper.app` 路径。
- clean TCC、签名状态、重建 packaged app 等排障说明。
- 详细系统设置路径和底层状态。

### 6.4 History 方案

推荐独立普通窗口，而不是继续扩大 Settings card：

- toolbar：
  - Search
  - 类型筛选
  - 日期筛选
  - Refresh 仅作为恢复动作，不是主数据同步方式
- 主列表 / Table：
  - 时间
  - 来源 app / target
  - 状态
  - 原始 ASR 摘要
  - AI Polish 摘要
- detail / inspector：
  - 完整原始文本
  - 完整润色文本
  - 错误详情
  - 音频播放
  - Copy
  - Retry
  - Reveal in Finder
  - Delete
- 行为：
  - 新记录自动增量出现。
  - 支持键盘选择和上下文菜单。
  - 失败记录优先展示恢复动作。
  - 空状态说明“按 F5 开始首次听写”。

### 6.5 Terminology 方案

短期：

- 用完整 `Table` / `List` 替换前 5 条预览。
- 搜索、Terms / Corrections 筛选、排序。
- 新增、编辑、启停、删除。
- Import / Export。
- 删除“编辑 `config.json` 批量管理”的主流程文案。

中期：

- 增加 Quick Add panel，支持全局快捷键。
- Vocabulary 与 deterministic correction 使用清晰不同的字段和解释。
- 添加右键菜单、批量启停、重复项检测和导入预览。

### 6.6 HUD 方案

#### 保留

- graphite + ice blue 品牌。
- 9-bar waveform。
- F5 start / stop。
- ESC 和 inline close。
- Pasted / Copied 的不同语义。
- retryable error 的 Retry。

#### 改进

1. **稳定壳体宽度**
   - recording / processing / success 建议统一约 `272–288 × 44`。
   - error 如需更多文字，可使用约 `304–320 × 52–56`，而不是每个状态都改变壳体。
2. **错误停留**
   - retryable / actionable error：保持到 Retry、Cancel 或新一轮 F5。
   - 纯瞬时错误：至少 4–6 秒，并可通过 Settings 调整。
3. **系统辅助功能**
   - Reduce Motion：停用 70ms traveling ridge，使用静态或低频渐变。
   - Increase Contrast：提高 border、文字和图标对比。
   - VoiceOver：状态改变时发布简短 announcement。
4. **材质**
   - 可评估以 `NSVisualEffectView(.hudWindow/.popover)` 为底，再叠加 graphite tint。
   - 不建议直接移除当前品牌色，变成无差异的系统灰。
5. **位置**
   - 保持可见屏幕底部居中，但评估将视觉 inset 从 8 增至 16–24，降低贴边感。

Notch 模式放在 P2 作为可选项，不作为原生感的必要条件。

### 6.7 iOS / macOS 共同设计语言

“iOS 原生感”不等于把 iPhone tab bar、超大圆角卡片和移动端开关搬到 Mac。OpenWhisper 更适合采用 Apple 平台共同语言，同时尊重 macOS 窗口和键盘习惯：

- SF Symbols。
- 系统字体和 semantic text styles。
- semantic colors 与 materials。
- 标准 control size、focus ring 和 keyboard shortcut。
- 清晰的 primary / secondary / destructive action。
- Reduce Motion、Increase Contrast、VoiceOver。
- 本地化后仍可伸缩的布局。
- macOS 上使用 sidebar、toolbar、menu、table、inspector 和可调整窗口。

---

## 7. 分阶段改进计划

### 7.1 P0：原生骨架和关键状态

| 工作项 | 方法 | 验收结果 |
| --- | --- | --- |
| Settings sidebar 原生化 | `NavigationSplitView + List(selection:)` | 方向键可切换；VoiceOver 可读；跟随系统 sidebar row size |
| Settings window 行为 | 增加 `.resizable`、min size、frame autosave | 可调整并恢复窗口位置、尺寸和最后 pane |
| 表单降噪 | 用 `Form / Section / LabeledContent` 替代大部分卡片 | 不再出现大标题、卡片标题、tile 标题三层重复 |
| 保存语义 | 即时保存或明确 Apply / Revert dirty state | 用户能判断修改是否生效 |
| 权限分级 | Microphone required；Accessibility optional | 未授权 Accessibility 时明确进入 clipboard mode |
| 首次权限文案 | 用户说明与 diagnostics 分离 | 首次窗口不再显示 clean TCC、安装路径等工程词 |
| HUD 宽度和错误时长 | 稳定主状态宽度；actionable error 不自动消失 | 状态切换不明显横跳；错误可读可操作 |
| 空状态 | macOS 14+ `ContentUnavailableView`，macOS 13 fallback | History / Recovery / Terminology 都解释下一步 |
| 视觉事实源 | 代码 token、规范、截图和测试统一 | 不再出现 196/300 与 220/246 两套 HUD 尺寸 |

### 7.2 P1：完整工作流和可访问性

| 工作项 | 方法 | 验收结果 |
| --- | --- | --- |
| History window | List/Table + search + detail/inspector | 可搜索、复制、Retry、播放音频、删除 |
| Terminology manager | 完整列表、搜索、导入导出、上下文菜单 | 不依赖编辑 JSON 完成常规操作 |
| Quick Add | 非激活 keyable panel + 全局快捷键 | 不打开 Settings 也能添加术语或纠错 |
| Reduce Motion | HUD / pane 动画读取系统设置 | 开启后无高频 processing 动画 |
| Increase Contrast | 自绘 border / icon 提高对比 | 高对比模式下状态仍清晰 |
| VoiceOver | label、value、hint、labeled pair、group | 完成 Settings、HUD、History 键盘/读屏路径 |
| 本地化治理 | stable key、format key、translator comment | 英文/简中无裁切；tooltip/a11y 不再遗留硬编码 |
| Menu Bar IA | 增加 History…、Terminology… | 核心数据入口不必经过 Settings |

### 7.3 P2：增强而非补救

- 可选 Mini / Notch recorder mode。
- History 分析与统计。
- 多种 HUD 尺寸或位置偏好。
- 术语 usage count、冲突检测和导入预览。
- 更完整的本地模型管理；仅在产品路线需要时引入。

---

## 8. 推荐实现顺序

1. 先建立 `SettingsDestination`、窗口恢复和原生 sidebar。
2. 在不改业务逻辑的前提下，把现有 pane 内容迁入 `Form / Section`。
3. 拆除全局 footer，确定设置持久化语义。
4. 完成 required / optional 权限 summary 和 compact onboarding。
5. 修复 HUD 尺寸、错误停留、Reduce Motion 和事实源漂移。
6. 新建独立 History window，并复用现有 history / recovery 数据模型。
7. 将 Terminology 升级为完整 manager，再增加 Quick Add。
8. 最后做 Notch、统计等增强项。

这个顺序优先解决架构和系统行为，避免先花时间重画颜色、阴影或营销图，却继续保留 Web 管理台式交互。

---

## 9. 视觉与交互验收标准

### 9.1 Settings

- 默认尺寸在小型笔记本屏幕上完整可见。
- 窗口可 resize，并恢复 frame 和最后 pane。
- sidebar 支持鼠标、方向键、VoiceOver 和焦点环。
- 英文和简中均不截断主要标题、按钮和权限说明。
- 没有永久占位的全局 Save footer，或存在可验证的 dirty / Apply / Revert 状态。
- Advanced / Diagnostics 才显示安装路径、签名、TCC 和 config folder。

### 9.2 权限

- clean `.notDetermined` 状态下，仅打开 Settings 不触发系统权限请求。
- 用户按 F5 后，Microphone 首次路径按预期请求。
- Accessibility 未授权时仍可完成录音和转写。
- fallback 结果保留在 clipboard，并在 HUD / Settings 中明确显示。
- denied / restricted / signature anomaly 都有唯一、明确的修复动作。

### 9.3 HUD

- F5 开始和停止。
- ESC 取消。
- inline close 取消。
- Retry 可重新进入流程。
- recording / processing / success 主壳体宽度稳定。
- actionable error 不会在用户阅读前消失。
- Reduce Motion 下没有高频 waveform ridge。
- Increase Contrast 下边界和 glyph 仍清晰。
- VoiceOver 可读出 Recording、Processing、Pasted、Copied、Error 和 Retry。

### 9.4 History / Terminology

- 空、少量、大量数据状态均可用。
- 搜索、排序、键盘选择、上下文菜单和 destructive confirmation 可用。
- History 可播放音频、复制结果、Retry 失败记录。
- Terminology 可管理全部数据，不依赖直接编辑 `config.json`。

### 9.5 视觉事实源

建议 snapshot / semantic tests 至少断言：

- 每个 HUD 状态的准确 width / height。
- 标题、detail、icon 和 action 可见性。
- auto-hide delay 或持久化语义。
- 英文与简中截图。
- light / dark / Increase Contrast。
- Reduce Motion。
- Settings 的最小尺寸和关键 pane 不裁切。

安装版最终仍必须通过：

```sh
./scripts/visual_acceptance.sh --install
```

并使用 `/Applications/OpenWhisper.app` 做真实焦点、快捷键、权限和 paste-versus-clipboard 流程验证。

---

## 10. 当前视觉证据限制与已排除路径

### 已尝试

- 运行官方 installed-app visual acceptance。
- 通过 CoreGraphics 找到 HUD window。
- 尝试 `screencapture -l` 捕获窗口。
- 尝试系统辅助功能自动化。

### 当前阻塞

- 当前 macOS 会话缺少可用的屏幕录制权限，窗口截图失败并返回 `could not create image from window`。
- System Events 自动化被辅助功能权限拒绝。
- 本次会话没有暴露可用于原生 GUI 验证的 Computer Use 工具。

### 替代证据

品牌迁移前曾使用临时 Swift offscreen renderer 验证：

- 布局层级。
- 当前颜色、尺寸和文案组合。
- HUD 各状态的静态外观。

但不能证明：

- 安装版窗口材质和阴影的最终系统合成。
- 快捷键、焦点、鼠标 hit target。
- 动画时序和自动隐藏。
- TCC 系统弹窗顺序。
- 多屏、全屏和 Space 行为。

相关旧截图已在 OpenWhisper 品牌迁移时删除。因此，本报告是 **UI 架构与源码视觉调研结论**，不是当前 installed-app 交互验收通过证明。

---

## 11. 最终建议

最优先的五项改进是：

1. `NavigationSplitView + List(selection:)` 原生 Settings sidebar。
2. 移除卡片套卡片和全局 Save footer，改用原生 Form 与明确保存语义。
3. 建立 4 步 onboarding 和 required / optional / clipboard limited-mode 权限模型。
4. 将 History 和 Terminology 升级为完整管理工作流。
5. 统一 HUD 代码、规范、宣传截图和 snapshot tests，并修复宽度跳动与错误自动消失。

完成这五项后，OpenWhisper 会从“使用原生技术实现的功能型工具”提升为“行为、信息架构、可访问性和视觉证据都符合 macOS 习惯的成熟菜单栏产品”，同时不需要牺牲现有 HUD 品牌或 `F5` 单触发体验。

---

## 附录 A：关键源码索引

以下路径均相对各项目 pinned commit 的仓库根目录。

| 项目 | 关键证据路径 |
| --- | --- |
| OpenWhisper | `Sources/OpenWhisper/PreferencesWindowController.swift` |
| OpenWhisper | `Sources/OpenWhisper/OverlayController.swift` |
| OpenWhisper | `Sources/OpenWhisper/OverlayVisualModel.swift` |
| OpenWhisper | `Sources/OpenWhisper/StatusMenuController.swift` |
| OpenWhisper | `Sources/OpenWhisper/OpenWhisperVisualSystem.swift` |
| OpenWhisper | `Sources/OpenWhisper/MicrophonePermissionWindowController.swift` |
| OpenWhisper | `Sources/OpenWhisper/PermissionStatusMonitor.swift` |
| OpenWhisper | `docs/openwhisper-hud-visual-spec.md` |
| OpenWhisper | `scripts/verify_visual_acceptance.swift` |
| VoiceInk | `VoiceInk/HistoryWindowController.swift` |
| VoiceInk | `VoiceInk/Views/History/TranscriptionHistoryView.swift` |
| VoiceInk | `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` |
| VoiceInk | `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift` |
| VoiceInk | `VoiceInk/Views/Recorder/MiniRecorderPanel.swift` |
| VoiceInk | `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` |
| VoiceInk | `VoiceInk/Views/Onboarding/OnboardingView.swift` |
| Maccy | `Maccy/AppDelegate.swift` |
| Maccy | `Maccy/FloatingPanel.swift` |
| Maccy | `Maccy/Observables/AppState.swift` |
| CotEditor | `Packages/MacUI/Sources/ControlUI/SettingsWindow/SettingsWindowController.swift` |
| CotEditor | `Packages/MacUI/Sources/ControlUI/SettingsWindow/SettingsTabViewController.swift` |
| CotEditor | `CotEditor/Sources/Document Window/Content View/NoDocumentView.swift` |
| CotEditor | `Packages/MacUI/Sources/ControlUI/FormPopUpButton.swift` |
| Ice | `Ice/Settings/SettingsView.swift` |
| Ice | `Ice/Permissions/Permission.swift` |
| Ice | `Ice/Permissions/PermissionsManager.swift` |
| Ice | `Ice/Permissions/PermissionsView.swift` |
| Buzz | `buzz/widgets/transcription_tasks_table_widget.py` |
| Buzz | `buzz/widgets/preferences_dialog/models_preferences_widget.py` |
| Handy | `src/components/settings/history/HistorySettings.tsx` |
| Handy | `src/components/settings/models/ModelsSettings.tsx` |
| Handy | `src/overlay/RecordingOverlay.tsx` |
