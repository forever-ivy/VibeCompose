# OpenWhisper 品牌名称初步清查

> 日期：2026-07-14
>
> 结论：**阻断商业公开发布**

## 发现

初步公开检索发现，GitHub 上已经存在独立项目
[`dimatura/open-whisper`](https://github.com/dimatura/open-whisper)。该项目：

- 使用 `OpenWhisper` 名称；
- 同样属于 macOS 语音转文字 / 听写工具；
- 已发布可下载版本；
- 项目时间早于当前 OpenWhisper 商业发布准备。

这不是只有字符串相同的无关项目，而是同平台、同功能类别、同目标用户的
直接名称冲突。即使尚未确认注册商标，也足以使当前名称不满足计划书中的
“单一、清晰、可注册产品身份”和公开发布 clearance 门禁。

## 当前决定

- 不以 `OpenWhisper` 名称发布付费许可证、Stable 公证包、公共更新源、
  Homebrew 正式 Cask 或应用市场条目；
- 不声称已经完成商标、域名或社交账号清查；
- 代码、自动化和产品架构继续推进，但 production release gate 必须保持
  fail-closed；
- 产品所有者需要在“选择独立新名称”与“取得书面法律清查结论”之间作出
  决定。

机器可读状态位于 `release/brand-clearance.json`。只有该文件经过真实清查
后变为 `approved`、所有检查为真且冲突为空，商业 release readiness 才能
通过。
