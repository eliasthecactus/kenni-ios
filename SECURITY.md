# Security model — KENNI iOS

KENNI verifies that a contact is really who they claim to be, using keys that
never leave the device. This document is the short version; the crypto lives in
[`Core/Crypto`](kenni/kenni/Core/Crypto).

## Identity & keys

- The identity is 128 bits of `SecRandomCopyBytes` entropy, shown to the user as
  a 12-word **BIP39** phrase (implemented in-app, no dependency).
- Keys are derived deterministically with **HKDF-SHA256**:
  - Ed25519 signing key — the identity; signs verification requests/answers,
    challenge responses, identity bundles, and API requests.
  - X25519 key-agreement key — pairwise shared secrets with contacts.
  - A symmetric key for the optional encrypted backup.
- The phrase alone restores everything, fully offline.

## Storage & app lock

- The seed lives in the **Keychain**, `WhenUnlockedThisDeviceOnly`. An optional
  synchronizable copy (`WhenUnlocked`) enables iCloud Keychain backup — the
  choice is made during onboarding, **before** anything is written, so a key is
  never synced without consent.
- App lock uses `LAContext` (Face ID / Touch ID / device passcode). Where the
  device has none, a 6-digit PIN is stored as **PBKDF2-HMAC-SHA256** (210k
  iterations, per-PIN salt) and compared in constant time. The PIN gates the UI;
  the seed is separately protected by the Keychain.

## Trust model

- Contacts are exchanged **directly** (QR in person, or a link). The server never
  introduces identities.
- Every verification signature is checked **on-device against the stored public
  key** from that exchange — never against anything the server says. A compromised
  server cannot forge a contact or a confirmation.
- Online verification uses single-use nonces with a 90 s TTL. Offline verification
  uses an HMAC over the X25519-derived pairwise secret with a direction tag, so a
  challenge can't be reflected as its own answer.

## What leaves the device

- To the API: your public key, an APNs token, and opaque **signed** envelopes.
  Never names, photos, contacts, or private keys.
- Profile data (name, photo) is shared only peer-to-peer during key exchange.

## Reporting

Found a problem? Email **kenni@benavo.ch** rather than opening a public issue.
