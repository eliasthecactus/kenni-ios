import Testing
import Foundation
import CryptoKit
@testable import kenni

struct BIP39Tests {
    @Test func wordlistLoaded() {
        #expect(BIP39.wordlist.count == 2048)
        #expect(BIP39.wordlist.first == "abandon")
        #expect(BIP39.wordlist.last == "zoo")
    }

    /// Official BIP39 test vector: all-zero entropy.
    @Test func referenceVector() throws {
        let entropy = Data(repeating: 0, count: 16)
        let mnemonic = try BIP39.mnemonic(from: entropy)
        #expect(mnemonic == Array(repeating: "abandon", count: 11) + ["about"])
        #expect(try BIP39.entropy(from: mnemonic) == entropy)
    }

    /// Official BIP39 test vector: 0x7f repeated.
    @Test func referenceVector7f() throws {
        let entropy = Data(repeating: 0x7f, count: 16)
        let mnemonic = try BIP39.mnemonic(from: entropy)
        #expect(mnemonic == ["legal", "winner", "thank", "year", "wave", "sausage",
                             "worth", "useful", "legal", "winner", "thank", "yellow"])
    }

    @Test func roundtripRandomEntropy() throws {
        for _ in 0..<50 {
            let entropy = try BIP39.generateEntropy()
            let mnemonic = try BIP39.mnemonic(from: entropy)
            #expect(mnemonic.count == 12)
            #expect(try BIP39.entropy(from: mnemonic) == entropy)
        }
    }

    @Test func checksumRejectsTamperedPhrase() throws {
        let entropy = Data(repeating: 0, count: 16)
        var mnemonic = try BIP39.mnemonic(from: entropy)
        mnemonic[0] = "zoo"
        #expect(throws: BIP39Error.checksumMismatch) {
            _ = try BIP39.entropy(from: mnemonic)
        }
    }

    @Test func unknownWordRejected() {
        let words = Array(repeating: "kenni", count: 12)
        #expect(throws: BIP39Error.unknownWord("kenni")) {
            _ = try BIP39.entropy(from: words)
        }
    }

    @Test func wordCountValidated() {
        #expect(throws: BIP39Error.invalidWordCount) {
            _ = try BIP39.entropy(from: ["abandon"])
        }
    }
}

struct IdentityTests {
    @Test func derivationIsDeterministic() throws {
        let entropy = try BIP39.generateEntropy()
        let a = try KenniIdentity(entropy: entropy)
        let b = try KenniIdentity(entropy: entropy)
        #expect(a.signingKey.publicKey.rawRepresentation == b.signingKey.publicKey.rawRepresentation)
        #expect(a.agreementKey.publicKey.rawRepresentation == b.agreementKey.publicKey.rawRepresentation)
        #expect(a.fingerprint == b.fingerprint)
        #expect(a.idString == b.idString)
    }

    @Test func differentEntropyDifferentIdentity() throws {
        let a = try KenniIdentity(entropy: Data(repeating: 0, count: 16))
        let b = try KenniIdentity(entropy: Data(repeating: 1, count: 16))
        #expect(a.fingerprint != b.fingerprint)
    }

    @Test func signingAndAgreementKeysAreIndependent() throws {
        let identity = try KenniIdentity(entropy: Data(repeating: 3, count: 16))
        #expect(identity.signingKey.rawRepresentation != identity.agreementKey.rawRepresentation)
    }

    @Test func phraseRestoresFullIdentity() throws {
        let original = try KenniIdentity.generate()
        let restored = try KenniIdentity(mnemonic: original.mnemonic)
        #expect(restored.fingerprint == original.fingerprint)
        #expect(restored.signingKey.publicKey.rawRepresentation
                == original.signingKey.publicKey.rawRepresentation)
    }

    @Test func fingerprintFormat() throws {
        let identity = try KenniIdentity(entropy: Data(repeating: 5, count: 16))
        let parts = identity.fingerprint.split(separator: "-")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.count == 4 })
    }

    @Test func signatureVerifiesWithDerivedPublicKey() throws {
        let identity = try KenniIdentity.generate()
        let message = Data("kenni verification request".utf8)
        let signature = try identity.signingKey.signature(for: message)
        #expect(identity.signingKey.publicKey.isValidSignature(signature, for: message))
        // And a different identity's key must reject it.
        let other = try KenniIdentity.generate()
        #expect(!other.signingKey.publicKey.isValidSignature(signature, for: message))
    }

    @Test func rejectsWrongEntropySize() {
        #expect(throws: IdentityError.invalidEntropy) {
            _ = try KenniIdentity(entropy: Data(repeating: 0, count: 32))
        }
    }
}

struct Base32Tests {
    @Test func knownVectors() {
        // RFC 4648 vectors, unpadded
        #expect(Base32.encode(Data("f".utf8)) == "MY")
        #expect(Base32.encode(Data("fo".utf8)) == "MZXQ")
        #expect(Base32.encode(Data("foo".utf8)) == "MZXW6")
        #expect(Base32.encode(Data("foobar".utf8)) == "MZXW6YTBOI")
    }
}

