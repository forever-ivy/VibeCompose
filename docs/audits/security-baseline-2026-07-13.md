# VibeCompose macOS 安全基线

> 日期：2026-07-13
> 产品版本：`0.1.0 Alpha`
> 基线对象：本报告所在提交对应的 VibeCompose 产品化工作树
> 原始输入：[逻辑与安全审计报告](security-audit-2026-07-13.md)
> 报告性质：修复后基线；不改写原始审计快照，也不代表已经满足签名公开分发门禁

## 1. 结论

当前代码已经关闭原始审计中最直接的四个核心信任边界问题：

1. 旧 `launchAppContext` 不能再单独放行自动粘贴；
2. Managed ChatGPT Token 只能发送到内置的 HTTPS origin/path；
3. Recovery 元数据不能选择任意文件路径；
4. 并发 refresh 被合并，Sign out 会让迟到结果失效。

本轮产品化工作进一步建立了数据生命周期基线：

- 成功录音处理后删除，不再进入 Recovery；
- 失败录音默认保留 24 小时、最多 10 条；
- 文本历史默认保留 30 天、最多 500 条；
- 原始 ASR 文本默认不保存；
- 诊断默认保留 14 天、最多 1,000 条；
- 已知密码管理器、Keychain 和 Passwords 默认不落历史和恢复音频；
- Retry 有有效期，启动时清理孤儿文件；
- Public Alpha 只暴露 ChatGPT OAuth 路径，Provider 选择和 API Key 配置不进入首版界面；
- Settings 提供“删除全部数据并退出登录”，同时删除 ChatGPT 会话和遗留凭据。

后续可靠性加固又关闭了四个实现级缺口：

- 转写上传先通过 `open(O_NOFOLLOW)` 与 `fstat` 检查普通文件、大小、device/inode，再以 64 KB 分块生成 `0600` multipart 临时文件并通过 file upload 发送；
- URL、邮箱、路径、文件名、版本、IP、UUID、hash、命令参数和代码片段在语言/标点转换及 AI Polish 前被 token 化保护，模型必须逐一原样返回 token；
- 粘贴目标等待改为可取消异步时钟，不再用同步 sleep 阻塞 MainActor；
- 录音、处理中音频和 multipart 在初始化失败、启动失败、上传失败、取消、退出和下次启动时均有归属明确的清理路径。

Provider 可靠性层进一步把 401/403 challenge/429/接口变化/5xx/网络/无效响应
拆为有限类别：认证只刷新一次，限流尊重 `Retry-After`，暂时故障使用有上限退避，
Managed ASR、Recovery ASR 与 AI Polish 分 route 熔断；half-open 探测取消后会释放
探测占用，不会永久阻塞后续请求。诊断只记录类别，不保存响应正文。

发布门禁自身也补齐了临时文件生命周期：转写测试创建的 10–25 MB
音频 fixture 现在全部通过 `defer` 删除，完整 `scripts/check.sh` 前后不会新增
大体积临时 WAV；打包脚本在签名前使用 `plutil -lint` 校验 entitlement plist。

**仍不能公开声明为已完成签名公开分发。** 真实 Developer ID/公证证据、完整原生首次体验、生产 Updater 与 Capability Policy 托管/密钥及更新回滚/事故演练实证、明确支持联系人以及若干残余可靠性问题尚未关闭。

## 2. 基线状态

状态定义：

- **关闭**：现有实现和针对性测试共同证明原始利用路径已失效；
- **部分关闭**：核心风险已降低，但原始要求仍有未完成子项；
- **开放**：尚无足够证据证明问题关闭。

