# OpenWhisper macOS 产品化改造计划

> 日期：2026-07-13
> 状态：执行版 v1
> 范围：只启动 macOS 产品线
> 当前版本：`0.1.0 Alpha`
> 输入依据：安全审计、UI 对标调研、产品与商业化分析

## 1. 执行结论

OpenWhisper 的第一阶段目标不是快速堆功能，而是把现有的原生语音输入闭环改造成一款可以持续发布、可被用户信任、可支持商业化的 macOS 产品。

核心闭环保持不变：

```text
聚焦输入框
→ F5 开始录音
→ F5 停止录音
→ 转写
→ 术语保护与按需润色
→ 重新确认当前输入目标
→ 安全回填或保留到剪贴板
```

macOS 首发策略：

1. 只做 Mac，不并行启动 Windows、iOS、Android。
2. 先关闭安全、隐私和发布完整性阻断项，再扩大测试用户。
3. 保留原生 AppKit + SwiftUI 技术路线，不重写为跨平台壳。
4. 保留 `F5` 单触发工作流和现有 HUD 识别度。
5. Settings、Onboarding、History、Terminology 按标准 macOS 信息架构重做。
6. 免费核心交付完整听写闭环；付费功能只销售高级桌面工作流。
7. 默认账户路径必须明确上游依赖，不承诺稳定公开 API、无限用量或企业 SLA。
8. 第一个可售版本必须完成 Developer ID 签名、公证、更新、安全门禁和数据删除能力。

## 2. 当前基线

### 2.1 已具备能力

- 原生 macOS 菜单栏应用。
- AppKit + SwiftUI 界面。
- 全局 `F5` 开始、再次 `F5` 停止。
- 麦克风录音、HUD 状态、取消和 Retry。
- 浏览器连接 ChatGPT，Keychain 保存会话。
- 默认账户转写路径。
- OpenAI-Compatible 高级恢复路径。
- 本地术语、确定性纠错和文本导入。
- 可选 AI Polish。
- 自动粘贴与剪贴板兜底。
- 历史、失败音频 Recovery、延迟日志。
- 英文和简体中文 UI。
- Swift 单元测试、打包脚本和安装版验收脚本。

### 2.2 当前阻断项

安全审计确认的主要问题：

- 旧启动上下文可以放宽粘贴条件。
- Managed Token 可以被配置发送到任意 URL。
- Recovery 元数据存在路径逃逸风险。
- Token refresh 存在竞态和注销后会话复活风险。
- 录音时长上限未真正执行。
- 音频、全文和日志缺少合理默认留存策略。
- OAuth callback 存在崩溃、取消和超时生命周期问题。
- 签名、Gatekeeper、Cask 哈希和安装链不闭环。
- 技术字面量可能被归一化破坏。
- MainActor、旧异步任务和 HUD 回调存在跨会话污染风险。
- 当前测试可能在未完成真实 TCC/GUI 验收时仍显示全绿。

UI 调研确认的主要问题：

- Settings 更像桌面 Web 管理台，不像标准 macOS Settings。
- 首次使用和权限修复混入过多工程诊断信息。
- History 和 Terminology 只是设置页中的有限预览。
- HUD 不同状态宽度跳变，错误停留时间不足。
- Reduce Motion、Increase Contrast、VoiceOver 覆盖不完整。
- 代码、视觉规范、截图和视觉测试不是同一事实源。

商业化分析确认的主要约束：

- 不能销售或承诺上游模型额度。
- 不能把未公开账户路径包装成企业 SLA。
- 商业价值应来自原生客户端、工作流、个性化、签名更新、支持和团队能力。
- 订阅只能对应真实持续服务，例如同步、团队管理和持续模板服务。

## 3. 产品定义

### 3.1 品类

> 面向 Mac 知识工作者的原生全局语音输入层。

### 3.2 核心用户

第一阶段只聚焦：

- 开发者和 AI Coding 用户；
- 产品经理、创始人、研究者和内容工作者；
- 中英文混输频繁的人；
- 每天在多个应用中输入大量长文本的人；
- 已有 ChatGPT 账户、不想再维护复杂模型配置的人。

### 3.3 核心价值