struct ExchangeTests {
    @Test func bundleRoundtripAndVerify() throws {
        let identity = try KenniIdentity.generate()
        let bundle = try IdentityBundle.make(identity: identity, name: "Elias Frehner")
        #expect(bundle.isValid)
        let decoded = IdentityBundle(qrString: bundle.qrString)
        #expect(decoded == bundle)
        #expect(decoded?.fingerprint == identity.fingerprint)
    }

    @Test func tamperedNameIsRejected() throws {
        let identity = try KenniIdentity.generate()
        let bundle = try IdentityBundle.make(identity: identity, name: "Elias")
        let forged = IdentityBundle(v: bundle.v, id: bundle.id, ka: bundle.ka,
                                    name: "Impostor", sig: bundle.sig)
        #expect(!forged.isValid)
        #expect(IdentityBundle(qrString: forged.qrString) == nil)
    }

    @Test func swappedKeysAreRejected() throws {
        let alice = try KenniIdentity.generate()
        let mallory = try KenniIdentity.generate()
        let bundle = try IdentityBundle.make(identity: alice, name: "Alice")
        // Mallory tries to put her key agreement key under Alice's name+signature.
        let forged = IdentityBundle(v: 1, id: bundle.id,
                                    ka: mallory.agreementKey.publicKey.rawRepresentation,
                                    name: bundle.name, sig: bundle.sig)
        #expect(!forged.isValid)
    }

    @Test func pairwiseSecretIsSymmetric() throws {
        let alice = try KenniIdentity.generate()
        let bob = try KenniIdentity.generate()
        let aliceSide = try Pairwise.secret(
            myAgreementKey: alice.agreementKey,
            theirAgreementKey: bob.agreementKey.publicKey.rawRepresentation)
        let bobSide = try Pairwise.secret(
            myAgreementKey: bob.agreementKey,
            theirAgreementKey: alice.agreementKey.publicKey.rawRepresentation)
        #expect(aliceSide == bobSide)
        #expect(aliceSide.count == 32)
        // And a third party derives something different.
        let eve = try KenniIdentity.generate()
        let eveSide = try Pairwise.secret(
            myAgreementKey: eve.agreementKey,
            theirAgreementKey: bob.agreementKey.publicKey.rawRepresentation)
        #expect(eveSide != aliceSide)
    }

    @Test func challengeResponseHappyPath() throws {
        let bob = try KenniIdentity.generate()
        let challenge = try VerifyChallenge.make()
        let response = try VerifyResponse.make(challenge: challenge, identity: bob)
        let decoded = VerifyResponse(qrString: response.qrString)
        #expect(decoded != nil)
        #expect(decoded?.isValid(challenge: challenge,
                                 expectedKey: bob.signingKey.publicKey.rawRepresentation) == true)
    }

    @Test func challengeResponseRejectsImpostorAndReplay() throws {
        let bob = try KenniIdentity.generate()
        let mallory = try KenniIdentity.generate()
        let challenge = try VerifyChallenge.make()
        // Impostor signs with her own key: must fail against Bob's stored key.
        let forged = try VerifyResponse.make(challenge: challenge, identity: mallory)
        #expect(!forged.isValid(challenge: challenge,
                                expectedKey: bob.signingKey.publicKey.rawRepresentation))
        // Replay of an old response against a fresh challenge: must fail.
        let old = try VerifyResponse.make(challenge: challenge, identity: bob)
        let freshChallenge = try VerifyChallenge.make()
        #expect(!old.isValid(challenge: freshChallenge,
                             expectedKey: bob.signingKey.publicKey.rawRepresentation))
    }
}

struct VerifyFlowTests {
    @Test func requestEnvelopeRoundtripAndValidation() throws {
        let alice = try KenniIdentity.generate()
        let bob = try KenniIdentity.generate()
        let bobKey = bob.signingKey.publicKey.rawRepresentation
        let request = try VerifyRequestEnvelope.make(identity: alice, to: bobKey)

        let decoded = VerifyRequestEnvelope(payloadString: request.payloadString)
        #expect(decoded != nil)
        #expect(decoded!.isValid(expectedFrom: alice.signingKey.publicKey.rawRepresentation))
        // Claiming it came from someone else must fail.
        #expect(!decoded!.isValid(expectedFrom: bobKey))
    }