| 审计 ID | 状态 | 当前证据 | 残余工作 |
| --- | --- | --- | --- |
| OW-AUD-001 错误目标自动粘贴 | 部分关闭 | `TextInjector.injectionPlan` 不再把旧启动上下文视为可编辑证明；Retry/Recovery Retry 强制复制；发送前重新检查当前可编辑焦点与同一 AX target；发送后用 AX value/range 前后快照区分 `inserted_verified`、`paste_dispatched` 和 `clipboard`，无法确认时保留转写剪贴板；安装版 TextEdit 已观察到 `inserted_verified`；隔离 Terminal 使用一次性无历史 HOME 执行生成 proof，稳定得到 `paste_dispatched`、转写保留和验收前剪贴板恢复 | 需完成不读取/修改个人数据的 Notes 手动矩阵及第三方编辑器矩阵；不支持可靠 AX 文本快照的目标应稳定落入 `paste_dispatched`，不能误报已确认插入 |
| OW-AUD-002 Managed Token 任意 endpoint | 关闭 | `ManagedEndpointPolicy` 固定 `https://chatgpt.com` 两个 path；拒绝 query、fragment、userinfo、非 443 端口；`SecureHTTPClient` 拒绝重定向；自定义 endpoint 只使用独立 Keychain API Key；`OPENAI_API_KEY` 单独存在不能启用或授权 Recovery | 继续保留 managed/user-owned credential 隔离和重定向回归测试 |
| OW-AUD-003 Recovery 路径逃逸 | 关闭 | 记录只持久化 UUID；文件名由 UUID 派生；Recovery 根目录、JSONL index、Audio 目录与音频文件均检查 symlink；同时检查普通文件、包含关系、25 MB 与 RIFF/WAVE 头；启动时把遗留音频权限收紧为 `0600` | 增加更大规模损坏 JSONL/path fuzz 作为持续门禁 |
| OW-AUD-004 refresh 竞态/注销复活 | 关闭 | `RefreshFlight` 合并并发 refresh；generation 与原 refresh token 双重提交校验；Sign out 取消 flight 并递增 generation | 可进一步迁移到 actor，减少锁式状态管理复杂度 |
| OW-AUD-005 录音上限/大文件内存 | 关闭 | `AudioRecorder` 使用 deadline task 硬停止；`ChatGPTTranscriber` 通过 `O_NOFOLLOW` + `fstat` 在读取内容前拒绝空文件、非普通文件和超过 25 MB 的文件，并对 device/inode/size 二次校验；multipart 以 64 KB 分块写入 `0600` 临时文件并用 `URLSession.upload(fromFile:)` 发送 | 真实慢磁盘、网络取消和系统低磁盘空间仍纳入安装版压力测试，但不再存在整段音频与 multipart 同时驻留内存的原始路径 |
| OW-AUD-006 成功音频与全文持久化 | 关闭 | 成功路径不再写 Recovery；raw ASR 默认关闭；History/Recovery/Diagnostics 按时间与数量轮转；敏感 App 排除；Delete All Data；中英文隐私政策已披露最终文本、失败音频和诊断默认留存 | 在公开发布前补齐长期社区隐私联系人 |
| OW-AUD-007 OAuth callback 生命周期 | 关闭 | 校验 method/path/state；重复 query 返回 400 且不会结束合法等待；timeout/cancel 会停止 listener 并释放 continuation | 仍需真实浏览器关闭、网络切换和端口冲突验收 |
| OW-AUD-008 发布完整性 | 部分关闭 | 严格 env parser；Hardened Runtime；Developer ID/Team ID 强校验；notarytool/stapler 路径；Gatekeeper fail-closed；安装 staging/旧版备份/失败恢复；ZIP/DMG SHA-256 与 release manifest；Cask 默认全零 checksum fail-closed；Sparkle 2.9.4 已固定、嵌入、签名并接入菜单/设置；支持外部私钥或 Keychain 生成签名 appcast，并用内置公钥对 ZIP 做 CryptoKit 实际验签；本地 ad-hoc 构建仅为无 Team ID 框架加载临时关闭 library validation，商业 gate 明确拒绝该 entitlement | 当前证书已撤销，尚无真实 Developer ID + notarization/staple 产物；生产 feed/公钥/私钥未配置，尚无真实签名 appcast、自动更新和回滚实机证据 |
| OW-AUD-009 技术字面量归一化 | 关闭 | `TechnicalLiteralTokenizer` 保护 URL、邮箱、POSIX/Windows 路径、文件名、版本、IP、UUID、hash、CLI flag、环境变量、inline/fenced code 和代码符号；本地处理使用 private-use token，AI Polish 使用显式 model-safe token；token 缺失或重复即回退；Settings 支持简体、繁体、原样及自动/全角/半角/原样标点 | 扩充真实混输语料和边缘文件名 corpus，保持 round-trip 门禁 |
| OW-AUD-010 MainActor/旧回调污染 | 关闭 | 协调器使用 `activeSessionID`，取消后迟到 pipeline 或注入结果不能写入新状态；`AsyncPasteTargetWaiter` 与 `AsyncPasteVerificationWaiter` 使用 `ContinuousClock` 和可取消 `Task.sleep`，只在短检查/激活/AX 采样阶段回到 MainActor；HUD apply/hide 使用 presentation generation 拒绝 stale auto-hide 与动画 completion | 多应用真实验证矩阵继续归入 OW-AUD-001，不再用单一 `.pasted` 状态掩盖验证边界 |
| OW-AUD-011 剪贴板恢复竞态 | 关闭 | 恢复前校验 pasteboard change count 与 VibeCompose 所有权 | 真实跨应用复制/Universal Clipboard 场景继续验收 |
| OW-AUD-012 首次麦克风顺序 | 部分关闭 | `.notDetermined` 有独立请求动作；Settings/Onboarding 共用异步请求结果，并在成功回调后有上限地轮询真实权限状态；未收敛时显示明确恢复文案和“刷新权限状态”；四步 Onboarding 已实现；`permission_surface_acceptance.sh` 已在当前授权 TCC 状态下黑盒确认安装版两张权限卡均显示“已授权” | clean TCC 下的系统提示顺序、拒绝后修复及完整首次成功听写仍缺可信安装版原生 GUI 证据 |
| OW-AUD-013 配置 URL 崩溃 | 关闭 | 可配置 endpoint 经 `validatedUserOwnedURL` 返回可理解错误；Managed URL 为编译时常量 | 对全部高风险文本字段统一失焦/提交校验 |
| OW-AUD-014 Settings stale index | 关闭 | Terminology 条目持久化稳定 UUID；独立 Manager 的选择、编辑、启停和删除均按 ID 定位；旧配置迁移补齐稳定 ID；导入和 Quick Add 在写入前执行重复与语义冲突检测 | 继续保留 ID 迁移、删除后编辑和冲突分类回归测试 |
| OW-AUD-015 失败清理不完整 | 关闭 | Recorder 初始化写入失败和启动失败会删除 partial WAV；上传成功、失败或取消均删除 multipart；`shutdown()` 同步删除处理中自有音频；下次启动只清理严格 UUID 命名的 `vibecompose-*.wav` 与 `vibecompose-upload-*.multipart`，跳过目录和 lookalike，删除 symlink 本身而不触碰目标 | 继续做真实磁盘满、SIGKILL 后重启和长时间压力测试 |
| OW-AUD-016 死配置/预检偏差 | 关闭 | Public Alpha Provider Policy 在加载时统一迁移到 ChatGPT 路径；首版设置不再暴露 Provider 选择 | 为每个公开设置保持行为契约和安装版交互证据 |
| OW-AUD-017 测试可能假绿 | 部分关闭 | 高风险边界已有纯单元测试，仓库提供安装版 smoke 与 visual acceptance | TCC、焦点、热键、多应用真实操作仍必须使用 `/Applications/VibeCompose.app` 验收，不能只引用单元测试 |