- 快：无需切换编辑器或聊天窗口。
- 准：术语、产品名、路径和技术字面量得到保护。
- 稳：失败保留录音和文本，可恢复。
- 安全：不能证明目标可写时不自动粘贴。
- 透明：上游、隐私、费用和恢复边界写清楚。

### 3.4 近期不做

- Windows、iOS、Android 客户端。
- 会议机器人、多人分轨和会议纪要平台。
- 常驻监听和唤醒词。
- 通用自动化/RPA。
- 企业知识库和复杂团队后台。
- 默认 onboarding 中的本地模型管理。
- 多 Provider 市场。
- 依赖未公开账户路径的企业可用性承诺。

## 4. 产品身份与仓库治理

### 4.1 统一身份

产品身份以 `docs/product/brand-identity.md` 为准：

- 名称：`OpenWhisper`
- Bundle ID：`app.openwhisper.mac`
- 可执行文件：`OpenWhisper`
- 安装路径：`/Applications/OpenWhisper.app`
- 数据目录：`~/Library/Application Support/OpenWhisper/`
- Keychain：`app.openwhisper.mac.ChatGPTSession`
- 环境变量：`OPENWHISPER_*`
- Release：`OpenWhisper-<version>-macos-<arch>`

### 4.2 品牌发布门禁

在任何付费公开发布前完成：

- 名称与商标可用性检索；
- 域名、GitHub、社交账号和支持邮箱确认；
- Apple Developer Bundle ID 注册；
- 产品图标和菜单栏图标最终定稿；
- 中英文名称、口号和独立项目声明定稿；
- MIT 许可证原始版权与许可声明保留；
- 第三方依赖许可证清单生成。

### 4.3 仓库目标结构

当前第一轮已经按文档职责整理。代码在第二轮改造成 feature-first：

```text
Sources/OpenWhisper/
  App/
    AppDelegate.swift
    AppCoordinator.swift
    ProductIdentity.swift
  DesignSystem/
    Colors.swift
    Typography.swift
    Icons.swift
    Layout.swift
  Features/
    Onboarding/
    Dictation/
    Settings/
    History/
    Terminology/
    Recovery/
  Core/
    Auth/
    Audio/
    Providers/
    Insertion/
    Storage/
    Metrics/
  Infrastructure/
    Keychain/
    Accessibility/
    Networking/
    Updates/
    Licensing/
```

重组原则：

- 先建立模块边界和测试，再移动文件。
- 不在安全修复期间同时做无关的大规模移动。
- 每次移动保持编译和测试可运行。
- UI 与业务逻辑分离，Provider 与 Auth 分离，Storage 与 View 分离。

## 5. 目标 macOS 产品架构

### 5.1 产品表面

最终保留六个明确表面：

1. **Menu Bar**
   - 当前状态；
   - Start/Stop 提示；
   - History；
   - Terminology；
   - Settings `⌘,`；
   - Quit `⌘Q`。
2. **Dictation HUD**
   - Recording；
   - Processing；
   - Pasted；
   - Copied；
   - Error；
   - Retryable Error。
3. **Onboarding**
   - Welcome；
   - Connect；
   - Microphone；
   - Paste & Practice。
4. **Settings**
   - General；
   - Account & Permissions；
   - Dictation；
   - AI Polish；
   - Paste；
   - Privacy；
   - Advanced & Diagnostics。
5. **History**
   - 搜索、筛选、详情、复制、重试、删除和音频播放。
6. **Terminology**
   - 搜索、新增、编辑、导入、导出、启停和 Quick Add。

### 5.2 核心状态机

建立单一 `DictationSession` 状态机：

```text
idle
→ requestingPermission
→ recording(sessionID)
→ stopping(sessionID)
→ transcribing(sessionID)
→ polishing(sessionID)?
→ preparingInsertion(sessionID)
→ inserted | copied | recoverableFailure | terminalFailure
→ idle
```

所有异步结果必须携带 `sessionID` 或 generation。只有当前 session 可以：

- 修改 HUD；
- 写入历史；
- 更新 Retry；
- 执行粘贴；
- 删除音频；
- 修改菜单栏状态。

### 5.3 Provider 边界

```swift
protocol TranscriptionProvider {
    var identity: ProviderIdentity { get }
    func transcribe(_ audio: RecordedAudio, context: TranscriptionContext) async throws -> Transcript
}
```

