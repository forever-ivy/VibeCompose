/**
 * Localized overrides for each skill's display name + summary.
 *
 * English is intentionally NOT stored here — it is read from the repo's
 * SKILL.md frontmatter at build time (see lib/catalog.ts) so website copy
 * can never drift from the shipped skill. This file only adds the zh-Hans
 * translation layer.
 */

export interface LocalizedSkillCopy {
  name: string;
  summary: string;
}

/** zh-Hans overrides keyed by skill slug. */
export const skillCopyZh: Record<string, LocalizedSkillCopy> = {
  direct: {
    name: "直接转写",
    summary: "忠实还原你的口述，只做轻度清理，不改结构",
  },
  reply: {
    name: "回复",
    summary: "口述变成简洁自然的回复，审阅后直接发送",
  },
  email: {
    name: "邮件",
    summary: "一句话起草目的明确、有下一步行动的完整邮件",
  },
  "better-question": {
    name: "更好的提问",
    summary: "粗糙的口头问题变成清晰、具体、结构良好的提问",
  },
  "social-post": {
    name: "社交帖子",
    summary: "口头想法变成有吸引力、可直接发布的帖子",
  },
  "context-rewrite": {
    name: "上下文改写",
    summary: "保留事实与技术细节，按你的指令改写选中文本",
  },
  "context-reply": {
    name: "上下文回复",
    summary: "结合选中消息和你的口述意图，起草有依据的回复",
  },
  "context-summarize": {
    name: "摘要",
    summary: "按你的偏好压缩选中文本为要点或一句话",
  },
  "clipboard-rewrite": {
    name: "剪贴板改写",
    summary: "按口述指令改写剪贴板中的现有内容",
  },
  "paragraph-polish": {
    name: "段落润色",
    summary: "按口述指令就地润色或改写光标所在段落",
  },
  "backend-prompt": {
    name: "后端提示词",
    summary: "口述变成带约束、步骤和验收标准的后端实现任务",
  },
  "code-prompt": {
    name: "代码提示词",
    summary: "准确保留路径、命令和 API 的编码需求，可直接交给 Agent",
  },
  "frontend-prompt": {
    name: "前端提示词",
    summary: "口述变成包含组件、交互和无障碍要求的前端任务",
  },
  "code-review-comment": {
    name: "代码评审意见",
    summary: "口头评审观察变成结构化、建设性的 Review 评论",
  },
  "commit-message": {
    name: "提交信息",
    summary: "祈使语气的 commit message，说明改了什么以及为什么",
  },
  "bug-report": {
    name: "缺陷报告",
    summary: "观察到的行为变成可复现的 Bug 报告，不臆造证据",
  },
  "changelog-entry": {
    name: "更新日志条目",
    summary: "口述变更说明变成 Keep a Changelog 规范条目",
  },
  "incident-report": {
    name: "事故报告",
    summary: "口述事故描述变成含时间线与根因的结构化复盘",
  },
  "meeting-action-items": {
    name: "会议行动项",
    summary: "从会议内容中提取决策、行动项、负责人和待确认问题",
  },
  "standup-update": {
    name: "站会同步",
    summary: "口述工作小结变成「昨天 / 今天 / 阻塞」结构",
  },
  "product-brief": {
    name: "产品简报",
    summary: "口述产品想法变成含范围和成功标准的简洁简报",
  },
  "customer-support-reply": {
    name: "客服回复",
    summary: "有同理心的客服回复，只含核实步骤，不做无依据承诺",
  },
  translate: {
    name: "翻译",
    summary: "翻译成你指定的语言，保留原意和技术术语",
  },
};