## 3. 当前隐私默认值

`PrivacyConfig` 的代码默认值为：

```text
historyEnabled = true
historyRetentionDays = 30
historyRecordLimit = 500
storeRawTranscripts = false

failedAudioRecoveryEnabled = true
failedAudioRetentionHours = 24
failedAudioRecordLimit = 10

diagnosticsEnabled = true
diagnosticsRetentionDays = 14
diagnosticsRecordLimit = 1000

excludeSensitiveApps = true
```

当前内置敏感应用集合包括：

- 1Password；
- Bitwarden；
- LastPass；
- macOS Keychain Access；
- macOS Passwords。

额外 bundle ID 可以由用户配置。匹配时，VibeCompose 跳过 transcript history 和 failed-audio recovery。

## 4. 删除全部数据的边界

“删除全部数据”执行以下动作：

1. 取消当前录音/处理或清理 Pending Retry；
2. Sign out，并删除 Keychain 中的 ChatGPT session；
3. 删除 Keychain 中的遗留 Provider 凭据；
4. 验证删除目标确实是 VibeCompose Application Support 目录；
5. 拒绝通过 symlink 删除；
6. 删除整个 `~/Library/Application Support/VibeCompose/`；
7. 以 `0700` 重建空目录；
8. 保存新的默认 `AppConfig`；
9. 将运行状态切回需要重新连接 ChatGPT。

边界测试必须使用临时目录，不得把任意上级目录或 symlink 当作可删除目标。

## 5. 针对性自动化证据