Provider 必须明确区分：

- Managed account route；
- User-owned API route；
- 未来的本地模型 route。

Managed Token 只能由 Managed Provider 使用，并且只能访问编译时或签名配置中的 HTTPS allowlist。用户可编辑 endpoint 只能与用户自己的 API Key 配对。

### 5.4 数据边界

```text
Keychain
  ChatGPT session
  Compatible provider keys

Application Support/OpenWhisper
  config.json
  history.jsonl / database
  recovery metadata
  failed audio with TTL
  rotating diagnostics
```

默认策略：

- 成功音频：转写结束后删除；
- 失败音频：保留 24 小时，可配置；
- 文本历史：默认开启，但有数量和时间上限；
- 敏感应用：默认不写历史；
- 日志：不写 Token、完整音频、完整剪贴板或完整账户标识；
- 用户可一键删除全部数据并退出登录。

## 6. 安全改造工作流

### 6.1 P0：必须先关闭

#### OW-SEC-001 安全粘贴

实现：

- `launchAppContext` 仅用于尝试恢复前台应用。
- 录音开始时记录 PID、bundle ID、进程启动标识、窗口和 focused element 摘要。
- 粘贴前重新读取 frontmost app 和 focused AX element。
- 只有当前 focused element 明确可写时发送 `Cmd+V`。
- Retry 默认只复制，除非用户重新建立可编辑焦点。
- 将“已发送粘贴事件”和“已确认插入”分成不同结果。

验收：

- 无焦点、只读、按钮、密码框、窗口切换、进程重启时均不发送粘贴事件。
- 失败结果完整留在剪贴板。
- 自动化测试和真实 TextEdit/Notes/Terminal 场景均通过。

#### OW-SEC-002 Managed Token 目标白名单

实现：

- Managed provider 不读取普通配置中的 URL。
- scheme 必须是 HTTPS。
- host、port、path 和重定向目标进入 allowlist。
- URLSession 默认拒绝跨 origin 重定向携带 Authorization。
- User-owned endpoint 使用独立 Keychain API Key。

验收：

- 任意配置不能让 Managed Token 到达测试服务器。
- 非 allowlist URL 在请求创建前失败。
- 重定向不能带出 Authorization、音频或全文。

#### OW-SEC-003 Recovery 路径约束

实现：

- Recovery 只保存 opaque record ID，不信任任意文件名。
- 读取前标准化路径、解析符号链接，并验证包含关系。
- 音频文件使用随机 ID 和固定扩展名。
- 元数据损坏时隔离记录，不上传任何文件。

验收：

- `..`、绝对路径、符号链接和大小写变体都无法逃逸。
- Fuzz 测试覆盖损坏 JSONL 和异常路径。

#### OW-SEC-004 Auth single-flight 与 generation

实现：

- Auth 状态由 actor 管理。
- 同一时刻最多一个 refresh。
- 每次登录、刷新、退出生成新的 session generation。
- 迟到结果只有 generation 匹配时才能写 Keychain。
- 401 只触发一次刷新和一次原请求重试。

验收：

- 并发 20 个 refresh 只产生一个网络请求。
- Sign out 后迟到 refresh 不会恢复会话。
- 新登录不会被旧 refresh 覆盖。

### 6.2 P1：隐私与生命周期

#### OW-SEC-005 录音硬上限

- 录制层使用单调时钟执行硬上限。
- 到时自动停止并进入转写或明确失败。
- 上传前检查时长和大小，但不能只依赖上传前检查。
- 设置页显示上限和实际行为。

#### OW-SEC-006 OAuth callback 安全

- 重复 query 参数返回可理解错误，不崩溃。
- 只有匹配 state、path 和 method 的请求能结束流程。
- 取消、超时、浏览器关闭都释放 listener 和 continuation。
- callback 页面不显示 Token 或敏感参数。

#### OW-SEC-007 剪贴板所有权

- 记录 pasteboard change count。
- 只在 change count 未变化时恢复旧剪贴板。
- 默认继续保留最新转写，除非用户主动开启恢复。

#### OW-SEC-008 发布完整性

