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

## Releases

Push a version tag and GitHub Actions builds the iOS app and publishes an installable
`.ipa` to a GitHub Release:

```sh
git tag v1.0.2 && git push origin v1.0.2
```

The workflow (`.github/workflows/release-ipa.yml`) runs on a `macos-26` runner,

- builds kenni in `Release` for `generic/platform=iOS`,
- applies the tag version (`v1.0.2` → `1.0.2`) to the package,
- signs it with the team's Apple Development identity (development
  distribution, `debugging`) — installable on devices registered to the
  team, and
- creates a release named `kenni 1.0.2` with `kenni-1.0.2.ipa` attached.
  Versions containing a `-` (e.g. `v1.0.2-rc1`) are marked as pre-releases.

### One-time signing setup

iOS sideloading requires Apple's signing identity, which lives in your Apple
Developer account, **not** in the repo. The workflow imports it from four
[repository secrets](https://docs.github.com/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions):

| Secret | Contents |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Your signing certificate, `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password of that `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | Your provisioning profile, `base64`'d `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Any random string; guards the runner's throwaway keychain |

Export both from Xcode → **Settings → Accounts** → your team, then add the secrets
above. Steps mirror the
[GitHub guide for signing Xcode applications on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

> The runner signs with the imported certificate only. Your locally configured
> cloud-managed identity alone is not available to the workflow; the exports above
> are required for CI builds.