| 边界 | 主要测试 |
| --- | --- |
| 安全粘贴、Retry copy-only、剪贴板所有权 | `TextInjectorTests.swift`, `LiveTextInjectorAcceptanceTests.swift` |
| session generation 与取消 | `AppCoordinatorCancellationTests.swift` |
| Managed endpoint/redirect policy | `ManagedEndpointPolicyTests.swift`, `ChatGPTTranscriberTests.swift`, `TextPolishTests.swift` |
| Recovery Keychain 凭据、环境变量隔离、连接测试与错误脱敏 | `OpenAICompatibleCredentialStoreTests.swift`, `OpenAICompatibleConnectionTesterTests.swift`, `RuntimePreflightTests.swift`, `ChatGPTTranscriberTests.swift`, `ConfigTests.swift` |
| Recovery containment | `RecoveryHistoryTests.swift` |
| refresh single-flight/logout invalidation | `BrowserAuthBridgeTests.swift` |
| OAuth callback 生命周期 | `BrowserAuthBridgeTests.swift` |
| 录音硬上限 | `AudioRecorderTests.swift` |
| 音频 metadata-first、流式 multipart、symlink 与失败清理 | `ChatGPTTranscriberTests.swift` |
| 技术字面量、简繁与标点 round-trip | `TechnicalLiteralTokenizerTests.swift`, `DictationPipelineTests.swift`, `TextPolishTests.swift` |
| 可取消粘贴等待、session 取消与 HUD generation | `TextInjectorTests.swift`, `AppCoordinatorCancellationTests.swift`, `OverlayControllerTests.swift` |
| 启动/退出孤儿文件与 Recorder partial 清理 | `StoragePrivacyTests.swift`, `AudioRecorderTests.swift`, `AppCoordinatorCancellationTests.swift` |
| 测试音频 fixture 与 entitlement 语法门禁 | `ChatGPTTranscriberTests.swift`, `ReleaseIntegrityScriptTests.swift` |
| 产品表面固定 2x 截图、可见屏幕定位与局部边缘对比度门禁 | `ProductSurfaceSnapshotTests.swift`, `VisualAcceptanceScriptTests.swift`, `scripts/verify_accessibility_visual_acceptance.swift` |
| 麦克风请求后状态收敛、刷新修复与安装版权限表面 | `PermissionStatusMonitorTests.swift`, `AudioRecorderTests.swift`, `LocalizationTests.swift`, `VisualAcceptanceScriptTests.swift`, `scripts/verify_permission_surface.swift` |
| 脱敏支持诊断 ZIP、崩溃白名单摘要和校验和 | `SupportDiagnosticsTests.swift`, `SettingsProductizationTests.swift` |
| 双语隐私/条款/支持文档契约 | `PolicyDocumentationTests.swift` |
| Release manifest、Cask fail-closed 与 updater gate | `ReleaseIntegrityScriptTests.swift` |
| 候选配置、精确候选 installed-app 证据、品牌与 Pilot/Beta 公开发布门禁 | `scripts/verify_release_readiness.py`, `ReleaseIntegrityScriptTests.swift` |
| 签名 Provider Capability Policy、反重放、build/expiry 与发送前阻断 | `ProviderCapabilityPolicyTests.swift`, `ReleaseIntegrityScriptTests.swift` |
| Provider 错误分类、Retry-After、有限退避、route 熔断与 half-open 取消恢复 | `ProviderResilienceTests.swift`, `ChatGPTTranscriberTests.swift`, `TextPolishTests.swift`, `AppCoordinatorCancellationTests.swift` |
| 数据留存、权限、敏感 App、Delete All 路径和 Recovery Key 删除 | `StoragePrivacyTests.swift`, `AppCoordinatorCancellationTests.swift` |
| 诊断轮转 | `LatencyRecorderTests.swift` |

