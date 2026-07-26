# VibeCompose V1 PRD

## Summary

`VibeCompose` is a native macOS voice input tool for people who want a private,
repeatable writing workflow. The core promise is simple: install once, connect
ChatGPT through the default browser, no API key, no local model setup, press
`F5`, speak, choose a trusted Skill, and get an understandable result back.

## Product Comparison Matrix

| Product | Main model posture | Setup burden | Cross-app insertion | Zero-config browser route | Core weakness vs VibeCompose |
| --- | --- | --- | --- | --- | --- | --- |
| Wispr Flow | cloud-first | low | yes | no | cloud-first and broader surface |
| Aqua Voice | cloud/model-provider heavy | low-medium | yes | no | broader, heavier product surface |
| VoiceInk | local-first | medium | yes | no | local model setup and tuning burden |
| Superwhisper | hybrid local/cloud | medium | yes | no | still a model/config product |
| TapWisper | BYO provider | medium | yes | no | still needs provider setup |
| VoiceCommand | local STT + cloud command | medium | yes | no | still needs provider selection |
| **VibeCompose** | **browser ChatGPT session** | **very low** | **yes** | **yes** | **private backend dependency; Community Skills are inspectable** |

## Product Positioning

- Product name: `VibeCompose`
- Category: desktop voice input for office work
- Primary user: a repeat writer who wants faster writing without API keys or local model ops
- Primary jobs:
  - dictate emails, notes, chat replies, prompts, and briefs
  - avoid local model setup
  - reuse a familiar browser account without adding another service setup

## Core Value Proposition

- You already pay for ChatGPT.
- Install VibeCompose.
- Press `F5`.
- Speak.
- Get text back in the active app.

## V1 Scope

### Included

- native macOS menu bar app
- zero-config default route through VibeCompose-owned ChatGPT login state
- setup checks for ChatGPT login, microphone, and Accessibility
- safe paste into editable targets
- clipboard fallback otherwise
- GitHub release zip plus Homebrew Cask metadata

### Phased

- hidden `transcription.hintTerms` for terminology preservation
- packaged benchmark workflow for cold / warm regression checks
- advanced recovery route for OpenAI-compatible APIs

### Excluded

- enterprise/private deployment positioning
- Windows or iOS
- local model management
- multi-provider onboarding

## Key Risks

- V1 depends on a private backend path and local ChatGPT Web session behavior.
- Upstream changes can break transcription without any public API compatibility guarantee.
- The product must be honest about this dependency in UI and docs.

## Success Criteria

- fast first successful dictation after install
- most users complete setup without touching advanced settings
- strong repeat usage for short-form writing tasks
