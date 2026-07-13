# Changelog

## 0.1.0 — Unreleased

- Established OpenWhisper as the canonical product, executable, Swift target, bundle, data-directory, Keychain, packaging, and documentation identity.
- Added English and Simplified Chinese UI resources.
- Preserved the native macOS `F5 → speak → F5 → paste-or-copy` workflow.
- Added a centralized product identity and macOS-first repository structure.
- Reset release metadata for the first OpenWhisper alpha.
- Added security, UI, commercialization, and macOS productization documentation as release gates.
- Added an Auto Polish decision engine that skips short, low-complexity
  dictation, runs for corrections/structured/translation/email/long-form
  intent, and records only a bounded decision reason in local diagnostics.
- Isolated automated Settings, Onboarding, History, Terminology, and Quick Add
  snapshots from live configuration, account sessions, API credentials,
  transcripts, recovery records, and terminology.
- Added an installed-app accessibility structure acceptance harness covering
  every Settings pane, all four Onboarding steps, History, Terminology, and
  Quick Add. It audits the SwiftUI accessibility tree for actionable controls
  without names while keeping acceptance data isolated from the user's live
  content.
- Added a private installed-app interaction mode and launcher for official
  Computer Use keyboard/focus acceptance without reading or persisting the
  user's live configuration, credentials, transcripts, Recovery data, or
  terminology.
- Added opt-in local product metrics for app launch, Onboarding-step
  completion, dictation, discard, and Retry outcomes. Metrics use only
  version/build, enums, and duration/latency buckets, have bounded owner-only
  retention, are never uploaded automatically, and can be reviewed in support
  diagnostics or exported as an aggregate, timestamp-free JSON report for
  voluntary sharing.

OpenWhisper `0.1.0` is an alpha baseline, not a production or commercial release.
