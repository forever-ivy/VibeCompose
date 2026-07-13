# OpenWhisper 隐私政策

> 私有 Alpha 生效日期：2026 年 7 月 13 日
>
> 最后更新：2026 年 7 月 13 日
>
> 产品状态：macOS 预发布 Alpha

本政策描述当前的 OpenWhisper macOS 应用。OpenWhisper 目前不运营自己的分析、账户、同步、广告或转写服务器。

## 1. OpenWhisper 处理的数据

### 音频与转写请求

开始听写后，OpenWhisper 会在 Mac 上录制一段短音频。默认路径会使用你在 OpenWhisper 中连接的 ChatGPT 会话，把音频和转写指令发送到 ChatGPT 服务。如果选择高级 OpenAI-Compatible 恢复路径，音频会通过 HTTPS 发送到你配置的端点，并使用你自己的凭据。

高级设置中的连接测试只发送自动生成的 0.1 秒静音 WAV、所配置的模型和 Recovery 凭据，不会读取或发送你的录音、转写文本或术语。所配置的服务商仍可能对此请求计费。

OpenWhisper 是独立项目，与 OpenAI 不存在隶属、赞助或官方背书关系。第三方处理受你所选服务的条款和隐私政策约束：

- OpenAI 隐私政策：`https://openai.com/policies/privacy-policy/`
- OpenAI 使用条款：`https://openai.com/policies/terms-of-use/`

### 本地应用数据

OpenWhisper 可能在 `~/Library/Application Support/OpenWhisper/` 保存：

| 数据 | 默认留存 |
| --- | --- |
| 最终转写历史 | 30 天，最多 500 条 |
| 原始 ASR 文本 | 默认关闭，需显式开启 |
| 用于 Retry 的失败录音 | 24 小时，最多 10 条 |
| 成功录音 | 处理完成后删除 |
| 性能诊断 | 14 天，最多 1,000 条 |
| 本地产品指标 | 默认关闭；开启后 30 天，最多 5,000 条 |
| 设置和术语 | 直到修改或删除 |

已知密码管理器、钥匙串访问和 macOS“密码”默认不写入转写历史或失败音频 Recovery。你也可以添加其他敏感应用。

### Keychain 凭据

OpenWhisper 连接的 ChatGPT 会话保存在 macOS Keychain 服务 `app.openwhisper.mac.ChatGPTSession` 中。可选的 OpenAI-Compatible Recovery API 密钥独立保存在 `app.openwhisper.mac.OpenAICompatibleAPIKey`。OpenWhisper 不会从 `OPENAI_API_KEY` 读取该密钥，也不会有意把访问令牌、刷新令牌、API 密钥、Cookie 或 Authorization Header 写入 `config.json`、转写历史、诊断、截图或日志。

## 2. 诊断与支持归档

性能诊断只包含耗时、字节数、服务类别、结果类别和错误类别，不应包含音频、转写正文、剪贴板内容或凭据。

可选的本地产品指标默认关闭。开启后只包含产品版本/构建、已完成的 Onboarding 步骤、服务类别、音频时长区间、处理延迟区间、交付类别和失败类别；不包含音频、转写或剪贴板正文、应用名称、Bundle Identifier、文件路径、账户信息或持久用户/安装标识，也不会由 OpenWhisper 自动上传。
开启后，你可以使用 **设置 → 隐私 → 导出产品指标** 创建汇总 JSON，自行检查或自愿分享。报告只包含各维度计数，不包含单条事件时间戳。

当你选择 **设置 → 高级 → 导出诊断** 时，OpenWhisper 会在本地创建一个 ZIP，由你检查后手动分享。归档包含：

- 产品、操作系统、权限、认证状态和签名状态摘要；
- 非敏感配置开关和留存值；
- 脱敏延迟记录；
- 只含枚举与区间值的可选本地产品指标；
- 最多五份近期 OpenWhisper 崩溃报告的白名单元数据；
- 文件校验和。

归档不包含音频、转写正文、剪贴板文本、账户邮箱、术语、自定义端点 URL、凭据、原始崩溃报告正文、历史、Recovery 元数据或 `config.json`，也不会自动上传。

## 3. 剪贴板与辅助功能

OpenWhisper 会先把完成的转写写入 macOS 剪贴板。只有在辅助功能权限有效且当前目标明确可编辑时，才可能发送 `Cmd+V`；否则结果保留在剪贴板中供手动粘贴。OpenWhisper 不会有意保存无关的剪贴板内容。

## 4. 你的控制权

你可以：

- 关闭或限制转写历史、失败音频 Recovery、诊断和本地产品指标；
- 导出汇总后的本地产品指标，供自己检查或自愿分享；
- 关闭原始转写保存；
- 添加禁止生成历史或 Recovery 的敏感应用；
- 删除单条历史或 Recovery；
- 退出 ChatGPT；
- 单独移除 OpenAI-Compatible Recovery 密钥；
- 使用“删除全部数据”删除本地设置、术语、历史、失败录音、诊断、产品指标、Retry 文件、已保存的 ChatGPT 会话和 Recovery API 密钥。

删除 OpenWhisper 本地数据不会删除已经发送到第三方服务或由第三方保留的数据。第三方数据需要通过对应服务的账户和隐私控制处理。

## 5. 数据分享与出售

OpenWhisper 目前不出售个人信息、不展示广告，也不会向 OpenWhisper 自营服务器上传产品分析数据。只有在你主动使用第三方转写服务、手动分享支持归档或适用法律要求时，数据才会被披露。

## 6. 安全

OpenWhisper 使用独立的 macOS Keychain 项保存 ChatGPT 会话和可选 Recovery API 密钥，并采用系统支持范围内的仅用户可读写文件权限、有限留存、HTTPS 端点校验、拒绝重定向和保守粘贴策略。任何安全措施都无法保证绝对安全。请保持 macOS 更新，并在分享诊断归档前自行检查。

## 7. 未成年人

OpenWhisper 是面向有权使用所连接第三方服务的用户的生产力工具，不面向 13 岁以下儿童。

## 8. 政策变更

重大变更会在本文件中标注日期，并在发布说明中概述。公开收费发布前，必须补齐明确的商业运营主体和永久隐私联系方式。

## 9. 联系方式

私有 Alpha 参与者应使用获授权的 OpenWhisper GitHub Issue Tracker。不要附加音频、转写正文、凭据、原始崩溃报告或无关个人信息。永久商业隐私联系方式仍是发布门禁。
