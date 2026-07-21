# Changelog

## 0.1.0 — Unreleased

- Established OpenWhisper as the canonical product, executable, Swift target, bundle, data-directory, Keychain, packaging, and documentation identity.
- Added English and Simplified Chinese UI resources.
- Preserved the native macOS `F5 → speak → F5 → paste-or-copy` workflow.
- Added a centralized product identity and macOS-first repository structure.
- Reset release metadata for the first OpenWhisper alpha.
- Added security, UI, and macOS release documentation as engineering gates.
- Added an Auto Polish decision engine that skips short, low-complexity
  dictation, runs for corrections/structured/translation/email/long-form
  intent, and records only a bounded decision reason in local diagnostics.
- Added application-aware Voice Modes for Direct, Reply, Email, Agent Plan,
  Code Prompt, and Translate. Settings can choose a default mode or assign
  exact bundle-identifier rules without reading window or document content;
  runtime configuration freezes the selected mode at recording time and
  strips the full rule list before provider use.
- Added a repository hygiene release precheck that fails on legacy product
  identity markers, common committed-secret patterns, missing Simplified
  Chinese literals, duplicate localization keys, or broken local Markdown
  links.
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
- Made HUD accessibility display options injectable while preserving live
  macOS Reduce Motion and Increase Contrast behavior in normal launches.
  Installed-app visual acceptance now forces a deterministic baseline, proves
  the reduced-motion processing waveform remains pixel-stable across paired
  captures, and proves Increase Contrast visibly changes the error shell,
  detail text, and retry control without changing HUD geometry.
- Added opt-in local product metrics for app launch, Onboarding-step
  completion, dictation, discard, and Retry outcomes. Metrics use only
  version/build, enums, and duration/latency buckets, have bounded owner-only
  retention, are never uploaded automatically, and can be reviewed in support
  diagnostics or exported as an aggregate, timestamp-free JSON report for
  voluntary sharing.
- Added bounded Provider resilience for managed transcription, recovery
  transcription, and AI Polish: classified failures, one-shot authentication
  refresh, `Retry-After` handling, exponential backoff with jitter, independent
  route circuit breakers, and cancellation-safe half-open probes.
- Expanded installed paste acceptance from TextEdit to a privacy-isolated
  TextEdit/Terminal matrix. Terminal uses a disposable HOME with history
  disabled and a generated proof file, verifies the expected
  `paste_dispatched` clipboard fallback, removes every temporary artifact, and
  restores the complete pre-acceptance clipboard snapshot.
- Replaced fixed Voice Modes with thirteen stable, versioned declarative Skills,
  a deterministic resolver, fixed-order prompt compiler, local validators,
  Direct fallback, app rules, migration compatibility, and redacted history
  and diagnostics.
- Added a global Skill Switcher, a dedicated Installed/Discover/Created Skill
  Library, editable Preview, structured redacted Skill Run receipts, Safe Undo,
  Creator/Test Bench, and five Pilot-focused tasks: Bug Report, Commit Message,
  Meeting Action Items, Product Brief, and Customer Support Reply.
- Added explicit selected-text context grants, sensitive-app denial before
  capture, frozen AX element/range/text hashes, Context Rewrite and Context
  Reply, local Diff Preview, and copy-only fallback when the selection changes.
- Added five local Style Capsules, user-created Capsule analysis/edit/export/
  deletion, per-Skill assignments, sample clearing, three built-in Domain
  Packs, deterministic terminology precedence, conflict visibility, and
  mandatory Preview for high-risk medical terminology.
- Added constrained local `.openwhisperskill` import with package-size and
  file-type limits, path/symlink/executable rejection, permission review,
  content hashes, multi-version activation and rollback, disable/uninstall,
  Skill Inspector, Golden contract tests, bilingual errors, and a maintained
  example package.
- Documented and enforced the Phase 6 boundary: no remote Registry, publisher
  trust badge, arbitrary Action, Shell, file-system, custom-network, Keychain,
  or generic MCP authority is enabled by Community Skills.
- Added source, signed-candidate, and signed-final release evidence gates for
  installed-app, signing, public-hosting, tag, artifact, and Cask evidence.
  Placeholder templates remain fail-closed.
- Added a pinned two-phase signed-release GitHub Actions workflow. `prepare`
  creates one Developer ID/notarized candidate; `finalize` restores the exact
  source-commit-bound candidate with a separate SHA-256 instead of rebuilding
  on a fresh runner, verifies byte-identical published appcast/policy files,
  and withholds private signing keys from finalization.
- Recorded a same-category OpenWhisper naming conflict as a blocking public
  distribution naming gate rather than claiming trademark/domain clearance.

OpenWhisper `0.1.0` is an alpha baseline, not a stable signed release.
