import Foundation
import CryptoKit

enum APIError: Error {
    case badURL
    case http(Int, String)
    case decoding
}

/// Talks to kenni-api with proof-of-key request signing:
/// "kenni/v1/api\n{METHOD}\n{path}\n{timestamp}\n{body}" signed with the identity key.
struct APIClient {
    let identity: KenniIdentity

    static var baseURL: URL {
        #if DEBUG
        // Dev/simulator builds hit the dev relay by default; set the
        // "kenni.apiBaseURL" override (e.g. http://127.0.0.1:8080) to point at a
        // local server instead. Release builds always use production.
        if let override = UserDefaults.standard.string(forKey: "kenni.apiBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://kenniapi-dev.benavo.ch")!
        #else
        return URL(string: "https://kenniapi.benavo.ch")!
        #endif
    }

    struct VerifyStatus: Codable {
        let requestID: String
        let status: String // pending | answered | expired
        let requestPayload: String
        let responsePayload: String?
    }

    struct Business: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let logoURL: URL?
        let address: String
        let websiteURL: URL?
    }

    // MARK: Endpoints
    //
    // Signed requests register this device and relay live-check envelopes. The
    // approved-business lookup is intentionally unsigned so looking up a PIN
    // never reveals or links the user's identity key.

    static func identifyBusiness(pin: String) async throws -> Business {
        let body = try JSONEncoder().encode(["pin": pin])
        var request = URLRequest(url: baseURL.appending(path: "/v1/businesses/identify"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        guard let business = try? JSONDecoder().decode(Business.self, from: data) else {
            throw APIError.decoding
        }
        return business
    }

    func registerDevice(apnsToken: String) async throws {
        _ = try await send("POST", "/v1/devices", body: ["apnsToken": apnsToken])
    }

    func sendVerifyRequest(_ envelope: VerifyRequestEnvelope) async throws {
        _ = try await send("POST", "/v1/verify/requests", body: [
            "requestID": envelope.reqID,
            "to": envelope.to.base64URLEncodedString(),
            "payload": envelope.payloadString,
        ])
    }

    func respond(reqID: String, payload: String) async throws {
        _ = try await send("POST", "/v1/verify/requests/\(reqID)/response",
                           body: ["payload": payload])
    }

    func status(reqID: String) async throws -> VerifyStatus {
        try await decode(try await send("GET", "/v1/verify/requests/\(reqID)", body: nil))
    }

    // MARK: Plumbing

    private func send(_ method: String, _ path: String,
                      body: [String: String]?) async throws -> Data {
        let bodyData: Data
        if let body {
            bodyData = try JSONEncoder().encode(body)
        } else {
            bodyData = Data()
        }
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        if body != nil {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = Data("kenni/v1/api\n\(method)\n\(path)\n\(timestamp)\n\(String(decoding: bodyData, as: UTF8.self))".utf8)
        let signature = try identity.signingKey.signature(for: message)
        request.setValue(identity.idString, forHTTPHeaderField: "X-Kenni-Id")
        request.setValue(timestamp, forHTTPHeaderField: "X-Kenni-Timestamp")
        request.setValue(signature.base64URLEncodedString(), forHTTPHeaderField: "X-Kenni-Signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badURL }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw APIError.decoding
        }
        return value
    }
}
