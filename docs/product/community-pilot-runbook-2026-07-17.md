# VibeCompose Community Skills Pilot Runbook

> Date: 2026-07-17  
> Status: execution kit ready for product-owner approval and recruitment; no participant evidence has been claimed  
> Scope: Phase 4 of the Community Skills core plan

## 1. Exit criteria

The Pilot runs for at least four complete weeks with 30–50 target users. It may
exit only when all of the following evidence exists:

- at least 20 participants have valid non-Direct runs in week 1;
- at least 300 non-Direct Skill runs cover the core scenarios;
- at least five authors outside the core team create or Fork a qualifying Skill;
- first useful non-Direct output upper-median bucket is at most 3–5 minutes;
- Skill Switcher upper-median bucket is at most 1–3 seconds;
- selected installation identity matches the frozen run identity at least 97% of the time;
- final application rate is at least 70%;
- Preview cancellation after a result is available is at most 20%;
- wrong-Skill rate is at most 3%;
- official/curated Validator fallback rate is at most 5%;
- qualified authors' Creator first-success upper-median bucket is at most 5–15 minutes;
- W1 effective retention is at least 40% and W4 is at least 20%;
- Critical privacy, security, or wrong-target delivery incidents are zero.

Failing a threshold means another local Pilot iteration. It does not authorize a
public Registry or a lower safety threshold.

The operational recruitment copy, consent script, 15 launch tasks, header-only
evidence templates, and privacy-bounded aggregation command are in the
[Community Pilot launch kit](community-pilot-launch-kit-2026-07-18.md). Repository
readiness is not participant evidence: CS-013 begins only after product-owner
approval and the first explicit participant consent.

## 2. Pilot content

The installed build exposes 13 reviewed built-in Skills. The five Pilot-focused
additions are Bug Report, Commit Message, Meeting Action Items, Product Brief,
and Customer Support Reply. Together with Direct, Reply, Email, Backend Prompt,
Code Prompt, Translate, Context Rewrite, and Context Reply, they cover the first
13 repeatable tasks without enabling scripts, Shell, MCP, network actions, or a
remote Registry.

Each curated external Skill must pass the
[Community Skill contribution guide](../engineering/community-skill-contribution-guide.md)
before it is shared with participants.

## 3. Privacy-preserving research mode

This Pilot uses local evidence plus researcher observation. It does not upload
product events.

- Participants explicitly consent to each observed session and interview.
- VibeCompose's Product Metrics setting remains off unless a participant
  separately opts into a local export.
- Participants export aggregate product metrics or selected redacted History
  receipts themselves; researchers never collect audio, transcript text,
  selection text, generated text, edits, Prompt content, terminology, file
  paths, window titles, account identity, or hardware identity.
- A participant is referenced only by a researcher-generated random cohort code
  stored outside VibeCompose. The participant can request a new code or deletion
  at any time.
- Free-form notes describe the task category and failure reason, not private
  content.

## 4. Session protocol

### First-use session

1. Confirm consent and explain the private ChatGPT browser connection.
2. Ask the participant to open Skill Library and choose a non-Direct task.
3. Observe Discover → Test → Use Next Time → F5 start/stop → Preview →
   Replace/Paste/Copy → History.
4. Record elapsed time to first applied/copied non-Direct result.
5. Ask the participant to explain which Skill ran, why it was selected, which
   Context was used, and what happened to the target text.

### Weekly session

1. Export local aggregate metrics only if the participant opts in.
2. Review redacted run outcomes and classify cancellations, Validator fallback,
   target verification failure, wrong Skill, and copy-only fallback.
3. Test one routine task and one recovery task.
4. In weeks 2–4, invite willing participants to create or Fork a Skill through
   Creator and Test Bench without writing YAML.

## 5. Observation worksheet

Record one row per observed run using the header-only
[observation template](community-pilot-observations-template.csv). The complete
enum reference and cross-field rules are defined in the
[launch kit](community-pilot-launch-kit-2026-07-18.md). The worksheet accepts only
these fields:

| Field | Allowed value |
| --- | --- |
| Cohort code | Random researcher code |
| Study week | W0, W1, W2, W3, W4 |
| Run kind | direct, non-direct |
| Task category | dictation, developer, communication, rewrite, professional template |
| Skill source | built-in, curated, local-created, imported |
| Resolution | next-run, app-default, global-default, safe-fallback |
| Selected installation identity matched frozen run | yes, no, not-applicable |
| Switcher duration | under_1s, 1_to_3s, 3_to_10s, over_10s, not_used |
| First-use duration | under_3m, 3_to_5m, 5_to_10m, over_10m, not_achieved, not_first_use |
| Result available | yes, no |
| Result action | replace, paste, copy, cancel |
| Result edited | yes, no, not-applicable |
| Validator outcome | passed, fallback, not-run |
| Target outcome | verified, paste-dispatched, copy-only, not-applicable |
| Failure class | none, wrong-skill, context, validator, target, provider, usability |

Never add content excerpts, filenames, app titles, email addresses, or account
identifiers to this worksheet.

The participant manifest and incident register are separate, enum-only files.
Run `python3 scripts/summarize_community_pilot.py --self-test` before collecting
evidence, then generate a row-free weekly aggregate. Passing its automated gates
still requires the manual product-owner review in sections 6 and 8.

## 6. Weekly review

The product owner reviews:

- time to first useful result and Switcher time distributions;
- final action, Preview edit, Preview cancel, Validator fallback, and wrong-Skill
  rates;
- W1/W4 effective retention;
- target verification failures without relaxing verification;
- uninstall/disable reasons for non-built-in Skills;
- author completion time and quality-gate failures.

Every change to a curated Skill records the observed failure class, the revision,
Golden-test changes, and whether permissions, risk, or delivery changed.

## 7. Incident stop rule

Pause the Pilot immediately for any private-content disclosure, executable Skill
behavior, unauthorized Context capture, blind target replacement, credential
exposure, or other Critical event. Preserve redacted technical evidence, notify
the product owner, fix and re-run the installed-app safety matrix before the
Pilot resumes.

## 8. Registry decision

At the end of week 4, compare real evidence with sections 12.3 and 17 of the
Community Skills core plan. A Registry proposal may be written only if every Go
condition is satisfied and the product owner accepts the moderation and
maintenance responsibility. Otherwise the decision is to improve local
discovery, content, Creator, and Preview and run another Pilot.
