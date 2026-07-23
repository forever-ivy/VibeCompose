# VibeWhisper macOS 原生 UI 重构计划

> 日期：2026-07-14  
> 最近修订：2026-07-17  
> 状态：Apple Books 式常驻侧边栏与转译态 Activity Glow 已落地；Settings 信息架构已由 Community Skills 核心计划收敛为五个入口  
> 参考：Apple HIG 的 Sidebars、Split views、Settings、Feedback、Progress indicators，以及 Apple Books 的窗口构图  
> 范围：Settings、菜单栏图标、视觉反馈、双语布局、Logo 与安装版验收

## 1. 重构目标

本次重构不是在旧界面上继续增加卡片和固定宽度，而是重建一个遵循 macOS
窗口行为、信息密度和可访问性习惯的设置体验：

1. 消除标题、侧边栏、正文、分段控件和英文文本之间的重叠。
2. 侧边栏始终可见，不再提供折叠按钮或隐藏状态。
3. 采用稳定的三层结构：系统标题栏 / 分组侧边栏 / 单列详情内容。
4. 语言切换只放在 Settings → General，不再占用主界面或标题栏。
5. 中文和英文使用同一套响应式组件，不为英文复制另一套固定尺寸界面。
6. 视觉反馈从普通跑马灯升级为可识别但克制的 `AI Activity Glow`。
7. App Icon、菜单栏图标和品牌资料统一使用彩色无限结徽标。

## 2. 现状诊断

原界面截图暴露的主要问题：

- 自绘品牌标题进入侧边栏顶部，同时与 macOS traffic lights 和标题栏文字争夺空间；
- 详情页大量使用固定宽度、横向 `HStack` 和不可压缩文本，英文切换后控件互相覆盖；
- 侧边栏项目过多且全部同级，账户、听写、视觉、AI、上下文、术语、粘贴、隐私和高级设置缺少层次；
- 多层浅灰卡片、分组背景、分隔线和胶囊控件同时出现，视觉语法不统一；
- 可折叠侧边栏会让主要设置入口消失，并在窗口状态切换时造成不必要的布局漂移；
- 语言入口位置不稳定，切换语言后当前窗口中的固定尺寸不会重新适配；
- 蓝色跑马灯只有“边框在动”，不能清楚表达录音、处理、成功、复制和错误的不同状态。

## 3. 设计原则

### 3.1 原生优先

- 使用系统 `.sidebar` List、统一 `NSToolbar` 和系统标题栏；主设置侧栏常驻且始终挂载，
  不再提供宽度归零或折叠动画。
- 使用系统字体、系统背景色、`controlBackgroundColor`、原生 Picker、Toggle 和 Button。
- 不模拟 iOS 大圆角面板，不叠加多层玻璃卡片，不自绘 traffic lights。
- 保留 macOS 的 Reduce Motion、Increase Contrast、VoiceOver 和键盘行为。

### 3.2 单一信息层级

```text
Window / Unified Toolbar
├── Sidebar（导航）
└── Detail（标题、说明、单层设置分组）
```

详情区采用无外框的单层设置分组，以原生行、分隔线和 DisclosureGroup 组织；页面标题
不在内容区重复，不再使用包住整页的巨型圆角卡片。

### 3.3 内容决定高度，容器决定宽度

- 文本允许垂直扩展，禁止通过缩小字体解决英文溢出。
- 标签与控件使用 `ViewThatFits`：宽窗口横排，窄窗口自动改为上下排列。
- 长选项优先 `.menu` Picker，不依赖固定宽度 Segmented Control。
- 所有说明文字使用 `fixedSize(horizontal: false, vertical: true)`。

## 4. 信息架构

侧边栏最终由十个同级项目收敛为五个可见入口。2026-07-15 之后的信息架构以
[Community Skills 核心计划](community-skills-core-next-step-plan-2026-07-15.md)
第 13 节为准：

