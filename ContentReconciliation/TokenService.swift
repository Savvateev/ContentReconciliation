import Foundation
import CryptoKit

enum TokenServiceError: LocalizedError {
    case badStatus(Int, String)
    case badResponse(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "сервер ответил кодом \(code): \(body)"
        case .badResponse(let body):
            return "не удалось разобрать ответ: \(body)"
        case .noToken:
            return "в ответе нет токена"
        }
    }
}

private struct TokenResponse: Decodable {
    let success: Bool
    let data: TokenData?
}

private struct TokenData: Decodable {
    let token: String
}

enum TokenService {
    static let endpoint = URL(string: "https://api.bsvyazi.ru/api/v1/billing/users/token")!
    /// Секретный ключ для подписи HMAC-SHA512 (не передаётся в запросе).
    static let secretKey = "Forex2012"
    static let salt = "12345"
    static let userAgent = "MikbillApiAgent/1.0"

    /// Запрашивает токен для одного uid. Запрос повторяет curl: multipart/form-data.
    static func fetchToken(uid: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let sign = hmacSha512(salt: salt, secretKey: secretKey)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = makeBody(
            boundary: boundary,
            fields: [("uid", uid), ("sign", sign), ("salt", salt)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard (200..<300).contains(code) else {
            throw TokenServiceError.badStatus(code, body)
        }

        guard let json = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw TokenServiceError.badResponse(body)
        }

        guard json.success, let token = json.data?.token, !token.isEmpty else {
            throw TokenServiceError.noToken
        }
        return token
    }

    /// HMAC-SHA512 от salt с ключом secretKey, в hex в нижнем регистре.
    static func hmacSha512(salt: String, secretKey: String) -> String {
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let mac = HMAC<SHA512>.authenticationCode(for: Data(salt.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeBody(boundary: String, fields: [(String, String)]) -> Data {
        var body = Data()
        for (name, value) in fields {
            body += Data("--\(boundary)\r\n".utf8)
            body += Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body += Data("\(value)\r\n".utf8)
        }
        body += Data("--\(boundary)--\r\n".utf8)
        return body
    }
}
