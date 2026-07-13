# OpenWhisper License Operations

## Runtime configuration

Private Alpha packaging defaults to:

```text
OWProPreviewEnabled = true
```

Commercial packaging must provide:

```text
OPENWHISPER_PRO_PREVIEW_ENABLED=0
OPENWHISPER_LICENSE_PUBLIC_ED_KEY=<32-byte Ed25519 public key in base64>
```

The public key is written to `OWLicensePublicEDKey` in the signed app's
Info.plist. The private key must be generated and stored outside the repository
and outside the application bundle.

The release gate rejects:

- a commercial build with Pro Preview enabled;
- a missing or malformed license public key;
- a package whose Info.plist does not explicitly declare preview state.

## Operator tool

The repository builds `OpenWhisperLicenseTool` from the independent
`OpenWhisperLicensing` target.

Generate a keypair into a secure directory outside the repository:

```bash
swift run OpenWhisperLicenseTool generate-keypair \
  --private-key /secure/location/openwhisper-license-private.key \
  --public-key /secure/location/openwhisper-license-public.key
```

The tool refuses to replace existing files. It writes the private key with
mode `0600` and the public key with mode `0644`.

Issue a device-bound receipt:

```bash
swift run OpenWhisperLicenseTool issue \
  --private-key /secure/location/openwhisper-license-private.key \
  --output /secure/location/customer.owlicense \
  --product app.openwhisper.mac \
  --license-id license-001 \
  --activation-id activation-001 \
  --device-id 11111111-2222-3333-4444-555555555555 \
  --edition founderPro \
  --features voiceModes,quickAdd \
  --issued-at 2026-07-14T00:00:00Z \
  --verification-due-at 2026-08-14T00:00:00Z \
  --offline-grace-ends-at 2026-09-14T00:00:00Z \
  --maximum-build 100 \
  --maximum-devices 3
```

Verify the exact receipt before delivery:

```bash
swift run OpenWhisperLicenseTool verify \
  --public-key /secure/location/openwhisper-license-public.key \
  --receipt /secure/location/customer.owlicense \
  --product app.openwhisper.mac \
  --device-id 11111111-2222-3333-4444-555555555555 \
  --current-build 1 \
  --now 2026-07-14T01:00:00Z
```

## Client behavior

The client:

1. generates a random Device ID in a device-only Keychain item;
2. reads a maximum 64 KiB receipt selected by the user;
3. rejects symlinks, directories, empty files, oversized files, unknown
   schemas, duplicate features, wrong products, wrong devices, invalid dates,
   excessive grace periods, invalid limits, and invalid signatures;
4. saves the receipt only after cryptographic and structural validation;
5. enables only enumerated features while the receipt is active or inside its
   bounded offline grace period;
6. keeps Community dictation available for every failure state.

The receipt payload bytes are signed directly and transported inside a JSON
envelope. Verification does not depend on re-serializing JSON.

## Current operational limit

The local Alpha implements signed receipt import, device binding, offline
grace, build entitlement, removal, and Delete All Data. A production
activation/deactivation service, checkout integration, seat recovery, receipt
refresh, refund revocation, and support tooling are still external launch
requirements. Until those exist, the app must not claim that buying or
activating a production license is available.