| 入口 | 内容 |
| --- | --- |
| General | 应用语言、ChatGPT 连接、默认 Skill 摘要、听写与 Switcher 快捷键 |
| Input & Output | 听写、转写、标点、AI 转换、Paste & Clipboard |
| Context & Privacy | 当前可用 Context、权限、Style、Terminology 摘要、敏感应用、留存与删除 |
| Appearance & Feedback | Refined HUD、AI Activity Glow、Hidden、声音与通知 |
| Advanced | OpenAI-Compatible 恢复、已配置时的 Provider Safety / 更新与诊断 |

兼容性深链接保持有效：

- `Account` 归一到 `General`；
- `AI Polish` 与 `Paste` 归一到 `Input & Output`；
- `Terminology` 与 `Privacy` 归一到 `Context & Privacy`；
- 旧配置中的 Settings pane 值不会导致空白页；
- 新安装和未知 pane 均回到 `General`。

## 5. 窗口与布局规格

| 项目 | 规格 |
| --- | --- |
| 默认内容尺寸 | `980 × 680 pt` |
| 最小窗口尺寸 | `900 × 620 pt` |
| 侧边栏 | 常驻 `218 pt`，全高系统 `.thinMaterial`，与详情区以 `0.5 pt` 发丝线分隔 |
| 详情内容最大宽度 | `700 pt`，在详情画布内居中 |
| 详情水平内边距 | `36 pt` |
| 详情顶部 / 底部 | `30 / 44 pt` |
| 一级区块间距 | `16–20 pt` |
| 正文标题 | `24 pt semibold` |
| 设置行标题 / 说明 | `13 pt medium` / `11–12 pt secondary` |
| 品牌交互色 | `#0074FF`（RGB `0, 116, 255`） |
| 侧栏选中态 | 使用系统 `List(selection:)` 的原生持续选中态，跟随系统 Accent Color |

窗口使用透明原生标题栏、`.fullSizeContentView` 和 `.unified` 工具栏。主设置窗口采用
固定双栏 `HStack`：左侧是始终挂载的系统 `.sidebar` List 与全高 `.thinMaterial`，右侧
是最大 `700 pt` 的安静滚动内容列。侧栏没有 `sidebarToggle`、宽度归零、延迟挂载或
折叠动画，因此导航入口、traffic lights 和详情内容在窗口调整尺寸时都保持稳定。

## 6. 双语与语言切换

### 6.1 产品规则

- 语言入口仅存在于 Settings → General → App Language。
- 支持 `System Language`、`简体中文`、`English`。
- 修改后立即刷新菜单栏、Settings、HUD 文案和之后打开的窗口。
- 正在进行的录音 Session 继续使用录音开始时冻结的配置，不因语言切换中断。
- History、Terminology、Onboarding 等非当前窗口在下次打开时按新语言重建。

### 6.2 工程规则

- `L10n` 通过线程安全状态选择 `.lproj` Bundle，而不是读取一次后永久缓存。
- 英文为源码键，简体中文由 `zh-Hans.lproj/Localizable.strings` 覆盖。
- 配置缺失 `appLanguage` 时迁移为 `.system`。
- 所有新增可见文案必须通过本地化检查，禁止在 SwiftUI 视图中拼接不可翻译片段。

### 6.3 英文布局验收尺寸

至少覆盖：

- `900 × 620` 最小窗口；
- `980 × 680` 默认窗口；
- `1180 × 760` 宽窗口；
- 中文和英文各一组截图；
- 五个权威页面全部覆盖。

验收要求：无裁切、无重叠、无横向滚动、Toggle 和菜单 Picker 可见，五个导航入口始终可达。

## 7. AI Activity Glow

`AI Activity Glow` 是 Agent Presence Indicator，不是控件 Focus Ring。它表达：

> 当前显示器或聚焦窗口正在被 VibeWhisper 的 AI 输入流程使用。

### 7.1 视觉结构

