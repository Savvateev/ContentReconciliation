import Foundation

struct CabinetInfo {
    var user: String?
    var fio: String?
    var phone: String?
    var address: String?
    var mobTel: String?
    var smsTel: String?
    var subscriptions: [Subscription]
}

enum CabinetServiceError: LocalizedError {
    case badStatus(Int, String)
    case badResponse(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "сервер ответил кодом \(code): \(body)"
        case .badResponse(let body):
            return "не удалось разобрать ответ: \(body)"
        case .apiError(let message):
            return "сервер вернул ошибку: \(message)"
        }
    }
}

private struct CabinetResponse: Decodable {
    let success: Bool
    let message: String?
    let data: CabinetData?
}

private struct CabinetData: Decodable {
    let user: String?
    let fio: String?
    let phone: String?
    let address: String?
    let mobTel: String?
    let smsTel: String?
    let fee: Fee?

    enum CodingKeys: String, CodingKey {
        case user, fio, phone, address, fee
        case mobTel = "mob_tel"
        case smsTel = "sms_tel"
    }
}

private struct Fee: Decodable {
    let subscriptions: Subscriptions?
}

private struct Subscriptions: Decodable {
    let detailed: [Subscription]?
}

enum CabinetService {
    static let endpoint = URL(string: "https://api.bsvyazi.ru/api/v1/cabinet/user")!

    /// Запрос cabinet/user. Возвращает тело ответа как есть.
    static func fetchRaw(token: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(TokenService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard (200..<300).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CabinetServiceError.badStatus(code, body)
        }
        return data
    }

    /// Получает данные пользователя по токену и разбирает нужные поля.
    static func fetchUser(token: String) async throws -> CabinetInfo {
        let data = try await fetchRaw(token: token)

        guard let json = try? JSONDecoder().decode(CabinetResponse.self, from: data) else {
            throw CabinetServiceError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }

        guard json.success, let info = json.data else {
            throw CabinetServiceError.apiError(json.message ?? "нет данных")
        }

        return CabinetInfo(
            user: info.user,
            fio: info.fio,
            phone: info.phone,
            address: info.address,
            mobTel: info.mobTel,
            smsTel: info.smsTel,
            subscriptions: info.fee?.subscriptions?.detailed ?? []
        )
    }
}

/// Текст для export.txt: ответ cabinet/user с именами всех полей, значения без изменений.
enum UserInfoExport {
    static func makeText(uid: String, login: String, raw: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw CabinetServiceError.badResponse(String(data: raw, encoding: .utf8) ?? "")
        }

        let pretty = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let json = String(data: pretty, encoding: .utf8) ?? ""

        return """
        Экспорт user info
        Запись: uid \(uid), login \(login)
        Поля в ответе api/v1/cabinet/user. Имена полей — ключи JSON.

        \(json)

        """
    }
}