- 解析环境文件时禁止执行任意 shell 内容。
- 固定 Developer ID 和 Team ID。
- Gatekeeper 任意失败均阻断。
- 安装前检查 bundle ID、签名、架构和版本。
- 安装使用 staging、原子替换和失败回滚。
- Cask 使用固定 SHA-256。

## 7. 原生 UI 与交互改造

### 7.1 Settings

目标：标准 macOS Settings，而不是自绘管理台。

实现：

- `NavigationSplitView + List(selection:)`。
- detail 使用 `Form`、`Section`、`LabeledContent`。
- 窗口可调整，保存 frame 和最后 pane。
- Toggle/Picker 即时保存。
- 高风险文本字段失焦或提交时校验。
- 删除全局 Save footer。
- Config Folder、签名和 TCC 诊断只放 Advanced。

验收：

- 键盘方向键、Tab、VoiceOver 可完整操作。
- 最小窗口尺寸下英文和简中不裁切。
- 修改保存状态明确，不存在模糊的全局保存。

### 7.2 Onboarding

四步：

1. Welcome：解释 F5 工作流和上游边界。
2. Connect：浏览器连接 ChatGPT。
3. Microphone：用户点击后才触发系统权限请求。
4. Paste & Practice：Accessibility 可选，提供真实练习输入框。

原则：

- Microphone = required。
- Accessibility = recommended。
- 未授权 Accessibility = Clipboard Mode，不是应用不可用。
- 首次流程不展示安装路径、clean TCC、签名和内部端点。

### 7.3 HUD

- Recording/Processing/Success 使用稳定宽度。
- Actionable error 保持到用户操作。
- 瞬时 error 至少停留 4–6 秒。
- Reduce Motion 下停止高频 traveling animation。
- Increase Contrast 下提高边框、图标和文本对比。
- 状态变化发送 VoiceOver announcement。
- 位置和显示器选择逻辑覆盖多屏、全屏和 Space。

### 7.4 History

从 Settings 拆成独立窗口：

- toolbar 搜索、日期和状态筛选；
- List/Table 展示时间、应用、状态和摘要；
- detail 展示原始文本、最终文本、错误和音频；
- Copy、Retry、Reveal、Delete；
- 自动增量刷新；
- 敏感应用记录清晰标记或不落盘。

### 7.5 Terminology

- 完整列表而不是前几条预览；
- term 和 correction 分型；
- 搜索、排序、启停、编辑、删除；
- 导入预览、冲突检测、导出；
- Quick Add 全局面板；
- 常规用户不需要编辑 `config.json`。

## 8. 性能与可靠性

### 8.1 目标指标

首轮目标值用于产品验收，不作为公开 SLA：

| 指标 | Alpha 目标 | Beta 目标 |
| --- | ---: | ---: |
| 首次成功听写率 | ≥ 80% | ≥ 95% |
| Retry 后成功率 | ≥ 95% | ≥ 99% |
| ≤10 秒音频 warm P50 | ≤ 6 秒 | ≤ 5 秒 |
| 崩溃自由会话 | ≥ 98.5% | ≥ 99.5% |
| 错误自动粘贴 | 0 | 0 |
| Sign out 后会话复活 | 0 | 0 |
| 成功音频超期留存 | 0 | 0 |

### 8.2 Text Polish 决策

建立 `TextPolishDecisionEngine`：

- 短句默认直接输出；
- 长段、Agent Plan、Email 等模式按规则润色；
- 技术字面量先标记保护；
- 润色失败永远回退到可用 ASR；
- 记录 decision reason、耗时和 fallback 原因；
- 不记录完整敏感文本到分析事件。

### 8.3 Provider 健康与熔断

- 401：刷新一次，失败后要求重新连接。
- 403：停止密集重试，保留音频，提示恢复路径。
- 429：尊重服务端等待信息并显示可重试时间。
- 404/Schema 变化：禁用对应能力并提示更新。
- 5xx/网络错误：有限指数退避和抖动。
- 大范围故障：远程或本地 kill switch 停止继续发送。

## 9. 隐私、数据和遥测

### 9.1 用户控制

Settings 新增 Privacy：

- 保存文本历史；
- 保存失败音频；
- 失败音频 TTL；
- 历史保留天数/条数；
- 敏感应用列表；
- 导出数据；
- 删除历史；
- 删除全部数据并退出登录。

### 9.2 最小遥测