```text
Ambient outer/inner glow
+ restrained core stroke
+ conic energy gradient
+ state-specific pulse
```

- Recording：蓝 / 冰蓝 / 青色缓慢流动，并随音量改变强度；
- Processing：靛蓝到青色的连续能量流，速度略快于录音；
- Success：绿色单次收束脉冲；
- Copied：琥珀色单次脉冲，并显示必要的复制原因文本；
- Error：红色双脉冲；
- Reduce Motion：取消旋转、呼吸和脉冲，只保留静态高对比状态边缘；
- Increase Contrast：增强核心描边和状态对比，不增加动画速度。

### 7.2 行为边界

- 非激活 `NSPanel`，不抢键盘焦点；
- `ignoresMouseEvents = true`，不阻断鼠标；
- 支持活动显示器和实验性的聚焦窗口目标；
- 多显示器时录音开始后冻结目标，避免光晕跳屏；
- 不截图、不实时模糊屏幕、不读取窗口正文；
- 旧配置值 `blueSignalFrame` 与旧启动参数继续迁移到 `aiActivityGlow`。

## 8. Logo 与菜单栏图标

品牌源文件：

`packaging/assets/VibeWhisperLogoSource.png`

生成规则：

- App Icon：彩色无限结置于原生浅色圆角方形底板；
- 状态栏图标：从同一轮廓生成透明单色 Template，不使用白色 App Icon 底板；
- `scripts/render_app_icon.swift` 统一生成 iconset、ICNS 和 `StatusBarLogoTemplate.png`；
- 打包检查验证资源存在、状态栏 PNG 为 `72 × 72` 且含 Alpha；
- 禁止分别手工修改 App Icon 和状态栏图标造成品牌漂移。

## 9. 实施映射

| 范围 | 主要实现 |
| --- | --- |
| Settings IA / 窗口 | `PreferencesWindowController.swift`、`SettingsWindowState.swift` |
| 响应式设置行 | `SettingsComponents.swift` |
| 动态语言 | `Localization.swift`、`AppConfig.swift`、`AppCoordinator.swift`、`StatusMenuController.swift` |
| Skills Library / Creator | `AINativeSettingsViews.swift`、`SkillCreatorSettingsView.swift` |
| Context Center | `ContextFabricRuntime.swift`、`ContextRuntime.swift` |
| Activity Glow | `VisualFeedback.swift`、`BlueSignalFrameController.swift`、`FeedbackSurfaceController.swift` |
| Logo / Icon | `VibeWhisperVisualSystem.swift`、`scripts/render_app_icon.swift`、`scripts/package_app.sh` |

## 10. 验收矩阵

### 10.1 自动化

- Settings pane 默认值、旧 pane 迁移、窗口 autosave；
- `AppLanguage` 配置迁移和往返；
- 中文本地化完整性；
- `blueSignalFrame → aiActivityGlow` 解码迁移和新值编码；
- Reduce Motion 下 Activity Glow 无连续动画；
- App Icon / 状态栏资源打包检查；
- Settings 中文 / 英文固定尺寸快照；
- Refined HUD / Activity Glow / Hidden 状态脚本。

### 10.2 安装版人工与脚本验收

1. 从 `/Applications/VibeWhisper.app` 启动，不从 `dist` 启动。
2. 打开 Settings，在最小尺寸检查全高侧栏和八个始终可见的导航入口。
3. 在 General 切换 English，检查标题、长说明、Picker、Toggle 和 Skills Inspector。
4. 切回简体中文，确认菜单栏和新开窗口同步。
5. 在 Appearance 依次预览 Refined HUD、AI Activity Glow、Hidden。
6. 验证 F5 开始 / F5 停止、Esc 取消、Retry、复制兜底和 TextEdit 插入。
7. 开启 Reduce Motion / Increase Contrast 后重复 Activity Glow 状态检查。
8. 检查 Dock、Finder、About/安装包和菜单栏使用同一无限结视觉身份。

