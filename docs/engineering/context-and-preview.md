# OpenWhisper Context Broker and Diff Preview

> Status: selected-text context implemented for the macOS alpha
> Scope: explicit per-Skill permission, bounded AX selection capture, sensitive
> app denial, local Preview, and verified replacement

## Privacy boundary

The first Context Broker capability is `selection`. OpenWhisper does not use
this path to read an entire window, document, screen, clipboard, browser DOM,
conversation, terminal history, or file.

Selection content is read only when all of these conditions hold:

1. the resolved Skill declares the `selection` capability;
2. selected-text context is enabled;
3. the launch application is not covered by the sensitive-app policy;
4. the Skill has an `alwaysAllow` grant or the user chooses **Allow Once**;
5. Accessibility exposes the same editable target captured when dictation
   started;
6. the selected text is non-empty and within the configured character limit.

The default permission is **Ask every time**. Settings → Context exposes
**Ask every time**, **Always allow**, **Never allow**, a global capability
toggle, a 2,000 / 6,000 / 12,000 character limit, and permission reset.

Choosing **Voice Only** continues without reading selected text. Choosing
**Cancel** cancels the dictation session.

## Session capture

`ContextBroker` runs after local runtime preflight and before recording starts.
It produces a `PreparedSkillContext` containing:

- prompt-safe selected text, when authorized;
- the granted capability enum;
- selected character count;
- a transient `SelectionContextSnapshot`;
- a bounded reason code;
- an optional persistent grant selected by the user.

`SelectionContextSnapshot` contains the original AX target identity, UTF-16
selection range, selected text, and SHA-256 digest. It is never encoded into
`config.json`, History, Recovery, product metrics, or support diagnostics.

The selected text is inserted into the fixed Skill Prompt Compiler context
section as untrusted data. It cannot grant permissions, alter the provider,
execute code, or weaken local output and paste policy.

## Diff Preview and routing

`OutputRouter` enforces the local Skill delivery contract:

| Condition | Route |
| --- | --- |
| Direct, low risk, no selection | existing automatic verified paste path |
| `previewThenPaste` | Preview |
| any selection-backed automatic result | Preview |
| high risk | Preview |
| retry or `copyOnly` | clipboard only |

Preview shows:

- Skill ID and version;
- validation state;
- source, final result, and local line/word Diff;
- context category, never a hidden context source;
- Copy;
- Replace Selection when a frozen selection exists;
- Paste to Target when no selection replacement is available;
- Cancel.

The Preview window is local. Opening it does not send another provider request.

## Safe selection replacement

Before dispatching paste, `TextInjector` reactivates the original launch
application and checks:

1. the same process and AX element are still focused for that application;
2. the selected UTF-16 range is unchanged;
3. the selected text SHA-256 digest is unchanged;
4. the target remains editable immediately before Cmd-V;
5. existing post-paste value/range verification still succeeds when the target
   exposes readable AX text.

If the target, range, text, or verification surface changed, OpenWhisper does
not replace the selection. It keeps the result in the clipboard and reports
`Copied — selection changed`.

Without Accessibility, Context Broker cannot capture selection and output
continues through Preview or clipboard fallback without claiming that context
was read.

## Data minimization

Latency diagnostics may store only:

- approved capability enum values;
- bounded selected-character count;
- existing built-in Skill ID/version and validator issue codes.

They do not store selected text, its digest, AX identifiers, app names, bundle
identifiers, Prompt bodies, clipboard content, or Preview text.

Retry configuration explicitly clears `SkillPromptContext`, so selected text
does not remain attached to retained retry audio.

## Automated verification

Primary tests:

- `ContextRuntimeTests.swift`
- `PreviewRuntimeTests.swift`
- `TextInjectorTests.swift`
- `AppCoordinatorCancellationTests.swift`

The installed visual harness captures `11-diff-preview.png` from
`/Applications/OpenWhisper.app` using the private `--preview-demo` launch mode.

Run:

```bash
swift test
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/visual_acceptance.sh --install
```
