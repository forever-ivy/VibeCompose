# OpenWhisper 上游事故与恢复预案

> 运行基线日期：2026 年 7 月 13 日

## 目的

OpenWhisper 默认账户路径依赖未公开为稳定公共 API 的 ChatGPT 上游行为。本预案用于避免上游事故演变为重复发送凭据、静默数据丢失或误导性产品承诺。

## 检测分类

| 信号 | 分类 | 默认动作 |
| --- | --- | --- |
| 401 或非 Cloudflare 403 | 认证变化 | 最多刷新一次，随后要求重新连接 |
| Cloudflare 403 | 上游挑战 | 有限自动尝试，保留失败音频并显示 Retry |
| 404 或 Schema 不兼容 | 上游契约变化 | 停止把能力视为健康，要求更新应用或使用恢复路径 |
| 429 | 容量/限流 | 停止密集重试，在可用时显示重试时间 |
| 网络/5xx | 短暂故障 | 仅有限重试，保留可恢复工作 |
| 重复跨用户错误结果或凭据风险 | 安全事故 | 禁用受影响发布路径并发布安全更新 |

## 用户恢复

1. 大范围故障期间不要反复点击 Retry；
2. 仅在用户开启失败音频恢复时保留录音；
3. 认证失败后重新连接 ChatGPT；
4. 无法证明自动粘贴安全时使用剪贴板模式；
5. 高级用户可以把自己的 API Key 保存到钥匙串，配置 HTTPS OpenAI-Compatible 端点和模型，执行合成静音连接测试，确认可能产生的服务商费用后切换听写 ASR；
6. 事故结束后切回 ChatGPT 账户路径；
7. 不再需要恢复时，删除 Recovery Key、失败音频或全部本地数据。

## 运营响应

1. 使用非敏感测试账户和安装版确认故障；
2. 判断事故影响认证、转写、AI Polish 还是粘贴；
3. 停止发布推广并更新状态/发布说明；
4. 不通过提高重试次数掩盖故障；
5. 发布更高 revision、仅停用受影响托管能力的签名能力策略；
6. 在更新公开状态前，验证策略签名、build 范围、到期时间和安装版阻断行为；
7. 如果上游契约或客户端行为需要代码修改，再准备签名 Hotfix；
8. 使用安装版流程和回滚路径验证 Hotfix；
9. 公布恢复步骤以及用户是否需要处理本地数据；
10. 完成事故复盘，但不保存用户音频或转写正文。

## Kill Switch 状态

当前应用已经实现面向托管转写和 ChatGPT AI Polish 的远程签名能力 Kill
Switch 基础：

- 只从已签名 App 内固定的无凭据 HTTPS 地址获取策略；
- 使用 App 内固定、与更新签名分离的 Ed25519 公钥验签；
- 策略只能停用指定托管能力，不能重定向请求或提供凭据；
- 在读取录音、解析托管 Token 或发送转写文本前检查；
- 最长有效期 31 天，可限定 build 范围，并通过单调 revision 拒绝回滚和重放；
- 以仅当前用户可读写方式缓存；无效或旧策略不能替换已接受且仍生效的停用策略。

私有 Alpha 仍刻意不写入生产 URL 和公钥。商业发布继续受独立生产签名密钥、永久
HTTPS 策略托管、初始签名策略及安装版事故演练约束。

生成和验证策略时，私钥不得进入仓库：

```bash
OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE=/secure/openwhisper-capability.key \
scripts/generate_provider_capability_policy.swift \
  --revision 1 \
  --incident-id OW-INC-2026-001 \
  --expires-at 2026-07-14T12:00:00Z \
  --disable managedTranscription

scripts/verify_provider_capability_policy.swift \
  --policy dist/provider-capabilities.json \
  --public-key BASE64_PUBLIC_KEY \
  --build 1
```

## 沟通规则

- 不得把默认路径描述为稳定公共 API 或保证 SLA；
- 不得要求用户发送访问令牌、Cookie、API 密钥、原始音频或完整转写；
- 明确受影响版本和日期；
- 区分上游故障、OpenWhisper 会话过期和本地权限问题；
- 公开 Beta 前必须提供英文和简体中文恢复说明。