    @Test func answerBindsToRequestAndSigner() throws {
        let alice = try KenniIdentity.generate()
        let bob = try KenniIdentity.generate()
        let mallory = try KenniIdentity.generate()
        let bobKey = bob.signingKey.publicKey.rawRepresentation
        let request = try VerifyRequestEnvelope.make(identity: alice, to: bobKey)

        let yes = try VerifyAnswerEnvelope.make(request: request, answer: true, identity: bob)
        let decoded = VerifyAnswerEnvelope(payloadString: yes.payloadString)
        #expect(decoded?.isValid(request: request, responderKey: bobKey) == true)
        #expect(decoded?.answer == true)

        // Impostor's signature fails against Bob's stored key.
        let forged = try VerifyAnswerEnvelope.make(request: request, answer: true, identity: mallory)
        #expect(!forged.isValid(request: request, responderKey: bobKey))

        // An answer cannot be replayed against a different request.
        let otherRequest = try VerifyRequestEnvelope.make(identity: alice, to: bobKey)
        #expect(!yes.isValid(request: otherRequest, responderKey: bobKey))
    }

    @Test func deniedAnswerKeepsItsMeaning() throws {
        let alice = try KenniIdentity.generate()
        let bob = try KenniIdentity.generate()
        let bobKey = bob.signingKey.publicKey.rawRepresentation
        let request = try VerifyRequestEnvelope.make(identity: alice, to: bobKey)
        let no = try VerifyAnswerEnvelope.make(request: request, answer: false, identity: bob)
        // Flipping the bit invalidates the signature.
        let flipped = VerifyAnswerEnvelope(reqID: no.reqID, nonce: no.nonce,
                                           answer: true, ts: no.ts, sig: no.sig)
        #expect(no.isValid(request: request, responderKey: bobKey))
        #expect(!flipped.isValid(request: request, responderKey: bobKey))
    }

    @Test func offlineCodesAreDeterministicAndDistinct() {
        let secret = Data(repeating: 7, count: 32)
        let otherSecret = Data(repeating: 8, count: 32)
        let code = OfflineCodes.response(secret: secret, challenge: "123456")
        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
        #expect(code == OfflineCodes.response(secret: secret, challenge: "123456"))
        #expect(code != OfflineCodes.response(secret: otherSecret, challenge: "123456"))
        #expect(code != OfflineCodes.response(secret: secret, challenge: "654321"))
        // The challenge itself is never a valid reply (direction tag).
        #expect(OfflineCodes.response(secret: secret, challenge: "123456") != "123456")
    }

    @Test func randomChallengeFormat() {
        for _ in 0..<20 {
            let challenge = OfflineCodes.randomChallenge()
            #expect(challenge.count == 6)
            #expect(challenge.allSatisfy { $0.isNumber })
        }
    }

    @Test func staleRequestIsRejected() throws {
        let alice = try KenniIdentity.generate()
        let bob = try KenniIdentity.generate()
        let bobKey = bob.signingKey.publicKey.rawRepresentation
        // Hand-build an envelope with a timestamp well outside the TTL window.
        let old = Date().timeIntervalSince1970 - (VerifyRequestEnvelope.ttl + 60)
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let from = alice.signingKey.publicKey.rawRepresentation
        let message = Data("kenni/v1/verify-req".utf8) + Data("stale".utf8) + nonce + from + bobKey
            + Data(String(Int(old)).utf8)
        let sig = try alice.signingKey.signature(for: message)
        let stale = VerifyRequestEnvelope(reqID: "stale", nonce: nonce, from: from,
                                          to: bobKey, ts: old, sig: sig)
        #expect(!stale.isValid(expectedFrom: from))
    }
}

struct LinkTests {
    private func param(_ string: String) -> String? {
        URL(string: string).flatMap { RootView.exchangeBundleParam(from: $0) }
    }

    @Test func parsesEmbeddedBundleParam() {
        // App's own scheme (primary) and the universal-link form (bonus).
        #expect(param("kenni://x?b=ABC123") == "ABC123")
        #expect(param("https://benavo.ch/x?b=ABC123") == "ABC123")
    }

    @Test func rejectsUnrelatedLinks() {
        #expect(param("https://benavo.ch/apps/kenni") == nil)
        #expect(param("kenni://x") == nil)
        #expect(param("kenni://verify?b=abc") == nil)  // wrong host
        #expect(param("https://benavo.ch/x?t=old-token") == nil)
    }

    /// A share link round-trips: build it, extract the param, rebuild the bundle.
    @Test func shareLinkRoundTrips() throws {
        let identity = try KenniIdentity.generate()
        let bundle = try IdentityBundle.make(identity: identity, name: "Ladina")
        let url = try #require(bundle.shareURL)
        let extracted = try #require(param(url.absoluteString))
        let rebuilt = IdentityBundle(linkParam: extracted)
        #expect(rebuilt == bundle)
        #expect(rebuilt?.fingerprint == identity.fingerprint)
    }

    @Test func tamperedLinkBundleRejected() throws {
        let identity = try KenniIdentity.generate()
        let bundle = try IdentityBundle.make(identity: identity, name: "Ladina")
        let forged = IdentityBundle(v: bundle.v, id: bundle.id, ka: bundle.ka,
                                    name: "Impostor", sig: bundle.sig)
        #expect(IdentityBundle(linkParam: forged.linkParam) == nil)
    }
}
