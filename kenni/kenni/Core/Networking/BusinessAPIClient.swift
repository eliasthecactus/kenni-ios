import CryptoKit
import Foundation

struct BusinessProfile: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let logoURL: URL?
    let address: String
    let websiteURL: URL?
}

struct ClaimedBusinessDevice: Codable {
    let deviceID: UUID
    let deviceLabel: String
    let business: BusinessProfile
}

struct BusinessDeviceStatus: Codable {
    let deviceID: UUID
    let deviceLabel: String
    let status: String
    let revokedAt: Int?
    let business: BusinessProfile
}

struct IssuedBusinessPIN: Codable {
    let pin: String
    let expiresAt: Int
}

struct BusinessEnrollmentLink: Equatable, Identifiable {
    let token: String
    var id: String { token }

    init?(url: URL) {
        guard url.scheme == "kenni", url.host == "business", url.path == "/enroll",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              token.count <= 200,
              token.split(separator: ".", maxSplits: 1).count == 2 else { return nil }
        self.token = token
    }

    init?(text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        self.init(url: url)
    }
}


struct BusinessAPIClient {
    let deviceID: UUID
    let signingKey: Curve25519.Signing.PrivateKey

    private struct ClaimBody: Codable {
        let token: String
        let publicKey: String
        let signature: String
    }

    private struct APNSBody: Codable { let apnsToken: String }
    private struct PINBody: Codable { let pin: String }

    static func claim(token: String, signingKey: Curve25519.Signing.PrivateKey) async throws -> ClaimedBusinessDevice {
        let publicKey = signingKey.publicKey.rawRepresentation.base64URLEncodedString()
        let message = Data("kenni/v1/business-enrollment\n\(token)\n\(publicKey)".utf8)
        let signature = try signingKey.signature(for: message).base64URLEncodedString()
        let body = try JSONEncoder().encode(ClaimBody(
            token: token, publicKey: publicKey, signature: signature))
        let data = try await unsignedRequest(
            method: "POST", path: "/v1/business-device-invitations/claim", body: body)
        return try decode(data)
    }

    func status() async throws -> BusinessDeviceStatus {
        try Self.decode(try await signedRequest(method: "GET", path: "/v1/business-devices/me"))
    }

    func registerAPNSToken(_ token: String) async throws {
        let body = try JSONEncoder().encode(APNSBody(apnsToken: token))
        _ = try await signedRequest(
            method: "PUT", path: "/v1/business-devices/apns-token", body: body)
    }

    func issueVerificationPIN() async throws -> IssuedBusinessPIN {
        try Self.decode(try await signedRequest(
            method: "POST", path: "/v1/business-devices/verification-pins"))
    }

    static func verifyBusiness(pin: String) async throws -> BusinessProfile {
        let body = try JSONEncoder().encode(PINBody(pin: pin))
        return try decode(try await unsignedRequest(
            method: "POST", path: "/v1/business-verifications/verify", body: body))
    }


    private func signedRequest(method: String, path: String,
                               body: Data = Data()) async throws -> Data {
        var request = URLRequest(url: APIClient.baseURL.appending(path: path))
        request.httpMethod = method
        if !body.isEmpty {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = Data("kenni/v1/business-device\n\(method)\n\(path)\n\(timestamp)\n\(String(decoding: body, as: UTF8.self))".utf8)
        let signature = try signingKey.signature(for: message)
        request.setValue(deviceID.uuidString, forHTTPHeaderField: "X-Kenni-Business-Device")
        request.setValue(timestamp, forHTTPHeaderField: "X-Kenni-Business-Timestamp")
        request.setValue(signature.base64URLEncodedString(),
                         forHTTPHeaderField: "X-Kenni-Business-Signature")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    private static func unsignedRequest(method: String, path: String,
                                        body: Data) async throws -> Data {
        var request = URLRequest(url: APIClient.baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badURL }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw APIError.decoding
        }
        return value
    }
}
