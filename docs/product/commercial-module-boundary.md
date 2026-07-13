# OpenWhisper Commercial Module Boundary

> Decision date: July 14, 2026
> Scope: macOS Community, official Pro builds, and future private modules

## 1. Licensing decision

The repository-level `LICENSE` remains the original MIT License and continues
to cover the source files shipped from this repository unless a file or
subdirectory carries an explicit different license notice.

OpenWhisper does not retroactively remove MIT rights from code that has already
been distributed under MIT. The official product can charge for signed builds,
brand, updates, support, and new commercial workflows, but it must not claim
that an MIT permission has been withdrawn.

## 2. Module responsibilities

```text
OpenWhisper
  Native macOS application and Community workflow

OpenWhisperLicensing
  Receipt models, Ed25519 verification, Keychain receipt/device storage,
  offline-grace evaluation, build entitlement, and feature-access protocol

OpenWhisperPro
  Future commercial-only workflow implementations
  (separate private package or explicitly separately licensed directory)
```

`OpenWhisperLicensing` is intentionally a standalone Swift target. It contains
no private signing key, payment credential, checkout secret, customer email,
or activation-server credential. Keeping receipt verification inspectable does
not grant the ability to issue valid receipts because only the public
verification key is embedded in the app.

Future proprietary implementation must not be added casually beneath the
repository's MIT scope. Before `OpenWhisperPro` code is introduced, it must
either:

1. live in a separate private repository/package with its own license; or
2. live in a clearly isolated directory with an explicit license file and
   build manifest boundary reviewed before distribution.

The first option is preferred because it avoids ambiguous mixed-license source
trees and lets Community builds compile without commercial source access.

## 3. Community invariants

The following remain available without a Pro receipt:

- ChatGPT connection and core dictation;
- the F5 start/stop workflow;
- safe paste and clipboard fallback;
- basic terminology management;
- Retry and failed-audio recovery;
- privacy controls and Delete All Data;
- OpenAI-Compatible Recovery;
- security and serious compatibility updates.

A missing, invalid, expired, mismatched, or unsupported Pro receipt must never
disable those Community capabilities.

## 4. Pro access boundary

The first feature gates are:

- application-aware Voice Modes;
- Quick Add.

The app checks access again at the runtime boundary. Editing `config.json`
cannot make an unlicensed Voice Mode reach a provider: the per-session
transcription configuration is forced to Direct and the application rule list
is removed when the signed entitlement does not allow Voice Modes.

The private Alpha sets `OWProPreviewEnabled=true` explicitly in the packaged
Info.plist. Preview access is not a paid activation, does not imply model
access, and is forbidden by the commercial release gate. A commercial build
must set preview to false and embed a valid 32-byte Ed25519 public key under
`OWLicensePublicEDKey`.

## 5. Receipt contract

A signed activation receipt contains only bounded operational fields:

- product, license, and activation identifiers;
- a random app-specific Device ID;
- edition and enumerated feature list;
- issue, verification-due, and offline-grace dates;
- maximum eligible build;
- device-count limit.

The Device ID is randomly generated and stored in Keychain. It is not derived
from the Mac serial number, Apple ID, email, hardware fingerprint, file path,
or document content.

Device-count enforcement belongs to the activation service when it issues a
device-bound receipt. The client verifies that the receipt matches the current
Device ID. Removing a local receipt does not silently claim that a server-side
seat was released; the future activation service must expose an explicit
deactivation/recovery operation.

## 6. Perpetual-use and update semantics

Pro is planned as a perpetual license for eligible builds:

- the receipt includes `maximumBuild`;
- an eligible installed build continues to work while its signed receipt is
  valid;
- a newer build outside the receipt entitlement does not delete or rewrite the
  receipt;
- the user can reinstall an eligible older build or import a renewed receipt;
- security fixes and core data-deletion controls are not converted into paid
  gates.

Periodic verification uses a bounded offline grace period. When grace ends,
only Pro workflows are disabled; Community dictation remains available and
the receipt remains recoverable.

## 7. Contribution and release rules

- Community pull requests must not depend on private Pro source.
- No license private key or payment secret may enter Git, the app bundle,
  diagnostics, or support archives.
- Production receipt keys must be separate from Sparkle and Provider
  Capability Policy keys.
- The commercial release gate must fail when Pro Preview is enabled or the
  license verification public key is absent/invalid.
- Delete All Data removes the local receipt and License Device ID in addition
  to account credentials and application data.
