# kenni-ios

KENNI iOS app — know who's really there.

Cryptographic identity verification for the internet age: exchange keys with people you know
(QR in person or link), then verify with one tap that whoever you're talking to — on a call,
in a chat, anywhere — is really them. Via a signed push confirmation, or fully offline with
spoken challenge codes.

- **Stack:** Swift, SwiftUI, iOS 17+, SwiftData, CryptoKit, VisionKit. No third-party packages.
- **Project:** `kenni/kenni.xcodeproj`
- **Plan:** see [`../PLAN.md`](../PLAN.md) (architecture §7, crypto §2–4, App Store §8)

## Related

| Repo / site | Purpose | Deployed at |
|---|---|---|
| `kenni-api` | Push relay + link exchange (Vapor) | https://kenniapi.benavo.ch |
| benavo.ch | Landing, Universal Links (AASA), `/x` exchange page, privacy | https://benavo.ch/apps/kenni |

Security notes: [`SECURITY.md`](SECURITY.md).