## 11. 完成定义

源码完成必须同时满足：

- 不再使用会让英文重叠的固定主布局；
- 语言只在 General 中切换并立即生效；
- 侧边栏常驻、无折叠入口，并保持原生 List 的键盘、选中和 VoiceOver 语义；
- 设置页使用无巨型外框的单层分组视觉层级；
- Activity Glow 覆盖录音、处理、成功、复制、错误和无障碍状态；
- Logo 同步到 App Icon 与菜单栏 Template；
- 单元、打包、视觉、反馈和粘贴验收全部通过；
- 最终正常启动的 `/Applications/VibeWhisper.app` 保持运行，供产品复核。

## 12. 2026-07-15 实施与验收结果

当前规划范围已落地并通过以下本地门禁：

- `scripts/check.sh`：全部单元、集成、仓库卫生、打包和签名元数据检查通过；
- `scripts/settings_bilingual_acceptance.sh`：General、Appearance、AI Polish、
  Terminology & Context 在 `900 × 620`、`980 × 680`、`1180 × 760` 三档窗口下，
  简体中文与英文共 24 张安装版快照通过；未发现文字或控件重叠；随后补充的
  折叠回归修复会移除系统自动重排项，只保留一个窗口级原生标题栏附件按钮；
- 安装版侧栏坐标验收：收起与展开各连续采样 100 次，标题栏按钮均为 100/100 可见，
  `x/y` 固定为 `405/107`、命中区域固定为 `38 × 38`；侧栏入口数量按 `4 → 0 → 4`
  正常往返。展开后交通灯和按钮共同位于全高 `.sidebar` 材质内，符合 Apple Notes
  的窗口级标题栏布局；
- 展开卡顿根因复核：CPU 采样显示主线程大部分时间空闲，逐帧录屏进一步定位到
  `NavigationSplitView` 在展开末段才挂载侧栏 List 内容；同时存在的内层 `minWidth`
  约束会放大末段位移。主设置分栏改为“`224 pt` 侧栏始终挂载 + 外层宽度裁剪”后，
  多轮展开/收起中边界、图标、文字和选中态从首帧连续出现，不再发生末段内容跳入；
- 侧栏选中态按产品参考图落地：`#EFEFEF` 连续圆角背景搭配 `#0074FF` 图标和文字；
  同一品牌蓝已用于 SwiftUI 控件 tint、状态蓝和网站交互色；
- VibeWhisper 使用标准 `.regular` 激活策略并继续提供菜单栏入口；Dock 始终显示品牌
  App Icon，Settings 黄色按钮可原生最小化、从 Dock 恢复，并保持窗口状态一致；
- `scripts/visual_acceptance.sh --install`：Refined HUD 的录音、处理、确认插入、
  Paste Sent、Copied、Error、Retryable Error、Reduce Motion 与 Increase Contrast 通过；
- `scripts/feedback_mode_acceptance.sh`：Refined HUD、AI Activity Glow、Hidden
  三种模式状态语义一致；
- `scripts/accessibility_visual_acceptance.sh`：五个权威 Settings 页面及旧 deep-link
  兼容别名、Onboarding、History、Terminology、Quick Add 的默认与 Increase Contrast
  快照通过；
- `scripts/accessibility_acceptance.sh`：全部可操作控件具有可访问名称；
- `scripts/paste_acceptance.sh --install`：TextEdit 为 `inserted_verified` 且恢复原剪贴板，
  Terminal 为 `paste_dispatched` 且保留转写兜底；
- App Icon、状态栏 Template、ZIP、DMG 和已安装 App 均由同一无限结品牌源生成并通过
  签名与包完整性检查。