如果启用产品指标，只允许记录：

- 安装/启动版本；
- onboarding 步骤完成；
- 听写开始、成功、失败类别；
- 大致音频时长桶；
- 粘贴或剪贴板结果；
- provider 类别；
- 延迟桶；
- crash 标识。

禁止记录：

- 音频；
- 转写全文；
- 剪贴板内容；
- Token；
- 邮箱、账号 ID；
- 目标文档内容；
- 完整文件路径；
- 未经脱敏的错误响应体。

默认策略应在隐私文档和 UI 中保持一致。

## 10. 签名、安装、更新和 CI/CD

### 10.1 构建通道

| 通道 | 签名 | 用途 |
| --- | --- | --- |
| Dev | ad-hoc 或本地开发证书 | 单机开发，不对外分发 |
| Internal Alpha | 固定开发/Developer ID | 小规模内测 |
| Closed Beta | Developer ID + notarization | 外部邀请测试 |
| Stable | Developer ID + notarization + signed updater | 商业发布 |

### 10.2 CI 门禁

PR：

- Swift build/test；
- lint/format；
- secret scan；
- dependency license scan；
- localization key consistency；
- docs links；
- landing content contract。

Release：

- clean checkout；
- 固定 Xcode/macOS runner；
- build archive；
- codesign verify；
- notarize/staple；
- Gatekeeper assess；
- ZIP/DMG 重装验证；
- 生成 SHA-256 manifest；
- 更新 Cask；
- installed-app smoke；
- 产物和符号归档。

### 10.3 更新系统

稳定版需要：

- 签名更新清单；
- 分通道更新；
- 强制最低安全版本能力；
- 失败回滚；
- 更新前后数据兼容测试；
- release notes 中英文同步。

具体 updater 方案在关闭安全 P0 后选型，避免过早耦合。

## 11. 商业版本设计

### 11.1 Community

永久免费核心：

- 连接和基础转写；
- F5 工作流；
- 安全粘贴和剪贴板兜底；
- 基础术语；
- Retry；
- 隐私控制和删除数据；
- 高级恢复路径；
- 安全更新。

不得限制：

- 基础听写次数；
- 安全粘贴；
- 失败恢复；
- 数据删除；
- 严重安全修复。

### 11.2 Pro

一次性购买销售新增桌面效率能力：

- 应用感知 Voice Modes；
- 项目级词库；
- 高级 History；
- Quick Add；
- 指令模式；
- 高级自动化和自定义；
- 多设备许可证。

代码边界：

```text
OpenWhisperCore        MIT 核心
OpenWhisperPro         商业模块
OpenWhisperLicensing   许可证与收据
```

在开始 Pro 编码前先确认开源/闭源仓库边界、构建方式和贡献规则。

### 11.3 订阅与团队

近期不启动。只有存在真实持续服务时才考虑：

- 加密同步；
- 配置备份；
- 团队共享词库；
- MDM 与席位管理；
- 持续模板服务；
- 公共 API 或自营基础设施。

## 12. 版本路线图

### Phase 0：身份与仓库基线（已启动）

目标：形成单一 OpenWhisper 产品身份。

完成标准：

- Swift target、包、Bundle、路径、Keychain、脚本和文档统一；
- 旧发布素材和过时截图移除；
- MIT License 保留；
- `0.1.0` Alpha 基线可构建、安装和运行；
- 三份输入报告纳入新的文档结构。

### Phase 1：安全阻断项（第 1–2 周）

- OW-SEC-001 至 OW-SEC-004；
- URL 强校验；
- 安全粘贴；
- Recovery containment；
- Auth actor/single-flight；
- 对应回归和动态 PoC。

退出条件：所有 P0 关闭，PoC 无法复现。

### Phase 2：隐私与状态机（第 3–4 周）

- DictationSession generation；
- 录音硬上限；
- OAuth 生命周期；
- clipboard ownership；
- 成功音频删除；
- 历史与日志留存；
- Delete All Data。

退出条件：隐私默认值与文档一致，迟到异步结果不能污染新会话。

### Phase 3：原生体验（第 5–7 周）

- Settings 原生化；
- 4 步 Onboarding；
- HUD 稳定尺寸和可访问性；
- History 独立窗口；
- Terminology Manager；
- 简中/英文 layout pass。

