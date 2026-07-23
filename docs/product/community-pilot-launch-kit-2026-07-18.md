# VibeWhisper Community Skills Pilot Launch Kit

> Date: 2026-07-18  
> Status: execution kit ready; recruitment has not been claimed or started by this repository  
> Scope: non-UI launch materials for CS-013 / Phase 4

This kit turns the [Community Pilot runbook](community-pilot-runbook-2026-07-17.md)
into an executable, privacy-bounded study. It does not authorize a public
Registry, remote analytics, participant outreach, or collection of private
content. The VibeWhisper product owner must approve the study owner, recruitment
channel, installed build, and incident owner before the first invitation is
sent.

## 1. Launch authorization

Record the following in the product owner's private study log, outside this
repository:

- product owner and research lead;
- privacy/security incident owner and backup;
- recruitment channel and intended audience;
- exact installed build version, build number, archive hash, and signing state;
- planned W0 date and four complete study weeks;
- where consent records and the three bounded CSV files are stored;
- confirmation that remote Registry and external Actions remain disabled.

CS-013 changes from `ready` to `in progress` only after the product owner records
that approval and at least one participant has explicitly consented. A template,
test row, invitation draft, or repository commit is not participant evidence.

## 2. Recruitment target and screener

Recruit 30–50 target users. The cohort must be large enough to retain at least
20 participants with valid non-Direct runs in W1 and should include at least
eight people willing to try Creator/Fork so that five qualified external authors
remain achievable.

Core-team members may rehearse the protocol, but their rows must not enter the
Pilot evidence and they never count toward participant or author thresholds.

Use a mix of:

- developers who regularly write tasks, bug reports, commit messages, or code prompts;
- knowledge workers who regularly draft replies, email, meeting actions, briefs, or support responses;
- prospective community authors willing to create or Fork one narrow, repeatable Skill.

The screener may ask only whether the candidate uses macOS, can install a private
test build, already has access to the browser-based ChatGPT connection, performs
one of the target tasks repeatedly, and can attend W0 plus weekly follow-ups.
Names and contact details stay in the approved recruitment system. They never
enter the Pilot CSV files or VibeWhisper diagnostics.

### Recruitment copy — English

> We are running a four-week private study of VibeWhisper Community Skills on
> macOS. The study observes whether task-specific Skills make voice input easier
> to review and apply. Participation is voluntary. VibeWhisper does not upload
> study analytics; researchers collect only bucketed outcomes and aggregate
> reports you explicitly choose to share. We do not collect audio, transcript or
> generated text, selected text, prompts, file names, window titles, account
> details, or device identifiers. You may stop or withdraw your study records at
> any time.

### 招募文案 — 中文

> 我们正在进行一项为期四周的 VibeWhisper Community Skills macOS 私有研究，
> 目的是了解面向具体任务的 Skill 是否能让语音输入更容易审阅和使用。参与完全自愿。
> VibeWhisper 不会自动上传研究数据；研究员只记录分桶后的结果，以及你明确选择分享的
> 本地汇总报告。我们不会收集音频、转写或生成正文、选区、Prompt、文件名、窗口标题、
> 账户信息或设备标识。你可以随时停止参与或要求删除研究记录。

## 3. Consent script

Before observing or recording a row, the researcher must say:

> This session records only a random cohort code, study week, task category,
> bounded timing buckets, Skill source category, final action, Validator/target
> outcome, and failure category. It does not record your words, audio, screen
> content, generated result, edits, app or file names, email, ChatGPT account, or
> device identity. Product Metrics stays off unless you separately enable it and
> choose to export its aggregate report. You may skip any task, stop the session,
> or withdraw your study rows. Do you consent to this session?

The researcher records `consent_status=yes` only after an explicit answer. A
participant who declines must not have observation rows. Screen or audio
recording is outside this protocol and requires separate, specific consent and
storage approval.

## 4. Privacy-bounded evidence files

Use copies of these header-only templates:

- [participant manifest](community-pilot-participants-template.csv);
- [observation worksheet](community-pilot-observations-template.csv);
- [incident register](community-pilot-incidents-template.csv).

Store real files outside the repository, or under the ignored local
`.pilot-data/` directory. Never commit participant evidence. Generate random
cohort codes in the form `P-` followed by 6–12 uppercase letters or digits. The
mapping from code to contact identity stays in the approved recruitment system,
not beside the evidence files.

The CSV schemas contain no free-text field. If a value is not in the documented
enum, classify it during weekly review before adding the row; do not put a note,
content excerpt, path, title, email, or identifier into another cell.

Run the schema and aggregation preflight:

```bash
python3 scripts/summarize_community_pilot.py --self-test
```

Generate a row-free aggregate report:

```bash
python3 scripts/summarize_community_pilot.py \
  --participants /secure/path/participants.csv \
  --observations /secure/path/observations.csv \
  --incidents /secure/path/incidents.csv \
  --output /secure/path/community-pilot-summary.json
```

