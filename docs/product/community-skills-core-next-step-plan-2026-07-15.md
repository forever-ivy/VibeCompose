# VibeCompose Community Skills Roadmap

> Updated: 2026-07-28
>
> Scope: open-source macOS client, declarative Skills, local installation, and
> community contribution.

## Product direction

VibeCompose is an independent community project for voice-first writing on
macOS. The primary loop is:

1. press the configured shortcut;
2. speak;
3. transcribe through the connected ChatGPT account;
4. resolve a declarative Skill;
5. review or deliver the result safely.

The Public Alpha presents one provider route: browser OAuth with the user's
ChatGPT account. Community Skills remain local, inspectable, and
non-executable.

## Principles

- **One trigger:** the same shortcut starts and stops recording.
- **One public provider path:** ChatGPT browser OAuth.
- **Declarative Skills:** prompts and metadata, never executable code.
- **Local control:** local settings, bounded history, explicit context grants,
  and conservative paste.
- **Inspectable behavior:** Preview, validation results, receipts, and source
  files remain reviewable.
- **Honest dependency:** public copy states that ChatGPT web endpoints are
  undocumented and may change.

## Completed foundation

- built-in Skill registry and deterministic resolver;
- global Skill Switcher and application rules;
- editable Preview and safe delivery;
- selected-text permissions and sensitive-app blocking;
- Writing Styles and terminology layers;
- local Community Skill import, validation, versioning, rollback, and
  uninstall;
- Creator/Test Bench and Golden contract checks;
- redacted diagnostics and bounded local data retention.

## Next milestones

### 1. Public repository readiness

- keep README, OAuth, privacy, build, and contribution docs current;
- keep issue and pull-request templates suitable for community contributors;
- publish reproducible source-build and installed-app verification steps;
- ensure release artifacts match the tagged source revision.

### 2. Community Skill quality

- keep the package format narrow and deterministic;
- expand schema validation and clear rejection messages;
- add reviewed examples for common developer and writing workflows;
- require Golden cases for structured output Skills;
- document safe use of selected text, terminology, and Writing Styles.

### 3. Contributor experience

- provide a minimal Skill template;
- make local validation available through one command;
- publish review criteria and compatibility rules;
- label beginner-friendly issues;
- keep contributor examples free of private user data.

### 4. Reliability and accessibility

- preserve focus across Skill switching;
- test the installed app in real editable targets;
- maintain VoiceOver, Reduce Motion, Increase Contrast, keyboard navigation,
  and bilingual layout coverage;
- keep clipboard fallback distinct from verified insertion.

## Acceptance

- a new contributor can build and launch the installed app with one command;
- OAuth and remote data flow are documented accurately;
- the first-release UI contains no provider selector or API-key setup;
- Skill switching keeps focus on the original project surface;
- Skills cannot execute code or silently acquire new permissions;
- unit, integration, packaged smoke, and installed interaction checks pass.