退出条件：clean TCC 新用户可完成首次成功听写，关键流程可键盘和 VoiceOver 操作。

### Phase 4：分发基础（第 8–9 周）

- Developer ID；
- notarization/staple；
- fail-closed release scripts；
- SHA-256；
- updater 选型与最小实现；
- crash diagnostics；
- 隐私、条款和支持文档。

退出条件：全新 Mac 可下载、验证、安装、更新和卸载。

### Phase 5：Closed Beta（第 10–12 周）

- 30–50 名目标用户；
- 首次成功漏斗；
- 延迟和失败分类；
- 真实 App 兼容矩阵；
- 支持工单分类；
- 上游故障演练；
- 0.2.x Beta。

退出条件：Beta 指标达标，无未关闭 P0/P1 发布阻断项。

### Phase 6：Founder Pro（第 13–16 周）

- License Manager；
- Direct/Reply/Email/Agent Plan；
- 项目词库；
- 高级 History；
- 退款和支持流程；
- 价格验证；
- 0.5.x Release Candidate。

退出条件：付费理由来自工作流价值，不是上游额度承诺。

### Phase 7：1.0 商业发布

只有同时满足以下条件才发布：

- 安全和隐私门禁全部通过；
- 稳定签名、公证和更新；
- 崩溃自由会话与成功率达标；
- 退款、支持、条款和隐私完成；
- 品牌名称完成公开发布清查；
- 上游故障时存在可用恢复路径；
- 安装版真实流程验收通过。

## 13. 统一 Backlog

| ID | 优先级 | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- | --- |
| OW-MAC-001 | P0 | 安全粘贴重构 | AX inspector | 无可编辑焦点时零粘贴事件 |
| OW-MAC-002 | P0 | Managed endpoint allowlist | Provider split | Token 无法到达自定义 origin |
| OW-MAC-003 | P0 | Recovery containment | Storage API | 路径逃逸和符号链接测试通过 |
| OW-MAC-004 | P0 | Auth actor/single-flight | Session generation | 注销后无会话复活 |
| OW-MAC-005 | P1 | DictationSession 状态机 | 001/004 | 旧回调不修改新 session |
| OW-MAC-006 | P1 | 录音硬上限 | AudioRecorder | 到时自动停止且资源释放 |
| OW-MAC-007 | P1 | 数据留存与 Delete All | Storage service | 成功音频不长期保留 |
| OW-MAC-008 | P1 | OAuth 生命周期 | BrowserAuthBridge | 重复参数/取消/超时不崩溃不挂起 |
| OW-MAC-009 | P1 | Settings 原生化 | Config API | resize、键盘、VoiceOver、即时保存 |
| OW-MAC-010 | P1 | Onboarding | Permission model | clean TCC 首次成功闭环 |
| OW-MAC-011 | P1 | HUD a11y 和稳定几何 | Design tokens | 状态不横跳，错误可操作 |
| OW-MAC-012 | P1 | History window | Retention | 搜索、详情、Copy、Retry、Delete |
| OW-MAC-013 | P1 | Terminology manager | Dictionary model | 常规管理不编辑 JSON |
| OW-MAC-014 | P1 | Release fail-closed | Signing identity | Gatekeeper/签名失败阻断 |
| OW-MAC-015 | P1 | Notarization + updater | 014 | 新机安装和更新成功 |
| OW-MAC-016 | P2 | Product metrics | Privacy spec | 无敏感内容事件 |
| OW-MAC-017 | P2 | Voice Modes | Text polish engine | Direct 无额外延迟 |
| OW-MAC-018 | P2 | License Manager | Commercial boundary | 离线宽限与设备限制可恢复 |
| OW-MAC-019 | P2 | App compatibility matrix | Closed Beta | 目标 App 成功/降级明确 |
| OW-MAC-020 | P2 | Support diagnostics bundle | Redaction | 导出包无 Token/正文/音频 |

## 14. 第一执行 Sprint（10 个工作日）

### Day 1–2

- 冻结 OpenWhisper identity；
- 建立 `ProductIdentity` 一致性测试；
- 重置 `0.1.0` Alpha；
- 清理安装、LaunchAgent、Application Support 和 TCC 的本地旧状态；
- 为四个 P0 建立可重复 PoC 测试。

