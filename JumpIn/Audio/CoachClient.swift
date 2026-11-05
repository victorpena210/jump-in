import Foundation
import Security

protocol CoachingService {
    func suggest(_ request: CoachRequest, baseURL: URL, token: String) async throws -> String
    func check(baseURL: URL, token: String) async throws
}

final class CoachClient: NSObject, CoachingService, URLSessionTaskDelegate {
    // Never forward a transcript or bearer token to a redirected endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func suggest(_ request: CoachRequest, baseURL: URL, token: String) async throws -> String {
        let data = try await send(path: "api/coach", body: JSONEncoder().encode(request), baseURL: baseURL, token: token)
        let reply = try JSONDecoder().decode(CoachReply.self, from: data)
        let suggestion = reply.suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty, suggestion.count <= 500 else {
            throw AudioFailure.message("The coach returned an empty or oversized suggestion. Try again.")
        }
        return suggestion
    }

    func check(baseURL: URL, token: String) async throws {
        _ = try await send(path: "api/ready", body: nil, baseURL: baseURL, token: token)
    }

    private func send(path: String, body: Data?, baseURL: URL, token: String) async throws -> Data {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioFailure.message("Enter the backend access token in Coach settings.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AudioFailure.message("No response from the coach backend.") }
        guard (200..<300).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 401, 403: message = "The backend access token was rejected. Check Coach settings."
            case 429: message = "The coach is busy or its request limit was reached. Wait a minute before retrying."
            case 503: message = "The backend needs its OpenAI API key or model configured."
            default: message = "The coach could not respond (HTTP \(response.statusCode)). Check the backend and try again."
            }
            throw AudioFailure.message(message)
        }
        return data
    }
}

enum CoachKeychain {
    private static let service = "technology.renatus.JumpIn.backend"
    static func read(for address: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: address,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String, for address: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: address]
        if token.isEmpty { SecItemDelete(query as CFDictionary); return }
        let data = Data(token.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AudioFailure.message("Could not save the backend token in Keychain.")
            }
        } else if result != errSecSuccess {
            throw AudioFailure.message("Keychain did not allow the token to be updated.")
        }
    }
}