完整仓库检查命令：

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
```

2026-07-13 19:52（UTC+8）本地基线执行结果：**退出码 0**。Swift build/test、Landing Page 内容契约和 packaged-app metadata 检查均通过。该结果使用 ad-hoc 签名，仅证明当前开发构建与自动化门禁，不替代 Developer ID、公证或真实 GUI/TCC 验收。

同日对 `/Applications/VibeCompose.app` 的启动清理进行实机检查：原有 Recovery WAV 从 `0644` 被统一收紧为 `0600`，应用以 Settings 模式保持运行。

自动验收模式会在账户管理器创建前统一进入隐私隔离，使用默认配置和内存凭据，不读取真实 Keychain，避免 `SecItemCopyMatching` 阻塞或用户状态泄漏。产品表面截图还会拒绝全黑/近似纯色的 CoreGraphics 帧，回退到确定性 content-view 渲染，并再次执行非纯色门禁。

同日最新安装版自动验收证据：

- `dist/permission-surface-acceptance/20260713T111946Z`：安装版 Settings → Account 黑盒截图中麦克风与辅助功能标签均被 Vision 识别，`已授权` 状态识别数为 `2`；
- `dist/paste-acceptance/20260713T115507Z`：隔离 TextEdit 观察到 `inserted_verified`；隔离无历史 Terminal 观察到 `paste_dispatched`、生成 proof 命令执行成功和转写保留；两者均恢复验收前完整剪贴板，且无目标进程或临时文件残留；
- `dist/accessibility-acceptance/20260713T111949Z`：13 个产品表面的可操作控件均无缺失名称；
- `dist/accessibility-visual-acceptance/20260713T084453Z`：六个 Settings pane、四步 Onboarding、History、Terminology 和 Quick Add 均输出稳定 2x 成对截图；统一逻辑分辨率上的局部边缘对比度全部提升；
- `dist/product-surface-acceptance/20260713T112011Z`：History、Terminology 和 Quick Add 渲染、几何及非纯色门禁通过；
- `dist/visual-acceptance/20260713T111636Z`：HUD 全状态、Reduce Motion 静态性和 Increase Contrast 差异门禁通过。

本机两个 Apple Development identity 仍被 Gatekeeper 判定为
`CSSMERR_TP_CERT_REVOKED`。上述证据使用稳定 designated requirement 的
ad-hoc 本地构建，不构成 Developer ID、notarization/staple 或 clean TCC
首次授权证明。

## 6. 安装版验收要求

单元测试通过不构成最终验收。涉及 TCC、焦点、热键和多步 GUI 的证据必须来自：

```text
/Applications/VibeCompose.app
```

最低安装版矩阵：

1. Settings 的 Privacy & Data 中英文布局；
2. 删除全部数据二次确认；
3. clean TCC 下麦克风提示顺序；
4. Accessibility 已授权与未授权的 paste/copy 分支；
5. TextEdit/Notes/Terminal 的 F5 开始、F5 停止；
6. ESC、HUD inline close、错误后 Retry；
7. Retry 完成后只复制，不自动发送 `Cmd+V`；
8. 关闭窗口后正常菜单栏实例仍保持运行。

## 7. 签名公开分发 No-Go

以下任一项未关闭时，不能发布公开签名版：

- OW-AUD-008 发布完整性；
- Developer ID、Team ID、notarization/staple；
- fail-closed Gatekeeper 与 SHA-256 manifest；
- 签名 updater 和 rollback；
- 四步 Onboarding；
- Settings/History/Terminology 原生产品表面；
- 法律/隐私/支持联系方式与公开分发说明；
- 生产上游故障 kill switch URL/密钥、首份签名策略和安装版事故演练；
- 完整 installed-app 用户流验收；
- 所有 P0/P1 release blocker 的复核证据。

`scripts/verify_release_readiness.py --phase public` 现在把品牌清查、精确候选
installed-app 验收、四周 Community Pilot 汇总、产品所有者人工复核、版本 tag 和
发布 manifest 绑定为同一 fail-closed 报告。当前品牌记录仍为 `blocked`，真实 Pilot
尚未开始，因此该门禁按设计保持关闭；候选脚本、模板或 ad-hoc 证据不能让它通过。
签名候选还必须保存 App/DMG 两份 `notarytool --output-format json` 回执；两者都要
为 `Accepted`、submission ID 合法且互不相同，并同时通过 stapler 与 Gatekeeper。
公开联系面同样 fail-closed：support/security/privacy/legal URL、责任角色与复核状态
必须进入受保护证据，并与中英文政策逐字一致；仍写“私有 Alpha”的政策不能发布。

## 8. 下一安全工作序列

1. 继续关闭 OW-AUD-008：取得有效 Developer ID/Team ID、生产 Sparkle 与 Capability Policy 独立密钥/托管地址，完成真实签名、公证、签名 appcast、首份能力策略、更新回滚与事故演练；
2. 在已通过 TextEdit/隔离 Terminal 自动预检的基础上，完成不读取或修改个人笔记的 Notes 手动矩阵及第三方编辑器矩阵，验证 `inserted_verified`、`paste_dispatched`、`clipboard` 与剪贴板恢复行为均符合实现；
3. 完成 clean TCC Onboarding、键盘和 VoiceOver 安装版验收；
4. 把私有 Alpha 双语政策定稿为带明确支持联系人和公开分发说明的版本；
5. 对磁盘满、SIGKILL 后重启、慢网络和大文件取消做持续压力测试。