### Day 3–4

- 拆分 Managed Provider 与 User-owned Provider；
- 实现 URL allowlist 和 redirect policy；
- 增加 Token 泄露负向测试。

### Day 5–6

- 重构安全粘贴决策；
- 发送粘贴前重新检查 focus/window/process；
- 添加 TextEdit、Notes、Terminal 和无焦点验收矩阵。

### Day 7

- Recovery opaque ID、路径标准化和符号链接防护；
- 路径 fuzz 测试。

### Day 8–9

- Auth actor、single-flight、generation 和 logout invalidation；
- 并发测试与 401 重试限制。

### Day 10

- 全量 build/test/package/install；
- 运行动态 PoC；
- `/Applications/OpenWhisper.app` 真实权限与输入验收；
- 输出 Alpha 0.1.0 安全基线报告。

Sprint 完成定义：

- 四个 P0 均有失败前测试和修复后测试；
- 安装版仍能完成 F5 录音和 paste-or-copy；
- 无新旧身份混用；
- 未关闭问题进入 backlog，不以“测试全绿”替代真实验收。

## 15. 产品指标与决策门槛

### 15.1 激活漏斗

```text
下载
→ 首次启动
→ 完成连接
→ 麦克风授权
→ 第一次录音
→ 第一次转写成功
→ 第一次安全回填/复制
→ 第 5 次成功听写
→ 第 7 日仍活跃
```

### 15.2 North Star

> 每周成功完成并被用户实际采用的语音输入次数。

不能只统计“接口返回成功”，还需要区分：

- pasted；
- copied；
- user retried；
- discarded；
- failure category。

### 15.3 Go / No-Go

Closed Beta Go：

- P0 全部关闭；
- 首次成功率 ≥80%；
- 错误自动粘贴为 0；
- 数据删除可验证；
- 安装版可重复通过。

Founder Pro Go：

- Beta 首次成功率 ≥95%；
- Retry 后 ≥99%；
- 崩溃自由会话 ≥99.5%；
- 第 7 日留存和访谈证明用户愿为工作流付费；
- 上游故障不会导致付费能力完全不可用。

1.0 Go：

- 稳定签名、公证、更新和回滚；
- 隐私、条款、退款、支持完成；
- 品牌和商业边界复核完成；
- 无未关闭 P0/P1 release blocker。

## 16. 风险清单

| 风险 | 概率 | 影响 | 应对 |
| --- | ---: | ---: | --- |
| 上游私有路径变化 | 高 | 严重 | Provider 抽象、熔断、恢复路径、快速更新 |
| 账户限制或 OAuth 变化 | 中高 | 严重 | 降低重试、明确边界、准备 BYOK/本地替代 |
| 品牌名称冲突 | 中 | 高 | 付费公开发布前完成 clearance |
| TCC/签名不稳定 | 中 | 高 | 固定 Developer ID、安装路径和真实验收 |
| 音频/文本隐私事故 | 中 | 严重 | 默认删除、最小留存、敏感 App 策略 |
| 自动粘贴到错误目标 | 中 | 严重 | 每次重新验证、无法证明即复制 |
| 支持成本过高 | 高 | 中高 | Onboarding、诊断导出、错误分类、兼容矩阵 |
| MIT 核心被复制 | 高 | 中 | 品牌、签名、更新、Pro 工作流、支持与社区 |
| 过早多平台扩张 | 中 | 高 | 1.0 前只做 macOS |

## 17. 完成定义

OpenWhisper macOS “产品化完成”不是代码能运行，而是同时满足：

- 单一、清晰、可注册的产品身份；
- 安全审计 P0/P1 发布阻断项关闭；
- 用户可理解并控制数据；
- 原生 Settings、Onboarding、HUD、History 和 Terminology；
- 可签名、公证、安装、更新、回滚；
- 真实 installed-app 权限与输入流程验收；
- 中英文文案、隐私、条款、支持和退款一致；
- 上游失败时有明确恢复和停止策略；
- 商业收费对应新增工作流，而非未控制的模型额度。

最终原则：

> 先把 OpenWhisper 做成一款快、稳、准、可信的 Mac 输入工具，再考虑更多平台、团队功能和规模化商业化。