The summarizer rejects unknown columns, free text, symbolic-link inputs,
unconsented observations, invalid action/target combinations, and critical
incidents as an exit pass. Its output contains no cohort code or row-level
evidence. Passing automated thresholds still returns
`manual_review_required`; it never makes the Registry decision.

## 5. Stable enum reference

Participant manifest:

- `consent_status`: `yes`, `no`;
- `target_segment`: `developer`, `knowledge-worker`, `community-author`;
- `enrollment_status`: `invited`, `consented`, `active`, `withdrawn`, `completed`;
- `author_outcome`: `not_attempted`, `started`, `qualified`, `failed_quality_gate`;
- `creator_first_success_duration`: `under_5m`, `5_to_15m`, `15_to_30m`, `over_30m`, `not_attempted`, `not_completed`.

Observation worksheet:

- `study_week`: `W0`–`W4`; `run_kind`: `direct`, `non-direct`;
- `task_category`: `dictation`, `developer`, `communication`, `rewrite`, `professional-template`;
- `skill_source`: `built-in`, `curated`, `local-created`, `imported`;
- `resolution`: `next-run`, `app-default`, `global-default`, `safe-fallback`;
- `selection_identity_match`: `yes`, `no`, `not-applicable`;
- `switcher_duration`: `under_1s`, `1_to_3s`, `3_to_10s`, `over_10s`, `not_used`;
- `first_use_duration`: `under_3m`, `3_to_5m`, `5_to_10m`, `over_10m`, `not_achieved`, `not_first_use`;
- `result_available`: `yes`, `no`; `result_action`: `replace`, `paste`, `copy`, `cancel`;
- `result_edited`: `yes`, `no`, `not-applicable`;
- `validator_outcome`: `passed`, `fallback`, `not-run`;
- `target_outcome`: `verified`, `paste-dispatched`, `copy-only`, `not-applicable`;
- `failure_class`: `none`, `wrong-skill`, `context`, `validator`, `target`, `provider`, `usability`.

Incident register:

- `severity`: `critical`, `high`, `medium`, `low`;
- `incident_class`: `private-content`, `executable-skill`, `unauthorized-context`, `wrong-target`, `credential`, `provider`, `usability`;
- `status`: `open`, `mitigated`, `closed`.

An incident row deliberately has no free-text description or participant code.
Redacted technical evidence belongs in the product owner's restricted incident
system.

## 6. Fifteen launch tasks

Use synthetic or participant-provided non-sensitive content. Researchers observe
outcomes, never copy the content.

1. Direct dictation control into a disposable TextEdit document.
2. Turn a spoken intent into a concise team reply.
3. Draft an email with a purpose and next step.
4. Turn an idea into a backend implementation task with acceptance criteria.
5. Create a code prompt that preserves a path, command, API, and identifier.
6. Translate a short technical note while preserving version literals.
7. Rewrite selected text without losing dates, numbers, or factual claims.
8. Draft a reply grounded in selected synthetic source text.
9. Produce a Bug Report from observed/expected behavior and reproduction steps.
10. Produce an imperative Commit Message without inventing tests or files.
11. Extract meeting Decisions, Action Items, and Open Questions.
12. Produce a Product Brief with goals, non-goals, risks, and success criteria.
13. Draft a Customer Support Reply without invented refunds or timelines.
14. Exercise an explicit Validator fallback and edit-before-apply recovery.
15. Change the target/selection before delivery and verify safe copy-only fallback.

At W0, each participant completes one ordinary task and one recovery task. In
W1–W4, rotate categories rather than repeating only the easiest built-in Skill.
Willing authors begin Creator/Fork in W2 so there is time for quality-gate
feedback and a second attempt.

## 7. Weekly operating cadence

- **W0:** consent, install/build identity, first useful non-Direct result, safety explanation.
- **W1:** minimum three non-Direct runs, one recovery task, first aggregate review.
- **W2:** Creator/Fork attempt, curated content review, failure taxonomy review.
- **W3:** repeated real task, upgrade/rollback or import review, incident audit.
- **W4:** minimum three non-Direct runs, final interview, local aggregate export if opted in.

The product owner reviews the generated aggregate report and the manual items in
the runbook every week. A Critical incident pauses the Pilot immediately even if
it was mitigated or closed later.

## 8. Exit and Registry decision

The automated report is evidence, not authority. The product owner must still
review core-scenario sample sufficiency, W4 Skill concentration, uninstall or
disable reasons, interview interpretation, and ongoing moderation ownership.

Only after four complete weeks and every exit criterion is met may CS-013 be
marked complete. CS-014 and CS-015 remain blocked on that evidence. A failed
threshold means another local Pilot iteration, never a lower threshold or an
automatic public Registry launch.
