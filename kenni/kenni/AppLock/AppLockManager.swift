import Foundation
import LocalAuthentication
import CryptoKit
import CommonCrypto
import Security
import Observation

/// App lock: Face ID / Touch ID (with system passcode fallback) via LocalAuthentication.
/// If the device has neither biometrics nor a passcode, a 6-digit KENNI PIN
/// (salted SHA256 in the Keychain) takes over.
@Observable
final class AppLockManager {
    enum Method: String {
        case deviceAuth // Face ID / Touch ID / device passcode
        case pin        // custom KENNI PIN
    }

    private static let methodKey = "kenni.applock.method"
    private static let pinService = "ch.benavo.kenni.applock"
    private static let pinAccount = "pin"

    var isLocked = true
    private(set) var lastAuthError: String?

    var method: Method? {
        get { UserDefaults.standard.string(forKey: Self.methodKey).flatMap(Method.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: Self.methodKey) }
    }

    /// True when the device offers biometrics or a passcode.
    var deviceAuthAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context.biometryType
    }

    func unlockWithDeviceAuth(reason: String) async -> Bool {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: reason)
            if ok { isLocked = false; lastAuthError = nil }
            return ok
        } catch {
            lastAuthError = error.localizedDescription
            return false
        }
    }

    // MARK: PIN fallback

    func setPIN(_ pin: String) throws {
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else {
            throw SeedVaultError.keychain(errSecParam)
        }
        let digest = Self.hash(pin: pin, salt: Data(salt))
        try Self.storePinRecord(Data(salt) + digest)
        method = .pin
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let record = Self.loadPinRecord(), record.count == 16 + 32 else { return false }
        let salt = record.prefix(16)
        let stored = Data(record.dropFirst(16))
        let ok = Self.constantTimeEqual(Self.hash(pin: pin, salt: salt), stored)
        if ok { isLocked = false; lastAuthError = nil }
        return ok
    }

    func lock() { isLocked = true }

    /// Switches the lock to Face ID / Touch ID / device passcode after confirming
    /// it actually works, and forgets any stored PIN. Returns false if the user
    /// cancels or device auth isn't available.
    func switchToDeviceAuth(reason: String) async -> Bool {
        guard deviceAuthAvailable else { return false }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: reason)) ?? false
        guard ok else { return false }
        Self.deletePinRecord()
        method = .deviceAuth
        return true
    }

    /// Removes the stored PIN (used when switching to device auth).
    func clearPIN() { Self.deletePinRecord() }

    private static func deletePinRecord() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: pinService,
            kSecAttrAccount as String: pinAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// PBKDF2-HMAC-SHA256. A slow KDF so that, even if the (device-only) Keychain
    /// blob is ever extracted, brute-forcing a 6-digit PIN is expensive rather than
    /// instant. The PIN only gates the UI — the seed itself is separately protected
    /// by the Keychain — but defense in depth is cheap here.
    private static let pbkdf2Rounds: UInt32 = 210_000

    private static func hash(pin: String, salt: Data) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let pinBytes = Array(pin.utf8)
        let saltBytes = Array(salt)
        _ = saltBytes.withUnsafeBufferPointer { saltPtr in
            derived.withUnsafeMutableBufferPointer { outPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pin, pinBytes.count,
                    saltPtr.baseAddress, saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Rounds,
                    outPtr.baseAddress, outPtr.count)
            }
        }
        return Data(derived)
    }

    /// Length-independent, value-constant-time comparison.
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    private static func storePinRecord(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: pinService,
            kSecAttrAccount as String: pinAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SeedVaultError.keychain(status) }
    }

    private static func loadPinRecord() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: pinService,
            kSecAttrAccount as String: pinAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