验收证据位于 `dist/settings-bilingual-acceptance/20260715T040723Z`、
`dist/visual-acceptance/20260714T183451Z`、
`dist/feedback-mode-acceptance/20260714T183519Z`、
`dist/accessibility-visual-acceptance/20260714T184044Z`、
`dist/accessibility-acceptance/20260715T040830Z` 和
`dist/paste-acceptance/20260714T183536Z`；侧栏固定位置证据位于
`dist/settings-sidebar-acceptance/20260715T034815Z`，Dock 图标与窗口最小化证据位于
  `dist/window-activation-acceptance/20260715T044820Z`。

## 13. 2026-07-16 产品复核修订

产品复核不再接受可折叠侧栏和整页大卡片方案。当前实现按 Apple Books 的窗口构图调整为：

- `216 pt` 常驻系统 List 侧栏，窗口内缩 `8 pt`，使用动态系统 Material 和 `22 pt` 圆角；
- 不提供隐藏/显示侧栏按钮，不保留 `0 pt` 侧栏状态；
- 详情页取消重复页面标题和整页巨型卡片，保留原生设置行与分隔线；
- Activity Glow 从 Recording 进入 Processing 时不再执行 hide/show，原 panel 连续可见；
- Processing 使用三层、`0.95 s` 半周期的明显呼吸动画，并在调试快照中明确记录
  `aiActivityGlowState == processing`。

本节取代第 12 节中关于折叠按钮、收起/展开坐标和自绘选中态的旧结论；旧证据仅作为
历史实现记录，不代表当前产品行为。

安装版证据：

- 中英文设置页在 `900 × 620`、`980 × 680`、`1180 × 760` 三档窗口尺寸的 24 张截图：
  `dist/settings-bilingual-acceptance/20260715T181526Z`；
- Refined HUD、AI Activity Glow、Hidden 与 Reduce Motion 状态验收：
  `dist/feedback-mode-acceptance/20260715T182454Z`，其中 Processing 快照明确验证
  `aiActivityGlowIsVisible == true`、`aiActivityGlowState == processing`。
- 完整安装版 HUD 状态与状态切换视觉验收：
  `dist/visual-acceptance/20260715T182432Z`。

## 14. 2026-07-18 克制极简视觉收敛

- 参考 Typeless 的黑白层级、短文案与留白节奏，但继续使用 macOS 原生控件和系统行为；
- Settings 从浮动圆角侧栏调整为全高系统材质侧栏，详情收窄为 `700 pt` 阅读列；
- 页面切换由横向滑动与缩放弹簧改为 `0.18 s` 的轻量淡入，减少设置操作时的视觉噪声；
- 设置分组取消渐变、重阴影与多层卡片，按钮使用单色填充，状态摘要改为无框行；
- History 与 Terminology 不再嵌套第二层 `NavigationSplitView`，避免标题栏出现重复的
  sidebar toggle；搜索、筛选和主要操作统一使用紧凑的系统 toolbar 密度；
- Skill 资料库移除三层嵌套导航，改为顶部分段选择器以及“Skill 列表 + 详情”双栏工作区，
  让浏览、检查和启用操作保持在同一视觉层级；
- Onboarding 移除三张装饰性功能卡，保留一列清晰说明；Refined HUD 改用系统
  `NSVisualEffectView.Material.hudWindow` 材质与更轻的边框、阴影，并固定深色
  Graphite 表面，确保浅色桌面上仍有稳定对比；
- History 与 Terminology 集成到 Settings 后，独立快照启动参数会回落到对应 Settings
  pane，避免继续等待已经移除的独立窗口控制器。

本轮安装版证据：

- Refined HUD 全状态：`dist/visual-acceptance/20260718T052104Z`；
- Refined HUD、AI Activity Glow 与 Hidden 一致性：
  `dist/feedback-mode-acceptance/20260718T052129Z`；
- 中英文三档 Settings：`dist/settings-bilingual-acceptance/20260718T052230Z`；
- Settings、Onboarding、History、Terminology 与 Quick Add 的默认 / Increase Contrast
  矩阵：`dist/accessibility-visual-acceptance/20260718T052959Z`。
